{
  hostIndex,
  node-vpn-prefix,
  ...
}: let
  listenAddress = "${node-vpn-prefix}.${hostIndex}";
in {
  services.prometheus.exporters = {
    node = { enable = true; inherit listenAddress; };
    smartctl = { enable = true; inherit listenAddress; };
  };
}
