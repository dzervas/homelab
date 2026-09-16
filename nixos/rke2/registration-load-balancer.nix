{
  lib,
  machines,
  node-vpn-prefix,
  role,
  ...
}:
let
  serverMachines = lib.filterAttrs (_: machine: (machine.role or "agent") == "server") machines;
  registrationServers = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: machine:
      "    server ${name} ${node-vpn-prefix}.${machine.hostIndex}:9345 check check-ssl verify none"
    ) serverMachines
  );
in
{
  services.haproxy = {
    enable = true;
    config = ''
            global
              log stdout format raw local0

            defaults
              log global
              mode tcp
              timeout connect 5s
              timeout client 1m
              timeout server 1m

            frontend rke2-registration
              bind 127.0.0.1:9346
              default_backend rke2-registration-servers

            backend rke2-registration-servers
              option tcp-check
              default-server inter 2s fall 2 rise 2
      ${registrationServers}
    '';
  };

  systemd.services."rke2-${role}" = {
    after = [ "haproxy.service" ];
    wants = [ "haproxy.service" ];
  };
}
