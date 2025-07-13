{ pkgs, ... }: {
  environment = {
    systemPackages = [ pkgs.etcd ];
    variables = {
      ETCDCTL_ENDPOINTS = "https://127.0.0.1:2379";
      ETCDCTL_CACERT = "/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt";
      ETCDCTL_CERT = "/var/lib/rancher/k3s/server/tls/etcd/server-client.crt";
      ETCDCTL_KEY = "/var/lib/rancher/k3s/server/tls/etcd/server-client.key";
      ETCDCTL_API = "3";
    };
  };
}
