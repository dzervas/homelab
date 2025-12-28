local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local helm = tk.helm.new(std.thisFile);

helm.template('gemini', '../../charts/gemini')

// Restore PVC from snapshot procedure:
// 1. Find the snapshot timestamp with `k get volumesnapshot` (my-pvc-name-<timestamp>)
// 2. Stop the workload (e.g. `k scale all --all --replicas=0`)
// 3. `k annotate snapshotgroup/my-pvc-name --overwrite "gemini.fairwinds.com/restore=<timestamp>"`
// 4. Start the workload with `k scale all --all --replicas=x` or just `tf apply`
