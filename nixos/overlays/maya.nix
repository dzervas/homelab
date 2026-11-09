# Project Maya: the GLM-5.3-Flash engine (HIP) and its Python server, without maya.py's interactive
# setup (it writes into its own checkout). Model prep is `maya-glm-pack`, the config is written by the
# NixOS module that runs it.
{
  cmake,
  fetchFromGitHub,
  git,
  lib,
  makeWrapper,
  ninja,
  python3,
  rocmPackages,
  stdenv,
  writeShellApplication,
  # Strix Halo / Gorgon Halo (Radeon 8060S / 8065S)
  gpuTargets ? [ "gfx1151" ],
}:
let
  version = "1.1.57";
  rev = "c4effee67cb95fb4303720919b075fddf04b4e69"; # v1.1.55, for `maya --version`

  src = fetchFromGitHub {
    owner = "mw00";
    repo = "project-maya";
    tag = "v${version}";
    hash = "sha256-gs8rqaKFsXL5ViqX/pMRM2OKh9o9Lbb4KYvnbYeJZvo=";
  };

  # The ggml Maya is built and tested against (third_party/ggml/VERSION.txt); the pack tool reads GGUFs
  # through its gguf-py too. CMake would otherwise FetchContent it at configure time.
  llamaSrc = fetchFromGitHub {
    owner = "ggml-org";
    repo = "llama.cpp";
    rev = "3cf03257f219afbe7334045ff7c6a06ac68c627d";
    hash = "sha256-SRGoXa+4ACBCB3eaG9XFYhMN1i0FyPEy9Rrer+dFGYI=";
  };

  # setup.py's PY_PACKAGES minus the build tools
  python = python3.withPackages (
    p: with p; [
      jinja2
      jsonschema
      numpy
      pillow
      psutil
      pyyaml
      regex
      requests
      tokenizers # DeepSeek's pack: the Engram token map
      tqdm
    ]
  );
