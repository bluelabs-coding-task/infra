# BlueLabs coding task
The code is hosted in the GitHub organization `bluelabs-coding-task` (https://github.com/bluelabs-coding-task?type=source). It consists of two repositories:
- **infra**, for all the infrastructure tooling described below
- **development**, for the playerbio service

## Prerequisites
Here is the setup I have been using to work on the coding task:
 - e2-medium VM on Google Cloud
 - 100 GB disk storage
 - CentOS 8
 
 Since there are dashboards to be accessed externally, I have created a firewall rule to enable ingress traffic to all ports for the VM I have used.
 
 You don't have to use the same setup, but in case you opt for a different one, you may need to tweak the script below to adapt it to your scenario.

## Setup
1. Log into the VM **as root** (`sudo su -`).
1. Clone the `infra` repository (https://github.com/bluelabs-coding-task/infra.git). For example, on the Google Cloud VM:
    ```
    sudo dnf update -y
    sudo dnf install git -y
    git clone https://github.com/bluelabs-coding-task/infra.git
    ```
    When prompted insert the GitHub username and password/token (those provided via email or those of the `bluelabseu-bot`).
1. Export the following variables to set GitHub username and token:  
    ```
    export GITHUB_USERNAME=<<github-username>>  
    export GITHUB_TOKEN=<<github-token>>
    ```
    As in point 1, use those provided via email or those of the `bluelabseu-bot`. These credentials will be stored in a secret and used by the pipeline to clone the `playerbio` repository.
1. Run the setup script:
   ```
   cd infra
   chmod +x setup.sh
   ./setup.sh
   ```
   It will basically install Minikube, Helm and Docker, and deploy what's needed on the cluster.

### Tooling
Here is a list of the tools that will be installed on the Kubernetes cluster to build, deploy and monitor the service.
- **Tekton**, for building and deploying services. Though it is not meant to be a fully-fledged continuous delivery tool, I thought it was a good fit for this task, since it is open-source, it runs natively in Kubernetes, and fosters best practices for creating cloud-native pipelines.  
    The Tekton dashboard is exposed on port `30300`.
- **Prometheus**, for metric scraping. Exposed on port `30200`.
- **Promtail + Loki**, for log scraping and aggregation.
- **Grafana**, for visualization. Metrics collected by Prometheus and logs aggregated by Loki can be viewed here.  
    There are two preconfigured dashboards: one for generic cluster metrics (_Cluster Monitoring for Kubernetes_), and one specific to the PlayerBio service (_Erlang Service_), obtained by collecting the metrics it exposes.  
    Grafana is exposed on port `30100`.  
    The username is `admin`.  
    To get the password use:
    ```
    kubectl get secret infra-grafana -n infra -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
    ```
- **Docker registry**, for hosting Docker images (for the sake of completeness, since we are building locally, thus it would actually not be required). Exposed on port `30400`.
- **ChartMuseum**, for hosting Helm Charts.
- **Skaffold**, for continuous development. Further details below.

## The pipeline
The pipeline for the Elixir service is defined in declarative style in a yaml file: `infra/templates/build/pipeline-elixir-service.yaml`

It's a composition of tasks that basically do the following:
- Clone the repository.
- Increase chart and app patch versions automatically (more on this later).
- Push the Chart to Chartmuseum.
- Build the service with Kaniko (a cloud-native, lightweight and more secure Docker engine to build images within a cluster) and pushes the produced image to the Docker registry.
- Deploy the service in the `development` namespace. The service will be exposed on port `31100`.

You can manually trigger the pipeline with the following command:

`tkn pipeline start elixir-service --namespace=infra --serviceaccount=builder --param service-name=playerbio --workspace name=source,claimName=sources --use-param-defaults --showlog`

Once run, logs will start steaming. Alternatively, you can watch the pipeline progressing from the Tekton dashboard exposed on port `30300`.

The pipeline definition is applied to the `playerbio` service, but it is designed to be generic, and can be seamlessly reused to build any Elixir service.
Tasks are also generic: they can be cobbled together to form other pipelines with maximum flexibility (that's the beauty of Tekton). Tasks are composed of multiple step, and each step can be executed on a separate builder image, while sources are maintained in a PVC until the pipeline is complete.

### Automated versioning
The pipeline itself is not enough to implement a GitOps-oriented deployment process. However, it prepares the work by automatically increasing the versions of the Helm chart and of the application, and updating the Helm chart accordingly. This way, every build will generate different versions, either for the chart and for the image tag.

The `sem-ver` task (`infra/templates/build/task-sem-ver.yaml`) takes the Helm chart contained in the cloned `playerbio` repo as a reference, and does the following:
- Reads version from `Chart.yaml` and compares it with the latest chart pushed to ChartMuseum. If the major and minor versions match, it increases the patch version of the chart obtained from ChartMuseum, and updates the local chart accordingly. If the local major or minor versions are greater than those read from ChartMuseum (because they have been increased manually), it resets the patch version to 1.
- Does the same with `appVersion`.
- Pushes the updated Chart to ChartMuseum.
- Returns the new `version` and `appVersion` as results, so that it can be used by downstream tasks to tag the built image.

## Skaffold
The `skaffold.yaml` file in the root of the `playerbio` repo is preconfigured to build the service locally and deploy on the development namespace with release name `playerbio-local`. This will greatly simplify developing new features and quickly testing the outcome by sending the service code straight to a real cluster.

Just clone the `playerbio` repository (https://github.com/bluelabs-coding-task/playerbio.git) and run `skaffold dev` from the root of the repo, and it will:
- Build a Docker image based on the local code and push it to the cluster Docker registry.
- Deploy the service. At the end of the deployment, the command to get the related NodePort will be printed.
- Watch local files and re-trigger the build whenever there is a change.
- Cleanup the deployed release when exiting.

## Choices
- Though it is best practice, I haven't defined resource requests and limits on purpose, to avoid scheduling problems depending on the cluster where the coding task will be tested.
- I didn't explicitly set storage classes. Minikube provides its storage class and marks it as default, so that's the one that will be used.
- Ingresses are straightforward to configure in the cloud, but when testing locally, they typically require extra steps, such as configuring custom DNS rules on the host machine. To keep things simple, I have exposed all the relevant services via fixed NodePorts. This is definitely not suitable in a production context, but it will be enough for testing things locally.
- The Docker registry hosting built images runs within the cluster and is not exposed externally via ingress. Since the Docker engine needs to access a registry in order to pull images, when deploying the PlayerBio service, I'm setting the image to localhost:30400/playerbio. Again, not production ready but enough for testing locally.

## Improvement areas
- With proper instrumentation on deployed services, tracing (e.g. with Jaeger) may be added to have a clearer picture of how requests are flowing across the cluster.
- Services are exposed over HTTP. TLS is typically handled by cloud load balancers, that perform TLS termination for incoming requests, or right inside the cluster, by configuring tools like the **cert-manager**, that integrates with the ingress controller to dynamically provision and rotate certificated for services exposed via ingress.
- In a real scenario, multiple microservices would be developed by different teams, pushed to the **development** namespace, and gradually reach production. A GitOps-oriented process would be required to handle services promotions across environments in a clear, trackable and affordable fashion.
- The pipeline can only be triggered manually, since I'm assuming that the host VM is not exposed to the Internet. Tekton supports triggers to automatically run pipelines based on events happening on the GitHb repo, which may be added to improve the CI experience.
- Unfortunately there is no OOTB GitHub integration in Tekton, so the status of the pipeline does not reflect in GitHub. This prevents to exploit GitHub checks to enable merging only if required steps are green.