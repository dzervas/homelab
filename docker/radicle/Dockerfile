FROM alpine:3

RUN apk add --no-cache tar curl xz && adduser -D radicle

ARG VERSION=1.7.1
RUN curl -o radicle.tar.xyz https://files.radicle.xyz/releases/latest/radicle-${VERSION}-x86_64-unknown-linux-musl.tar.xz && \
	tar -C / -xf radicle.tar.xyz && \
	mv /radicle-${VERSION}-x86_64-unknown-linux-musl/bin/* /usr/local/bin && \
	rm -rf /radicle-${VERSION}-x86_64-unknown-linux-musl

WORKDIR /home/radicle
USER radicle:radicle

CMD ["radicle-node"]
