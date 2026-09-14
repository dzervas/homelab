{ buildGo125Module, fetchFromGitHub, lib, libseccomp, pkg-config, protobuf, protoc-gen-go, protoc-gen-go-grpc }:

let
  versions = import ./_sysbox_versions.nix;
in
buildGo125Module {
  pname = "sysbox-runc";
  inherit (versions) version;

  src = fetchFromGitHub versions.source;
  modRoot = "sysbox-runc";
  subPackages = [ "." ];
  tags = [ "seccomp" "apparmor" "idmapped_mnt" ];
  vendorHash = versions.components.sysbox-runc.vendorHash;

  nativeBuildInputs = [ pkg-config protobuf protoc-gen-go protoc-gen-go-grpc ];
  buildInputs = [ libseccomp ];

  # buildGoModule also runs this before vendoring the local IPC dependency.
  preBuild = ''
    cd ../sysbox-ipc/sysboxFsGrpc/sysboxFsProtobuf
    protoc -I . --go_out=paths=source_relative:. --go-grpc_out=paths=source_relative,require_unimplemented_servers=false:. sysboxFsProtobuf.proto
    cd ../../sysboxMgrGrpc/sysboxMgrProtobuf
    protoc -I . --go_out=paths=source_relative:. --go-grpc_out=paths=source_relative,require_unimplemented_servers=false:. sysboxMgrProtobuf.proto
    cd ../../../sysbox-runc
  '';

  ldflags = [
    "-X 'main.edition=Community Edition (CE)'"
    "-X main.version=${versions.version}"
    "-X main.commitId=${versions.components.sysbox-runc.rev}"
    "-X main.builtAt=1970-01-01T00:00:00Z"
    "-X main.builtBy=nix"
  ];

  # Upstream's test targets require privileged Docker, kernel headers, and Bats.
  doCheck = false;

  meta = {
    description = "OCI runtime for Sysbox system containers";
    homepage = "https://github.com/nestybox/sysbox";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    mainProgram = "sysbox-runc";
  };
}
