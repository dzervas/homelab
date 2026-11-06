{ lib, ... }: let
  # One key per client, so a single one can be revoked. Each reads LLM0_KEY_<NAME> from
  # environmentFile (a 32-byte hex key: openssl rand -hex 32); changing it needs a caddy restart,
  # since {env.*} is read from the process environment
  apiKeyClients = [
    "dzervas"
    "pol"
  ];
  apiKeys = map (client: "{env.API_KEY_${lib.toUpper client}}") apiKeyClients;
in {
  services.caddy = {
    enable = true;
    openFirewall = true; # 80 (redirect, LAN only), 443/tcp and 443/udp (HTTP/3)
    # Not in the nix store; root-only, read by systemd before caddy drops privileges
    environmentFile = "/var/lib/caddy/api-keys.env";
    email = "dzervas+homelab@dzervas.gr";

    # Access logs only (vhost logFormat default: /var/log/caddy/access-<host>.log).
    # Caddy never logs request/response bodies and redacts the Authorization,
    # Cookie and Set-Cookie headers unless `log_credentials` is set - never set it.
    # Reached through Traefik's TLS passthrough (envs/traefik/llm0.libsonnet), which only forwards
    # 443, so the certificate comes from TLS-ALPN-01 rather than HTTP-01
    virtualHosts."llm0.dzerv.art".extraConfig = ''
      tls {
        issuer acme {
          dir https://acme-v02.api.letsencrypt.org/directory
          disable_http_challenge
        }
      }

      # Only the inference routes llama-swap runs its per-model body filters on (setParams in
      # /llama-swap/config.yaml forces the engines' retention flags off). Everything else - llama-swap's
      # UI, /logs (engine output), /api/*, /upstream/* (skips the filters) - stays local.
      @models {
        method GET
        path /v1/models
      }
      @inference {
        method POST
        path /v1/chat/completions /v1/messages /v1/messages/count_tokens /v1/responses
      }

      # The header matcher compares exactly, so an unset key would accept an empty header: fail closed
      @keysMissing expression `${lib.concatMapStringsSep " || " (key: "${key} == ''") apiKeys}`
      # OpenAI clients send Authorization: Bearer, Anthropic ones (/v1/messages) send x-api-key
      # Repeated header lines OR their values; the `not` matches when neither field holds a key
      @unauthorized {
        not {
          ${lib.concatMapStringsSep "\n    " (key: "header Authorization \"Bearer ${key}\"") apiKeys}
        }
        not {
          ${lib.concatMapStringsSep "\n    " (key: "header X-Api-Key ${key}") apiKeys}
        }
      }
      handle @keysMissing {
        respond 503
      }
      handle @unauthorized {
        respond 401
      }

      # llama-swap has no auth of its own; keep the client keys out of it and the engines. Inside the
      # handles, since a top-level request_header runs before the matchers above
      handle @models {
        request_header -Authorization
        request_header -X-Api-Key
        reverse_proxy 127.0.0.1:8080 # llama-swap.nix
      }
      handle @inference {
        request_header -Authorization
        request_header -X-Api-Key
        # llama-swap filters only bodies it sees as JSON, while engines like Maya parse the body
        # regardless. llama-swap 224 also refuses to route a non-JSON body, so this is defense in depth
        # in case that changes.
        request_header Content-Type application/json
        reverse_proxy 127.0.0.1:8080
      }
      handle {
        respond 404
      }
    '';
  };
}
