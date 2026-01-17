{ pkgs, ... }: {
  languages = {
    rust.enable = true;
    python.enable = true;
    javascript = {
      enable = true;
      npm.enable = true;
      yarn.enable = true;
      bun.enable = true;
      pnpm.enable = true;
    };
  };

  packages = with pkgs; [
    opencode
    ripgrep
    fd
  ];

  containers."opencode" = {
    name = "opencode";
    registry = "docker://ghcr.io/dzervas/";

    copyToRoot = [];
    startupCommand = "${pkgs.opencode}/bin/opencode web";
  };
}
