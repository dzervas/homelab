{
  hostName,
  lib,
  home-vpn-prefix,
  node-vpn-prefix,
  ...
}:
{
  # Use predictable interface names starting with eth0
  boot.kernelParams = [ "net.ifnames=0" ];

  networking = {
    inherit hostName;
    useDHCP = lib.mkDefault true;
    domain = "dzerv.art";

    dhcpcd.denyInterfaces = [
      "lo"
      "cali*"
      "podman*"
      "veth*"
    ];

    firewall.enable = true;

    # Cilium is NOT compatible with nftables!
    nftables.enable = true;
  };

  services.fail2ban = {
    enable = true;
    ignoreIP = [
      "127.0.0.1/8"
      "${home-vpn-prefix}.0/24"
      "${node-vpn-prefix}.0/24"
    ];
  };

}
