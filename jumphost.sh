#!/bin/bash

# On jumphost
# these functions are tightly coupled with jumphost environment
get_uuid() {
  clustername=${1:?}
  pks cluster ${clustername} | awk '/UUID/{print $2}'
}

delete_nat_rule() {
  clustername=${1:?}
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
  release=${1:?}
  value=${2:?}
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

print_help() {
  type $1
}

get_ncp_process_id() {
  clustername=${1:?}
  uuid=$(get_uuid ${clustername})
  target=${2:?}
  bosh -d service-instance_${uuid} ssh ${target} 'ps -ef  | grep ncp' | awk '/start_ncp/{print $5}'
}

kill_ncp_process() {
  clustername=${1:?}
  uuid=$(get_uuid ${clustername})
  target=${2:?}
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

check_vmk50() {
  host_paths=$(govc ls /kubo-dc/host/* | grep -v Resources)
  readarray -t hosts <<<"$host_paths"
  for host in "${hosts[@]}"
  do
    host_ip=$(echo $host| rev | cut -d'/' -f 1 | rev)
    echo "$host_ip"

    sshpass -p 'Ponies!23' ssh -o StrictHostKeyChecking=no root@$host_ip "esxcfg-vmknic -l | grep vmk50"
    echo "###"
  done
}

get_pks_guid() {
  # TODO: $PKS_TILE_NAME is hardcoded here
  guid=$(${omcli} curl -s -p '/api/v0/staged/products' | jq  -cr '.[] | select( .type=="pivotal-container-service" ) | .guid')
  echo $guid
}

get_pks_info() {
  export PKS_GUID="$(get_pks_guid)"
  echo "PKS GUID: ${PKS_GUID}"
  export PKS_IP=$(${omcli} curl -s -p "/api/v0/deployed/products/${PKS_GUID}/status" | jq -cr '.status[].ips[0]')
  echo "PKS IP: ${PKS_IP}"
  echo "get pks certificate"
  ${omcli} curl -s -p "/api/v0/deployed/products/${PKS_GUID}/credentials/.pivotal-container-service.pks_tls" | jq -c -r .credential.value.cert_pem > /home/kubo/pks.crt
}

pks_login() {
  uaa_hostname=$(get_pks_property_value pks_api_hostname)
  username=${PKS_USERNAME:-alana} # use PKS_USERNAME here
  password=${PKS_PASSWORD:-password} # use PKS_PASSWORD here
  pks login -a ${uaa_hostname} -u ${username} -p ${password} -k
}

pks_setup_login() {
  echo "set target"
  uaa_hostname=$(get_pks_property_value pks_api_hostname)
  add_dns "30.0.0.12" ${uaa_hostname}
  uaac target https://${uaa_hostname}:8443 --skip-ssl-validation

  echo "Fetching uaa admin secret"
  guid=$(get_pks_guid)
  secret=$(${omcli} curl -s --path "/api/v0/deployed/products/${guid}/credentials/.properties.pks_uaa_management_admin_client"  | jq -c -r '.credential.value.secret')

  echo "uaac login"
  uaac token client get admin -s ${secret}

  username=${PKS_USERNAME:-alana} # use PKS_USERNAME here
  password=${PKS_PASSWORD:-password} # use PKS_PASSWORD here
  echo "uaac create user ${username}"
  uaac user add ${username} --given_name ${username} --family_name pks --emails ${username}@pks.com -p ${password}
  echo "uaac add user ${username} to pks.clusters.admin"
  uaac member add pks.clusters.admin ${username}

  echo "get pks certificate"
  ${omcli} curl -s -p "/api/v0/deployed/products/${guid}/credentials/.pivotal-container-service.pks_tls" | jq -c -r .credential.value.cert_pem > /home/kubo/pks.crt

  echo "pks login"
  pks login -a ${uaa_hostname} -u ${username} -p ${password} --ca-cert /home/kubo/pks.crt
}

list_product_properties() {
  guid=$1
  ${omcli} curl -s -p "/api/v0/staged/products/${guid}/properties" | jq -cr '.properties | keys[]' | sed 's/.properties.//g'
}

list_pks_properties() {
  guid=$(get_pks_guid)
  ${omcli} curl -s -p "/api/v0/staged/products/${guid}/properties" | jq -cr '.properties | keys[]' | sed 's/.properties.//g'
}

get_pks_property_value() {
  guid=$(get_pks_guid)
  key=$1
  ${omcli} curl -s -p "/api/v0/staged/products/${guid}/properties" | jq -cr ".properties[\".properties.${key}\"].value"
}

add_dns() {
  echo "${1}  ${2}" | sudo tee -a /etc/hosts > /dev/null
}

list_pks_utils() {
  echo "get_uuid"
  echo "delete_nat_rule"
  echo "replace_release_version"
  echo "get_ncp_process_id"
  echo "kill_ncp_process"
  echo "kill_procee_by_id_on_machine"
  echo "check_ncp_master_status"
  echo "list_machines"
  echo "find_ncp_master_machine"
  echo "check_vmk50"
  echo "get_pks_guid"
  echo "get_pks_info"
  echo "pks_login"
  echo "pks_setup_login"
  echo "list_product_properties"
  echo "list_pks_properties"
  echo "get_pks_property_value"
  echo "add_dns"
  echo "list_pks_utils"
  echo "disable_resurrector"
}

pks_utils_help() {
  func=${1:?pks_utils_help [funcname]}
  type ${func}
}

disable_resurrector() {
  ${omcli} configure-director --director-configuration '{"resurrector_enabled": false}'
}

watch_deployment() {
  source gw_scripts/bosh_env.sh
  bosh -d service-instance_$(get_uuid ${1}) task
}

install_gsutil_on_ubuntu() {
	export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)"
	echo "deb http://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
	curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
        sudo apt-get update && sudo apt-get install google-cloud-sdk
}


