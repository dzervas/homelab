{ pkgs, ... }: {
  boot = {
    # Required by openebs
    kernelModules = ["nvme_tcp" "dm_snapshot"];

    # Why not?
    kernelPackages = pkgs.linuxPackages_hardened;
  };
}
