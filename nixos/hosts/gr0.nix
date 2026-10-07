# OPEN (2026-10-07): etcd on gr0 stalls on fsync, so kube-apiserver-gr0's liveness
# probe fails on `[-]etcd failed` and the kubelet restarts it (15 restarts since
# 2026-09-17, each paired with gr0 going NotReady).
# - etcd-gr0 logged 1.1-6.4s `slow fdatasync` (expected <10ms) and ~7.5k slow
#   requests in 3h, vs. 24/3 on fra0/fra1, with no slow syncs there.
# - Node isn't resource-starved (8 CPU ~77% idle, 0.1% steal, 55% mem free).
#   I/O stall PSI jumps from ~1% to 25-58% when incidents start.
# - Suspect: etcd shares the disk with Longhorn replicas / postgres shared-1.
# - Still to check: `journalctl -k` for virtio/hung-task errors, `iostat -x 1`
#   during a stall, and what else writes to etcd's disk. Likely fix: give etcd
#   its own disk, or move I/O-heavy workloads off gr0.
{ modulesPath, ... }: {
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "floppy" "sr_mod" "virtio_blk" ];
  nixpkgs.hostPlatform = "x86_64-linux";

  disko.devices.disk.root.device = "/dev/vda";

  setup = {
    provider = "grnet";
    isEFI = false; # No EFI partition required in QEMU
  };
}
