{ disko, nixpkgs }: rec {
  mkMachine = {
    hostName,
    hostIndex,
    hostIP,
    machines ? {},
    role ? "agent",
    system ? "x86_64-linux",
    ...
  }: nixpkgs.lib.nixosSystem {
    inherit system;

    specialArgs = {
      inherit hostName hostIndex machines role hostIP;

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

  mkNode = self: nixpkgs: deploy-rs: name: machine: let
    system = if builtins.hasAttr "system" machine then builtins.getAttr "system" machine else "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
    deployPkgs = import nixpkgs {
      inherit system;
      overlays = [
        deploy-rs.overlays.default
        (self: super: { deploy-rs = { inherit (pkgs) deploy-rs; lib = super.deploy-rs.lib; }; })
      ];
    };
  in {
      hostname = "${name}.dzerv.art";
      profiles.system = {
        user = "root";
        sshUser = "root";
        path = deployPkgs.deploy-rs.lib.activate.nixos self.nixosConfigurations.${name};
      } // (if name == "gr1" then  {
	      # gr1 is fucking slow...
				gr1.profiles.system = {
		      activationTimeout = 600;
		      confirmTimeout = 120;
        };
      } else {});
  };
}
