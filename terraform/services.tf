resource "consul_intention" "proxy_jira" {
  source_name = "proxy-traefik"
  destination_name = "jira-software"
  action = "allow"
}

resource "consul_intention" "jira" {
  source_name = "jira-software"
  destination_name = "jira-database"
  action = "allow"
}

resource "nomad_job" "jira" {
  jobspec = templatefile("${path.module}/nomad/jira.nomad", { domain = var.domain })
}
