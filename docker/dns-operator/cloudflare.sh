CLOUDFLARE_BASE="https://api.cloudflare.com/client/v4/"
CLOUDFLARE_HEADER="Authorization: Bearer $CLOUDFLARE_API_TOKEN"

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
	echo "CLOUDFLARE_API_TOKEN is not set. Please set it to your Cloudflare API token."
	exit 1
fi

function cf() {
	endpoint=$1

	result="$(curl -sL \
		-H "Content-Type: application/json" \
		-H "$CLOUDFLARE_HEADER" \
		"$CLOUDFLARE_BASE/$endpoint" \
		${@:2})"

	errors=$(echo "$result" | jq -r '.errors[]? | @base64')

	if [ -n "$errors" ]; then
		echo "Errors encountered:"
		for error in $errors; do
			error_json=$(echo "$error" | base64 --decode)
			echo "$error_json"
		done
		exit 1
	fi

	echo "$result"
}

function cf-zones() {
	cf zones | jq -r '.result[] | .id + ":" + .name'
}
