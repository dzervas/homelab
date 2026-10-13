#!/usr/bin/env python3
"""Render-contract checks only; Kubernetes CEL compilation/live admission are separate gates."""
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
ENV = pathlib.Path(__file__).resolve().parent
render = json.loads(subprocess.check_output(["tk", "eval", str(ENV)], cwd=ROOT))
mutation = render["mutation"]
guard = render["guard"]
namespace = "woodpecker-canary"
creator = "system:serviceaccount:forgejo:woodpecker-canary-agent"

assert render["workerNamespace"]["metadata"]["name"] == namespace
assert render["workerNamespace"]["metadata"]["labels"]["pod-security.kubernetes.io/enforce"] == "privileged"
assert render["workerServiceAccount"]["automountServiceAccountToken"] is False
assert render["workerServiceAccount"]["metadata"]["namespace"] == namespace
assert mutation["apiVersion"] == "admissionregistration.k8s.io/v1beta1"
for policy in (mutation, guard):
    assert policy["metadata"]["annotations"]["tanka.dev/namespaced"] == "false"
    assert policy["spec"]["failurePolicy"] == "Fail"
    assert policy["spec"]["matchConstraints"]["namespaceSelector"]["matchLabels"] == {
        "kubernetes.io/metadata.name": namespace
    }
assert "matchConditions" not in guard["spec"], "All isolated-namespace Pods must be guarded"
assert mutation["spec"]["matchConstraints"]["resourceRules"][0]["operations"] == ["CREATE"]
conditions = {item["name"]: item["expression"] for item in mutation["spec"]["matchConditions"]}
assert creator in conditions["trusted-creator"]
assert "request.userInfo.username" in conditions["trusted-creator"]
assert "^(clone|prototype-(build|warm|dind|docker)-(amd64|arm64))$" in conditions["canonical-step"]
for label, value in (("repo-name", "homelab"), ("repo-full-name", "dzervas-homelab"),
                     ("event", "manual"), ("commit-branch", "main")):
    assert f"['woodpecker-ci.org/{label}'] == '{value}'" in conditions["reserved-metadata"]
assert "woodpecker-prototype" not in conditions["reserved-metadata"], "Routing label is not authorization"

variables = {item["name"]: item["expression"] for item in mutation["spec"]["variables"]}
assert 'startsWith("prototype-build-")' in variables["cache"]
assert 'startsWith("prototype-warm-")' in variables["cache"]
assert 'startsWith("prototype-dind-")' in variables["dind"]
assert variables["arch"] == 'string(object.spec.nodeSelector["kubernetes.io/arch"])'
assert variables["clone"] == 'variables.step == "clone"'
assert 'woodpecker-ci.org/task-uuid' in variables["task"]
patch = mutation["spec"]["mutations"][0]["jsonPatch"]["expression"]
assert "variables.cache ?" in patch and "variables.dind ?" in patch
for field in ("/spec/nodeSelector", "/spec/runtimeClassName", "/spec/automountServiceAccountToken",
              "/cache", "/var/lib/docker", "emptyDir: Object.spec.volumes.emptyDir{}", "privileged: false"):
    assert field in patch
assert "'gvisor-dind'" in patch
assert "'gvisor-dind-runtime': 'running'" in patch
assert "path: '/spec/overhead', value: {'cpu': '50m', 'memory': '64Mi'}" in patch
assert "allowPrivilegeEscalation: variables.dind" in patch
for symbol in ('Object.spec.containers.securityContext',
               'Object.spec.containers.securityContext.capabilities',
               'Object.spec.containers.securityContext.seccompProfile',
               'Object.spec.securityContext.seccompProfile',
               'Object.spec.affinity', 'Object.spec.affinity.podAffinity',
               'Object.spec.affinity.podAffinity.requiredDuringSchedulingIgnoredDuringExecution',
               'Object.spec.affinity.podAffinity.requiredDuringSchedulingIgnoredDuringExecution.labelSelector',
               'Object.spec.volumes', 'Object.spec.volumes.persistentVolumeClaim',
               'Object.spec.volumes.emptyDir', 'Object.spec.volumes.configMap',
               'Object.spec.volumes.configMap.items', 'Object.spec.containers.volumeMounts'):
    assert symbol + '{' in patch
for field in ('requiredDuringSchedulingIgnoredDuringExecution', 'kubernetes.io/hostname',
              'variables.task', 'woodpecker-prototype-dind', "readOnly: true"):
    assert field in patch
