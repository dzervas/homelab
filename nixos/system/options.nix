{ lib, ... }: with lib; {
  options.setup = {
    provider = mkOption {
      type = types.str;
      default = "homelab";
      description = "Provider of the node (e.g., 'grnet', 'oracle', 'homelab')";
    };
    isEFI = mkOption {
      type = types.bool;
      default = true;
      description = "Whether the system needs an EFI partition (no for QEMU VMs)";
    };
    taints = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Taints to apply to the node, e.g., ['noSchedule', 'noExecute']";
    };
  };
}
