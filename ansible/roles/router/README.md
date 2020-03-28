# Linux router ansible role

This is a linux router ansible role. I'm testing it on my Alix 2 by PCEngines
but any distro should do it.

I really need to pivot to OpenWRT support

The variables required are a lot, but I'm documenting as much as I can below:

```yaml
---

# HostAPD stuff - Take care with the country code (mine was locked)
# and modes. Also try to enable 802.11w that encrypts deauthentication frames
# AKA mitigates deauthentication attacks
hostapd_driver: nl80211
hostapd_mode: g
hostapd_channel: 11
hostapd_country_code: US
hostapd_80211d: false
hostapd_80211h: false
hostapd_80211n: true
hostapd_80211w: true
hostapd_80211ac: false
hostapd_80211ax: false
# For 802.11n:
# hostapd_mode: n
# hostapd_80211n: true
# hostapd_wmm_enabled: true
# hostapd_require_ht: true
# Set "hostapd_ht_capab" according to "iw list" of your device
# Check https://w1.fi/cgit/hostap/plain/hostapd/hostapd.conf
# For 802.11ac (recommended):
# hostapd_mode: a
# hostapd_channel: 36
# hostapd_80211ac: true
# hostapd_wmm_enabled: true
# hostapd_require_vht: true
# hostapd_vht_oper_chwidth: 0 # 0: 20 or 40MHz, 1: 80MHz, 2: 160MHz, 3: 80+80MHz
# hostapd_vht_oper_centr_freq_seg0_idx: 42 # Center channel
# Set "hostapd_vht_capab" according to "iw list" of your device
# Check https://w1.fi/cgit/hostap/plain/hostapd/hostapd.conf

# DNS configuration
dns_tld: local # The TLD of your network(s). Hostname "hello" will be accessible as "hello.lan"
dns_hostname: router # Hostname of the target device
dns_local_ttl: 300 # TTL for local DNS records (NOT taken by DHCP leases)
dns_dhcp_ttl: 30 # TTL for DHCP DNS records (hostnames) - keep it low in case some IP changes

# Subnet configuration
# My current setup has in mind different vlan per subnet - you can ommit that
# Each subnet will have a separate network interface name (custom),
# which is actually a bridge
# Variables marked as (R) are required, (O) are optional and (R-<var>) are
# required if <var> is set
# Above unmarked variables are not required and the defaults are shown
# NOTE: You can have more than one WiFi networks with the same WiFi card
subnets:
  # Minimal setup - this is a completely private network with no DHCP
  # Good choice as a management network
  - iface: man0 # (R) Subnet interface name
    cidr: 192.168.0.1/24 # (R) Subnet CIDR
    bridges: # (R) Physical interface of the subnet
      - eth1
      - eth2
    allow_internet: false # (R) Allow internet access
    dhcp: false # (R) Enable DHCP on that interface

  # Maximum setup - this is a regular network with hidden WiFi & DHCP
  # Good choice as an IoT connectivity network
  # No reason your lamp needs access to your iPhone - Cloud FTW
  - iface: iot0
    cidr: 172.16.16.1/24
    bridges:
      - eth1
      - eth2
    vlan_id: 172 # (O) VLAN ID of the subnet
    allow_internet: true
    wifi_ssid: IoT # (O) SSID of the WiFi network
    wifi_passphrase: OneReallyReallyLongPassword # (R-wifi_ssid) WiFi password
    wifi_iface: wlan0 # (R-wifi_ssid) Physical interface of the WiFi card
    wifi_hidden: true # (O) Is the WiFi SSID hidden?
    dhcp: true
    dhcp_range_start: 100 # (O) DHCP starting range - only last bits
    dhcp_range_end: 200 # (O) DHCP ending range - this will result in a range of 172.16.16.100-172.16.16.200
    dhcp_lease_time: 24h # (O) How much time are the DHCP leases kept
    dhcp_static_lease_time: 30d # (O) How much time are the static DHCP leases kept
    dhcp_static_leases: # (O) List of static DHCP leases
      - mac: xx:xx:xx:xx:xx:xx # (R) MAC address of the device
        ip_index: 10 # (R) IP last bits to give -> 172.16.16.10
        hostname: raspberry # (O) Device hostname (ommit the TLD)
        lease_time: 15d # (O) Lease time (overrites above)

  - iface: lan0
    cidr: 10.13.37.1/24
    bridges:
      - eth1
      - eth2
    vlan_id: 1337
    allow_internet: true
    wifi_ssid: "Beautiful WiFi"
    wifi_passphrase: GreatPassword
    wifi_hidden: 0
    wifi_iface: wlan0
    dhcp: true
    dhcp_range_start: 100
    dhcp_range_end: 200
    dhcp_lease_time: 6h
    dhcp_static_lease_time: 30d
    dhcp_static_leases:
      - mac: yy:yy:yy:yy:yy:yy
        ip_index: 80
        hostname: server
```

WiFi is configured as WPA2-PSK CCMP.
