{
  buildGo125Module,
  fetchFromGitHub,
  fuse3,
  lib,
  libseccomp,
  makeWrapper,
  pkg-config,
  protobuf,
  protoc-gen-go,
  protoc-gen-go-grpc,
}: let
  versions = import ./_sysbox_versions.nix;
in
  buildGo125Module rec {
    pname = "sysbox-fs";
    version = lib.strings.removePrefix "v" versions.source.tag;

    src = fetchFromGitHub versions.source;
    modRoot = "sysbox-fs";
    subPackages = [ "cmd/sysbox-fs" ];
    vendorHash = "sha256-m3VlF5fZ6agKvRZAJX9Jpokb4pmtSUMdXikzqof8bbw=";

    nativeBuildInputs = [ makeWrapper pkg-config protobuf protoc-gen-go protoc-gen-go-grpc ];
    buildInputs = [ libseccomp ];

    # buildGoModule also runs this before vendoring the local IPC dependency.
    preBuild = ''
      cd ../sysbox-ipc/sysboxFsGrpc/sysboxFsProtobuf
      protoc -I . --go_out=paths=source_relative:. --go-grpc_out=paths=source_relative,require_unimplemented_servers=false:. sysboxFsProtobuf.proto
      cd ../../sysboxMgrGrpc/sysboxMgrProtobuf
      protoc -I . --go_out=paths=source_relative:. --go-grpc_out=paths=source_relative,require_unimplemented_servers=false:. sysboxMgrProtobuf.proto
      cd ../../../sysbox-fs
    '';

    ldflags = [
      "-X 'main.edition=Community Edition (CE)'"
      "-X main.version=${version}"
      "-X main.commitId=${versions.source.tag}"
      "-X main.builtAt=1970-01-01T00:00:00Z"
      "-X main.builtBy=nix"
    ];

    postFixup = ''
      wrapProgram $out/bin/sysbox-fs --prefix PATH : ${lib.makeBinPath [ fuse3 ]}
    '';

    # Upstream's fs tests perform real FUSE mounts in a privileged test container.
    doCheck = false;

    meta = {
      description = "FUSE daemon for Sysbox system containers";
      homepage = "https://github.com/nestybox/sysbox";
      license = lib.licenses.asl20;
      platforms = lib.platforms.linux;
      mainProgram = "sysbox-fs";
    };
  }
