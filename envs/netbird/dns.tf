resource "netbird_dns_zone" "vpn" {
  name                 = "vpn.dzerv.art"
  domain               = "vpn.dzerv.art"
  enabled              = true
  enable_search_domain = true
  distribution_groups  = [data.netbird_group.all.id]
}

resource "netbird_dns_record" "kube" {
  zone_id = netbird_dns_zone.vpn.id
  name    = "kube.vpn.dzerv.art"
  type    = "CNAME"
  content = "kubernetes.default.vpn.dzerv.art"
  ttl     = 60
}
