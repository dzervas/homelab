{ config, lib, modulesPath, ... }: {
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "sd_mod" ];
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
