# ansible-kubeadm
 kubeadm 搭建高可用集群

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
