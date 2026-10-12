#!/usr/bin/env python3
"""Offline cache invariants: tk eval envs/forgejo | python3 envs/forgejo/verify-cache.py [--baseline FILE]"""
import argparse
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--baseline", type=Path, help="Pre-extraction tk eval output (configuration only)")
args = parser.parse_args()
root = json.load(sys.stdin)


def resources(value):
    if isinstance(value, dict):
        if "kind" in value and "apiVersion" in value:
            yield value
        else:
            for child in value.values():
                yield from resources(child)


objects = list(resources(root))
cache = root["forgejoRunnerCache"]
workload = cache["workload"]
assert workload["kind"] == "StatefulSet"
assert workload["metadata"]["name"] == "forgejo-runner-cache"
assert workload["spec"]["selector"]["matchLabels"]["app"] == "forgejo-runner-cache"
claim, = workload["spec"]["volumeClaimTemplates"]
assert claim["metadata"]["name"] == "data"
assert claim["spec"]["storageClassName"] == "longhorn-throwaway"
assert claim["spec"]["resources"]["requests"]["storage"] == "20Gi"
service = cache["service"]
assert service["metadata"]["name"] == "forgejo-runner-cache"
assert service["spec"]["ports"] == [{"name": "http", "port": 4001, "protocol": "TCP", "targetPort": 4001}]
server, = workload["spec"]["template"]["spec"]["containers"]
assert server["image"] == "data.forgejo.org/forgejo/runner:13"
assert server["args"] == ["forgejo-runner", "cache-server", "--dir=/data", "--port=4001", "--secret=$(CACHE_SECRET)"]
secret = root["forgejoRunnerSecret"]["spec"]
assert secret["refreshPolicy"] == "OnChange"
assert secret["target"]["template"]["data"] == {
    "token": "c0ffee00f0f9e7a1{{ .password | sha1sum | trunc 24 }}",
    "cache-secret": "{{ .password | sha256sum }}",
}
assert secret["dataFrom"][0]["sourceRef"]["generatorRef"]["name"] == "password"

mirror = root["cacheSigningMirror"]
assert mirror["metadata"]["namespace"] == "forgejo-runners"
assert mirror["metadata"]["name"] == "forgejo-runner-cache-signing"
assert mirror["spec"]["data"] == [{"secretKey": "cache-secret", "remoteRef": {"key": "forgejo-runner", "property": "cache-secret"}}]
assert "dataFrom" not in mirror["spec"]
store = root["cacheSigningStore"]["spec"]
assert store["conditions"] == [{"namespaces": ["forgejo-runners"]}]
assert store["provider"]["kubernetes"]["remoteNamespace"] == "forgejo"
secret_rule, review_rule = root["cacheSigningRole"]["rules"]
assert secret_rule == {"apiGroups": [""], "resources": ["secrets"], "resourceNames": ["forgejo-runner"], "verbs": ["get"]}
assert review_rule["resources"] == ["selfsubjectrulesreviews"]

route, = [o for o in objects if o["kind"] == "HTTPRoute" and "forgejo-cache.vpn.dzerv.art" in o["spec"].get("hostnames", [])]
assert route["spec"]["parentRefs"] == [{"name": "traefik-gateway", "namespace": "traefik", "sectionName": "websecure-vpn"}]
rule, = route["spec"]["rules"]
assert rule["backendRefs"][0]["name"] == "forgejo-runner-cache"
assert rule["backendRefs"][0]["port"] == 4001
assert all(f["type"] == "ExtensionRef" for f in rule.get("filters", []))
assert not any("magicentry" in f["extensionRef"]["name"] for f in rule.get("filters", []))
assert not any(f["type"] in ["URLRewrite", "RequestRedirect"] for f in rule.get("filters", []))
backend = root["cacheBackendPolicy"]["spec"]
assert backend["endpointSelector"]["matchLabels"] == {"app": "forgejo-runner-cache"}
deny, = backend["ingressDeny"]
assert deny["fromEndpoints"] == [{"matchLabels": {"k8s:io.kubernetes.pod.namespace": "forgejo-runners"}}]
assert deny["toPorts"] == [{"ports": [{"port": "4001", "protocol": "TCP"}]}]
assert backend["ingress"][0]["fromEndpoints"][0]["matchLabels"]["k8s:io.kubernetes.pod.namespace"] == "traefik"

