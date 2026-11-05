# GPT root disk with the ESP, shared by every role. The rest of the disk is
# partitioned by disk/<role>.nix
{
  config,
  lib,
  ...
}:
{
  disko.devices.disk.root = {
    # `device` is defined in the host configuration
    type = "disk";

    content = {
      # type = if config.setup.isEFI then "gpt" else "msdos";
      type = "gpt";

      partitions = {
        boot = lib.mkIf (!config.setup.isEFI) {
          size = "1M";
          type = "EF02"; # for grub MBR
        };

        # Grub doesn't support f2fs so EFI ESP is used for the kernel + initrd
        ESP = {
          size = "1G";
          type = "EF00";
          priority = 1; # Needs to be first partition
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [
              "uid=0"
              "gid=0"
              "umask=077"
              "fmask=077"
              "dmask=077"
            ];
          };
        };
      };
    };
  };
}
