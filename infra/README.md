This Helm chart allows provisioning of:
- Monitoring stack (Grafana, Prometheus, Promtail, Loki)
- CI/CD framework (Tekton)
- Docker registry
- ChartMuseum

 ## Manual installation  ##
 `helm dependency update`
 
 `helm upgrade --install infra --set github.username=<<github-username>> --set github.token=<<github-token>> .`
