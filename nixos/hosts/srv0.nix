# 2026-10-14: wg0 to gr0/fra1 died while fra0 kept working. The carrier CGNAT
# (behind the TRB501 modem) dropped replies to srv0's mapping; the modem's
# /proc/net/nf_conntrack showed those flows [UNREPLIED]. Moving srv0 to listen
# port 51821 and back to 51820 got a fresh carrier mapping and fixed it. While on
# 51821, srv0's own firewall/Cilium path dropped the replies too, since only
# 51820 is opened. Recheck this if it recurs.
{
  config,
  lib,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usb_storage"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-intel" ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  disko.devices = {
    disk = {
      # Root 256GB NVMe pre-installed
      root.device = "/dev/nvme0n1";

      # SATA III Transcend TS2TSSD452K 2TB from Vinted
      ssd = {
        type = "disk";
        device = "/dev/sda";

        content = {
          type = "gpt";

          partitions.ssdpv = {
            size = "100%";
            content = {
              type = "lvm_pv";
              vg = "ssdpool";
            };
          };
        };
      };
    };
    # lvm_vg.mainpool.lvs.containerd = {
    #   size = "50G";
    #   lvm_type = "thinlv";
    #   pool = "thinpool";
    #   content = {
    #     type = "filesystem";
    #     format = "ext4";
    #     mountpoint = "/var/lib/rancher/rke2/agent/containerd";
    #     mountOptions = [
    #       "discard"
    #       "noatime"
    #       "nodiratime"
    #       "nodev"
    #       "nosuid"
    #       "commit=120"
    #     ];
    #   };
    # };
    lvm_vg.ssdpool = {
      type = "lvm_vg";
      lvs = {
        builder = {
          size = "250G";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/builder";
            mountOptions = [
              "discard"
              "noatime"
              "nodiratime"
              "nodev"
              "nosuid"
            ];
          };
        };

        storage = {
          size = "100%";
        };
      };
    };
  };
}
