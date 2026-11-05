_: {
  services.llama-swap = {
    enable = true;
    # Only reachable through caddy
    listenAddress = "127.0.0.1";
    port = 8080;

    # TODO: models/engines
    settings = {
      # Request/response bodies must never be kept: llama-swap otherwise holds
      # captures in memory and serves them over its API/UI
      captureBuffer = 0;
    };
  };
}
