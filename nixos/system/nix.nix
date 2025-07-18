{ pkgs, ... }: {
  nixpkgs.config.allowUnfree = true;

  nix = {
    package = pkgs.nix;
    extraOptions = ''
      # Garbage collect when free space is less than 32GB
      min-free = ${toString (32 * 1024 * 1024 * 1024)}
    '';
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      warn-dirty = false;
      max-jobs = "auto";
      cores = 0;  # Use all available cores
      build-cores = 0;
      http-connections = 50; # Parallel downloads
      auto-optimise-store = true;
      download-buffer-size = 524288000; # 500MB buffer size

      # Keep more derivations in memory
      keep-derivations = true;
      keep-outputs = true;

      # Only allow wheel users to run nix
      allowed-users = [ "@wheel" ];

      # Binary caches
      substituters = [
        "https://cache.nixos.org/"
        "https://nix-community.cachix.org"
      ];

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
    gc = {
      automatic = true;
      options = "--delete-older-than 7d";
      dates = "08:00:00";
    };
    optimise = {
      automatic = true;
      dates = ["09:00:00"];
    };
  };
}
