#!/bin/sh
opkg install acme acme-dnsapi vim
opkg install prometheus-node-exporter-lua-hostapd_stations prometheus-node-exporter-lua-hostapd_ubus_stations prometheus-node-exporter-lua-nat_traffic prometheus-node-exporter-lua-netstat prometheus-node-exporter-lua-openwrt prometheus-node-exporter-lua-wifi prometheus-node-exporter-lua-wifi_stations prometheus-node-exporter-lua
opkg install unzip

curl -O -L "https://github.com/grafana/agent/releases/latest/download/grafana-agent-linux-arm64.zip"
unzip "grafana-agent-linux-arm64.zip"
rm "grafana-agent-linux-arm64.zip"
chmod a+x grafana-agent-linux-arm64