# ansible-kubeadm
 kubeadm 搭建高可用集群

## ansibe 配置

```bash
# 在线安装
ansible-galaxy collection install community.general
ansible-galaxy collection install ansible.posix
# This collection supports Kubernetes versions >= 1.24.x
ansible-galaxy collection install kubernetes.core

# 离线安装
ansible-galaxy install collection-modules/ansible-posix-1.5.4.tar.gz -p $HOME/.ansible/collections/
ansible-galaxy install collection-modules/community-general-7.0.0.tar.gz -p $HOME/.ansible/collections/
```

```bash
kube_offline_version=1.20.15
# kube_offline_version=1.18.20
ansible all -m copy -a "src=/k8s_cache_${kube_offline_version}.tgz dest=/k8s_cache_${kube_offline_version}.tgz"
ansible all -m shell -a "rm -rf /k8s_cache"
ansible all -m shell -a "tar zxf /k8s_cache_${kube_offline_version}.tgz -C /"
ansible all -m shell -a " cp -a /cri-dockerd /k8s_cache/binary/"
ansible all -m copy -a "src=/root/docker dest=/k8s_cache/binary/"

```
authorization-mode
第一个 master 节点（deploy 节点）

```bash
cp -f /k8s_cache/resource.yml /etc/ansible/group_vars/all/resource.yml
```

