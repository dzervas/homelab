{ disko, nixpkgs }: rec {
  mkMachine = {
    hostName,
    hostIndex,
    hostIP,
    machines ? {},
    nodes ? {},
    role ? "agent",
    system ? "x86_64-linux",
    ...
  }: nixpkgs.lib.nixosSystem {
    inherit system;

    specialArgs = {
      inherit hostName hostIndex machines nodes role hostIP;

      node-vpn-prefix = "10.20.30";
      node-vpn-iface = "wg0";

      home-vpn-prefix = "100.100.50";
    };

    modules = [
      { nixpkgs.overlays = [ (import ./overlays) ]; }
      disko.nixosModules.disko

      ./rke2
      ./system
      ./hosts/${hostName}.nix
    ];
  };

  # `nodes` exposes every evaluated machine to the others (e.g. to read a peer's setup.provider)
  mkMachines = machines: let
    nodes = builtins.mapAttrs
      (name: machine: mkMachine (machine // { inherit machines nodes; hostName = name; }))
      machines;
  in nodes;

  mkNode = self: nixpkgs: deploy-rs: name: machine: let
    system = if builtins.hasAttr "system" machine then builtins.getAttr "system" machine else "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
    deployPkgs = import nixpkgs {
      inherit system;
      overlays = [
        deploy-rs.overlays.default
        (_self: super: { deploy-rs = { inherit (pkgs) deploy-rs; lib = super.deploy-rs.lib; }; })
      ];
    };
  in {
      hostname = "${name}.dzerv.art";
      profiles.system = {
        user = "root";
        sshUser = "root";
        path = deployPkgs.deploy-rs.lib.activate.nixos self.nixosConfigurations.${name};

        # Big updates sometimes time out
        activationTimeout = 600;
        confirmTimeout = 120;
      };
  };
}
