# hipfire: AMD-native LLM engine (Rust + HIP) with the Strix Halo XDNA2 NPU prefill route.
# Built with upstream's own nix/package.nix and nix/kernels.nix, against this flake's nixpkgs
# (ROCm 7.2.3: upstream's warning about ROCm 6.4.3 segfaulting on gfx1151 doesn't apply).
{
  callPackage,
  fetchFromGitHub,
  # Strix Halo / Gorgon Halo; upstream packages precompiled kernels for these, others JIT-compile
  gpuTargets ? [ "gfx1151" ],
}:
let
  version = "0.4.5";
  src = fetchFromGitHub {
    owner = "warpfront";
    repo = "hipfire";
    tag = "v${version}";
    hash = "sha256-j7XXAGQzJ02EIMFEEWyR4WnPMRFPy/WpM84AHDZLSW8=";
  };
  cargoLockFile = "${src}/Cargo.lock";

  kernels = callPackage "${src}/nix/kernels.nix" { inherit src cargoLockFile gpuTargets; };
in
callPackage "${src}/nix/package.nix" {
  inherit src cargoLockFile kernels;
  rocmSupport = true;
}
