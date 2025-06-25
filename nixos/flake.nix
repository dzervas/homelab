{
  outputs = { nixpkgs, disko, ... }: {
    # For a fresh install:
    # nixos-anywhere --flake .#local0 --target-host root@<host> --generate-hardware-config nixos-generate-config ./srv0.nix
    # nixos-anywhere --flake .#local0 --target-host root@<host>
    # For a rebuild:
    # nixos-rebuild switch --flake .#srv0 --target-host root@srv0.lan
    nixosConfigurations.srv0 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko

        ./boot.nix
        ./disk.nix
        ./k3s.nix
        ./network.nix
        ./nix.nix
        ./system.nix
        ./srv0.nix

        { networking.hostName = "srv0"; }
      ];
    };
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };
}
