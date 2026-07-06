local timezone = import 'helpers/timezone.libsonnet';
local lab = import 'labsonnet.libsonnet';

// Pi Coding Agent (spawned by pi-web) reads custom providers from
// $PI_CODING_AGENT_DIR/models.json - env vars alone can't register a provider,
// but the apiKey supports "$ENV" interpolation, so the sk-dummy token comes
// from CLIPROXYAPI_API_KEY below. cliproxyapi is reachable thanks to the
// 'ai/enable' pod label (see envs/cliproxyapi networkPolicy).
local models = std.manifestJsonEx({
  providers: {
    cliproxyapi: {
      baseUrl: 'http://cliproxyapi.cliproxyapi.svc:8317/v1',
      api: 'openai-completions',
      apiKey: '$CLIPROXYAPI_API_KEY',
      models: [
        { id: 'gpt-5.5', reasoning: true },
        { id: 'claude-opus-4-8', reasoning: true, input: ['text', 'image'] },
        { id: 'claude-sonnet-5', reasoning: true, input: ['text', 'image'] },
        { id: 'claude-fable-5', reasoning: true, input: ['text', 'image'] },
      ],
    },
  },
}, '  ');

// pi-web has no container image, so run the adhoc oneliner installer on a
// stock node image. Containers have no user-service manager, so the
// installer's `pi-web install` step fails (ignored) - run the daemon and
// server directly instead.
local install = |||
  curl -fsSL https://raw.githubusercontent.com/jmfederico/pi-web/main/install.sh | sh || true
  mkdir -p /data/.pi/agent
  cat > /data/.pi/agent/models.json <<'EOF'
  %s
  EOF
  pi-web-sessiond &
  exec pi-web-server
||| % models;

lab.new('pi-web', 'node:22')
+ lab.withCreateNamespace()
+ lab.withType('StatefulSet')
+ lab.withCommand(['sh', '-c', install])
+ lab.withPV('/data', { name: 'data', size: '10Gi' })
+ lab.withVpnHttp(8504, 'pi.vpn.dzerv.art')
+ lab.withPodLabels({ 'ai/enable': 'true' })
+ lab.withEnv({
  HOME: '/data',
  npm_config_prefix: '/data/.npm-global',
  PATH: '/data/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
  PI_WEB_HOST: '0.0.0.0',
  PI_WEB_PORT: '8504',
  PI_WEB_ALLOWED_HOSTS: 'pi.vpn.dzerv.art',
  PI_WEB_DATA_DIR: '/data/.pi-web',
  PI_CODING_AGENT_DIR: '/data/.pi/agent',
  XDG_CONFIG_HOME: '/data/.config',
  CLIPROXYAPI_API_KEY: 'sk-dummy',
  TZ: timezone,
})