helper_path = Path(__file__).with_name("cache-client.libsonnet")
client = json.loads(subprocess.check_output(["jsonnet", str(helper_path)]))
assert client["config"] == {
    "enabled": True,
    "external_server": "https://forgejo-cache.vpn.dzerv.art",
    "secret_url": "file:/run/secrets/forgejo-cache/cache-secret",
    "host": "__RUNNER_POD_IP__",
    "proxy_port": 4002,
}
subprocess.run(["sh", "-n"], input=client["prepareConfig"].encode(), check=True)
with tempfile.TemporaryDirectory() as directory:
    source = Path(directory) / "source.yaml"
    target = Path(directory) / "private.yaml"
    assert client["runnerEnvs"] == {"FORGEJO_RUNNER_POD_IP": client["config"]["host"]}
    source.write_text(json.dumps({"cache": client["config"], "runner": {"envs": client["runnerEnvs"]}}))
    script = client["prepareConfig"].replace("/config/config.yaml", str(source)).replace("/runner-config/config.yaml", str(target))
    for ip in ["10.200.1.2", "fd00::1234"]:
        target.unlink(missing_ok=True)
        subprocess.run(["sh", "-ec", script], env={"PATH": os.environ["PATH"], "POD_IP": ip}, check=True)
        rendered = json.loads(target.read_text())
        assert rendered["cache"]["host"] == ip
        assert rendered["runner"]["envs"]["FORGEJO_RUNNER_POD_IP"] == ip
        assert stat.S_IMODE(target.stat().st_mode) == 0o600
    for ip in ["", "10.200.1.2/evil", "$(echo injected)"]:
        assert subprocess.run(["sh", "-ec", script], env={"PATH": os.environ["PATH"], "POD_IP": ip}, capture_output=True).returncode != 0

workflow_path = Path(__file__).resolve().parents[2] / ".forgejo/workflows/cache-canary.yaml"
workflow = json.loads(subprocess.check_output(["yq", "-o=json", ".", str(workflow_path)]))
assert set(workflow["on"]) == {"workflow_dispatch"}
assert workflow["jobs"]["cache"]["strategy"]["matrix"]["arch"] == ["amd64", "arm64"]
for step in workflow["jobs"]["cache"]["steps"]:
    if "run" in step:
        subprocess.run(["sh", "-n"], input=step["run"].encode(), check=True)
        if "<<'JS'" in step["run"]:
            script = step["run"].split("<<'JS'\n", 1)[1].rsplit("\nJS", 1)[0]
            subprocess.run(["node", "--input-type=module", "--check"], input=script.encode(), check=True)

