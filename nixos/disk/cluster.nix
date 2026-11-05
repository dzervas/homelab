# RKE2 node storage (containerd + Longhorn) on a thin pool, shared by the server and agent roles
{ lib, ... }:
{
  disko.devices.lvm_vg.mainpool.lvs = {
    # Due to the thin provisioned root & nix, this lv can be oversized but disko doesn't do that
    # This could be VDO to add compression and dedup but it comes with a performance penalty
    thinpool = {
      size = "99%";
      lvm_type = "thin-pool";
      # Fail writes with ENOSPC when the pool fills instead of queueing them
      # indefinitely. The default `queue_if_no_space` turns pool exhaustion
      # into silent torn/zero-filled writes (\x00) that corrupt data on the
      # Longhorn thinlv below; apps/filesystems can survive honest ENOSPC but
      # not lying writes. See INCIDENT-2026-06-23 (envs/longhorn).
      # lvcreate rejects --errorwhenfull for thin pools; set the creation
      # default instead. Disko interpolates extraArgs as shell text.
      extraArgs = [
        "--config"
        (lib.escapeShellArg "activation { error_when_full = 1 }")
      ];
    };

    containerd = {
      size = "50G";
      lvm_type = "thinlv";
      pool = "thinpool";
      content = {
        type = "filesystem";
        format = "ext4";
        mountpoint = "/var/lib/rancher/rke2/agent/containerd";
        mountOptions = [
          "discard"
          "noatime"
          "nodiratime"
          "nodev"
          "commit=120"
        ];
      };
    };

    longhorn = {
      size = "100%";
      lvm_type = "thinlv";
      pool = "thinpool";
      content = {
        type = "filesystem";
        format = "ext4";
        mountpoint = "/var/lib/longhorn-mainpool";
        extraArgs = [
          "-m"
          "0"
          "-L"
          "longhorn-v1"
        ];
        mountOptions = [
          "discard"
          "noatime"
          "nodev"
          "nosuid"
          "errors=remount-ro"
        ];
      };
    };
  };
}

# To migrate to the new thin lv:
# lvremove mainpool/storage
# lvcreate -l 99%FREE -T mainpool/thinpool
