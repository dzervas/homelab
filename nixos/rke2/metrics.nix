{
	config,
  hostIndex,
  node-vpn-iface,
  node-vpn-prefix,
  ...
}: let
  listenAddress = "${node-vpn-prefix}.${hostIndex}";
in {
  services.prometheus.exporters = {
    node = {
	    inherit listenAddress;
	    enable = true;
			openFirewall = true;
			firewallRules = ''iifname ${node-vpn-iface} tcp dport ${toString config.services.prometheus.exporters.node.port} counter accept'';
    };
    smartctl = {
	    inherit listenAddress;
	    enable = true;
			openFirewall = true;
			firewallRules = ''iifname ${node-vpn-iface} tcp dport ${toString config.services.prometheus.exporters.smartctl.port} counter accept'';
    };
  };
}
