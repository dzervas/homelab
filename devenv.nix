{ pkgs, ... }: {
  languages.jsonnet.enable = true;
  packages = with pkgs; [
    tanka
    jsonnet-bundler
  ];

  env = {
    TANKA_PAGER="${pkgs.bat}/bin/bat -p -l yaml";
  };
}
