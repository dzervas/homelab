# Nix-packaged engines, bind-mounted read-only at /opt/engines in the llama-swap sandbox, so the
# hand-managed /llama-swap/config.yaml never names a store path. A change here changes the unit,
# so llama-swap restarts with it on switch.
{
  buildEnv,
  hipfire,
  lib,
  maya,
  slotDir,
  writeShellScriptBin,
  writeTextDir,
}: let
  mayaShare = "${maya}/share/maya";
  mayaVision = "${maya.vision}/bin/maya-vision";

  # maya.py's write_config for a GLM HIP quant on a unified-memory APU (Strix Halo). Lives in the
  # store on purpose: Maya keeps web-chat answers in answers/ beside its config and writes the
  # config back from its dashboard, and a read-only folder refuses both.
  glm-maya-m = {
    exe = "${maya}/libexec/maya/maya";
    args = [
      "--glm-pack"
      "/models/maya/GLM-5.3-Flash/Maya-M/pack"
      "--max-context"
      "1048576" # GLM-5.3's own reach. ~12.5 KB of pinned RAM per token with --kv-streaming on: ~13 GB
      "--expert-cache"
      "auto"
      "--prefill"
      "auto"
      "--kv-streaming"
      "on"
      "--expert-profile"
      "${mayaShare}/data/expert-profile-glm.bin"
    ];
    cwd = mayaShare;
    tokenizer = "/models/maya/GLM-5.3-Flash/Maya-M/pack/tokenizer";
    model_name = "glm-5.3-flash";
    backend = "hip";
    gpu = [ 0 ];
    # GLM's generation_config, Maya's default effort
    sampling = {
      temperature = 1.0;
      top_p = 0.95;
    };
    reasoning_effort = "max";
    env = {
      STRATA_GLM_RESERVE_MB = "1024"; # hip_reserve_mib on a Linux APU
      STRATA_GLM_RAM_HEADROOM_GB = "8";
      STRATA_GLM_SPLIT = "0"; # one GPU
      STRATA_GLM_PREFILL_SUB = "1024";
      STRATA_GLM_PREFILL_MB = "6144"; # >= 96 GB of RAM

      # Parked conversations on the NVMe instead of the read-only pack folder. A slot is the KDA
      # state (~150 MB) plus the KV latents (~12.5 KB a token): ~1.6 GB at 128K, ~13 GB at 1M,
      # written and read back whole on a switch. 512 GB holds ~38 full 1M conversations; the
      # least recently used go first, and the engine never leaves the disk below 8 GB free.
      STRATA_GLM_SLOT_DIR = "${slotDir}/glm";
      STRATA_GLM_SLOTS = "64";
      STRATA_GLM_SLOT_GB = "512";
      # Every hipBLASLt version's table for the arch; the engine picks the one matching its hipBLASLt,
      # or plain hipBLAS when none does. Ordered as maya.py sorts them.
      STRATA_HIPBLASLT_TUNING =
        lib.concatMapStringsSep ":" (v: "${mayaShare}/tools/hip/gfx1151-glm-hipblaslt-${v}.txt")
          [
            "100202"
            "100401"
            "100401-b"
            "100500"
          ];
    };
    # No "log": the server would tee its lines and the engine's stderr into it

    # vision_step: maya-vision starts only while a request's new pictures are encoded, in GPU memory
    # the model lends it. The tower and its tokenizer are the same for every GLM-5.3-Flash quant.
    vision = {
      exe = mayaVision;
      mmproj = "/models/maya/GLM-5.3-Flash/vision/mmproj-GLM-5.3-Flash-F16.gguf";
      model = "/models/maya/GLM-5.3-Flash/vision/GLM-5.3-Flash-vocab.gguf";
      gpu = true;
    };
  };

  # maya.py's write_config_qwen for unsloth's UD-IQ2_XS: the same `maya` engine on its Qwen path,
  # the shards and the n-gram table read in place (the table memory-mapped, never loaded)
  qwenDir = "/models/maya/Qwen3.8-Flash-Next/UD-IQ2_XS";
  qwen-ud-iq2_xs = {
    exe = "${maya}/libexec/maya/maya";
    args = [
      "--pack"
      "${qwenDir}/pack"
      "--native"
      "${qwenDir}/Qwen3.8-Flash-Next-UD-IQ2_XS-00001-of-00003.gguf"
      "--ple-gguf" # the n-gram table's shard
      "${qwenDir}/Qwen3.8-Flash-Next-UD-IQ2_XS-00003-of-00003.gguf"
      "--ple-io"
      "mmap"
      "--spec"
      "4" # decode windows of up to 4 tokens (prompt-lookup and MTP drafts)
      "--prefill"
      "auto"
      "--expert-cache"
      "auto"
      "--max-context"
      "262144" # the model's native reach
      "--kv"
      "int8"
      "--expert-profile"
      "${qwenDir}/pack/expert-profile.bin"
      # The setup keeps the drafter only where it measures >= 3% faster; `--mtp-max-t 1` turns
      # its drafts off while keeping it loaded (the server needs it)
      "--mtp"
      "${qwenDir}/pack/mtp"
      "--vision" # picture rows at the <|image_pad|> tokens (GENI requests)
    ];
    cwd = mayaShare;
    tokenizer = "${qwenDir}/pack/tokenizer";
    model_name = "qwen3.8-flash-next";
    backend = "hip";
    gpu = [ 0 ];
    # Qwen/Qwen3.8-Flash-Next's card; its template always thinks
    sampling = {
      temperature = 1.0;
      top_p = 0.95;
      top_k = 20;
      min_p = 0.0;
    };
    reasoning_effort = "xhigh";
    # qwen_vision_step: the base model's tower as llama.cpp's mmproj, the vocabulary from the GGUF
    vision = {
      exe = mayaVision;
      mmproj = "${qwenDir}/../vision/mmproj-F16.gguf";
      model = "${qwenDir}/Qwen3.8-Flash-Next-UD-IQ2_XS-00001-of-00003.gguf";
      gpu = true;
    };
  };

  # maya.py's write_config_ds4 for Maya-XS (v2) on one HIP GPU: the `maya-ds4` engine, the Engram
  # tables and the DSpark drafter indexed into its pack by maya-ds4-pack
  ds4Dir = "/models/maya/DeepSeek-V4.1-Flash";
  deepseek-maya-xs = {
    exe = "${maya}/libexec/maya/maya-ds4";
    args = [
      "--pack"
      "${ds4Dir}/Maya-XS/maya-ds4"
      "--max-context"
      "1048576" # the model's own reach; ~1.1 KB of caches a position
      "--tp"
      "1"
      "--threads"
      "on" # one GPU: the chunked prompt path
      "--reserve-mib"
      "1024" # hip_reserve_mib on a Linux APU
      # (no --vision off: the engine runs the tower maya-ds4-vision made, indexed into the pack)
      # The setup writes `none` until its calibration measures drafting faster; this box holds the
      # whole model, where drafting pays. `none` frees the drafter's memory if it measures slower.
      # "--dspark"
      # "on"
      "--parallel"
      "4"
    ];
    cwd = mayaShare;
    tokenizer = "${ds4Dir}/Maya-XS/maya-ds4/tokenizer";
    model_name = "deepseek-v4.1-flash";
    backend = "hip";
    gpu = [ 0 ];
    # deepseek-ai's card; the encoder's default effort
    sampling = {
      temperature = 1.0;
      top_p = 1.0;
    };
    reasoning_effort = "high";

    env = {
      MAYA_DS4_SLOTS = "32";
      MAYA_DS4_SLOT_GB = "512";
      MAYA_DS4_SLOT_DIR = "${slotDir}/ds4";
      MAYA_DS4_SLOT_KEEP = "1";
      MAYA_DS4_SLOT_DAYS = "7";

      MAYA_DS4_EXPERT_MMQ = "1";
      MAYA_DS4_EXPERT_MMQ_MIN = "1";

      MAYA_DS4_KEEP_THINKING = "1";

      DS4_ROUND_LOG = "/tmp/ds4-rounds.log";
    };
  };

  # hipfire's serve with this box's model folder. Its state (serve.pid, kernel cache, verified-file
  # records) goes to $HOME/.hipfire, the sandbox's writable cache dir. Session state stays in RAM:
  # the session cache's disk tier is off by default and parked multi-slot sessions spill to
  # $TMPDIR/hipfire-swap-<pid> (tmpfs, llama-swap.nix).
  hipfire-serve = writeShellScriptBin "hipfire-serve" ''
    export HIPFIRE_MODELS_DIR=/models/hipfire
    # The model registry bundled in the binary, never refreshed from GitHub
    export HIPFIRE_NO_REGISTRY_FETCH=1
    exec ${hipfire}/bin/hipfire serve "$@"
  '';
in buildEnv {
  name = "inference-engines";
  paths = [
    maya
    hipfire-serve
    (writeTextDir "etc/maya/glm-5.3-flash-maya-m.json" (builtins.toJSON glm-maya-m))
    (writeTextDir "etc/maya/qwen3.8-flash-next-ud-iq2_xs.json" (builtins.toJSON qwen-ud-iq2_xs))
    (writeTextDir "etc/maya/deepseek-v4.1-flash-maya-xs.json" (builtins.toJSON deepseek-maya-xs))
  ];
}
