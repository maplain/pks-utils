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
  testbed_get_key 'http_proxy' $1
}

get_nsxt_manager() {
  testbed_get_key 'nsx_manager/hostname' $1
}

list_nimbus_testbeds() {
  ssh -i ~/.ssh/easy fangyuanl@pa-dbc1109.eng.vmware.com "/mts/git/bin/nimbus-ctl --lease 7 --testbed list | awk '/sc-prd-vc/{print}'" | awk -F ',' '{print $1}'
}

extend_lease_testbed() {
  ssh -i ~/.ssh/easy fangyuanl@pa-dbc1109.eng.vmware.com "/mts/git/bin/nimbus-ctl --lease 7 --testbed extend-lease $1"
}

list_local_pks_utils() {
  echo "gen_key_for_jumphost"
  echo "get_key"
  echo "get_proxy"
  echo "get_nsxt_manager"
  echo "list_nimbus_testbeds"
  echo "extend_lease_testbed"
  echo "view_pipeline"
}

view_pipeline() {
  target=${1}
  pp=${2}
  if [[ "$target" == "" || "$pp" == "" ]]; then
    echo "view_pipeline [concourse target name] [concourse pipeline name]"
  fi
  open "$(fly targets | grep ${target} | awk '{print $2}')/teams/$(fly targets | grep ${target} | awk '{print $3}')/pipelines/${pp}"
}
