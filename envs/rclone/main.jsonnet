local k = import 'k.libsonnet';
local externalSecrets = import 'external-secrets-libsonnet/0.19/main.libsonnet';
local lab = import 'labsonnet.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';

local externalSecret = externalSecrets.nogroup.v1.externalSecret;
local networkPolicy = k.networking.v1.networkPolicy;
local serviceAccount = k.core.v1.serviceAccount;
local roleBinding = k.rbac.v1.roleBinding;
local role = k.rbac.v1.role;
local statefulSet = k.apps.v1.statefulSet;
local container = k.core.v1.container;

local namespace = 'rclone';

{
  // TODO: Metrics
  // TODO: auth-proxy command to authenticate each user to the correct fs+path
  // TODO: Fix this:
  // To refresh:
  // rclone authorize onedrive <client_id> <client_secret>
  // paste the output in 1password rclone token config

  rcloneRC:
    lab.new('rclone-rc', 'rclone/rclone')
    + lab.withNamespace(namespace)
    + lab.withCreateNamespace()
    + lab.withType('StatefulSet')
    + lab.withVpnHttp(8080, 'webdav.vpn.dzerv.art')
    + lab.withCommand(['sh', '-c'])
    + lab.withEmptyDir('/runtime')
    + lab.withSecretMount('/secret', 'rclone-secrets-op')
    + lab.withSecretEnv({
      WEBDAV_PIXEL_PASS: { name: 'rclone-secrets-op', key: 'webdav-pixel-pass' },
      S3_LONGHORN_PASS: { name: 'rclone-secrets-op', key: 's3-longhorn-pass' },
    })
    + lab.withArgs([|||
      rclone rcd --rc-addr=127.0.0.1:5572 --rc-no-auth --config=/runtime/rclone.conf --cache-dir=/tmp/.rclone --temp-dir=/tmp  --metrics-addr=0.0.0.0:9090 &
      pid=$!

      until rclone rc core/version; do
        echo "Waiting for rclone rcd to come up..."
        sleep 1
      done

      echo "Starting WebDAV..."
      rclone rc serve/start type=webdav fs=onedrive: addr=:8080 vfs_cache_mode=full user=pixel "pass=$WEBDAV_PIXEL_PASS"
      echo "Starting S3..."
      rclone rc serve/start type=s3 fs=s3: addr=:9000 vfs_cache_mode=full user=longhorn "pass=$S3_LONGHORN_PASS"
      echo "All done! returning control to rclone rcd"

      rclone rc core/version

      wait "$pid"
    |||])
    + lab.withInitContainer(
      container.new('token-sync', 'bitnami/kubectl')
      + container.withRestartPolicy('Always') # Makes it a sidecar
      + container.withCommand(['sh', '-c'])
      + container.withArgs([|||
        set -eu
        SOURCE=/secret/rclone.conf
        CONFIG=/runtime/rclone.conf
        SECRET_NAME=rclone-onedrive-token
        NAMESPACE="$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)"

        # Prepare the rclone.conf
        cp "$SOURCE" "$CONFIG"
        token="$(kubectl --namespace $NAMESPACE get secret $SECRET_NAME -o go-template='{{ .data.onedrive_token | base64decode }}')"
        # Escape for sed replacement.
        escaped_token="$(printf '%s' "$token" | sed 's/[\/&]/\\&/g')"
        sed -i "s/<onedrive_token>/$escaped_token/" "$CONFIG"

        if grep -q '<onedrive_token>' "$CONFIG"; then
          echo "Failed to substitute OneDrive token" >&2
          exit 1
        fi

        last_hash="$(sha256sum "$CONFIG" | awk '{print $1}')"
        echo "Config built successfully, current hash: $last_hash"

        while true; do
            sleep 10

            hash="$(sha256sum "$CONFIG" | awk '{print $1}')"
            [ "$hash" = "$last_hash" ] && continue
            sleep 1
            settled_hash="$(sha256sum "$CONFIG" | awk '{print $1}')"
            [ "$hash" = "$settled_hash" ] || continue

            echo "Config change detected, syncing to kubernetes secret, new hash: $hash"

            token="$(
                awk '
                    /^\[onedrive\]$/ {
                        in_onedrive = 1
                        next
                    }

                    /^\[/ {
                        in_onedrive = 0
                    }

                    in_onedrive && /^[[:space:]]*token[[:space:]]*=/ {
                        sub(/^[[:space:]]*token[[:space:]]*=[[:space:]]*/, "")
                        print
                        exit
                    }
                ' "$CONFIG"
            )"

            if [ -z "$token" ]; then
                echo "rclone.conf changed but could not extract [onedrive] token" >&2
                continue
            fi

            token_b64="$(printf '%s' "$token" | base64 -w0 | tr -d '\n')"

            kubectl patch secret "$SECRET_NAME" --namespace $NAMESPACE --type=merge \
                --patch='{"data":{"onedrive_token":'"$token_b64"'}}'

            last_hash="$settled_hash"
        done
      |||])
    )
    + { workload+: statefulSet.spec.template.spec.withServiceAccountName('rclone-rc') },

  rcloneRCServiceAccount: serviceAccount.new('rclone-rc'),
  rcloneRCRole:
    role.new('rclone-rc')
    + role.withRules([
      {
        apiGroups: [''],
        resources: ['secrets'],
        verbs: ['get', 'patch'],
        resourceNames: ['rclone-onedrive-token']
      },
      {
        apiGroups: [''],
        resources: ['secrets'],
        verbs: ['list'],
      },
    ]),

  rcloneRCRoleBinding:
    roleBinding.new('rclone-rc')
    + roleBinding.roleRef.withApiGroup('rbac.authorization.k8s.io')
    + roleBinding.roleRef.withKind('Role')
    + roleBinding.roleRef.withName('rclone-rc')
    + roleBinding.withSubjects([{
      kind: 'ServiceAccount',
      name: 'rclone-rc',
      namespace: namespace,
    }]),

  secret:
    externalSecret.new('rclone-secrets-op')
    + externalSecret.spec.secretStoreRef.withKind('ClusterSecretStore')
    + externalSecret.spec.secretStoreRef.withName('1password')
    + externalSecret.spec.withDataFrom([{ extract: { key: 'rclone' } }]),
}
