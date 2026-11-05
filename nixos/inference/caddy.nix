{ config, ... }:
{
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

      # TODO: Translate the client API token to the llama-swap one
      reverse_proxy ${config.services.llama-swap.listenAddress}:${toString config.services.llama-swap.port}
    '';
  };
}
