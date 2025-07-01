{ config, ... }: {
  disko.devices.disk.root = {
    # `device` is defined in the host configuration
    type = "disk";

    content = {
      # type = if config.setup.isEFI then "gpt" else "msdos";
      type = "gpt";

      partitions = if config.setup.isEFI then {
        ESP = {
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
      } else {
        boot = {
          size = "1M";
          type = "EF02"; # for grub MBR
        };
      } // {
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ]; # Override existing partition
            subvolumes = {
              "/" = { mountpoint = "/"; };
              "/nix" = {
                mountpoint = "/nix";
                mountOptions = [
                  "compress=zstd:5"
                  "noatime" # Don't keep access times
                  "nodiratime" # Ditto for directories
                  "discard=async" # Asynchronously discard old files with SSD TRIM operations
                ];
              };
              "/ceph" = {
                mountpoint = "/ceph";
                mountOptions = [
                  "compress=no"
                  "noatime" # Don't keep access times
                  "nodiratime" # Ditto for directories
                  "discard=async" # Asynchronously discard old files with SSD TRIM operations
                ];
              };
              "/ceph-zstd" = {
                mountpoint = "/ceph-zstd";
                mountOptions = [
                  "compress=zstd:3"
                  "noatime" # Don't keep access times
                  "nodiratime" # Ditto for directories
                  "discard=async" # Asynchronously discard old files with SSD TRIM operations
                ];
              };
            };
          };
        };
      };
    };
  };
}
