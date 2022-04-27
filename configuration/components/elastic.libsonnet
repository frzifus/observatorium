// These are the defaults for this components configuration.
// When calling the function to generate the component's manifest,
// you can pass an object structured like the default to overwrite default values.
local defaults = {
  local defaults = self,

  name: 'observatorium-xyz',
  namespace: error 'must provide namespace',
  tenants: [],
  enabled: false,

  commonLabels:: {
    'app.kubernetes.io/name': 'elasticsearch',
    'app.kubernetes.io/part-of': 'observatorium',
    'app.kubernetes.io/instance': defaults.name,
  },
};


function(params) {
  local elastic = self,

  // Combine the defaults and the passed params to make the component's config.
  config:: defaults + params,

  local normalizedName(id) =
    std.strReplace(id, '_', '-'),

  local newCommonLabels(component) =
    elastic.config.commonLabels {
      'app.kubernetes.io/component': normalizedName(component),
    },

  local newElastic(component, config) =
    local name = normalizedName(elastic.config.name + '-elastic-' + component);
    {
      apiVersion: 'logging.openshift.io/v1',
      kind: 'Elasticsearch',
      metadata: {
        name: name,
        namespace: elastic.config.namespace,
        labels: newCommonLabels(component),
      },
      spec: elastic.config.elasticSpec,
    } + {
      spec+: {
        doNotProvision: false,
        // NOTE: is it needed??
        // if ... elastic.config.name tenant exists == add prefix to spec
      },
    },
}
