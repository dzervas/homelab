#!/usr/bin/env bash
set -euo pipefail
nixos-rebuild switch --no-reexec --flake ./nixos --target-host root@srv0.lan
nixos-rebuild switch --no-reexec --flake ./nixos --target-host gr1.dzerv.art
nixos-rebuild switch --no-reexec --flake ./nixos --target-host frankfurt0.dzerv.art --build-host frankfurt0.dzerv.art
nixos-rebuild switch --no-reexec --flake ./nixos --target-host frankfurt1.dzerv.art --build-host frankfurt1.dzerv.art
