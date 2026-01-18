{ pkgs, ... }: {
	overlays = [
		# TODO: Update command
    (final: prev: {
      opencode = prev.opencode.overrideAttrs (oldAttrs: rec {
	      version = "1.1.23";
				src = final.fetchFromGitHub {
			    owner = "anomalyco";
			    repo = "opencode";
			    tag = "v${version}";
			    hash = "sha256-cvz4HO5vNwA3zWx7zdVfs59Z7vD/00+MMCDbLU5WKpM=";
			  };
				node_modules = oldAttrs.node_modules.overrideAttrs (oldNMAttrs: {
					inherit version src;
					outputHash = "sha256-WZauk7tIq+zpzsnmRpCSBQV3DChVUtDxd8kf2di13Jk=";
				});
      });
    })
  ];

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
    curl
  ];

  containers."opencode" = {
    name = "opencode";
    registry = "docker://ghcr.io/dzervas/";
    startupCommand = "${pkgs.opencode}/bin/opencode web --hostname 0.0.0.0 --port 4096 --cors opencode.vpn.dzerv.art";
  };
}
