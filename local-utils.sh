#!/bin/bash

gen_key_for_jumphost() {
  target=$1
  ip=$2
  email=$3
  if [ -z "${email}" ]; then
    email="pks@vmware.com"
  fi
  ssh-keygen -t rsa -b 4096 -C "${email}" -N '' -f ~/.ssh/$target
  sshpass -p 'Ponies!23' scp ~/.ssh/${target}.pub kubo@${ip}:/home/kubo/.ssh/
  sshpass -p 'Ponies!23' ssh kubo@${ip} "cat ~/.ssh/${target}.pub >> ~/.ssh/authorized_keys"
  sshpass -p 'Ponies!23' ssh kubo@${ip} 'sudo systemctl restart sshd'
  sshpass -p 'Ponies!23' ssh kubo@${ip} "sudo sed -i 's/#AuthorizedKeysFile/AuthorizedKeysFile/' /etc/ssh/sshd_config"
  echo alias goto-${target}=\'ssh -i ~/.ssh/${target} kubo@${ip}\' >> ~/.zshrc
}

testbed_get_key() {
  key=$1
  file=$2
  bosh int --path=/$1 $2
}

get_proxy() {
  testbed_get_key 'network/http proxy' $1
}

claim_lock_with_path() {
  if [ -z "$1" ]; then
    echo "claim_lock [path to lock]"
    return
  fi
  if [ ! -f $1 ]; then
    echo "$1 doesn't exist"
  fi
  d=$(dirname $1)
  f=$(basename $1)
  git mv $1 ${d%%${f}}/../claimed/
  git commit -am "claim ${f}"
  git pull origin $(git rev-parse --abbrev-ref HEAD) -r
  git push origin $(git rev-parse --abbrev-ref HEAD)
}

release_lock_with_path() {
  if [ -z "$1" ]; then
    echo "release_lock [path to lock]"
    return
  fi
  if [ ! -f $1 ]; then
    echo "$1 doesn't exist"
  fi
  d=$(dirname $1)
  f=$(basename $1)
  git mv $1 ${d%%${f}}/../unclaimed/
  git commit -am "release ${f}"
  git pull origin $(git rev-parse --abbrev-ref HEAD) -r
  git push origin $(git rev-parse --abbrev-ref HEAD)
}

get_lc_golang() {
  leetcode show ${1} -g -l golang
}

get_nsxt_manager() {
  testbed_get_key 'nsx_manager/hostname' $1
}

list_all_nimbus_testbeds() {
	list_nimbus_wdc_testbeds
	list_nimbus_sc_testbeds
}

list_nimbus_wdc_testbeds() {
  ssh -i ~/.ssh/easy fangyuanl@pa-dbc1109.eng.vmware.com "/mts/git/bin/nimbus-ctl -L wdc --lease 7 --testbed list | awk '/wdc-prd-vc/{print}'" | awk -F ',' '{print $1}'
}

list_nimbus_sc_testbeds() {
  ssh -i ~/.ssh/easy fangyuanl@pa-dbc1109.eng.vmware.com "/mts/git/bin/nimbus-ctl -L sc --lease 7 --testbed list | awk '/sc-prd-vc/{print}'" | awk -F ',' '{print $1}'
}

kill_sc_testbed() {
  ssh -i ~/.ssh/easy fangyuanl@pa-dbc1109.eng.vmware.com "/mts/git/bin/nimbus-ctl -L sc --lease 7 --testbed kill $1"
}

kill_wdc_testbed() {
  ssh -i ~/.ssh/easy fangyuanl@pa-dbc1109.eng.vmware.com "/mts/git/bin/nimbus-ctl -L wdc --lease 7 --testbed kill $1"
}

extend_sc_testbed() {
  ssh -i ~/.ssh/easy fangyuanl@pa-dbc1109.eng.vmware.com "/mts/git/bin/nimbus-ctl -L sc --lease 7 --testbed extend-lease $1"
}

extend_wdc_testbed() {
  ssh -i ~/.ssh/easy fangyuanl@pa-dbc1109.eng.vmware.com "/mts/git/bin/nimbus-ctl -L wdc --lease 7 --testbed extend-lease $1"
}