in
stdenv.mkDerivation (finalAttrs: {
  pname = "maya";
  inherit version src;

  nativeBuildInputs = [
    cmake
    git # applies third_party/ggml/mmq-fused-swiglu.patch to the build tree's ggml copy
    makeWrapper
    ninja
  ];

  buildInputs = with rocmPackages; [
    clr
    hipblas
    hipblaslt
    rocwmma
  ];

  cmakeFlags = [
    # maya.py's compile_engine_hip
    (lib.cmakeBool "STRATA_ENABLE_HIP" true)
    (lib.cmakeBool "STRATA_ENABLE_CUDA" false)
    (lib.cmakeBool "STRATA_PREFILL_MMQ" true)
    (lib.cmakeBool "STRATA_NATIVE_EXPERTS" true)
    (lib.cmakeBool "STRATA_BUILD_TESTS" false)
    (lib.cmakeFeature "CMAKE_HIP_ARCHITECTURES" (lib.concatStringsSep ";" gpuTargets))
    (lib.cmakeFeature "CMAKE_HIP_COMPILER" "${rocmPackages.clr.hipClangPath}/clang++")
    # The HIP compiler isn't the cc-wrapper, so buildInputs' include paths don't reach it. rocWMMA is
    # header-only and included bare (glm_batch.cu's WMMA prompt attention on gfx11xx/gfx12xx).
    (lib.cmakeFeature "CMAKE_HIP_FLAGS" "-isystem${rocmPackages.rocwmma}/include")
    (lib.cmakeFeature "STRATA_GGML_DIR" "${llamaSrc}")
    (lib.cmakeFeature "MAYA_BUILD_ID" (builtins.substring 0 12 rev))

    # Otherwise ggml-cpu is built with -march=native for whichever machine builds it. Portable is
    # an AVX2 baseline, then Zen 5's AVX-512 on top. Maya's own AVX-512 CPU kernels are per-file and
    # picked at run time either way.
    (lib.cmakeBool "STRATA_PORTABLE" true)
    (lib.cmakeBool "GGML_AVX512" true)
    (lib.cmakeBool "GGML_AVX512_VBMI" true)
    (lib.cmakeBool "GGML_AVX512_VNNI" true)
    (lib.cmakeBool "GGML_AVX512_BF16" true)
    (lib.cmakeBool "GGML_AVX_VNNI" true)
  ];

  # maya: GLM-5.3-Flash and Qwen3.8-Flash-Next; maya-ds4: DeepSeek-V4.1-Flash
  ninjaFlags = [
    "maya"
    "maya-ds4"
  ];

  # The server finds its siblings from serve/'s parent (ROOT): keep the source tree's layout
  installPhase = ''
    runHook preInstall

    share=$out/share/maya
    mkdir -p $out/bin $share/data
    cp -r ../serve ../tools ../VERSION $share/
    cp ../data/expert-profile-*.bin $share/data/
    install -Dm755 maya $out/libexec/maya/maya
    install -Dm755 maya-ds4 $out/libexec/maya/maya-ds4

    makeWrapper ${python.interpreter} $out/bin/maya-server \
      --add-flags "$share/serve/server.py --engine maya"

    runHook postInstall
  '';

  passthru = {
    inherit llamaSrc python;

    # maya.py's compile_vision for HIP: maya-vision, the image encoder GLM-5.3-Flash and Qwen3.8 read
    # pictures with (DeepSeek's engine runs its own tower). llama.cpp's mtmd at the same pinned commit
    # as the engine's ggml, with GLM-5.3's vision tower patched in.
    vision = stdenv.mkDerivation {
      pname = "maya-vision";
      inherit version src;

      nativeBuildInputs = [
        cmake
        ninja
        python3 # glm5next_patch.py
      ];
      buildInputs = with rocmPackages; [
        clr
        hipblas
        rocblas
      ];

      # The patch edits llama.cpp's tree in place
      postPatch = ''
        cp -r ${llamaSrc} $NIX_BUILD_TOP/llama.cpp
        chmod -R u+w $NIX_BUILD_TOP/llama.cpp
        python3 tools/vision/glm5next_patch.py $NIX_BUILD_TOP/llama.cpp
      '';
      preConfigure = ''
        appendToVar cmakeFlags "-DLLAMA_DIR=$NIX_BUILD_TOP/llama.cpp"
      '';
      cmakeDir = "../tools/vision";
      cmakeFlags = [
        (lib.cmakeBool "STRATA_VISION_HIP" true)
        (lib.cmakeFeature "STRATA_VISION_HIP_TARGETS" (lib.concatStringsSep ";" gpuTargets))
        (lib.cmakeFeature "AMDGPU_TARGETS" (lib.concatStringsSep ";" gpuTargets))
        (lib.cmakeFeature "CMAKE_HIP_ARCHITECTURES" (lib.concatStringsSep ";" gpuTargets))
        (lib.cmakeFeature "CMAKE_HIP_COMPILER" "${rocmPackages.clr.hipClangPath}/clang++")
        (lib.cmakeFeature "CMAKE_EXE_LINKER_FLAGS" "-no-pie")
        # As the engine: not -march=native for the build machine, Zen 5's AVX-512 explicitly
        (lib.cmakeBool "STRATA_PORTABLE" true)
        (lib.cmakeBool "GGML_AVX512" true)
        (lib.cmakeBool "GGML_AVX512_VBMI" true)
        (lib.cmakeBool "GGML_AVX512_VNNI" true)
        (lib.cmakeBool "GGML_AVX512_BF16" true)
        (lib.cmakeBool "GGML_AVX_VNNI" true)
      ];
      ninjaFlags = [ "maya-vision" ];

      installPhase = ''
        runHook preInstall
        install -Dm755 bin/maya-vision $out/bin/maya-vision
        runHook postInstall
      '';
    };

    # maya.py's pack_step for a GLM GGUF quant: the engine's index of the model files, the small float
    # weights and the tokenizer, written beside the GGUF files (the engine finds them at <pack>/..)
    glm-pack = writeShellApplication {
      name = "maya-glm-pack";
      runtimeInputs = [ python ];
      text = ''
        if [ $# -ne 1 ]; then
          echo "usage: maya-glm-pack <first .gguf shard>" >&2
          exit 1
        fi
        shard=$(realpath "$1")
        pack="$(dirname "$shard")/pack"

        STRATA_GGUF_PY=${llamaSrc}/gguf-py \
          python ${finalAttrs.finalPackage}/share/maya/tools/iq_pack.py \
          --gguf "$shard" --out "$pack" --compat-bf16

        # base_template: GLM-5's chat template when the GGUF carries none
        if [ ! -f "$pack/tokenizer/chat_template.jinja" ]; then
          install -m644 ${finalAttrs.finalPackage}/share/maya/serve/glm5_chat_template.jinja \
            "$pack/tokenizer/chat_template.jinja"
        fi
        echo "pack: $pack"
      '';
    };

    # maya.py's qwen_pack_step for unsloth's split GGUF: the pack beside the shards, the MTP drafter
    # from the separate MTP head (its 512 experts requantized to 2 bits) and the shipped expert profile
    qwen-pack = writeShellApplication {
      name = "maya-qwen-pack";
      runtimeInputs = [ python ];
      text = ''
        if [ $# -ne 2 ]; then
          echo "usage: maya-qwen-pack <first .gguf shard> <mtp .gguf>" >&2
          exit 1
        fi
        shard=$(realpath "$1")
        mtp=$(realpath "$2")
        pack="$(dirname "$shard")/pack"
        tools=${finalAttrs.finalPackage}/share/maya/tools
        export STRATA_GGUF_PY=${llamaSrc}/gguf-py

        python "$tools/iq_pack.py" --gguf "$shard" --out "$pack" --compat-bf16
        python "$tools/mtp_from_gguf.py" --gguf "$mtp" --out "$pack/mtp"
        install -m644 ${finalAttrs.finalPackage}/share/maya/data/expert-profile-qwen.bin \
          "$pack/expert-profile.bin"
        echo "pack: $pack"
      '';
    };

    # maya.py's ds4_pack_step for a GGUF quant: tools/ds4/pack_gguf.py writes <model>/maya-ds4,
    # indexing the shards in place, the Engram tables and the DSpark drafter
    ds4-pack = writeShellApplication {
      name = "maya-ds4-pack";
      runtimeInputs = [ python ];
      text = ''
        if [ $# -ne 3 ]; then
          echo "usage: maya-ds4-pack <model dir with the shards> <Engram tables dir> <drafter .json>" >&2
          exit 1
        fi
        export STRATA_GGUF_PY=${llamaSrc}/gguf-py
        python ${finalAttrs.finalPackage}/share/maya/tools/ds4/pack_gguf.py \
          --model "$(realpath "$1")" --engram "$(realpath "$2")" --drafter "$(realpath "$3")"
        echo "pack: $(realpath "$1")/maya-ds4"
      '';
    };

    # maya.py's ds4_vision_step from unsloth's mmproj-BF16.gguf (the same vision.bin, byte for byte, as
    # from DeepSeek's checkpoint, without its range request): vision.bin + vision.json beside the mmproj.
    # maya-ds4-pack takes them from <model>/../vision.
    ds4-vision = writeShellApplication {
      name = "maya-ds4-vision";
      runtimeInputs = [ python ];
      text = ''
        if [ $# -ne 1 ]; then
          echo "usage: maya-ds4-vision <mmproj-BF16.gguf, in the vision folder beside the quants' folders>" >&2
          exit 1
        fi
        mmproj=$(realpath "$1")
        python ${finalAttrs.finalPackage}/share/maya/tools/ds4/vision_pack.py \
          --dir "$(dirname "$mmproj")" --mmproj "$mmproj"
      '';
    };
  };

  meta = {
    description = "Runs GLM-5.3-Flash, DeepSeek-V4.1-Flash and Qwen3.8-Flash-Next with tiered expert offloading";
    homepage = "https://github.com/mw00/project-maya";
    license = lib.licenses.mit;
    mainProgram = "maya-server";
    platforms = [ "x86_64-linux" ];
  };
})
