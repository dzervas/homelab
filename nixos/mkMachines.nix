{ disko, nixpkgs }: rec {
  mkMachine = {
    hostName,
    hostIndex,
    machines ? {},
    role ? "agent",
    system ? "x86_64-linux",
    ...
  }: nixpkgs.lib.nixosSystem {
    inherit system;

    specialArgs = {
      inherit hostName hostIndex machines role;

      node-vpn-prefix = "10.20.30";
      node-vpn-iface = "wg0";

      home-vpn-prefix = "100.100.50";
      home-vpn-iface = "tailscale0";
    };

    modules = [
      disko.nixosModules.disko

      ./rke2
      ./system
      ./hosts/${hostName}.nix
    ];
  };

  mkMachines = machines: builtins.mapAttrs
    (name: machine: mkMachine (machine // { inherit machines; hostName = name; }))
    machines;

  mkNode = deploy-rs: self: name: machine: let
    system = if builtins.hasAttr "system" machine then builtins.getAttr "system" machine else "x86_64-linux";
  in {
      hostname = "${name}.dzerv.art";
      profiles.system = {
        user = "root";
        sshUser = "root";
        path = deploy-rs.lib.${system}.activate.nixos self.nixosConfigurations.${name};
      };
  };
}
