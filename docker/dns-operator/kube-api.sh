function watch-ingress() {
	info "Watching ingress resources for changes..."
	kubectl get ingress -A -o json -w | \
		jq --unbuffered -r '.metadata.namespace + ":" + .metadata.name + ":" + (.spec.rules | tostring)' | \
		while IFS=: read -r namespace name rules; do
			info "Processing ingress $namespace/$name"

			echo "$rules" | jq -c '.[]' | while read -r rule; do
				process-rule "$namespace" "$rule"
			done
		done
}

function process-rule() {
	local namespace="$1"
	local rule="$2"
	eval "$(jq -r '@sh "host=\(.host) service=\(.http.paths[0].backend.service.name)"' <<< "$rule")"

	if [ -z "$host" ] || [ -z "$service" ]; then
		warn "Invalid rule: $rule"
		return
	fi

	echo -n "$host:"
	get-service-nodes "$namespace" "$service"
}

function get-service-nodes() {
	local namespace="$1"
	local service="$2"
	local selector="$(kubectl get service "$service" -n "$namespace" -o json | jq -r '.spec.selector | to_entries | map(.key + "=" + .value) | join(",")')"

	if [ -z "$selector" ]; then
		warn "No selector found for service $namespace/$service"
		return
	fi

	kubectl get pods -n "$namespace" -l "$selector" -o json | jq -r '.items | map(.spec.nodeName) | unique | join(",")'
}
