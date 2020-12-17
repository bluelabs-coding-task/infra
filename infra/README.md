 This repo contains all needed configuration file to install the monitoring stack (Grafana, Prometheus, Docker Registry).

 ## Install manually  ##
 `helm3 dependency update`
 
 `helm3 upgrade --install monitoring-stack -f values-<<cluster_name>>.yaml .`