[Randsw/ha-kubernetes-cluster: High availible kubernetes cluster deploy for education purpose with the ability to deploy a single-node option. Using Vagrant to provision VM and ansible over kubeadm for kubernetes cluster creation. Infrastructure components deployed with Helm. CNI - Cilium](https://github.com/Randsw/ha-kubernetes-cluster)

## calico

```bash
# helm show values projectcalico/tigera-operator --version v3.25.0
mkdir calico && cd calico
helm repo add projectcalico https://docs.projectcalico.org/charts
helm repo update
cat > values.yaml <<EOF
installation:
  enabled: true
  kubernetesProvider: ""
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 172.30.0.0/16
      encapsulation: IPIP
      natOutgoing: Enabled
      nodeSelector: all()
    nodeAddressAutodetectionV4:
      interface: "eth.*|en.*"
EOF
# kubectl delete crd apiservers.operator.tigera.io
# kubectl delete ns tigera-operator

# kubectl create namespace tigera-operator,1.18支持 3.22.5
curl -o /usr/local/bin/calicoctl -O -L  "https://github.com/projectcalico/calicoctl/releases/download/v3.20.6/calicoctl"
chmod +x /usr/local/bin/calicoctl

# 1.18以下版本
version=3.22.5
helm upgrade --install calico projectcalico/tigera-operator \
  --create-namespace -n tigera-operator \
  -f values.yaml \
  --version v${version}

# 1.18以上版本
helm upgrade --install calico projectcalico/tigera-operator \
  --create-namespace -n tigera-operator \
  -f values.yaml
```

## nfs storage class

安装 nfs server

```bash
yum install nfs-utils rpcbind -y
systemctl enable --now rpcbind.service
systemctl enable --now nfs.service
mkdir -p /nfs/data
chown nfsnobody:nfsnobody /nfs/data
echo "/nfs/data 172.21.139.222/20(rw,sync,no_root_squash)">>/etc/exports
echo "/nfs/data 127.0.0.1(rw,sync,no_root_squash)">>/etc/exports
exportfs -rv
showmount -e localhost
```

```bash
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm upgrade --install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace kube-system \
  --set nfs.server=172.21.139.222 \
  --set nfs.path=/nfs/data \
  --set storageClass.name=nfs-storage-class \
  --set storageClass.reclaimPolicy=Delete \
  --set storageClass.accessModes=ReadWriteMany
```

## apisix
[apache/apisix-helm-chart: Apache APISIX Helm Chart](https://github.com/apache/apisix-helm-chart)

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add apisix https://charts.apiseven.com
helm repo update
# hostnetwork
helm upgrade --install apisix apisix/apisix \
  --create-namespace --namespace ingress-apisix \
  --set apisix.hostNetwork=true \
  --set admin.allow.ipList="{0.0.0.0/0}" \
  --set dashboard.enabled=true \
  --set etcd.persistence.storageClass="nfs-storage-class" \
  --set etcd.persistence.size="2Gi" \
  --set ingress-controller.enabled=true


# LoadBalancer
helm upgrade --install apisix apisix/apisix \
  --create-namespace --namespace ingress-apisix \
  --set gateway.type=LoadBalancer \
  --set admin.allow.ipList="{0.0.0.0/0}" \
  --set dashboard.enabled=true \
  --set etcd.persistence.storageClass="nfs-storage-class" \
  --set etcd.persistence.size="2Gi" \
  --set ingress-controller.enabled=true

kubectl patch svc -n ingress-apisix apisix-gateway --patch \
  '{"spec": { "type": "LoadBalancer", "ports": [{"name": "apisix-gateway", "nodePort": 30000, "port": 80, "protocol": "TCP", "targetPort": 9080}]}}'

# 1.18以下版本
cat <<EOF | kubectl apply -f -
---
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: apisix-dashboard
  namespace: ingress-apisix
  annotations:
    kubernetes.io/ingress.class: "apisix"
spec:
  rules:
    - host: dashboard.apisix.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              serviceName: apisix-dashboard
              servicePort: 80
EOF

# 1.18 以上版本
cat <<EOF | kubectl apply -f -
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: apisix-dashboard
  namespace: ingress-apisix
  annotations:
    kubernetes.io/ingress.class: "apisix"
spec:
  rules:
  - host: dashboard.apisix.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: apisix-dashboard
            port:
              number: 80
EOF
```

## metrics-server

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
# 1.18以下版本
helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system --version 3.9.0
# 1.18以上版本
helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system
```

## kuboard

KUBOARD_ENDPOINT 参数的作用是，让部署到 Kubernetes 中的 kuboard-agent 知道如何访问 Kuboard Server,配置成 nodePort 地址

在浏览器输入 http://your-host-ip:80 即可访问 Kuboard v3.x 的界面，登录方式：
用户名： admin
密 码： Kuboard123

ansible kube_masters -a "rm -rf /usr/share/kuboard/etcd"

```bash
kubectl create secret tls kuboard-ing --cert kuboard.yourdomian.com.crt --key kuboard.yourdomian.com.key -n kuboard
kubectl create ingress kuboard -n kuboard --class=apisix --rule="kuboard.yourdomian.com/*=kuboard-v3:80,tls=kuboard-ing"
```

curl -sfL  https://raw.githubusercontent.com/labring/sealos/v4.2.0/scripts/install.sh \
    | sh -s v4.2.0 labring/sealos
docker pull labring/calico:3.24.6
sealos run labring/calico:3.24.6


docker.io/calico/cni                                                          v3.26.0             5d6f5c26c6554       93.3MB
docker.io/calico/csi                                                          v3.26.0             151c86d530ac9       9.87MB
docker.io/calico/kube-controllers                                             v3.26.0             45ae357729e3a       33.8MB
docker.io/calico/node-driver-registrar                                        v3.26.0             f26b4a3a9c76f       12.2MB
docker.io/calico/node                                                         v3.26.0             44f52c09decec       87.6MB
docker.io/calico/pod2daemon-flexvol                                           v3.26.0             d9eeedbe7ebbf       7.28MB
docker.io/calico/typha                                                        v3.26.0             0be6373f732be       29.3MB
ghcr.io/kube-vip/kube-vip                                                     v0.6.0              8c4c99e346ae7       41.7MB
ghcr.io/labring/lvscare                                                       v4.2.0              7eefe1e428415       41.2MB
quay.io/tigera/operator                                                       v1.30.0             1e8ef36e5f251       21.2MB
registry.cn-hangzhou.aliyuncs.com/google_containers/coredns                   1.10.1              ead0a4a53df89       53.6MB
registry.cn-hangzhou.aliyuncs.com/google_containers/coredns                   v1.10.1             ead0a4a53df89       53.6MB
registry.cn-hangzhou.aliyuncs.com/google_containers/etcd                      3.5.7-0             86b6af7dd652c       297MB
registry.cn-hangzhou.aliyuncs.com/google_containers/kube-apiserver            v1.27.2             c5b13e4f7806d       122MB
registry.cn-hangzhou.aliyuncs.com/google_containers/kube-controller-manager   v1.27.2             ac2b7465ebba9       114MB
registry.cn-hangzhou.aliyuncs.com/google_containers/kube-proxy                v1.27.2             b8aa50768fd67       72.7MB
registry.cn-hangzhou.aliyuncs.com/google_containers/kube-scheduler            v1.27.2             89e70da428d29       59.8MB
registry.cn-hangzhou.aliyuncs.com/google_containers/pause                     3.9                 e6f1816883972       747kB
registry.k8s.io/cpa/cluster-proportional-autoscaler                           v1.8.8              b6d1a4be0743f       39.4MB
registry.k8s.io/dns/k8s-dns-node-cache                                        1.22.21             9bcddad607048       69.7MB
registry.k8s.io/metrics-server/metrics-server                                 v0.6.3              817bbe3f2e517       29.9MB
registry.k8s.io/node-problem-detector/node-problem-detector                   v0.8.13             f6ff5cfa085f0       58MB
swr.cn-east-2.myhuaweicloud.com/kuboard/etcd-host                             3.4.16-2            d6066d124f666       53.1MB
swr.cn-east-2.myhuaweicloud.com/kuboard/kuboard-agent                         v3                  02a2e9bda11af       46.6MB
swr.cn-east-2.myhuaweicloud.com/kuboard/kuboard                               v3                  21def9ea80053       201MB
