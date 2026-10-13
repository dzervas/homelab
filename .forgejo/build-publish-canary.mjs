// Registry-only CLI: no builder, Docker daemon, BuildKit endpoint or TLS keys needed.
// Sibling tags use run ID, NOT run_attempt: partial reruns retain successful jobs.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

const digestPattern = /^sha256:[a-f0-9]{64}$/;
function digest(value) {
  assert.match(value, digestPattern, 'Expected immutable sha256 digest');
  return value;
}
function platform(config, arch) {
  assert.equal(config.os, 'linux');
  assert.equal(config.architecture, arch);
  // AMD64 has no variant; ARM64 is either implicit v8 or explicitly v8.
  assert.ok(!config.variant || (arch === 'arm64' && config.variant === 'v8'));
}
function index(raw, siblings) {
  assert.equal(raw.schemaVersion, 2);
  assert.ok(['application/vnd.oci.image.index.v1+json',
    'application/vnd.docker.distribution.manifest.list.v2+json'].includes(raw.mediaType));
  assert.equal(raw.manifests.length, 2, 'Require exactly the two native siblings');
  for (const arch of ['amd64', 'arm64']) {
    const matches = raw.manifests.filter(m => m.platform?.architecture === arch);
    assert.equal(matches.length, 1);
    platform(matches[0].platform, arch);
    assert.equal(matches[0].digest, siblings[arch]);
  }
}
function publish(image, runID, cli) {
  assert.match(image, /^[a-zA-Z0-9._:/-]+$/);
  assert.ok(!image.includes('@'));
  assert.match(runID, /^[0-9]+$/);
  const siblings = {};
  for (const arch of ['amd64', 'arm64']) {
    const tag = `${image}:canary-build-${runID}-${arch}`;
    siblings[arch] = digest(cli(['inspect', tag, '--format', '{{.Manifest.Digest}}']).trim());
    // Verify config at immutable digest, not the now-mutable tag. Index siblings
    // (including attestations) are intentionally rejected: provenance/sbom are disabled.
    const ref = `${image}@${siblings[arch]}`;
    const raw = JSON.parse(cli(['inspect', ref, '--raw']));
    assert.ok(!raw.manifests && raw.config && raw.layers, 'Require single-platform image manifest');
    platform(JSON.parse(cli(['inspect', ref, '--format', '{{json .Image}}'])), arch);
    console.log(`CANARY_SIBLING ${arch} ${siblings[arch]}`);
  }
  assert.notEqual(siblings.amd64, siblings.arm64);
  const target = `${image}:canary-${runID}`;
  cli(['create', '--tag', target, ...Object.values(siblings).map(d => `${image}@${d}`)]);
  const published = digest(cli(['inspect', target, '--format', '{{.Manifest.Digest}}']).trim());
  index(JSON.parse(cli(['inspect', `${image}@${published}`, '--raw'])), siblings);
  console.log(`BUILD_PUBLISH_CANARY_PASS ${target} ${published}`);
}

// Offline negative cases exercise the SAME publish path without network/credentials.
if (process.argv[2] === '--self-test') {
  const siblings = { amd64: `sha256:${'a'.repeat(64)}`, arm64: `sha256:${'b'.repeat(64)}` };
  const published = `sha256:${'c'.repeat(64)}`;
  const image = 'registry.example/owner/repo/kagi-mcp';
  function fixture({ wrongConfig = false, wrongIndex = false, invalidDigest = false, extra = false } = {}) {
    const calls = [];
    const cli = args => {
      calls.push(args);
      if (args[0] === 'create') return '';
      const ref = args[1];
      if (args.at(-1) === '{{.Manifest.Digest}}') {
        if (ref.endsWith('-amd64')) return invalidDigest ? 'invalid' : siblings.amd64;
        if (ref.endsWith('-arm64')) return siblings.arm64;
        return published;
      }
      if (args.at(-1) === '{{json .Image}}') return JSON.stringify({ os: 'linux',
        architecture: ref.endsWith(siblings.amd64) || wrongConfig ? 'amd64' : 'arm64' });
      if (ref.endsWith(published)) {
        const manifests = Object.entries(siblings).map(([arch, d]) => ({
          digest: wrongIndex ? published : d, platform: { os: 'linux', architecture: arch },
        }));
        if (extra) manifests.push(manifests[0]);
        return JSON.stringify({ schemaVersion: 2, mediaType: 'application/vnd.oci.image.index.v1+json', manifests });
      }
      return JSON.stringify({ config: {}, layers: [] });
    };
    return { cli, calls };
  }
  const good = fixture();
  publish(image, '123', good.cli);
  const create = good.calls.find(c => c[0] === 'create');
  assert.deepEqual(create, ['create', '--tag', `${image}:canary-123`,
    `${image}@${siblings.amd64}`, `${image}@${siblings.arm64}`]);
  for (const options of [{ wrongConfig: true }, { invalidDigest: true }]) {
    const bad = fixture(options);
    assert.throws(() => publish(image, '123', bad.cli));
    assert.ok(!bad.calls.some(c => c[0] === 'create'), 'Reject before publication');
  }
  for (const options of [{ wrongIndex: true }, { extra: true }]) {
    assert.throws(() => publish(image, '123', fixture(options).cli));
  }
  assert.throws(() => platform({ os: 'windows', architecture: 'amd64' }, 'amd64'));
  assert.throws(() => platform({ os: 'linux', architecture: 'arm64', variant: 'v7' }, 'arm64'));
  console.log('BUILD_PUBLISH_CANARY_OFFLINE_PASS');
} else {
  publish(process.env.IMAGE, process.env.RUN_ID, args => execFileSync('docker',
    ['buildx', 'imagetools', ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] }));
}
