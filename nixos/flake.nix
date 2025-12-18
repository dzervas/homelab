{
  outputs = { self, nixpkgs, deploy-rs, disko, ... }: let
    machines = {
      gr0 =  { hostIndex = "100"; publicKey = "IL/4BsJxWB+D+k9tAyz3VaQD4F1J6+C1/FXByrUr9Ak="; role = "server"; };
      gr1 =  { hostIndex = "101"; publicKey = "Owhi+vyqYtFrSs9bOj8qnEsEvOiXD1zME41rLUQ2KV8="; };
      srv0 = { hostIndex = "150"; publicKey = "KGm/C81/0PyagQN8V4we8hnVvCLg22NKoUM/Nh3htBw="; };
      fra0 = { hostIndex = "200"; publicKey = "nJLpWuGE+NQA5k1nSAgTeFMpGbyGuT4ZAfi2OzsKjzY="; role = "server"; system = "aarch64-linux"; };
      fra1 = { hostIndex = "201"; publicKey = "gdS1om0jFmLu3omuE+aMwFpW1iMse0wjVEkPgZB67xs="; role = "server"; system = "aarch64-linux"; };
    };

    inherit (import ./mkMachines.nix { inherit disko nixpkgs; }) mkMachines mkNode;
  in {
    # For a fresh install:
    # nixos-anywhere --flake .#local0 --target-host root@<host> --generate-hardware-config nixos-generate-config ./hosts/srv0.nix
    # nixos-anywhere --flake .#local0 --target-host root@<host>
    # For a rebuild:
    # nixos-rebuild switch --flake .#srv0 --target-host root@srv0.lan
    nixosConfigurations = mkMachines machines;

    # deploy-rs stuff
    deploy.nodes = (builtins.mapAttrs (name: machine: mkNode self nixpkgs deploy-rs name machine) machines);
    checks = builtins.mapAttrs (_system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    deploy-rs.url = "github:serokell/deploy-rs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };
}
