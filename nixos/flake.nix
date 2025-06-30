{
  outputs = { nixpkgs, disko, ... }: let
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
      };
      modules = [
        disko.nixosModules.disko

        ./boot.nix
        ./disk.nix
        ./k3s.nix
        ./network.nix
        ./nix.nix
        ./options.nix
        ./system.nix
        ./hosts/${hostName}.nix
      ];
    };
    mkMachines = machines: builtins.mapAttrs
      (name: machine: mkMachine (machine // { inherit machines; hostName = name; }))
      machines;
  in {
    # For a fresh install:
    # nixos-anywhere --flake .#local0 --target-host root@<host> --generate-hardware-config nixos-generate-config ./hosts/srv0.nix
    # nixos-anywhere --flake .#local0 --target-host root@<host>
    # For a rebuild:
    # nixos-rebuild switch --flake .#srv0 --target-host root@srv0.lan
    nixosConfigurations = mkMachines {
      gr0 =        { hostIndex = "100"; publicKey = "ZUiMnTjo3wU1PoVXYC2VkHk6hnHFMFF74C1H1dS+cjI="; role = "server"; };
      gr1 =        { hostIndex = "101"; publicKey = "GO6R9Jh5Q36n2hmhtqqn2ITZqG/MzEexEfSLjmi9lXQ="; };
      srv0 =       { hostIndex = "150"; publicKey = "KGm/C81/0PyagQN8V4we8hnVvCLg22NKoUM/Nh3htBw="; };
      frankfurt0 = { hostIndex = "200"; publicKey = "kPRT5uFcM/BQBNSrCbcqg9lGwgJZQeiPnEn3lkZYSwQ="; role = "server"; system = "aarch64-linux"; };
      frankfurt1 = { hostIndex = "201"; publicKey = "1KjZhHkeQiA+32bwhLt86ZmacI8Io5xqnsi15GeBOXY="; role = "server"; system = "aarch64-linux"; };
    };
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };
}
