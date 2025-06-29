_: {
  disko.devices = {
    # Root 256GB NVMe pre-installed
    disk.root = {
      device = "/dev/nvme0n1";
      type = "disk";

      content = {
        type = "gpt";

        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            priority = 1; # Needs to be first partition
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };

          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ]; # Override existing partition
              subvolumes = {
                "/" = { mountpoint = "/"; };
                "/nix".mountOptions = [
                  "compress=zstd:5"
                  "noatime" # Don't keep access times
                  "nodiratime" # Ditto for directories
                  "discard=async" # Asynchronously discard old files with SSD TRIM operations
                ];
                "/ceph".mountOptions = [
                  "compress=no"
                  "noatime" # Don't keep access times
                  "nodiratime" # Ditto for directories
                  "discard=async" # Asynchronously discard old files with SSD TRIM operations
                ];
                "/ceph-zstd".mountOptions = [
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
