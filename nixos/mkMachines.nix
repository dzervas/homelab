{ disko, nixpkgs }: rec {
    mkMachine = {
      hostName,
      hostIndex,
      machines ? {},
      role ? "agent",
      system ? "x86_64-linux",
      publicKey ? null,
    }: nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit hostName hostIndex machines role;

        node-vpn-prefix = "10.20.30";
        node-vpn-iface = "wg0";

        home-vpn-prefix = "10.11.12";
        home-vpn-iface = "ztrfyoirbv";
      };
      modules = [
        disko.nixosModules.disko

        ./k3s
        ./system
        ./hosts/${hostName}.nix
      ];
    };

    mkMachines = machines: builtins.mapAttrs
      (name: machine: mkMachine (machine // { inherit machines; hostName = name; }))
      machines;
}
