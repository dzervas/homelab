local gemini = import 'helpers/gemini.libsonnet';

local namespace = 'n8n';

{
  // SnapshotGroup for n8n backups PVC using the gemini helper
  n8nBackup: gemini.backup(namespace, 'backups-n8n-0', [
    { every: 'day', keep: 3 },
    { every: 'week', keep: 4 },
    { every: 'month', keep: 1 },
  ]),
}
