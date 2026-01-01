FROM nicolaka/netshoot:v0.14

RUN apk update && apk add --no-cache mitmproxy

# Make sure the user is numeric so PSA "restricted" can verify
USER 65532:65532
WORKDIR /tmp
ENTRYPOINT ["/bin/bash"]
