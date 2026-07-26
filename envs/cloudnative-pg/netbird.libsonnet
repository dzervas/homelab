local postgres = import './cluster.libsonnet';

{
  // CNPG creates the `netbird` database and owner, plus a `netbird-app`
  // Secret containing connection details for the application.
  netbirdCluster: postgres.new('netbird', 'netbird', '5Gi'),
}
