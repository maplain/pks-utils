#!/bin/bash

# On jumphost
get_uuid() {
  clustername=${1}
  pks cluster ${clustername} | awk '/UUID/{print $2}'
}

delete_nat_rule() {
  clustername=${1}
  uuid=$(get_uuid ${clustername})
  pushd /home/kubo 2>&1 >/dev/null
    source gw_scripts/nsx_env.sh
    source nsx-helper-pkg/utils.sh
    id=$(pks::nsx::client get "logical-routers/${NSX_T0_ROUTER_ID}/nat/rules" | jq -cr ".results[] | select ( .display_name == \"pks-${uuid}-nat-rule\")| .id")
    if [ ! -z "${id}" ]; then
      pks::nsx::client delete "logical-routers/${NSX_T0_ROUTER_ID}/nat/rules/${id}"
    fi
  popd 2>&1 >/dev/null
}

replace_release_version() {
  release=${1}
  value=${2}
  deployment=$(bosh deployments | awk '{print $1}' | grep pivotal-container-service)
  bosh -d ${deployment} manifest > ${deployment}.manifest
  cat > ops.yml <<EOF
- type: replace
  path: /instance_groups/name=pivotal-container-service/properties/service_deployment/releases/name=${release}/version
  value: ${value}
- type: replace
  path: /releases/name=${release}/version
  value: ${value}
EOF
  bosh int -o ops.yml ${deployment}.manifest > ${deployment}.newm
  bosh -d ${deployment} deploy ${deployment}.newm
}

get_ncp_process_id() {
  clustername=${1}
  uuid=$(get_uuid ${clustername})
  target=$2
  bosh -d service-instance_${uuid} ssh ${target} 'ps -ef  | grep ncp' | awk '/start_ncp/{print $5}'
}

kill_ncp_process() {
  clustername=${1}
  uuid=$(get_uuid ${clustername})
  target=$2
  id=$(get_ncp_process_id ${uuid} ${target})
  kill_procee_by_id_on_machine "${id}"
}

kill_procee_by_id_on_machine() {
  clustername=${1}
  uuid=$(get_uuid ${clustername})
  target=$2
  id=$3
  bosh -d service-instance_${uuid} ssh ${target} "sudo su -c \"pkill -P ${id}\""
}

check_ncp_master_status() {
  clustername=${1}
  uuid=$(get_uuid ${clustername})
  target=$2
  bosh -d service-instance_${uuid} ssh ${target} "sudo su -c '/var/vcap/jobs/ncp/bin/nsxcli -c get ncp-master status'"
}

list_machines() {
  clustername=${1}
  uuid=$(get_uuid ${clustername})
  bosh -d service-instance_${uuid} vms |awk '/vm-/{print $1}'
}

find_ncp_master_machine() {
  clustername=${1}
  for m in $(list_machines ${clustername} | grep 'master'); do
    if check_ncp_master_status ${clustername} ${m} | grep 'This instance is the NCP master' 2>&1 >/dev/null; then
      echo ${m}
    fi
  done
}

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

get_key() {
  key=$1
  file=$2
  bosh int --path=/$1 $2
}

get_proxy() {
  testbed_get_key 'http_proxy' $1
}

get_nsxt_manager() {
  testbed_get_key 'nsx_manager/hostname' $1
}
