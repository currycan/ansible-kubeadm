# ansible-kubeadm
 kubeadm 搭建高可用集群

## ansibe 配置

```bash
# 在线安装
ansible-galaxy collection install community.general
ansible-galaxy collection install ansible.posix

# 离线安装
ansible-galaxy install collection-modules/ansible-posix-1.5.4.tar.gz -p $HOME/.ansible/collections/
ansible-galaxy install collection-modules/community-general-7.0.0.tar.gz -p $HOME/.ansible/collections/
```

```bash
# kube_offline_version=1.18.20
kube_offline_version=1.26.0
ansible all -m copy -a "src=/k8s_cache_${kube_offline_version}.tgz dest=/k8s_cache_${kube_offline_version}.tgz"
ansible all -m shell -a "rm -rf /k8s_cache"
ansible all -m shell -a "tar zxf /k8s_cache_${kube_offline_version}.tgz -C /"
```

第一个 master 节点（deploy 节点）

```bash
cp -f /k8s_cache/version.yml /etc/ansible/group_vars/all/version.yml
```
