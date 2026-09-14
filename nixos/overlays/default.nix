_final: prev: {
  sysbox-mgr = prev.callPackage ./sysbox-mgr.nix { };
  sysbox-fs = prev.callPackage ./sysbox-fs.nix { };
  sysbox-runc = prev.callPackage ./sysbox-runc.nix { };
}
