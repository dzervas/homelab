{
  backup(namespace, pvcClaimName, schedule=null): {
    apiVersion: 'gemini.fairwinds.com/v1',
    kind: 'SnapshotGroup',
    metadata: {
      name: '%s-backup' % pvcClaimName,
      namespace: namespace,
    },
    spec: {
      persistentVolumeClaim: {
        claimName: pvcClaimName,
      },
      schedule: if schedule != null then schedule else [
        { every: 'day', keep: 3 },
        { every: 'week', keep: 2 },
        { every: 'month', keep: 2 },
      ],
    },
  },

  backupMany(namespace, pvcClaimNames, schedule=null): [
    self.backup(
      namespace=namespace,
      pvcClaimName=claimName,
      schedule=schedule
    )
    for claimName in pvcClaimNames
  ],
}
