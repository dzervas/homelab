// Runner v13.2 proxy/auth sources: https://code.forgejo.org/forgejo/runner/src/tag/v13.2.0/act/cacheproxy/handler.go
{
  secretName: 'forgejo-runner-cache-signing',
  secretKey: 'cache-secret',
  secretPath: '/run/secrets/forgejo-cache',
  proxyPort: 4002,
  externalServer: 'https://forgejo-cache.vpn.dzerv.art',

  // Enable only behind the live cache gate; project the key into Runner, never DinD or jobs
  config: {
    enabled: true,
    external_server: $.externalServer,
    secret_url: 'file:%s/%s' % [$.secretPath, $.secretKey],
    // Each proxy owns a process-local run map; a load-balanced runner Service is incorrect
    host: '__RUNNER_POD_IP__',
    proxy_port: $.proxyPort,
  },

  // Merge into runner.envs only when cache is enabled; the same substitution as cache.host
  // Exposes only the owning Pod IP to jobs so the live gate can reject load-balanced proxies
  runnerEnvs: { FORGEJO_RUNNER_POD_IP: $.config.host },

  // YAML does not expand environment variables; generate a private Runner-only config
  // POD_IP comes from Downward API; /runner-config must not be mounted into DinD
  prepareConfig: |||
    umask 077
    : "${POD_IP:?Runner Pod IP is missing}"
    case "$POD_IP" in
      *[!0-9a-fA-F:.]*) echo 'Invalid Runner Pod IP' >&2; exit 1 ;;
    esac
    sed "s/__RUNNER_POD_IP__/$POD_IP/g" /config/config.yaml > /runner-config/config.yaml
  |||,
}
