{
  hostIndex,
  node-vpn-prefix,
  ...
}:
{
  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "${node-vpn-prefix}.${hostIndex}";
  };
}
