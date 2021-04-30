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
}
