#!/usr/bin/env python3
"""Offline canary checks; does not contact Kubernetes or run dockerd."""
import json
from pathlib import Path
import subprocess
import tempfile


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
assert not any(o['kind'] in ['Secret', 'ExternalSecret', 'Role', 'ClusterRole'] for o in objects)
policy = next(o for o in objects if o['kind'] == 'ValidatingAdmissionPolicy')
assert policy['spec']['failurePolicy'] == 'Fail'
assert policy['spec']['matchConstraints']['namespaceSelector']['matchLabels'] == {
    'kubernetes.io/metadata.name': 'forgejo-dind-canary',
}
binding = next(o for o in objects if o['kind'] == 'ValidatingAdmissionPolicyBinding')
assert binding['spec']['policyName'] == policy['metadata']['name']
assert binding['spec']['validationActions'] == ['Deny']

jobs = [o for o in objects if o['kind'] == 'Job']
assert {o['metadata']['name'] for o in jobs} == {'gvisor-dind-amd64', 'gvisor-dind-arm64'}
for job in jobs:
    spec = job['spec']
    assert spec['activeDeadlineSeconds'] == 900 and spec['backoffLimit'] == 0
    template = spec['template']
    pod = template['spec']
    arch = pod['nodeSelector']['kubernetes.io/arch']
    assert pod['runtimeClassName'] == 'gvisor-dind'
    assert pod['restartPolicy'] == 'Never' and pod['automountServiceAccountToken'] is False
    assert pod['securityContext']['seccompProfile']['type'] == 'RuntimeDefault'
    assert not any(pod.get(key, False) for key in ['hostPID', 'hostIPC', 'hostNetwork', 'shareProcessNamespace'])
    hints = template['metadata']['annotations']
    assert hints['dev.gvisor.spec.mount.dind-socket.share'] == 'pod'
    assert hints['dev.gvisor.spec.mount.dind-socket.type'] == 'tmpfs'
    volumes = {v['name']: v for v in pod['volumes']}
    assert volumes['dind-socket']['emptyDir'] == {'medium': 'Memory', 'sizeLimit': '16Mi'}
    assert volumes['docker-data']['emptyDir']['sizeLimit'] == '2Gi'
    assert all('emptyDir' in v or 'configMap' in v for v in volumes.values())
    daemon, = pod['initContainers']
    tester, = pod['containers']
    assert daemon['image'] == 'docker:29.5.3-dind'
    assert tester['image'] == 'docker:29.5.3-cli'
    assert daemon['name'] == 'dind' and daemon['restartPolicy'] == 'Always'
    assert daemon['startupProbe']['exec']['command'] == ['docker', 'info']
    assert set(daemon['securityContext']['capabilities']['add']) >= {'SYS_ADMIN', 'NET_ADMIN', 'NET_RAW'}
    for container in [daemon, tester]:
        assert container['securityContext']['capabilities']['drop'] == ['ALL']
        assert not container['securityContext'].get('privileged', False)
        assert {'cpu', 'memory', 'ephemeral-storage'} <= container['resources']['limits'].keys()
        envs = {e['name']: e.get('value', '') for e in container['env']}
        assert envs['DOCKER_HOST'] == 'unix:///run/dind/docker.sock'
        assert envs['DOCKER_TLS_CERTDIR'] == ''
    assert tester['securityContext']['allowPrivilegeEscalation'] is False
    assert not tester['securityContext']['capabilities'].get('add')
    assert next(e['value'] for e in tester['env'] if e['name'] == 'EXPECTED_ARCH') == arch

scripts = next(o['data'] for o in objects if o['kind'] == 'ConfigMap')
for script in ['start-dockerd.sh', 'test-dind.sh']:
    with tempfile.NamedTemporaryFile(mode='w+', suffix='.sh') as source:
        source.write(scripts[script])
        source.flush()
        subprocess.run(['sh', '-n', source.name], check=True)
print('PASS: bounded architecture Jobs, socket sharing, credential-free templates, admission scope and POSIX script syntax')
