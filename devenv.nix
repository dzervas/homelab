{ pkgs, ... }:
{
  languages = {
    jsonnet.enable = true;
    python = {
      enable = true;

      # https://devenv.sh/guides/python/#python_venv
      venv = {
        enable = true;
        requirements = ''
            kr8s
            requests
            prometheus-client
        '';
      };
    };
  };

  packages = with pkgs; [
    tanka
    jsonnet-bundler
    deploy-rs

    # pv-migrate
    yq-go
    pv-migrate
  ];

  scripts = {
    tk-diff-all.exec = "tk env list --names | xargs -n1 --verbose tk diff -s";
    tk-chart-add.exec = ''test "$#" -eq 4 || echo "Usage: tk-chart-add <repo-url> <repo-name> <chart-name> <chart-version>" && tk tool charts add-repo $3 $1 && tk tool charts add $3/$2@$4'';
    tk-update-check.exec = ''
      echo "This is going to take some time..."
      echo
      tk tool charts version-check | \
      jq -r 'map(
      .name + " " + .current_version + (
      if .current_version ==  .latest_version.version then
      " ✅"
      else
      " -> " + .latest_version.version + " 🔃"
      end
      )) | .[]'
      '';

    tk-ns.exec = ''tk --ext-code namespaces=$(kubectl get ns -o json | jq -c '[.items[].metadata.name]') $@'';
  };

  env = {
    TANKA_PAGER = "${pkgs.bat}/bin/bat -p -l yaml";

    OUTPUT_PATH = "/tmp/dns.json";
    INGRESS_CLASS = "vpn";
    DOMAIN_SUFFIX = ".ts.dzerv.art";
    HEADSCALE_URL = "http://localhost:8080";
    HEADSCALE_API_KEY = "op://k8s-secrets/dns-controller/HEADSCALE_API_KEY";
    PYTHONUNBUFFERED = "1";

    CLIPROXYAPI_TOKEN = "op://k8s-secrets/cliproxyapi/password";
    CLIPROXYAPI_URL = "https://ai.vpn.dzerv.art";
  };
}
