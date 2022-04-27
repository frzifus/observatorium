local tenant = {
  name: 'test-oidc',
  id: '1610b0c3-c509-4592-a256-a1871353dbfa',
  clientID: 'observatorium',
  issuerURL: 'http://172.17.0.1:4444/',
  user: 'user',
};

local minio = (import '../../components/minio.libsonnet')({
  namespace: 'observatorium-minio',
  buckets: ['thanos', 'loki'],
  accessKey: 'minio',
  secretKey: 'minio123',
});

local api = (import 'observatorium-api/observatorium-api.libsonnet');
local obs = (import '../../components/observatorium.libsonnet');
local tracing = (import '../../components/tracing.libsonnet');
local elastic = (import '../../components/elastic.libsonnet');
local dev = obs {
  // REF: https://github.com/openshift/elasticsearch-operator/blob/master/config/samples/logging_v1_elasticsearch.yaml
  elastic: elastic(
    obs.elastic.config {
      spec: {
        managementState: 'Managed',
        nodeSpec: {
          resources: {
            limits: {
              memory: '1Gi',
            },
            requests: {
              cpu: '100m',
              memory: '512Mi',
            },
          },
        },
        nodes: [
          {
            nodeCount: 1,
            roles: [
              'client',
              'data',
              'master',
            ],
            storage: {
              size: '20G',
            },
          },
        ],
        redundancyPolicy: 'ZeroRedundancy',
        indexManagement: {
          policies: [
            {
              name: 'infra-policy',
              pollInterval: '30m',
              phases: {
                hot: {
                  actions: {
                    rollover: {
                      maxAge: '8h',
                    },
                  },
                },
                delete: {
                  minAge: '2d',
                },
              },
            },
          ],
          mappings: [
            {
              name: 'infra',
              policyRef: 'infra-policy',
              aliases: [
                'infra',
                'logs.infra',
              ],
            },
          ],
        },
      },
    },
  ),
  tracing: tracing(
    obs.tracing.config {
      tenants: [tenant.name],
      enabled: true,
      jaegerSpec: {
        strategy: 'production',
        storage: {
          type: 'elasticsearch',
          options: {
            es: {
              'server-urls': 'http://' + 'TODO(elasticsearch)' + ':9200',
            },
          },
        },
        ui: {
          options: {
            menu: [
              {
                items: [
                  {
                    label: 'Documentation',
                    url: 'https://access.redhat.com/documentation/en-us/openshift_container_platform/4.9/html/distributed_tracing/index',
                  },
                ],
                label: 'About',
              },
            ],
          },
        },
      },
    },
  ),
  api: api(
    obs.api.config {
      rbac: {
        roles: [
          {
            name: 'read-write',
            resources: [
              'logs',
              'metrics',
              'traces',
            ],
            tenants: [
              tenant.name,
            ],
            permissions: [
              'read',
              'write',
            ],
          },
        ],
        roleBindings: [
          {
            name: 'test',
            roles: [
              'read-write',
            ],
            subjects: [
              {
                name: tenant.user,
                kind: 'user',
              },
            ],
          },
        ],
      },
      tenants: {
        tenants: [
          {
            name: tenant.name,
            id: tenant.id,
            oidc: {
              clientID: tenant.clientID,
              issuerURL: tenant.issuerURL,
            },
            rateLimits: [
              {
                endpoint: '/api/metrics/v1/.+/api/v1/receive',
                limit: 1000,
                window: '1s',
              },
              {
                endpoint: '/api/logs/v1/.*',
                limit: 1000,
                window: '1s',
              },
            ],
          },
        ],
      },
    },
  ),
};

dev.manifests
{
  'minio-deployment': minio.deployment,
  'minio-pvc': minio.pvc,
  'minio-secret-thanos': {
    apiVersion: 'v1',
    kind: 'Secret',
    metadata: {
      name: 'thanos-objectstorage',
      namespace: dev.config.namespace,
    },
    stringData: {
      'thanos.yaml': |||
        type: s3
        config:
          bucket: thanos
          endpoint: %s.%s.svc.cluster.local:9000
          insecure: true
          access_key: minio
          secret_key: minio123
      ||| % [minio.service.metadata.name, minio.config.namespace],
    },
    type: 'Opaque',
  },
  'minio-secret-loki': {
    apiVersion: 'v1',
    kind: 'Secret',
    metadata: {
      name: 'loki-objectstorage',
      namespace: dev.config.namespace,
    },
    stringData: {
      endpoint: 'http://minio:minio123@%s.%s.svc.cluster.local.:9000/loki' % [minio.service.metadata.name, minio.config.namespace],
    },
    type: 'Opaque',
  },
  'minio-service': minio.service,
}
