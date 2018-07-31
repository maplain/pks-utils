#!/bin/bash

# On jumphost
delete_nat_rule() {
  clustername=${1}
  uuid=$(pks cluster ${clustername} | awk '/UUID/{print $2}')
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
