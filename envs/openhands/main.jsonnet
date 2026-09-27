local timezone = import 'helpers/timezone.libsonnet';
local lab = import 'labsonnet.libsonnet';

// OpenHands Agent Canvas all-in-one image (frontend + agent-server +
// automation), mirroring the upstream helm/agent-canvas chart which isn't
// published to any helm repo. It has no authentication of its own - keep it
// VPN-only and behind magicentry.
// LLM settings are configured from the UI and persisted in ~/.openhands;
// cliproxyapi (http://cliproxyapi.cliproxyapi.svc:8317/v1) is reachable
// thanks to the 'ai/enable' pod label (see envs/cliproxyapi networkPolicy).
lab.new('openhands', 'ghcr.io/openhands/agent-canvas:1.24.0')
+ lab.withCreateNamespace()
+ lab.withType('StatefulSet')
+ lab.withRunAsUser(10001)  // Image's openhands user
+ lab.withPV('/home/openhands/.openhands', { name: 'state', size: '5Gi' })
+ lab.withPV('/home/openhands/workspace', { name: 'workspace', size: '20Gi' })
+ lab.withVpnHttp(8000, 'agent.vpn.dzerv.art', magicentry={ name: 'OpenHands', realms: 'admin' })
+ lab.withPodLabels({ 'ai/enable': 'true' })
+ lab.withEnv({
  PORT: '8000',
  AGENT_SERVER_PORT: '18000',
  AUTOMATION_PORT: '18001',
  TZ: timezone,
})
