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