checks = "\n".join(item["expression"] for item in guard["spec"]["validations"])
for field in (creator, "oldObject.metadata.labels", "v.persistentVolumeClaim.claimName == v.name",
              "v.persistentVolumeClaim.claimName == variables.cacheClaim", "v.emptyDir",
              "hostNetwork", "hostPID", "hostIPC", "hostPort", "volumeDevices", "secretKeyRef",
              "imagePullSecrets", "ephemeralContainers", "mountPropagation", "procMount"):
    assert field in checks
assert "has(v.hostPath)" not in checks and "has(v.secret)" not in checks
assert "variables.clone && e.valueFrom.secretKeyRef.name == object.metadata.name + '-step-secret'" in checks
assert 'variables.step.endsWith("-" + variables.arch)' in checks
assert 'object.spec.nodeSelector["gvisor-dind-runtime"] == "running"' in checks
assert 'object.spec.overhead["cpu"] == "50m"' in checks
assert 'object.spec.overhead["memory"] == "64Mi"' in checks
assert 'size(object.spec.overhead) == 2' in checks
assert "size(object.spec.affinity.podAffinity.requiredDuringSchedulingIgnoredDuringExecution) == 1" in checks
assert render["guardBinding"]["spec"]["validationActions"] == ["Deny"]
assert render["mutationBinding"]["spec"]["policyName"] == mutation["metadata"]["name"]
for claim, arch in zip(render["cacheClaims"], ("amd64", "arm64")):
    assert claim["metadata"]["namespace"] == namespace
    assert claim["metadata"]["name"] == f"woodpecker-prototype-cache-{arch}"
    assert claim["spec"]["accessModes"] == ["ReadWriteOncePod"]
    assert claim["spec"]["resources"]["requests"]["storage"] == "2Gi"
network = render["network"]
assert network["metadata"]["namespace"] == namespace
assert "ingress" not in network["spec"], "Worker policy must not admit cross-namespace ingress"
clone_ingress = render["cloneIngress"]
assert clone_ingress["metadata"]["namespace"] == "traefik"
assert clone_ingress["spec"]["ingress"] == [{
    "fromEndpoints": [{"matchLabels": {
        "k8s:io.kubernetes.pod.namespace": namespace,
        "k8s:woodpecker-ci.org/step": "clone",
    }}],
    "toPorts": [{"ports": [{"port": "10443", "protocol": "TCP"}]}],
}]
assert len(network["spec"]["endpointSelector"]["matchExpressions"][0]["values"]) == 9
assert "clone" in network["spec"]["endpointSelector"]["matchExpressions"][0]["values"]
ports = {p["port"] for rule in network["spec"]["egress"] for to in rule["toPorts"] for p in to["ports"]}
assert ports == {"53", "443", "10443", "2376"}
for arch, deployment in render["agents"].items():
    spec = deployment["spec"]["template"]["spec"]
    assert deployment["metadata"]["namespace"] == "forgejo"
    assert spec["nodeSelector"] == {"kubernetes.io/arch": arch}
    assert spec["serviceAccountName"] == "woodpecker-canary-agent"
    agent = spec["containers"][0]
    env = {item["name"]: item.get("value", "") for item in agent["env"]}
    assert agent["image"] == "woodpeckerci/woodpecker-agent:v3.19.0"
    assert env["WOODPECKER_BACKEND_K8S_NAMESPACE"] == namespace
    assert env["WOODPECKER_MAX_WORKFLOWS"] == "1"
    assert env["WOODPECKER_AGENT_CONFIG_FILE"] == ""
    for required in ("!woodpecker-prototype=true", "!woodpecker-ci.org/event=manual",
                     "!woodpecker-ci.org/commit-branch=main",
                     "!woodpecker-ci.org/repo-full-name=dzervas/homelab", "platform=linux/" + arch):
        assert required in env["WOODPECKER_AGENT_LABELS"].split(",")
    for flag in ("POD_LABELS_ALLOW_FROM_STEP", "POD_ANNOTATIONS_ALLOW_FROM_STEP",
                 "POD_NODE_SELECTOR_ALLOW_FROM_STEP", "POD_AFFINITY_ALLOW_FROM_STEP",
                 "RUNTIME_CLASS_ALLOW_FROM_STEP", "SERVICE_ACCOUNT_NAME_ALLOW_FROM_STEP",
                 "ALLOW_NATIVE_SECRETS"):
        assert env["WOODPECKER_BACKEND_K8S_" + flag] == "false"
print("PASS: isolated workers/agents, authenticated/manual scope, security/cache/network render contracts")
print("Not proved: CEL type checking/admission, feature/API gates, RWOP attach or live gVisor/DinD")
