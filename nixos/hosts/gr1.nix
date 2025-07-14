_: {
  imports = [ ./gr0.nix ];

  setup.taints = [
    "storage-only=true:NoSchedule"
  ];
}
