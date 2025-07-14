_: {
  services.cron = {
    enable = true;
    systemCronJobs = [
      # Remove old k3s container images daily
      "@daily sh -c '/var/lib/rancher/rke2/bin/crictl rmi --prune'"
    ];
  };
}
