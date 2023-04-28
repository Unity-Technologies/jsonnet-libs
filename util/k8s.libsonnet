{
  flattenKubernetesObjects(object)::
    if std.isObject(object)
    then
      // a Kubernetes object is characterized by having an apiVersion and Kind
      if std.objectHas(object, 'apiVersion') && std.objectHas(object, 'kind')
      then [object]
      else
        self.flattenKubernetesObjects(std.objectValues(object))
    else if std.isArray(object)
    then
      std.flatMap(
        function(obj)
          self.flattenKubernetesObjects(obj),
        object
      )
    else error 'not a valid kubernetes object: "%s"' % std.toString(object),

  patchKubernetesObjects(object, patch, kind=null, name=null)::
    if std.isObject(object)
    then
      // a Kubernetes object is characterized by having an apiVersion and Kind
      if std.objectHas(object, 'apiVersion') && std.objectHas(object, 'kind')
         && (kind == null || object.kind == kind) && (name == null || object.metadata.name == name)
      then object + patch
      else
        std.mapWithKey(
          function(key, obj)
            self.patchKubernetesObjects(obj, patch, kind, name),
          object
        )
    else if std.isArray(object)
    then
      std.map(
        function(obj)
          self.patchKubernetesObjects(obj, patch, kind, name),
        object
      )
    else object,

  patchLabels(object, labels={})::
    self.patchKubernetesObjects(
      object,
      {
        metadata+: {
          labels+: labels,
        },
      }
    ),

  removeCPULimits(krd)::
    // helper func: type safe std.get()
    local get(object, field) = if std.isObject(object) then std.get(object, field, {}) else {};
    // helper func: knocks out the cpu limit if present
    local patch(c) =
      if get(get(c, 'resources'), 'limits') != {} then
        std.mergePatch(c, { resources: { limits: { cpu: null } } })
      else c;
    // Deployment like
    if get(get(get(get(krd, 'spec'), 'template'), 'spec'), 'containers') != {} then
      krd {
        spec+: {
          template+: {
            spec+: {
              containers: std.map(patch, super.containers),
              [if std.objectHas(krd.spec.template.spec, 'initContainers') then 'initContainers']: std.map(patch, super.initContainers),
            },
          },
        },
      }
    // CRDs, like prometheus.monitoring.coreos.com
    else if get(get(get(krd, 'spec'), 'resources'), 'limits') != {} then
      krd {
        spec: patch(super.spec),
      }
    else
      krd,
}
