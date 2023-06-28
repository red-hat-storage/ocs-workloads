# Repo consumed by https://github.com/red-hat-storage/ocs-ci

Repo will contain workload files to setup

- AMQ
- Couchbase
- Logging
- ECK
    This is the elastic search deployment files.
    
    The yaml files was pulled from : https://download.elastic.co/downloads/eck/<version\>/
    
    The current version is 1.7.1, this version is the supported one for k8s 1.22
    
    to deploy on k8s before 1.16 the *-legacy.yaml files need to be used.
- [RDR](/rdr/)
- [MDR](/mdr/)

