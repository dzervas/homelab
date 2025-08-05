#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/log.sh"
source "$(dirname "$0")/cloudflare.sh"
source "$(dirname "$0")/kube-api.sh"

ZONES=$(cf-zones)

if [ -z "$ZONES" ]; then
	error "No zones found. Please ensure your API token has the correct permissions."
	exit 1
fi

info "Processing zones:"
echo "$ZONES" | while IFS=: read -r zone_id zone_name; do
	info "- $zone_name (ID: $zone_id)"
done

info "Starting DNS Operator"
watch-ingress
