{ pkgs, ... }:
{
  languages.jsonnet.enable = true;
  packages = with pkgs; [
    tanka
    jsonnet-bundler
    deploy-rs
  ];

  env = {
    TANKA_PAGER = "${pkgs.bat}/bin/bat -p -l yaml";
  };
}
