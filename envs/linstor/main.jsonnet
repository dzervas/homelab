local cluster = import 'cluster.libsonnet';
local k = import 'k.libsonnet';
local networkPolicies = import 'networkPolicies.libsonnet';
local operator = import 'operator.libsonnet';
local scheduler = import 'scheduler.libsonnet';

{
  namespace: k.core.v1.namespace.new('linstor'),
} + operator + cluster + networkPolicies + scheduler
