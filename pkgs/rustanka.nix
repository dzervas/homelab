{
  fetchFromGitHub,
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "rustanka";
  version = "0.1.1";

  src = fetchFromGitHub {
    owner = "grafana";
    repo = "rustanka";
    tag = "v${finalAttrs.version}";
    hash = "sha256-desRBEp2jibfYvxCUQSe6v3wG8uX7/zu/dphglp7AS8=";
  };

  cargoHash = "sha256-M0khkhQwpz/le5nhfX6yy9iIscYPGvwhuTaWLj7OaJY=";

  # build.rs only trusts a non-placeholder Cargo version, otherwise it shells out to git.
  # Upstream's release workflow stamps the tag in the same way.
  # Done in preBuild, after cargoSetupHook compares Cargo.lock against the vendored copy.
  preBuild = ''
    sed -i 's/^version = "0.1.0"/version = "${finalAttrs.version}"/' cmds/rtk/Cargo.toml
    sed -i '/^name = "rtk"$/{n;s/^version = "0.1.0"/version = "${finalAttrs.version}"/}' Cargo.lock
  '';

  cargoBuildFlags = [ "-p" "rtk" ];

  # The test suite shells out to tk/helm/kustomize and compares against them
  doCheck = false;

  meta = with lib; {
    description = "Drop-in Rust replacement for Grafana Tanka";
    homepage = "https://github.com/grafana/rustanka";
    license = licenses.mit;
    mainProgram = "rtk";
    platforms = platforms.unix;
  };
})
