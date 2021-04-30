# Unity's Jsonnet libraries

This repository contains various Jsonnet libraries we use at Unity Data
Platform:


* [`util`](util/): Utility functions for kubernetes.
* [`elasticsearch6`](elasticsearch6/): A set of extensible configurations for
  running Elasticseach 6.


### How to consume
All jb compliant tools should be able to consume from this library
```
jb init
jb install git+ssh://git@github.com/Unity-Technologies/jsonnet-libs.git/elasticsearch6
```
