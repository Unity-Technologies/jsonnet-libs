(import './config.libsonnet') +
{
  local config = $._config.elasticsearch6,
  local images = $._images.elasticsearch6,

  elasticsearch6+: {
    pod_disruption_budget: {
      apiVersion: 'policy/v1beta1',
      kind: 'PodDisruptionBudget',
      metadata: {
        name: '%s-master-pdb' % config.cluster_name,
      },
      spec: {
        maxUnavailable: 1,
        selector: {
          matchLabels: {
            app: '%s-master' % config.cluster_name,
          },
        },
      },
    }
    ,
    service: {
      kind: 'Service',
      apiVersion: 'v1',
      metadata: {
        name: '%s-master' % config.cluster_name,
        labels: {
          app: '%s-master' % config.cluster_name,
        },
        annotations: {},
      },
      spec: {
        type: 'ClusterIP',
        selector: {
          app: '%s-master' % config.cluster_name,
        },
        ports: [
          {
            name: 'http',
            protocol: 'TCP',
            port: 9200,
          },
          {
            name: 'transport',
            protocol: 'TCP',
            port: 9300,
          },
        ],
      },
    },
    service_headless: {
      kind: 'Service',
      apiVersion: 'v1',
      metadata: {
        name: '%s-master-headless' % config.cluster_name,
        labels: {
          app: '%s-master' % config.cluster_name,
        },
        annotations: {
          'service.alpha.kubernetes.io/tolerate-unready-endpoints': 'true',
        },
      },
      spec: {
        clusterIP: 'None',
        publishNotReadyAddresses: true,
        selector: {
          app: '%s-master' % config.cluster_name,
        },
        ports: [
          {
            name: 'http',
            port: 9200,
          },
          {
            name: 'transport',
            port: 9300,
          },
        ],
      },
    },
    statefulset: {
      apiVersion: 'apps/v1',
      kind: 'StatefulSet',
      metadata: {
        name: '%s-master' % config.cluster_name,
        labels: {
          app: '%s-master' % config.cluster_name,
        },
        annotations: {
          esMajorVersion: '6',
        },
      },
      spec: {
        serviceName: '%s-master-headless' % config.cluster_name,
        selector: {
          matchLabels: {
            app: '%s-master' % config.cluster_name,
          },
        },
        replicas: 3,
        podManagementPolicy: 'Parallel',
        updateStrategy: {
          type: 'RollingUpdate',
        },
        volumeClaimTemplates: [
          {
            metadata: {
              name: '%s-master' % config.cluster_name,
            },
            spec: {
              accessModes: [
                'ReadWriteOnce',
              ],
              resources: {
                requests: {
                  storage: '4G',
                },
              },
              storageClassName: 'standard',
            },
          },
        ],
        template: {
          metadata: {
            name: '%s-master' % config.cluster_name,
            labels: {
              app: '%s-master' % config.cluster_name,
            },
            annotations: {},
          },
          spec: {
            securityContext: {
              fsGroup: 1000,
              runAsUser: 1000,
            },
            affinity: {
              podAntiAffinity: {
                requiredDuringSchedulingIgnoredDuringExecution: [
                  {
                    labelSelector: {
                      matchExpressions: [
                        {
                          key: 'app',
                          operator: 'In',
                          values: [
                            '%s-master' % config.cluster_name,
                          ],
                        },
                      ],
                    },
                    topologyKey: 'kubernetes.io/hostname',
                  },
                ],
              },
            },
            terminationGracePeriodSeconds: 120,
            volumes: null,
            enableServiceLinks: true,
            initContainers: [
              {
                name: 'configure-sysctl',
                securityContext: {
                  runAsUser: 0,
                  privileged: true,
                },
                image: images.elasticsearch,
                imagePullPolicy: 'IfNotPresent',
                command: [
                  'sysctl',
                  '-w',
                  'vm.max_map_count=262144',
                ],
                resources: {},
              },
            ],
            containers: [
              {
                name: 'elasticsearch',
                securityContext: {
                  capabilities: {
                    drop: [
                      'ALL',
                    ],
                  },
                  runAsNonRoot: true,
                  runAsUser: 1000,
                },
                image: images.elasticsearch,
                imagePullPolicy: 'IfNotPresent',
                readinessProbe: {
                  exec: {
                    command: [
                      'sh',
                      '-c',
                      |||
                        #!/usr/bin/env bash -e
                        # If the node is starting up wait for the cluster to be ready (request params: "wait_for_status=green&timeout=1s" )
                        # Once it has started only check that the node itself is responding
                        START_FILE=/tmp/.es_start_file

                        # Disable nss cache to avoid filling dentry cache when calling curl
                        # This is required with Elasticsearch Docker using nss < 3.52
                        export NSS_SDB_USE_CACHE=no

                        http () {
                          local path="${1}"
                          local args="${2}"
                          set -- -XGET -s

                          if [ "$args" != "" ]; then
                            set -- "$@" $args
                          fi

                          if [ -n "${ELASTIC_USERNAME}" ] && [ -n "${ELASTIC_PASSWORD}" ]; then
                            set -- "$@" -u "${ELASTIC_USERNAME}:${ELASTIC_PASSWORD}"
                          fi

                          curl --output /dev/null -k "$@" "http://127.0.0.1:9200${path}"
                        }

                        if [ -f "${START_FILE}" ]; then
                          echo 'Elasticsearch is already running, lets check the node is healthy'
                          HTTP_CODE=$(http "/" "-w %{http_code}")
                          RC=$?
                          if [[ ${RC} -ne 0 ]]; then
                            echo "curl --output /dev/null -k -XGET -s -w '%{http_code}' \${BASIC_AUTH} http://127.0.0.1:9200/ failed with RC ${RC}"
                            exit ${RC}
                          fi
                          # ready if HTTP code 200, 503 is tolerable if ES version is 6.x
                          if [[ ${HTTP_CODE} == "200" ]]; then
                            exit 0
                          elif [[ ${HTTP_CODE} == "503" && "6" == "6" ]]; then
                            exit 0
                          else
                            echo "curl --output /dev/null -k -XGET -s -w '%{http_code}' \${BASIC_AUTH} http://127.0.0.1:9200/ failed with HTTP code ${HTTP_CODE}"
                            exit 1
                          fi

                        else
                          echo 'Waiting for elasticsearch cluster to become ready (request params: "wait_for_status=green&timeout=1s" )'
                          if http "/_cluster/health?wait_for_status=green&timeout=1s" "--fail" ; then
                            touch ${START_FILE}
                            exit 0
                          else
                            echo 'Cluster is not yet ready (request params: "wait_for_status=green&timeout=1s" )'
                            exit 1
                          fi
                        fi
                      |||,
                    ],
                  },
                  failureThreshold: 3,
                  initialDelaySeconds: 10,
                  periodSeconds: 10,
                  successThreshold: 3,
                  timeoutSeconds: 5,
                },
                ports: [
                  {
                    name: 'http',
                    containerPort: 9200,
                  },
                  {
                    name: 'transport',
                    containerPort: 9300,
                  },
                ],
                resources: {
                  limits: {
                    cpu: '1000m',
                    memory: '2Gi',
                  },
                  requests: {
                    cpu: '1000m',
                    memory: '2Gi',
                  },
                },
                env: [
                  {
                    name: 'node.name',
                    valueFrom: {
                      fieldRef: {
                        fieldPath: 'metadata.name',
                      },
                    },
                  },
                  {
                    name: 'discovery.zen.minimum_master_nodes',
                    value: '2',
                  },
                  {
                    name: 'discovery.zen.ping.unicast.hosts',
                    value: '%s-master-headless' % config.cluster_name,
                  },
                  {
                    name: 'cluster.name',
                    value: config.cluster_name,
                  },
                  {
                    name: 'network.host',
                    value: '0.0.0.0',
                  },
                  {
                    name: 'ES_JAVA_OPTS',
                    value: '-Xmx1g -Xms1g',
                  },
                  {
                    name: 'node.data',
                    value: 'true',
                  },
                  {
                    name: 'node.ingest',
                    value: 'true',
                  },
                  {
                    name: 'node.master',
                    value: 'true',
                  },
                ],
                volumeMounts: [
                  {
                    name: '%s-master' % config.cluster_name,
                    mountPath: '/usr/share/elasticsearch/data',
                  },
                ],
              },
            ],
          },
        },
      },
    },
  },
}
