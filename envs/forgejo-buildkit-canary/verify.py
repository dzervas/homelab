#!/usr/bin/env python3
"""Offline render/security checks; optional CEL fixtures for the parent's Go harness."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tomllib


env = Path(__file__).resolve().parent
render = json.loads(subprocess.check_output(['tk', 'eval', str(env)], text=True))


def resources(value):
    if isinstance(value, dict):
        if 'kind' in value and 'apiVersion' in value:
            yield value
        else:
            for child in value.values():
                yield from resources(child)
    elif isinstance(value, list):
        for child in value:
            yield from resources(child)


objects = list(resources(render))
assert not any(o['kind'] in ['Secret', 'ExternalSecret', 'Role', 'ClusterRole', 'RoleBinding', 'ClusterRoleBinding'] for o in objects)
policy = next(o for o in objects if o['kind'] == 'ValidatingAdmissionPolicy')
assert policy['spec']['failurePolicy'] == 'Fail'
assert policy['spec']['matchConstraints']['namespaceSelector']['matchLabels'] == {
    'kubernetes.io/metadata.name': 'forgejo-buildkit-canary',
}
binding = next(o for o in objects if o['kind'] == 'ValidatingAdmissionPolicyBinding')
assert binding['spec']['policyName'] == policy['metadata']['name']
assert binding['spec']['validationActions'] == ['Deny']
sa = next(o for o in objects if o['kind'] == 'ServiceAccount')
assert sa['metadata']['name'] == 'default' and sa['automountServiceAccountToken'] is False

builders = [o for o in objects if o['kind'] == 'StatefulSet']
jobs = [o for o in objects if o['kind'] == 'Job']
assert len(builders) == 2 and len(jobs) == 4
assert {b['spec']['template']['spec']['nodeSelector']['kubernetes.io/arch'] for b in builders} == {'amd64', 'arm64'}
for builder in builders:
    spec = builder['spec']
    assert spec['replicas'] == 1
    claim, = spec['volumeClaimTemplates']
    assert claim['metadata']['name'] == 'state'
    assert claim['spec']['storageClassName'] == 'longhorn'
    assert claim['spec']['accessModes'] == ['ReadWriteOnce']
    assert claim['spec']['resources']['requests']['storage'] == '2Gi'
    daemon, = spec['template']['spec']['containers']
    assert daemon['name'] == 'buildkit'
    arch = spec['template']['spec']['nodeSelector']['kubernetes.io/arch']
    assert daemon['command'] == ['buildkitd', '--config', '/config/buildkitd.toml', '--oci-worker-platform', 'linux/' + arch]
    assert daemon['securityContext']['runAsUser'] == 0
    assert daemon['securityContext']['allowPrivilegeEscalation'] is True
    assert 'SYS_ADMIN' in daemon['securityContext']['capabilities']['add']
    assert not any(v.get('secret', {}).get('secretName') == 'buildkit-probe-client' for v in spec['template']['spec']['volumes'])
for test in jobs:
    spec = test['spec']
    assert spec['activeDeadlineSeconds'] == 900 and spec['backoffLimit'] == 0
    assert spec['ttlSecondsAfterFinished'] == 86400
    assert spec['suspend'] == ('-warm-' in test['metadata']['name'])
    probe, = spec['template']['spec']['containers']
    assert probe['name'] == 'probe'
    assert probe['securityContext']['allowPrivilegeEscalation'] is False
    assert not probe['securityContext']['capabilities'].get('add')
    assert any(v.get('secret', {}).get('secretName') == 'buildkit-probe-client' for v in spec['template']['spec']['volumes'])
for workload in builders + jobs:
    pod = workload['spec']['template']['spec']
    assert pod['runtimeClassName'] == 'gvisor-dind'
    assert pod['automountServiceAccountToken'] is False
    assert pod['securityContext']['seccompProfile']['type'] == 'RuntimeDefault'
    assert not any(pod.get(k, False) for k in ['hostNetwork', 'hostPID', 'hostIPC', 'shareProcessNamespace'])
    assert not pod.get('initContainers')
    assert all(set(v) <= {'name', 'emptyDir', 'persistentVolumeClaim', 'configMap', 'secret'} for v in pod['volumes'])
    for container in pod['containers']:
        assert container['image'] == 'moby/buildkit:v0.30.0'
        assert not container['securityContext'].get('privileged', False)
        assert container['securityContext']['capabilities']['drop'] == ['ALL']
        assert not container.get('volumeDevices')
        assert {'cpu', 'memory', 'ephemeral-storage'} <= container['resources']['limits'].keys()

certs = {o['metadata']['name']: o['spec'] for o in objects if o['kind'] == 'Certificate'}
assert certs['buildkit-ca']['isCA'] is True
assert certs['buildkit-ca']['issuerRef'] == {'name': 'buildkit-selfsigned', 'kind': 'Issuer'}
assert certs['buildkit-probe-client']['usages'] == ['client auth']
for arch in ['amd64', 'arm64']:
    cert = certs[f'buildkit-{arch}-tls']
    assert cert['usages'] == ['server auth']
    assert f'buildkit-{arch}.forgejo-buildkit-canary.svc' in cert['dnsNames']
    assert cert['issuerRef'] == {'name': 'buildkit-ca', 'kind': 'Issuer'}

networks = {o['metadata']['name']: o['spec'] for o in objects if o['kind'] == 'CiliumNetworkPolicy'}
server = networks['buildkit-server']
client = networks['buildkit-probe']
assert server['endpointSelector']['matchLabels']['role'] == 'server'
assert client['endpointSelector']['matchLabels']['role'] == 'probe'
assert len(server['ingress']) == 2 and client['ingress'] == []
assert server['ingress'][0]['fromEndpoints'][0]['matchLabels']['k8s:role'] == 'probe'
assert server['ingress'][0]['toPorts'][0]['ports'] == [{'port': '1234', 'protocol': 'TCP'}]
assert server['ingress'][1] == {
    'fromEndpoints': [{'matchLabels': {
        'k8s:io.kubernetes.pod.namespace': 'forgejo-runners',
        'k8s:app': 'forgejo-keda-runner',
    }}],
    'toPorts': [{'ports': [{'port': '1234', 'protocol': 'TCP'}]}],
}
actions_object = next(o for o in objects if o['kind'] == 'CiliumNetworkPolicy'
                      and o['metadata']['name'] == 'buildkit-canary-actions')
assert actions_object['metadata']['namespace'] == 'forgejo-runners'
actions = actions_object['spec']
assert actions['endpointSelector']['matchLabels'] == {'app': 'forgejo-keda-runner'}
assert actions['egress'] == [{
    'toEndpoints': [{'matchLabels': {
        'k8s:io.kubernetes.pod.namespace': 'forgejo-buildkit-canary',
        'k8s:app': 'buildkit-canary',
        'k8s:role': 'server',
    }}],
    'toPorts': [{'ports': [{'port': '1234', 'protocol': 'TCP'}]}],
}]
assert server['egress'][1] == {'toEntities': ['world'], 'toPorts': [{'ports': [{'port': '80', 'protocol': 'TCP'}, {'port': '443', 'protocol': 'TCP'}]}]}
assert server['egress'][2] == {
    'toEndpoints': [{'matchLabels': {
        'k8s:io.kubernetes.pod.namespace': 'traefik',
        'app.kubernetes.io/name': 'traefik',
    }}],
    'toPorts': [{'ports': [{'port': '10443', 'protocol': 'TCP'}],
                 'serverNames': ['git.vpn.dzerv.art']}],
}
registry_object = next(o for o in objects if o['kind'] == 'CiliumNetworkPolicy'
                       and o['metadata']['name'] == 'buildkit-canary-registry')
assert registry_object['metadata']['namespace'] == 'traefik'
registry = registry_object['spec']
assert registry['endpointSelector']['matchLabels'] == {'app.kubernetes.io/name': 'traefik'}
assert registry['ingress'] == [{
    'fromEndpoints': [{'matchLabels': {
        'k8s:io.kubernetes.pod.namespace': 'forgejo-buildkit-canary',
        'k8s:app': 'buildkit-canary',
        'k8s:role': 'server',
    }}],
    'toPorts': [{'ports': [{'port': '10443', 'protocol': 'TCP'}]}],
}]
assert client['egress'][1]['toEndpoints'][0]['matchLabels']['k8s:role'] == 'server'
assert client['egress'][1]['toPorts'][0]['ports'] == [{'port': '1234', 'protocol': 'TCP'}]
for net in [client, server]:
    assert net['egress'][0]['toPorts'][0]['ports'] == [{'port': '53', 'protocol': 'UDP'}, {'port': '53', 'protocol': 'TCP'}]

config = tomllib.loads((env / 'buildkitd.toml').read_text())
assert config['insecure-entitlements'] == []
assert config['grpc']['address'] == ['tcp://0.0.0.0:1234']
assert set(config['grpc']['tls']) == {'cert', 'key', 'ca'}
oci = config['worker']['oci']
assert oci['snapshotter'] == 'native' and oci['noProcessSandbox'] is False
assert oci['networkMode'] == 'host' and oci['rootless'] is False
assert oci['gc'] is True and oci['max-parallelism'] == 1
assert config['worker']['containerd']['enabled'] is False
assert config['cdi']['disabled'] is True
subprocess.run(['sh', '-n', str(env / 'test-buildkit.sh')], check=True)

# Compile/evaluate actual CEL via /tmp/forgejo-canary-cel/check <fixtures.json>, if available
if len(sys.argv) == 2:
    good = {'spec': builders[0]['spec']['template']['spec']}
    probe = {'spec': jobs[0]['spec']['template']['spec']}
    cases = [{'name': 'builder', 'object': good, 'allowed': True}, {'name': 'probe', 'object': probe, 'allowed': True}]

    def negative(name, mutate, base=good):
        obj = copy.deepcopy(base)
        mutate(obj['spec'])
        cases.append({'name': name, 'object': obj, 'allowed': False})

    negative('host-network', lambda p: p.update(hostNetwork=True))
    negative('host-pid', lambda p: p.update(hostPID=True))
    negative('host-ipc', lambda p: p.update(hostIPC=True))
    negative('shared-pid', lambda p: p.update(shareProcessNamespace=True))
    negative('host-runtime', lambda p: p.update(runtimeClassName='runc'))
    negative('api-credentials', lambda p: p.update(automountServiceAccountToken=True))
    negative('projected-token', lambda p: p['volumes'].append({'name': 'token', 'projected': {'sources': [{'serviceAccountToken': {'path': 'token'}}]}}))
    negative('host-path', lambda p: p['volumes'].append({'name': 'host', 'hostPath': {'path': '/'}}))
    negative('privileged', lambda p: p['containers'][0]['securityContext'].update(privileged=True))
    negative('unmasked-proc', lambda p: p['containers'][0]['securityContext'].update(procMount='Unmasked'))
    negative('host-port', lambda p: p['containers'][0].update(ports=[{'hostPort': 1234}]))
    negative('device', lambda p: p['containers'][0].update(volumeDevices=[{'name': 'state', 'devicePath': '/dev/x'}]))
    negative('extra-cap', lambda p: p['containers'][0]['securityContext']['capabilities']['add'].append('SYS_MODULE'))
    negative('renamed-daemon', lambda p: p['containers'][0].update(name='other'))
    negative('init-daemon-exception', lambda p: p.update(initContainers=[p['containers'].pop(0)]))
    negative('ephemeral-daemon-exception', lambda p: p.update(ephemeralContainers=[p['containers'].pop(0)]))
    negative('probe-escalation', lambda p: p['containers'][0]['securityContext'].update(allowPrivilegeEscalation=True), probe)
    negative('probe-cap', lambda p: p['containers'][0]['securityContext']['capabilities'].update(add=['SYS_ADMIN']), probe)
    negative('unconfined', lambda p: p['securityContext']['seccompProfile'].update(type='Unconfined'))
    Path(sys.argv[1]).write_text(json.dumps({'expressions': [v['expression'] for v in policy['spec']['validations']], 'cases': cases}))
print('PASS: isolated bounded native OCI builders, mTLS/CA separation, cold/warm restart probes and script syntax (no live runtime claim)')