extend_all_wdc_testbed() {
  for i in $(list_all_nimbus_testbeds | awk -F':' '/wdc-prd-vc/{print $2}' | awk -F'(' '{print $1}' ); do
	 extend_wdc_testbed $i
  done
}

kill_testbed() {
  ssh -i ~/.ssh/easy fangyuanl@pa-dbc1109.eng.vmware.com "/mts/git/bin/nimbus-ctl --testbed kill $1"
}

gotojumpbox() {
  if [ -z "$1" ]; then
    echo "gotojumpbox [jumpbox ip]"
    return
  fi
  sshpass -p 'Ponies!23' ssh -o StrictHostKeyChecking=no kubo@$1
}

list_local_pks_utils() {
  echo "gen_key_for_jumphost"
  echo "get_key"
  echo "get_proxy"
  echo "get_nsxt_manager"
  echo "list_nimbus_testbeds"
  echo "extend_sc_testbed"
  echo "extend_wdc_testbed"
  echo "view_pipeline"
  echo "gotojumpbox"
  echo "fly_ab_hack_nimbus_validate"
  echo "fly_ab_latest_build"
  echo "kill_testbed"
  echo "view_definitions"
}

view_pipeline() {
  target=${1}
  pp=${2}
  if [[ "$target" == "" ]]; then
    echo "view_pipeline [concourse target name] [concourse pipeline name]"
    return
  fi
  if [[ "$pp" == "" ]]; then
    echo "warning: pipeline name not specified. will view all pipelines by default"
  fi
  open "$(fly targets | awk -v t=$target '{if ($1 == t) print $2}')/teams/$(fly targets | awk -v t=$target '{if ($1 == t) print $3}')/pipelines/${pp}"
}

fly_ab_latest_build() {
  pp=${1}
  job=${2}
  sta="$(fly -t npks builds  | grep ${1}/${2} | awk '{print $4}')"
  if [[ "${sta}" != "succeeded" && "${sta}" != "failed" && "${sta}" != "" ]]; then
    build="$(fly -t npks builds  | grep ${1}/${2} | awk '{print $3}')"
    fly -t npks ab -j=${1}/${2} -b="${build}"
  else
    echo "current build status: ${sta}"
  fi
}

fly_ab_hack_nimbus_validate() {
  if [ -z "$1" ]; then
    echo "fly_ab_hack_nimbus_validate [pool name]"
    return
  fi
  fly_ab_latest_build "hack-nimbus" "validate-${1}"
}

view_definitions() {
  open "https://github.com/maplain/pks-utils/blob/master/local-utils.sh"
}

switch_to_releng_gcloud() {
  gcloud auth activate-service-account --key-file <(ct vars get -k "pks-releng-gcp-json" -v <(ct p v -n nsx-t-secrets))
}

switch_to_pks_gcloud() {
  gcloud auth activate-service-account --key-file <(ct vars get -k "gcs-json-key" -v <(ct p v -n common-secrets))
}

cp_to_my_dbc() {
	scp $1 fangyuanl@pa-dbc1109.eng.vmware.com:/dbc/pa-dbc1109/fangyuanl/$2
}

takeshuttle() {
	sshuttle -r kubo@$1 30.0.0.0/16 192.168.111.0/24 192.168.150.0/24 192.167.0.0/24 \
      -e "ssh -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -o ServerAliveCountMax=2" \
      --no-latency-control
}

docker_cleanup() {
	for i in $(docker ps -a | awk '{if (NR>1) print $1}'); do docker rm -f $i; done
}

get_pks_utils() {
	pbcopy < <(echo -ne "source <(curl https://raw.githubusercontent.com/maplain/pks-utils/master/jumphost.sh)")
}

get_raas_password() {
	pbcopy < <(echo -ne 'Gobble79waffles!')
}

get_pks_login() {
	pbcopy < <(echo -ne 'pks login --skip-ssl-verification --username alana --password password --api pks.pks-api.cf-app.com')
}

