_: {
  services.caddy = {
    enable = true;
    openFirewall = true; # 80 (HTTP-01 + redirect), 443/tcp and 443/udp (HTTP/3)
    email = "dzervas+homelab@dzervas.gr";

    # Access logs only (vhost logFormat default: /var/log/caddy/access-<host>.log).
    # Caddy never logs request/response bodies and redacts the Authorization,
    # Cookie and Set-Cookie headers unless `log_credentials` is set - never set it.
    virtualHosts."ai.dzerv.art".extraConfig = ''
      tls {
        issuer acme {
          dir https://acme-v02.api.letsencrypt.org/directory
          disable_tlsalpn_challenge
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

      # TODO: Translate the client API token to the llama-swap one
      handle @models {
        reverse_proxy 127.0.0.1:8080 # llama-swap.nix
      }
      handle @inference {
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
