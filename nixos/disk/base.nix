# RKE2 node base layout: an LVM `mainpool` after the ESP, holding the f2fs root.
# disk/server.nix and disk/agent.nix set the root size.
_: {
  imports = [ ./esp.nix ];

  disko.devices = {
    disk.root.content.partitions.rootpv = {
      size = "100%";
      content = {
        type = "lvm_pv";
        vg = "mainpool";
      };
    };

    lvm_vg.mainpool = {
      type = "lvm_vg";
      lvs.root = {
        # `size` is defined in disk/<role>.nix
        priority = 1; # Needs to happen before any percentage sized lvs
        content = {
          type = "filesystem";
          format = "f2fs";
          mountpoint = "/";
          extraArgs = [
            "-O"
            "extra_attr,inode_checksum,sb_checksum,compression"
          ];
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
    };
  };
}
