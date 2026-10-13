#!/usr/bin/env python3
"""Offline invariants: tk eval envs/forgejo | python3 envs/forgejo/verify-native-runner.py"""
import argparse
import json
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--cache-enabled", action=argparse.BooleanOptionalAction, default=True,
                    help="Expect staged cache enabled (default); --no-cache-enabled checks rollback renders")
parser.add_argument("--keda", help="Also check the rendered KEDA environment JSON")
args = parser.parse_args()
root = json.load(sys.stdin)
job_image = "ghcr.io/catthehacker/ubuntu:act-24.04@sha256:62d572b92f9f32d3427b6d220ad1f9dca9c7b6ffad37d295425037dbff78abaf"


def resources(value):
    if isinstance(value, dict):
        if "kind" in value and "apiVersion" in value:
            yield value
        else:
            for child in value.values():
                yield from resources(child)


objects = list(resources(root))
by_name = {(o["kind"], o["metadata"]["name"]): o for o in objects}
ns = by_name["Namespace", "forgejo-runners"]
assert ns["metadata"]["labels"]["pod-security.kubernetes.io/enforce"] == "privileged"
assert ns["metadata"]["labels"]["ghcrCreds"] == "enabled"
policy = by_name["ValidatingAdmissionPolicy", "forgejo-native-job-security"]["spec"]
assert policy["failurePolicy"] == "Fail"
assert policy["matchConstraints"]["namespaceSelector"]["matchLabels"] == {
    "kubernetes.io/metadata.name": "forgejo-runners"
}
expressions = "\n".join(v["expression"] for v in policy["validations"])
for required in ["gvisor-dind", "hostNetwork", "hostPID", "hostIPC", "serviceAccountToken", "privileged", "volumeDevices"]:
    assert required in expressions, required

