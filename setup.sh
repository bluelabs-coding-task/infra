# Docker
yum install -y yum-utils
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install -y docker-ce-3:20.10.0-3.el8 docker-ce-cli-1:20.10.0-3.el8 containerd.io-1.4.3-3.1.el8
systemctl start docker
systemctl enable docker
usermod -aG docker $USER && newgrp docker

#Minikube
mkdir minikube
cd minikube || exit
curl -LO https://github.com/kubernetes/minikube/releases/download/v1.15.1/minikube-linux-amd64
install minikube-linux-amd64 /usr/local/bin/minikube
cd ..
rm -rf minikube
minikube start --driver=docker --cpus 2 --memory 2048 --disk-size=60g
ln -s $(which minikube) /usr/local/bin/kubectl

#Helm
mkdir helm
cd helm || exit
curl -LO https://get.helm.sh/helm-v3.4.2-linux-amd64.tar.gz
tar -zxvf helm-v3.4.2-linux-amd64.tar.gz
mv linux-amd64/helm /usr/local/bin/helm
cd ..
rm -rf helm

#Tekton
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/previous/v0.19.0/release.yaml
kubectl apply --filename https://github.com/tektoncd/dashboard/releases/download/v0.12.0/tekton-dashboard-release.yaml
kubectl expose deployment tekton-dashboard --name tekton-dashboard-nodeport --port=9097 --target-port=9097 --type=NodePort -n tekton-pipelines --overrides '{ "spec":{"ports":[{"port":9097,"protocol":"TCP","targetPort":9097,"nodePort":30300}]}}'

while [[ $(kubectl -n tekton-pipelines get pods -l app=tekton-pipelines-webhook -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for pod" && sleep 1; done
while [[ $(kubectl -n tekton-pipelines get pods -l app=tekton-pipelines-controller -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for pod" && sleep 1; done

#Tekton CLI
curl -LO https://github.com/tektoncd/cli/releases/download/v0.15.0/tkn_0.15.0_Linux_x86_64.tar.gz
tar xvzf tkn_0.15.0_Linux_x86_64.tar.gz -C /usr/local/bin tkn
rm -f tkn_0.15.0_Linux_x86_64.tar.gz

#Skaffold
curl -Lo skaffold https://storage.googleapis.com/skaffold/releases/latest/skaffold-linux-amd64
install skaffold /usr/local/bin/
rm -f skaffold

## Infra release
kubectl create ns infra
kubectl create ns development
kubectl config set-context --current --namespace=infra
cd infra/infra || exit
helm dependency update
helm upgrade --install infra --wait --set github.username=$GITHUB_USERNAME --set github.token=$GITHUB_TOKEN .


echo Complete!!!