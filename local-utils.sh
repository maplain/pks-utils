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

extend_sc_testbed() {
  ssh -i ~/.ssh/easy fangyuanl@pa-dbc1109.eng.vmware.com "/mts/git/bin/nimbus-ctl -L sc --lease 7 --testbed extend-lease $1"
}

extend_wdc_testbed() {
  ssh -i ~/.ssh/easy fangyuanl@pa-dbc1109.eng.vmware.com "/mts/git/bin/nimbus-ctl -L wdc --lease 7 --testbed extend-lease $1"
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

