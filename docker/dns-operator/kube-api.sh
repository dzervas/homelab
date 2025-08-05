function get-nodes-cidr() {
	info "Fetching node CIDRs..."
	kubectl get nodes -o json | jq -r '.items[] | .metadata.name + ":" + .spec.podCIDR'
}

function watch-ingress() {
	nodes="$(get-nodes-cidr)"

	info "Watching ingress resources for changes..."
	kubectl get ingress -A -o json -w | \
		jq --unbuffered -r '.metadata.namespace + ":" + .metadata.name + ":" + (.spec.rules | tostring)' | \
		while IFS=: read -r namespace name rules; do
			info "Processing ingress $namespace/$name"

			echo $rules
		done
}

function process-rule() {
	local rule="$1"
	
}
