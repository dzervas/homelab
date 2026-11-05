_: {
  imports = [
    ./base.nix
    ./cluster.nix
  ];

  disko.devices.lvm_vg.mainpool.lvs.root.size = "30G";
}
