{
  _config+:: {
    elasticsearch6: {
      cluster_name: 'elasticsearch',
    },
  },

  _images+:: {
    elasticsearch6: {
      elasticsearch: 'docker.elastic.co/elasticsearch/elasticsearch-oss:6.8.13',
    },
  },
}
