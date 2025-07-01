{ config, lib, ... }: {
  disko.devices.disk.root = {
    # `device` is defined in the host configuration
    type = "disk";

    content = {
      # type = if config.setup.isEFI then "gpt" else "msdos";
      type = "gpt";

      partitions = {
        ESP = lib.mkIf config.setup.isEFI {
          size = "1G";
          type = "EF00";
          priority = 1; # Needs to be first partition
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [
              "uid=0"
              "gid=0"
              "umask=077"
              "fmask=077"
              "dmask=077"
            ];
          };
        };

        boot = lib.mkIf (!config.setup.isEFI) {
          size = "1M";
          type = "EF02"; # for grub MBR
          priority = 1; # Needs to be first partition
        };

        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
