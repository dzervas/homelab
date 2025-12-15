{ pkgs, ... }:
{
  languages.jsonnet.enable = true;
  packages = with pkgs; [
    tanka
    jsonnet-bundler
    deploy-rs

    # pv-migrate
    yq-go
    pv-migrate
  ];

  env = {
    TANKA_PAGER = "${pkgs.bat}/bin/bat -p -l yaml";
  };
}
