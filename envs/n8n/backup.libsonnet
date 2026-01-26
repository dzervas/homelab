local namespace = 'n8n';

{
  // SnapshotGroup for n8n backups PVC
  // Note: Uses custom name 'n8n-backups' to match TF resource name
  n8nBackup: {
    apiVersion: 'gemini.fairwinds.com/v1',
    kind: 'SnapshotGroup',
    metadata: {
      name: 'n8n-backups',
      namespace: namespace,
    },
    spec: {
      persistentVolumeClaim: { claimName: 'backups-n8n-0' },
      schedule: [
        { every: 'day', keep: 3 },
        { every: 'week', keep: 4 },
        { every: 'month', keep: 1 },
      ],
    },
  },
}
