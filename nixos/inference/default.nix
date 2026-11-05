{ pkgs, ... }: {
  imports = [
    ./caddy.nix
    ./llama-swap.nix
  ];

  environment.systemPackages = with pkgs; [
    python3Packages.huggingface-hub # hf cli
    amdgpu_top
  ];
}
