#!/bin/bash

# 此脚本为批量部署服务器ssh key使用

# set -x

# check args count
if [ $# -ne 3 -a $# -ne 2 ]; then
    echo -e "\nUsage: $0 < hosts file > < username > <optional: password >\n"
    exit 1
fi

yum install -y expect

# check hosts file
hosts_file=$1
if ! test -e $hosts_file; then
    echo "[ERROR]: Can't find hosts file"
    exit 1
fi

username=$2
if test $# -eq 3 ; then
    password=$3
fi

# check sshkey file
sshkey_file=~/.ssh/id_ed25519.pub
if ! test -e $sshkey_file; then
    expect -c "
    spawn ssh-keygen -t ed25519
    expect \"Enter*\" { send \"\n\"; exp_continue; }
    "
fi

# get hosts list
hosts=$(ansible -i $hosts_file all --list-hosts | awk 'NR>1')
echo "======================================================================="
echo "hosts: "
echo "$hosts"
echo "======================================================================="

ssh_key_copy()
{
    # delete history
    if [ -f ~/.ssh/known_hosts ];then
        sed "/$1/d" -i ~/.ssh/known_hosts
    fi

    # start copy
    if [ -z $password ]; then
        expect -c "
        set timeout 100
        spawn ssh-copy-id $username@$1
        expect {
            \"yes/no\"   { send \"yes\n\"; exp_continue; }
            \"already exist on the remote system\" { exit 1; }
        }
        expect eof
        "
    else
        expect -c "
        set timeout 100
        spawn ssh-copy-id $username@$1
        expect {
            \"yes/no\"   { send \"yes\n\"; exp_continue; }
            \"*assword\" { send \"$password\n\"; }
            \"already exist on the remote system\" { exit 1; }
        }
        expect eof
        "
    fi
}

# auto sshkey pair
for host in $hosts; do
    echo "======================================================================="

    # check network
    ping -i 0.2 -c 3 -W 1 $host >& /dev/null
    if test $? -ne 0; then
        echo "[ERROR]: Can't connect $host"
        exit 1
    fi

    cat /etc/hosts | grep -v '^#' | grep $host >& /dev/null
    if test $? -eq 0; then
        hostaddr=$(cat /etc/hosts | grep -v '^#' | grep $host | awk '{print $1}')
        hostname=$(cat /etc/hosts | grep -v '^#' | grep $host | awk '{print $2}')
        ssh_key_copy $hostaddr
        ssh_key_copy $hostname
    else
        ssh_key_copy $host
    fi

    echo ""
done
