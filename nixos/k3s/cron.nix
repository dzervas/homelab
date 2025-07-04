_: {
  services.cron = {
    enable = true;
    systemCronJobs = [
      # Remove old k3s container images daily
      "@daily crictl rmi --prune"
    ];
  };
}
