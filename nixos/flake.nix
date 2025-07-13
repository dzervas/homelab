{
  outputs = { nixpkgs, disko, flake-utils, ... }: let
    machines = {
      gr0 =  { hostIndex = "100"; publicKey = "IL/4BsJxWB+D+k9tAyz3VaQD4F1J6+C1/FXByrUr9Ak="; role = "server"; };
      gr1 =  { hostIndex = "101"; publicKey = "Owhi+vyqYtFrSs9bOj8qnEsEvOiXD1zME41rLUQ2KV8="; };
      srv0 = { hostIndex = "150"; publicKey = "KGm/C81/0PyagQN8V4we8hnVvCLg22NKoUM/Nh3htBw="; };
      fra0 = { hostIndex = "200"; publicKey = "nJLpWuGE+NQA5k1nSAgTeFMpGbyGuT4ZAfi2OzsKjzY="; role = "server"; system = "aarch64-linux"; };
      fra1 = { hostIndex = "201"; publicKey = "gdS1om0jFmLu3omuE+aMwFpW1iMse0wjVEkPgZB67xs="; role = "server"; system = "aarch64-linux"; };
    };

    inherit (import ./mkMachines.nix { inherit disko nixpkgs; }) mkMachines mkShellApp;
    inherit (flake-utils.lib) eachDefaultSystemPassThrough;
    inherit (nixpkgs) lib;
  in {
    # For a fresh install:
    # nixos-anywhere --flake .#local0 --target-host root@<host> --generate-hardware-config nixos-generate-config ./hosts/srv0.nix
    # nixos-anywhere --flake .#local0 --target-host root@<host>
    # For a rebuild:
    # nixos-rebuild switch --flake .#srv0 --target-host root@srv0.lan
    nixosConfigurations = mkMachines machines;

    apps = eachDefaultSystemPassThrough (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      rebuild = name: builtins.concatStringsSep " " [
        "echo -e '\n🔄 Rebuilding ${name}.dzerv.art...\n';"

        "${pkgs.nixos-rebuild-ng}/bin/nixos-rebuild-ng" "switch"
        "--flake" ".#${name}"
        "--no-reexec"
        "--target-host" "${name}.dzerv.art"

        "&& echo -e '🎉 ${name}.dzerv.art build complete!\n'"
      ];
    in {
      # Per-machine app
      ${system} = lib.mapAttrs (name: _config:
        mkShellApp pkgs (rebuild name)
      ) machines // rec {
        all = let
          commands = lib.mapAttrsToList (name: _config: rebuild name) machines;
        in mkShellApp pkgs ''
          #!/bin/bash
          set -euo pipefail
          ${builtins.concatStringsSep "\n" commands}
        '';
        default = all;
      };
    });
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    flake-utils.url = "github:numtide/flake-utils";
  };
}
