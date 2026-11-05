# Single XFS root over the rest of the disk. Weights are large, written once and
# streamed sequentially, so no LVM, CoW or compression in the read path.
_: {
  imports = [ ./esp.nix ];

  disko.devices.disk.root.content.partitions.root = {
    size = "100%";
    content = {
      type = "filesystem";
      format = "xfs";
      mountpoint = "/";
      extraArgs = [
        # Size the AGs and the log for 32 concurrent writers (16C/32T) so parallel
        # writers (nix builds, model downloads) don't contend on AG/log locks.
        # mkfs picks this on its own for SSDs, but only if it detects one at
        # format time - pin it so the result doesn't depend on that detection
        "-d"
        "concurrency=32"
        "-l"
        "concurrency=32"
      ];
      mountOptions = [
        "noatime"
        "logbsize=256k" # Bigger in-memory log buffers for metadata-heavy writes (nix store)
        # No `discard`: the weekly fstrim timer (NixOS default) trims instead
      ];
    };
  };
}