for arch in ["amd64", "arm64"]:
    pool = by_name["ScaledJob", "keda-k8s-" + arch]["spec"]
    labels = ["k8s-canary", "k8s-canary-amd64"] if arch == "amd64" else ["k8s-canary-arm64"]
    assert pool["triggers"][0]["metadata"]["labels"].split(",") == labels
    assert pool["triggers"][0]["metadata"]["address"] == "https://git.vpn.dzerv.art"
    job = pool["jobTargetRef"]
    assert job["backoffLimit"] == 0 and job["activeDeadlineSeconds"] <= 21600
    pod = job["template"]
    spec = pod["spec"]
    assert spec["runtimeClassName"] == "gvisor-dind"
    assert spec["automountServiceAccountToken"] is False
    assert spec["nodeSelector"]["kubernetes.io/arch"] == arch
    annotations = pod["metadata"]["annotations"]
    assert annotations["dev.gvisor.spec.mount.dind-socket.type"] == "tmpfs"
    assert annotations["dev.gvisor.spec.mount.dind-socket.share"] == "pod"
    volumes = {v["name"]: v for v in spec["volumes"]}
    assert volumes["dind-socket"]["emptyDir"] == {"medium": "Memory", "sizeLimit": "16Mi"}
    assert volumes["docker-data"]["emptyDir"] == {"sizeLimit": "8Gi"}
    assert spec["securityContext"]["fsGroup"] == 1000
    assert volumes["registry-auth"]["secret"] == {
        "secretName": "ghcr-cluster-secret",
        "items": [{"key": ".dockerconfigjson", "path": "config.json"}],
        "defaultMode": 0o440,
    }
    assert not any("hostPath" in v or "persistentVolumeClaim" in v for v in volumes.values())
    daemon, register = spec["initContainers"]
    assert daemon["name"] == "dind" and daemon["image"] == "docker:29.5.3-dind"
    assert daemon["restartPolicy"] == "Always"
    assert daemon["startupProbe"]["exec"]["command"] == ["docker", "info"]
    assert daemon["startupProbe"]["failureThreshold"] * daemon["startupProbe"]["periodSeconds"] == 120
    daemon_mounts = {m["name"] for m in daemon["volumeMounts"]}
    assert daemon_mounts == {"dind-startup", "dind-socket", "docker-data"}
    assert not any("secretKeyRef" in e.get("valueFrom", {}) for e in daemon["env"])
    assert register["name"] == "register" and register["image"].endswith(":13.2.0")
    assert "--ephemeral" in register["command"][-1]
    assert "umask 077" in register["command"][-1]
    # Runner validates cache settings even in register; its key must remain worker-only.
    assert "--config /config/register.yaml register" in register["command"][-1], "Registration must not load the runtime cache config"
    registration = by_name["ConfigMap", "forgejo-docker-runner-" + arch]["data"]["register.yaml"]
    assert '"enabled": false' in registration
    assert '"secret_url"' not in registration and "__RUNNER_POD_IP__" not in registration
    assert '"file": "/runner-state/.runner"' in registration
    assert all(label + ":docker://" + job_image in registration for label in labels)
    assert next(e["value"] for e in register["env"] if e["name"] == "FORGEJO_URL") == "https://git.vpn.dzerv.art"
    assert {m["name"] for m in register["volumeMounts"]}.isdisjoint(daemon_mounts)
    worker, = spec["containers"]
    assert worker["image"] == register["image"]
    command = "\n".join(worker["command"])
    assert command.endswith("one-job") and "--wait" not in command
    assert {m["name"] for m in worker["volumeMounts"]} & daemon_mounts == {"dind-socket"}
    assert not any("secretKeyRef" in e.get("valueFrom", {}) for e in worker["env"])
    for c in [register, worker]:
        assert c["securityContext"]["allowPrivilegeEscalation"] is False
        assert c["securityContext"]["capabilities"] == {"drop": ["ALL"]}
    config = by_name["ConfigMap", "forgejo-docker-runner-" + arch]["data"]["config.yaml"]
    assert "docker://" in config and ":host" not in config
    assert '"docker_host": "unix:///run/dind/docker.sock"' in config
    assert '"DOCKER_HOST": "unix:///var/run/docker.sock"' in config
    assert next(e["value"] for e in worker["env"] if e["name"] == "DOCKER_HOST") == "unix:///run/dind/docker.sock"
    assert '"file": "/runner-state/.runner"' in config
    assert next(e["value"] for e in register["env"] if e["name"] == "RUNNER_LABELS").split(",") == [label + ":docker://" + job_image for label in labels]
    assert all(label + ":docker://" + job_image in config for label in labels)
    worker_mounts = {m["name"]: m for m in worker["volumeMounts"]}
    assert worker_mounts["registry-auth"] == {
        "name": "registry-auth", "mountPath": "/run/secrets/registry-auth", "readOnly": True,
    }
    assert next(e["value"] for e in worker["env"] if e["name"] == "DOCKER_CONFIG") == "/run/secrets/registry-auth"
    for c in [daemon, register]:
        assert "registry-auth" not in {m["name"] for m in c["volumeMounts"]}
        assert not any(e["name"] == "DOCKER_CONFIG" for e in c["env"])
    assert "DOCKER_CONFIG" not in config, "Registry auth must not enter workflow runner.envs"
    assert worker_mounts["runner-config"] == {"name": "runner-config", "mountPath": "/runner-state", "readOnly": True}
    if args.cache_enabled:
        assert '"enabled": true' in config
        for field in ['"host": "__RUNNER_POD_IP__"', '"proxy_port": 4002', '"external_server": "https://forgejo-cache.vpn.dzerv.art"', '"secret_url": "file:/run/secrets/forgejo-cache/cache-secret"']:
            assert field in config, field
        assert volumes["cache-signing"]["secret"] == {
            "secretName": "forgejo-runner-cache-signing",
            "items": [{"key": "cache-secret", "path": "cache-secret"}],
            "defaultMode": 0o440,
        }
        assert worker_mounts["cache-signing"]["mountPath"] == "/run/secrets/forgejo-cache"
        assert worker_mounts["cache-signing"]["readOnly"] is True
        assert worker_mounts["private-config"]["mountPath"] == "/runner-config"
        assert volumes["private-config"]["emptyDir"]["medium"] == "Memory"
        for c in [daemon, register]:
            assert {m["name"] for m in c["volumeMounts"]}.isdisjoint({"cache-signing", "private-config"})
        assert next(e["valueFrom"]["fieldRef"]["fieldPath"] for e in worker["env"] if e["name"] == "POD_IP") == "status.podIP"
        assert "umask 077" in command and "__RUNNER_POD_IP__" in command
        assert "> /runner-config/config.yaml" in command
        assert "--config /runner-config/config.yaml one-job" in command
        subprocess.run(["sh", "-n"], input=worker["command"][-1].encode(), check=True)
    else:
        assert '"enabled": false' in config
        assert not {"cache-signing", "private-config"} & volumes.keys()
        assert not any(e["name"] == "POD_IP" for e in worker["env"])
    assert '"insecure": false' in config
    assert '"valid_volumes": []' in config