# Execute the actual workflow probe against an offline fake API; no network or real credentials.
steps = workflow["jobs"]["cache"]["steps"]
lookup = next(step for step in steps if step.get("id") == "lookup")
probe = lookup["run"].split("<<'JS'\n", 1)[1].rsplit("\nJS", 1)[0]
mock = r'''
globalThis.fetch = async (url, options) => {
  const {createHash} = await import('node:crypto');
  const {spawnSync} = await import('node:child_process');
  const zstd = spawnSync('zstd', ['--quiet', '--version'], {encoding: 'utf8'});
  const compression = ((zstd.stdout || '') + (zstd.stderr || '')).trim() ? 'zstd-without-long' : 'gzip';
  const version = createHash('sha256').update(`.cache-canary|${compression}|1.0`).digest('hex');
  if (url.pathname !== '/owningRun/_apis/artifactcache/cache' ||
      url.searchParams.get('keys') !== 'forgejo-cache-canary-amd64-offline' ||
      url.searchParams.get('version') !== version ||
      options.headers.Accept !== 'application/json;api-version=6.0-preview.1' ||
      options.headers.Authorization !== 'Bearer offline-fake-token' || options.redirect !== 'error') {
    throw new Error('Wrong API protocol');
  }
  if (process.env.FAKE_STATUS === 'timeout') throw new Error('offline timeout');
  return {
    status: Number(process.env.FAKE_STATUS),
    json: async () => process.env.FAKE_ENTRY === 'malformed' ? {} : {
      cacheKey: 'forgejo-cache-canary-amd64-offline', archiveLocation: 'http://offline.invalid/archive',
    },
  };
};
'''
with tempfile.TemporaryDirectory() as directory:
    output = Path(directory) / "output"
    env = {
        "PATH": os.environ["PATH"], "ARCH": "amd64", "GENERATION": "offline",
        "ACTIONS_CACHE_URL": "http://10.200.1.2:4002/owningRun/",
        "FORGEJO_RUNNER_POD_IP": "10.200.1.2", "ACTIONS_RUNTIME_TOKEN": "offline-fake-token",
        "GITHUB_OUTPUT": str(output),
    }
    for changes, expected in [
        ({"FAKE_STATUS": "204"}, "MISS"),
        ({"FAKE_STATUS": "200"}, "HIT"),
        ({"FAKE_STATUS": "500"}, None),
        ({"FAKE_STATUS": "401"}, None),
        ({"FAKE_STATUS": "timeout"}, None),
        ({"FAKE_STATUS": "200", "FAKE_ENTRY": "malformed"}, None),
        ({"FAKE_STATUS": "204", "FORGEJO_RUNNER_POD_IP": ""}, None),
        ({"FAKE_STATUS": "204", "ACTIONS_CACHE_URL": "http://runner-service:4002/owningRun/"}, None),
        ({"FAKE_STATUS": "204", "ACTIONS_CACHE_URL": "http://10.200.1.2:4001/owningRun/"}, None),
        ({"FAKE_STATUS": "204", "ACTIONS_RUNTIME_TOKEN": ""}, None),
        ({"FAKE_STATUS": "204", "ACTIONS_CACHE_SERVICE_V2": "true"}, None),
    ]:
        output.unlink(missing_ok=True)
        result = subprocess.run(["node", "--input-type=module"], input=mock + probe,
                                text=True, env=env | changes, capture_output=True)
        if expected:
            assert result.returncode == 0, result.stderr
            assert output.read_text() == f"result={expected}\n"
        else:
            assert result.returncode != 0
            assert "CACHE_CANARY_PROBE_INCONCLUSIVE" in result.stderr
            assert not output.exists()
    assertions = next(step["run"] for step in steps if step.get("name") == "Assert expected hit and exact bytes")
    (Path(directory) / ".cache-canary").mkdir()
    for lookup_result, cache_hit, passes in [("MISS", "", True), ("", "", False), ("HIT", "", False), ("MISS", "true", False)]:
        result = subprocess.run(["sh", "-ec", assertions], cwd=directory, text=True, capture_output=True,
                                env=env | {"MODE": "probe", "LOOKUP_RESULT": lookup_result, "CACHE_HIT": cache_hit})
        assert (result.returncode == 0) == passes
        assert ("CACHE_CANARY_ISOLATION_PASS" in result.stdout) == passes

if args.baseline:
    baseline = json.loads(args.baseline.read_text())
    # Source generator and deprecated runner are byte-equivalent after canonical JSON encoding
    for name in ["forgejoRunnerSecret", "forgejoRunner", "forgejoRunnerConfig", "forgejo"]:
        assert json.dumps(root[name], sort_keys=True) == json.dumps(baseline[name], sort_keys=True), name
    # Only Gateway routing is added; cache workload, Service, PVC and labels remain identical
    old_cache = baseline["forgejoRunnerCache"]
    for name in ["workload", "service", "headlessService", "pvc", "namespace", "externalSecrets", "monitors"]:
        assert json.dumps(cache[name], sort_keys=True) == json.dumps(old_cache[name], sort_keys=True), name

print("PASS: cache identity, TLS route, signing-key mirror/RBAC, backend deny, private owning proxy, canary syntax and offline exact-lookup failure/miss tests")
