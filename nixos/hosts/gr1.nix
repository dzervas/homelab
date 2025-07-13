_: {
  imports = [ ./gr0.nix ];

  setup.taints = [
    "longhorn=true:NoSchedule"
    "storage-only=true:NoSchedule"
  ];
}
