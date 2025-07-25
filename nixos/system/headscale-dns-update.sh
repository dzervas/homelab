#!/usr/bin/env bash
set -euo pipefail

# Get all the services from active ingresses and arrange them in a namespace/name/fqdn format
services=$(kubectl get ingress -o json -A | jq -c '.items | map(.metadata.namespace as $ns| .spec.rules | map({fqdn: .host, namespace: $ns, service: (.http.paths | first).backend.service.name}) | .[]) | .[]')

# Output var of all the records
ingresses=""
for svc in $services; do
	fqdn=$(echo "$svc" | jq -r .fqdn)
	namespace=$(echo "$svc" | jq -r .namespace)
	service=$(echo "$svc" | jq -r .service)

	# Get the pod selectors of the service
	selectors=$(kubectl get service -n "$namespace" "$service" -o json | jq -r '.spec.selector | to_entries | map(.key + "=" + .value) | join(",")')
	# Get the host that the (first) pod are currently running on
	host="$(kubectl get pod -n "$namespace" -l "$selectors" -o json | jq -r '.items | first | .spec.nodeName')"
	# Get the tailscale IP address of the host
	ip=$(tailscale ip -4 "$host")

	# Create the DNS record in the format required by headscale
	ingress='{"name": "'$fqdn'", "type": "A", "value": "'$ip'"},'
	ingresses="$ingresses$ingress"
done
ingresses=${ingresses%,} # Remove trailing comma

# Get all the control plane hosts that are up
kube_api_host=$(kubectl get nodes -l node-role.kubernetes.io/control-plane=true | grep Ready | awk '{print $1}' | head -1)
kube_api_ip=$(tailscale ip -4 "$kube_api_host")
nodes=$(headscale nodes ls -o json | jq 'map({name: (.given_name + ".dzerv.art"), type: "A", value: (.ip_addresses | map(select(contains("."))) | first)})')
vpn_ip=$(tailscale ip -4 "$(hostname)")

# Sort the keys to bypass unnecessary updates (hedscale checks for hash of the file)
jq --slurp 'reduce .[] as $x ([]; . + $x) | sort_by(.name)' \
	<(echo '[{"name": "kube.dzerv.art", "type": "A", "value": "'"$kube_api_ip"'"}]' | jq -c) \
	<(echo '[{"name": "vpn.dzerv.art", "type": "A", "value": "'"$vpn_ip"'"}]' | jq -c) \
	<(echo "[$ingresses]" | jq -c) \
	<(echo "$nodes" | jq -c) \
	> /var/lib/headscale/dns.json