install_gsutil_on_ubuntu() {
	export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)"
	echo "deb http://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
	curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
        sudo apt-get update && sudo apt-get install google-cloud-sdk
}

get_pks_gkey() {
	pbcopy < <(ct vars get -k "gcs-json-key" -v <(ct p v -n common-secrets))
}

get_raas_gkey() {
	pbcopy < <(ct vars get -k "pks-releng-gcp-json" -v <(ct p v -n nsx-t-secrets))
}

get_gtoken() {
	pbcopy < <(echo ${GITHUB_TOKEN})
}

gen_self_signed_cert() {
	openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365
}

download_kiln() {
	wget https://github.com/pivotal-cf/kiln/releases/download/0.21.0/kiln-linux
	chmod +x kiln-linux
	sudo mv kiln-linux /usr/local/bin/kiln
}

get_p_pks_integration() {
	git clone https://github.com/pivotal-cf/p-pks-integrations
}

build_tile() {
    product_version=${1}

    kiln bake \
        --bosh-variables-directory p-pks-integrations/bosh-variables \
        --forms-directory p-pks-integrations/forms \
        --icon p-pks-integrations/icon.png \
        --instance-groups-directory p-pks-integrations/instance-groups \
        --jobs-directory p-pks-integrations/jobs \
        --metadata p-pks-integrations/base.yml \
        --migrations-directory migrations \
        --output-file p-pks-integrations/out/"pivotal-container-service-${product_version}.pivotal" \
        --properties-directory p-pks-integrations/properties \
        --releases-directory releases \
        --runtime-configs-directory p-pks-integrations/runtime-configs \
        --stemcell-tarball "$( find "p-pks-integrations/stemcells" -maxdepth 1 -name '*-vsphere-esxi-*-go_agent.tgz'  -print -quit )" \
        --variables-file p-pks-integrations/variables.yml \
        --version "$product_version" \
        --variable "metadata_git_sha=29a394cbd93a4f391a716c111ca585d20853d6e0" # dummy git sha
}


update_tile() {
  product_version=${1}
  #${omcli} upload-product -p p-pks-integrations/out/pivotal-container-service-${product_version}.pivotal
  ${omcli} stage-product -p pivotal-container-service -v ${product_version}
  ${omcli} apply-changes
}

install_kubeadm() {
  # Install https support
  apt-get update && apt-get install -y apt-transport-https
  # Get kubernetes repo key
  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
  # Add kubernetes repo to manifest
  cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
  apt-get update
  # install containerd
  apt-get install -y containerd
  # Install kubeadm and docker
  apt-get install -y kubelet kubeadm kubectl docker.io
}

# remember to change hostname
# hostnamectl set-hostname xx
# update /etc/hosts

kubeadm_init() {
	swapoff -a
	kubeadm init --pod-network-cidr=192.168.0.0/16
}

install_calico() {
	kubectl apply -f https://docs.projectcalico.org/v3.8/manifests/calico.yaml
}

install_workload() {
	kubectl run hello --image=k8s.gcr.io/echoserver:1.4 --port=8080
}

taint_masternode() {
	kubectl taint nodes --all node-role.kubernetes.io/master-
}

# add transfer.sh
transfer() { if [ $# -eq 0 ]; then echo -e "No arguments specified. Usage:\necho transfer /tmp/test.md\ncat /tmp/test.md | transfer test.md"; return 1; fi
tmpfile=$( mktemp -t transferXXX ); if tty -s; then basefile=$(basename "$1" | sed -e 's/[^a-zA-Z0-9._-]/-/g'); curl --progress-bar --upload-file "$1" "https://transfer.sh/$basefile" >> $tmpfile; else curl --progress-bar --upload-file "-" "https://transfer.sh/$1" >> $tmpfile ; fi; cat $tmpfile; rm -f $tmpfile; }

add_veth() {
	ip link add veth0 type veth peer name veth1
}

get_k8s_all_crds() {
	kubectl api-resources --verbs=list -o name | xargs -n 1 kubectl get -o name
}
