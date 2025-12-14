{ config, lib, role, ... }: {
  disko.devices = {
    disk.root = {
      # `device` is defined in the host configuration
      type = "disk";

      content = {
        # type = if config.setup.isEFI then "gpt" else "msdos";
        type = "gpt";

        partitions = {
          boot = lib.mkIf (!config.setup.isEFI) {
            size = "1M";
            type = "EF02"; # for grub MBR
          };

          # Grub doesn't support f2fs so EFI ESP is used for the kernel + initrd
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

          rootpv = {
            size = "100%";
            content = {
              type = "lvm_pv";
              vg = "mainpool";
            };
          };
        };
      };
    };
    lvm_vg.mainpool = {
      type = "lvm_vg";
      lvs = {
        root = {
          size = if role == "server" then "50G" else "30G";
          content = {
            type = "filesystem";
            format = "f2fs";
            mountpoint = "/";
            extraArgs = [ "-O" "extra_attr,inode_checksum,sb_checksum,compression" ];
            mountOptions = [
              "lazytime" # Update a/mtimes asynchronusely
              "nodiscard"

              # Compression
              "compress_algorithm=zstd:6"
              "compress_chksum" # Verify compressed blocks with checksu

              # Better garbage collection
              "atgc"
              "gc_merge"
            ];
          };
        };

        # Due to the thin provisioned root & nix, this lv can be oversized but disko doesn't do that
        # This could be VDO to add compression and dedup but it comes with a performance penalty
        thinpool = {
          size = "99%";
          lvm_type = "thin-pool";
        };
      };
    };
  };
}
