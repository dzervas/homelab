{
  outputs = { nixpkgs, disko, ... }: let
    mkMachine = {
      hostName,
      hostIndex,
      role ? "agent",
      provider ? "home",
      system ? "x86_64-linux",
    }: nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit hostName hostIndex provider role;
        node-vpn-prefix = "10.20.30";
      };
      modules = [
        disko.nixosModules.disko

        ./boot.nix
        ./disk.nix
        ./k3s.nix
        ./network.nix
        ./nix.nix
        ./system.nix
        ./hosts/${hostName}.nix

        { networking.hostName = hostName; }
      ];
    };
  in {
    # For a fresh install:
    # nixos-anywhere --flake .#local0 --target-host root@<host> --generate-hardware-config nixos-generate-config ./srv0.nix
    # nixos-anywhere --flake .#local0 --target-host root@<host>
    # For a rebuild:
    # nixos-rebuild switch --flake .#srv0 --target-host root@srv0.lan
    nixosConfigurations.srv0 = mkMachine { hostName = "srv0"; hostIndex = "150"; };
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };
}
