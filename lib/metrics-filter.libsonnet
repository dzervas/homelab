// Restrict which metrics a ServiceMonitor/PodMonitor ships.
//
// Alloy's prometheus.operator.{servicemonitors,podmonitors} components honour the
// `metricRelabelings` field of the CRs they discover, so an allow list added here is
// applied at scrape time by the collector - no Fleet Management edits required.
{
  // allowList(objects, regex) returns `objects` (a Tanka helm.template result) with a
  // keep-only-`regex` rule appended to every ServiceMonitor and PodMonitor endpoint.
  allowList(objects, regex): {
    local rule = { sourceLabels: ['__name__'], regex: regex, action: 'keep' },
    local withRule(endpoints) = [
      e { metricRelabelings: (if std.objectHas(e, 'metricRelabelings') then e.metricRelabelings else []) + [rule] }
      for e in endpoints
    ],

    [name]:
      local o = objects[name];
      local kind = if std.objectHas(o, 'kind') then o.kind else '';
      if kind == 'ServiceMonitor' then
        o { spec+: { endpoints: withRule(o.spec.endpoints) } }
      else if kind == 'PodMonitor' then
        o { spec+: { podMetricsEndpoints: withRule(o.spec.podMetricsEndpoints) } }
      else
        o
    for name in std.objectFields(objects)
  },
}
