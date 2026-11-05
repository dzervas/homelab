_final: prev: {
  hipfire = prev.callPackage ./hipfire.nix {};
  maya = prev.callPackage ./maya.nix {};
  sysbox-mgr = prev.callPackage ./sysbox-mgr.nix {};
  sysbox-fs = prev.callPackage ./sysbox-fs.nix {};
  sysbox-runc = prev.callPackage ./sysbox-runc.nix {};

  # nix-update:llama-swap --subpackage ui
  llama-swap = (prev.llama-swap.override {
    # v270's go.mod needs go >= 1.27.3; nixpkgs' default go is 1.26
    buildGoModule = prev.buildGoModule.override { go = prev.go_1_27; };
  }).overrideAttrs
    (
      finalAttrs: old: {
        version = "270";
        # nixpkgs' fetcher, keeping its leaveDotGit/postFetch that writes COMMIT and SOURCE_DATE_EPOCH
        src = old.src.override {
          tag = "v${finalAttrs.version}";
          hash = "sha256-OReJ4mR+eA8ZOSgGp+dBKFenR0TkLOmIk88GVmCevkk=";
        };
        vendorHash = "sha256-ESaG4DYGGlK+tPM9qHMcDSI0TLkg+DdMC6E8ik0jxIw=";
        # The web UI is only embedded with this tag since the embed.go / embed_notag.go split
        tags = (old.tags or []) ++ [ "embed_ui" ];
        # As nixpkgs does for process_command_forking_test.go: the newer vllm-wrapper test writes a
        # #!/bin/bash helper too, which the build sandbox doesn't have
        postPatch = old.postPatch + ''
            substituteInPlace cmd/vllm-wrapper/main_test.go \
              --replace-fail "#!/bin/bash" "#!${prev.lib.getExe prev.bash}"
          '';

        # Merged, not replaced: buildGoModule keeps overrideModAttrs in passthru. The UI follows
        # the package's version and src by itself (ui.nix takes finalPackage).
        passthru = old.passthru // {
          ui = old.passthru.ui.overrideAttrs (
            uiFinal: uiOld: {
              npmDepsHash = "sha256-vUYkqIfHE7nbpbDVMk8tCOQOP5c9rdr8dGBBBBKj0rc=";
              sourceRoot = "${uiOld.src.name}/ui"; # was ui-svelte
              # buildNpmPackage makes npmDeps from its original arguments, so neither the new
              # sourceRoot nor the hash reach it through overrideAttrs: rebuild it from the final ones
              npmDeps = prev.fetchNpmDeps {
                inherit (uiFinal) src sourceRoot postPatch;
                name = "${uiFinal.pname}-${uiFinal.version}-npm-deps";
                hash = uiFinal.npmDepsHash;
              };
            }
          );
        };
      }
    );
}
