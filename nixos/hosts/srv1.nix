{ config, lib, pkgs, ... }:
let
  # Build the disk in an x86_64 VM; emulate ARM only for installation commands.
  imagePkgs = import pkgs.path { system = "x86_64-linux"; };
  firmware = "${pkgs.raspberrypifw}/share/raspberrypi/boot";
  configTxt = pkgs.writeText "srv1-config.txt" ''
    [pi4]
    kernel=u-boot-rpi4.bin
    enable_gic=1
    armstub=armstub8-gic.bin
    disable_overscan=1
    arm_boost=1

    [all]
    arm_64bit=1
    enable_uart=1
    avoid_warnings=1
  '';
in
{
  imports = [ ../rke2/sysbox.nix ];

  nixpkgs.hostPlatform = "aarch64-linux";

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usb_storage"
    "sd_mod"
    "sdhci_iproc"
  ];

  # The shared module supplies the mainpool LVs, including the F2FS root.
  # Do not import sd-image-aarch64.nix: it builds ext4, not this Disko layout.
  disko.devices.disk.root = {
    device = "/dev/mmcblk0";
    imageSize = "40G";
    content = lib.mkForce {
      type = "gpt";
      partitions = {
        boot = {
          priority = 1;
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        rootpv = {
          priority = 2;
          size = "100%";
          content = {
            type = "lvm_pv";
            vg = "mainpool";
          };
        };
      };
    };
  };

  # Thin LVs need an explicit virtual size; "100%" is not the pool's size.
  # Grow this ext4 LV separately after expanding the card and thin pool.
  disko.devices.lvm_vg.mainpool.lvs.longhorn.size = lib.mkForce "8G";

  disko.memSize = 4096;
  disko.imageBuilder = {
    pkgs = imagePkgs;
    kernelPackages = imagePkgs.linuxPackages;
    enableBinfmt = true;
    extraRootModules = [ "f2fs" "dm_mod" "dm_thin_pool" ];
    extraPostVM = ''
      ${imagePkgs.zstd}/bin/zstd -T0 --rm "$out/root.raw"
    '';
  };

  # Firmware and extlinux share the first FAT partition. U-Boot never needs
  # to read LVM/F2FS; the initrd mounts root after loading from /boot.
  setup.noBootloader = true; # Disable the shared EFI bootloader, not extlinux.
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible = {
    enable = true;
    configurationLimit = 5;
  };
  boot.loader.timeout = 5;
  boot.kernelParams = [ "console=ttyAMA0,115200n8" "console=tty0" ];

  # Run on initial installation AND subsequent nixos-rebuild boot/switch.
  system.build.installBootLoader = lib.mkForce (pkgs.writeShellScript "install-srv1-boot" ''
    set -eu
    ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c "$1" -d /boot
    ${pkgs.coreutils}/bin/cp ${firmware}/bootcode.bin ${firmware}/fixup*.dat ${firmware}/start*.elf /boot/
    ${pkgs.coreutils}/bin/cp ${firmware}/bcm2711-rpi-4-b.dtb /boot/
    ${pkgs.coreutils}/bin/cp ${pkgs.ubootRaspberryPi4_64bit}/u-boot.bin /boot/u-boot-rpi4.bin
    ${pkgs.coreutils}/bin/cp ${pkgs.raspberrypi-armstubs}/armstub8-gic.bin /boot/
    ${pkgs.coreutils}/bin/cp ${configTxt} /boot/config.txt
  '');
}