egress = by_name["CiliumNetworkPolicy", "forgejo-native-canary"]["spec"]["egress"]
assert not any(p["port"] in ["80", "4001"] for rule in egress for group in rule.get("toPorts", []) for p in group["ports"])
traefik_rules = [rule for rule in egress if any(ep.get("matchLabels", {}).get("k8s:io.kubernetes.pod.namespace") == "traefik" for ep in rule.get("toEndpoints", []))]
assert len(traefik_rules) == 1
assert traefik_rules[0]["toPorts"] == [{"ports": [{"port": "10443", "protocol": "TCP"}], "serverNames": ["git.vpn.dzerv.art"] + (["forgejo-cache.vpn.dzerv.art"] if args.cache_enabled else [])}]
keda_selector = {"k8s:io.kubernetes.pod.namespace": "keda", "app.kubernetes.io/name": "keda-operator"}
registry_ingress = by_name["CiliumNetworkPolicy", "forgejo-ci-registry"]["spec"]["ingress"]
assert any(rule["fromEndpoints"] == [{"matchLabels": keda_selector}] and rule["toPorts"] == [{"ports": [{"port": "10443", "protocol": "TCP"}]}] for rule in registry_ingress)
if args.keda:
    with open(args.keda) as f:
        keda_objects = list(resources(json.load(f)))
    keda_policy, = [o["spec"] for o in keda_objects if o["kind"] == "CiliumNetworkPolicy" and o["metadata"]["name"] == "keda-operator-egress"]
    assert keda_policy["endpointSelector"]["matchLabels"] == {"app.kubernetes.io/name": "keda-operator"}
    operator, = [o for o in keda_objects if o["kind"] == "Deployment" and o["metadata"]["name"] == "keda-operator"]
    assert operator["metadata"]["namespace"] == "keda"
    assert operator["spec"]["template"]["metadata"]["labels"]["app.kubernetes.io/name"] == "keda-operator"
    assert any(rule.get("toEndpoints") == [{"matchLabels": {"k8s:io.kubernetes.pod.namespace": "traefik", "app.kubernetes.io/name": "traefik"}}] and rule["toPorts"] == [{"ports": [{"port": "10443", "protocol": "TCP"}], "serverNames": ["git.vpn.dzerv.art"]}] for rule in keda_policy["egress"])
    assert any(p["port"] == "80" for rule in keda_policy["egress"] for group in rule.get("toPorts", []) for p in group["ports"]), "Legacy scaler grants must remain additive"
api_ingress = by_name["CiliumNetworkPolicy", "forgejo-runners"]["spec"]["ingress"]
assert all(ep["matchLabels"]["k8s:io.kubernetes.pod.namespace"] == "traefik" for rule in api_ingress for ep in rule["fromEndpoints"])
script = by_name["ConfigMap", "forgejo-dind-startup"]["data"]["start-dockerd.sh"]
subprocess.run(["sh", "-n"], input=script.encode(), check=True)
for required in ["--group=1000", "--iptables=false", "--storage-driver=vfs", "--feature containerd-snapshotter=false", "--storage-opt vfs.xattrs=i_want_broken_containers"]:
    assert required in script
assert "2375" not in script and "tcp://" not in script
# Rollback and cache ownership survive replacement template changes
assert ("Deployment", "forgejo-runner") in by_name
assert ("StatefulSet", "forgejo-runner-cache") in by_name
print("NATIVE_RUNNER_OFFLINE_PASS (live cache/isolation/storage gates still required)")
