#!/bin/bash

init_k8s_master() {
	kubeadm init

	mkdir -p $HOME/.kube
	cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
	chown $(id -u):$(id -g) $HOME/.kube/config
}

init_k8s_worker() {
	workername=$1
	hostnamectl set-hostname $workername
	echo "127.0.0.1 ${workername}" >> /etc/hosts
}

install_dependencies() {
	# install calico
	kubectl apply -f https://docs.projectcalico.org/v3.8/manifests/calico.yaml

	tdnf install -y jq tar

	# install kustomize
	opsys=linux  # or darwin, or windows
	curl -s https://api.github.com/repos/kubernetes-sigs/kustomize/releases/latest |\
	  grep browser_download |\
	  grep $opsys |\
	  cut -d '"' -f 4 |\
	  xargs curl -O -L
	mv kustomize_*_${opsys}_amd64 kustomize
	chmod u+x kustomize
	mv kustomize /usr/local/bin
}

install_cloud_provider() {
	# install cloud provider
	pushd /usr/lib/vmware-wcpgc-manifests/
	  tar xzvf guest-cluster-cloud-provider-kustomize.tgz
	  pushd kustomize
	    bash deploy.sh -e gcova -m svcaccount
	  popd
	popd
}

master_run() {
	init_k8s_master
	install_dependencies

	# setup auto-completion
	source <(kubectl completion bash)

	install_cloud_provider
}
