function get-nodes-cidr() {
	echo "Fetching node CIDRs..."
	kubectl get nodes -o json | jq -r '.items[] | .metadata.name + ":" + .spec.podCIDR'
}

function watch-ingress() {
	nodes="$(get-nodes-cidr)"

	echo "Watching ingress resources for changes..."
	kubectl get ingress -A -o json -w | \
		jq --unbuffered -r '.metadata.namespace + ":" + .metadata.name + ":" + (.spec.rules | tostring)' | \
		while IFS=: read -r namespace name rules; do
			echo "Processing ingress $namespace/$name"

			# while IFS=: read -r 
		done
}
