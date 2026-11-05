# llama-swap and every engine it spawns (child processes share the unit's sandbox)
# run in a chroot holding only /nix/store, the read-only /models, /engines and
# /llama-swap, and a writable cache dir. Loopback-only networking and only the
# GPU devices are reachable.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # A directory, not a single file: file bind mounts pin the inode, so saves that
  # replace the file (vim, sed -i) would never reach the sandbox
  configDir = "/llama-swap";
  configFile = "${configDir}/config.yaml";
  cacheDir = "/var/cache/llama-swap";
  # Maya parks conversations it switches away from here (their state and token ids), so switching
  # back doesn't re-read the prompt. Emptied at every engine start (no MAYA_GLM_SLOT_KEEP).
  slotDir = "/models/maya/slot-cache";
  engines = pkgs.callPackage ./engines.nix { inherit slotDir; };

  # Request/response bodies must never be kept: llama-swap otherwise holds
  # captures in memory and serves them over its API/UI. The config lives outside
  # nix, so refuse to start or reload without the explicit opt-out.
  checkConfig = "${lib.getExe pkgs.yq-go} --exit-status '.captureBuffer == 0' ${configFile}";

  builderDir = {
    user = "builder";
    group = "builder";
    mode = "0755";
  };
in
{
  users = {
    # Owns /engines and /models, so engines are built and models downloaded
    # without root. llama-swap only gets read access.
    users.builder = {
      isSystemUser = true;
      group = "builder";
      home = "/engines";
      shell = pkgs.bashInteractive;
      packages = with pkgs.maya; [
        glm-pack
        qwen-pack
        ds4-pack
        ds4-vision
        pkgs.hipfire # `hipfire pull` into /models/hipfire
      ];
    };
    groups.builder = { };

    # A fixed user rather than DynamicUser, so the slot cache under /models can be its own
    users.llama-swap = {
      isSystemUser = true;
      group = "llama-swap";
    };
    groups.llama-swap = { };
  };

  # Maya's server keeps every request's pictures and their encodings in a tempfile.mkdtemp() folder
  # while the model runs. The service's private /tmp and /var/tmp (confinement's PrivateTmp) live in
  # the host's, so keep those in RAM. In-unit alternatives lose to the confinement module: a
  # TemporaryFileSystem under PrivateTmp is shadowed by its bind mounts, PrivateTmp = false makes
  # both inaccessible, and it can't take PrivateTmp = "disconnected" (it negates it as a boolean).
  boot.tmp.useTmpfs = true;
  fileSystems."/var/tmp" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [
      "mode=1777"
      "nosuid"
      "nodev"
    ];
  };

  systemd = {
    tmpfiles.settings.inference = {
      "/engines".d = builderDir;
      "/models".d = builderDir;
      "/models/huggingface".d = builderDir;
      "/models/llama.cpp".d = builderDir;
      "/models/maya".d = builderDir;
      "/models/hipfire".d = builderDir;
      ${slotDir}.d = {
        user = "llama-swap";
        group = "llama-swap";
        mode = "0700";
      };

      ${configDir}.d = {
        user = "root";
        group = "root";
        mode = "0755";
      };
      # Only created when missing, the file is managed by hand afterwards
      ${configFile}.f = {
        user = "root";
        group = "root";
        mode = "0644";
        argument = "captureBuffer: 0";
      };
    };

    services.llama-swap = {
      description = "llama-swap model and engine switcher";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        # JIT caches (vLLM, Triton, torch) need somewhere writable
        HOME = cacheDir;
        XDG_CACHE_HOME = cacheDir;

        HF_HOME = "/models/huggingface";
        HF_HUB_OFFLINE = "1"; # No network: never try to download
        LLAMA_CACHE = "/models/llama.cpp";

        # Maya: the server's lines stay on stdout (no log file beside the config) and no token-count file
        STRATA_SERVER_LOG = "0";
        MAYA_SAVINGS_PATH = "off";

        # Prebuilt engines in /engines run through the nix-ld shim in /lib64. Point
        # it at store paths, /run/current-system isn't in the chroot.
        NIX_LD = pkgs.stdenv.cc.bintools.dynamicLinker;
        NIX_LD_LIBRARY_PATH = lib.makeLibraryPath config.programs.nix-ld.libraries;
      };

      confinement.enable = true;

      serviceConfig = {
        ExecStartPre = checkConfig;
        ExecStart = "${lib.getExe pkgs.llama-swap} --listen=127.0.0.1:8080 --config=${configFile}";
        # Triggered by llama-swap-reload.path on every config change
        ExecReload = [
          checkConfig
          "${pkgs.coreutils}/bin/kill -HUP $MAINPID"
        ];
        Restart = "on-failure";
        RestartSec = 3;

        User = "llama-swap";
        Group = "llama-swap";
        CacheDirectory = "llama-swap";
        # /var/lib/llama-swap, kept across restarts: llama-swap's activity store (`store.path` in
        # config.yaml; timings and token counts per request - bodies only with captures, which
        # captureBuffer: 0 keeps off)
        StateDirectory = "llama-swap";
        UMask = "0077";

        BindReadOnlyPaths = [
          # The whole store, not just the closure: engines built by `builder` link
          # against arbitrary store paths
          "/nix/store"
          "/lib64"
          "/usr/bin/env" # Shebangs of engine scripts
          # `localhost` (llama-swap's default proxy, engines' own) - without it Go falls back to DNS on [::1]:53
          "/etc/hosts"
          configDir
          "/models"
          "/engines"
          "${engines}:/opt/engines"
        ];
        # The only writable spot in /models (mounted over the read-only /models above)
        BindPaths = [ slotDir ];

        # Host /dev is mounted but only the GPU and the NPU are openable (kfd, DRM render nodes and
        # the XDNA2 accel node, all 0666 via udev) besides the null/zero/random/tty basics
        PrivateDevices = false;
        DevicePolicy = "closed";
        DeviceAllow = [
          "/dev/kfd rw"
          "char-drm rw"
          "/dev/accel/accel0 rw" # hipfire's NPU prefill (raw amdxdna ioctls)
        ];

        # Only caddy (and the engines, via llama-swap) over loopback
        IPAddressDeny = "any";
        IPAddressAllow = "localhost";
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];

        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        LockPersonality = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectProc = "invisible";
        RemoveIPC = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
        ];
        SystemCallErrorNumber = "EPERM";
        # No MemoryDenyWriteExecute: vLLM/Triton/ROCm JIT-compile kernels
      };
    };

    # Hot reload through ExecReload, so the captureBuffer check guards reloads too
    # (llama-swap's own --watch-config would bypass it)
    paths.llama-swap-reload = {
      wantedBy = [ "multi-user.target" ];
      pathConfig.PathChanged = configFile;
    };
    services.llama-swap-reload = {
      description = "Reload llama-swap after a config change";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${config.systemd.package}/bin/systemctl reload llama-swap.service";
      };
    };
  };
}
