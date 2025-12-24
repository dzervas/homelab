{ config, home-vpn-iface, lib, modulesPath, ... }: {
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

  # Home Assistant whisper server
  virtualisation.oci-containers.containers = {
    faster-whisper = {
      image = "docker.io/rhasspy/wyoming-whisper";
	    pull = "always";
			autoRemoveOnStop = false;

			cmd = [
				"--model" "base.en"
				"--language" "en"
			];

			volumes = [ "/builder/whisper:/data" ];
			ports = [ "10300:10300" ];
    };
  };
	virtualisation.podman = {
		autoPrune.enable = true;
		defaultNetwork.settings.dns_enabled = true;
	};
  networking.firewall.interfaces.${home-vpn-iface}.allowedTCPPorts = [ 10300 ];
  networking.firewall.interfaces.podman0.allowedTCPPorts = [ 10300 ];
}
