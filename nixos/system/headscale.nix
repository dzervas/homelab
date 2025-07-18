{ config, hostName, hostIndex, node-vpn-prefix, home-vpn-prefix, ... }:let
  port = 9999;
in {
  services.headscale = {
    inherit port;

    enable = hostName == "gr0";
    address = "0.0.0.0";

    settings = let
      domain = "vpn.${config.networking.domain}";
    in {
      # TODO: Manage this with exgternal-dns
      server_url = "https://${domain}:${toString port}";
      acme_email = "dzervas@dzervas.gr";
      disable_check_updates = true;

      tls_cert_path = "/var/lib/headscale/${domain}-cert.pem";
      tls_key_path = "/var/lib/headscale/${domain}-key.pem";

      prefixes.v4 = "${home-vpn-prefix}.0/24";

      dns = {
        base_domain = config.networking.domain;
        search_domains = [config.networking.domain];
      };

      derp.server = {
        # enabled = true;
        region_code = "homelab";
        region_name = "DZervArt HomeLab";
      };

      metrics_listen_addr = "${node-vpn-prefix}.${hostIndex}:9090";
    };
  };

  networking.firewall.allowedTCPPorts = if config.services.headscale.enable then
    [ config.services.headscale.port ]
  else [];

  services.cron.systemCronJobs = let
    kubectl = "/var/lib/rancher/rke2/bin/kubectl";
    namespace = "cert-manager";
    secret = "headscale-vpn-certificate";
  in if config.services.headscale.enable then [
    "@weekly ${kubectl} get secrets -n ${namespace} ${secret} -o go-template='{{index .data \"tls.crt\" | base64decode}}' > ${config.services.headscale.settings.tls_cert_path}"
    "@weekly ${kubectl} get secrets -n ${namespace} ${secret} -o go-template='{{index .data \"tls.key\" | base64decode}}' > ${config.services.headscale.settings.tls_key_path}"
  ] else [];
}
