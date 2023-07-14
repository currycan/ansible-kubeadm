#! /bin/env bash

# docker run --name download -it \
#     -v $PWD/k8s_cache/:/k8s_cache \
#     -v /var/run/docker.sock:/var/run/docker.sock \
#     -v /Volumes/others/Github/ansible-kubeadm/tools/download.sh:/download.sh \
#     centos:7 bash

# docker run --name download -it \
#     -v $PWD/k8s_cache/:/k8s_cache \
#     -v /var/run/docker.sock:/var/run/docker.sock \
#     -v /etc/ansible/tools/download.sh:/download.sh \
#     centos:7 bash
# docker start -i download

set -e

# set output color
NC='\033[0m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'

log::err() {
    printf "[$(date +'%Y-%m-%dT%H:%M:%S.%2N%z')]${RED}[ERROR] %b\n" "$@"${NC}
}

log::info() {
    printf "[$(date +'%Y-%m-%dT%H:%M:%S.%2N%z')]${GREEN}[INFO] %b\n" "$@"${NC}
}

log::warning() {
    printf "[$(date +'%Y-%m-%dT%H:%M:%S.%2N%z')]${YELLOW}[WARNING] %b\n" "$@"${NC}
}

func() {
    echo "Usage:"
    echo "download.sh [-v k8sVersion]"
    echo "Description: download all in one depended offline packages"
    printf "${GREEN}k8sVersion: the version of kubernetes to be downloaded, such as 1.18.20.\n${NC}"
    exit -1
}

while getopts 'v:h' OPT; do
    case $OPT in
        v) k8sVersion="$OPTARG";;
        h) func;;
        ?) func;;
    esac
done

BASE_DIR=/k8s_cache
BINARY_DIR=${BASE_DIR}/binary
IMAGE_DIR=${BASE_DIR}/images
KERNEL_RPM_DIR=${BASE_DIR}/kernel
CHRONY_RPM_DIR=${BASE_DIR}/chrony
DEPENDENCE_RPM_DIR=${BASE_DIR}/dependence
CONTIANERD_RPM_DIR=${BASE_DIR}/containerd

KUBE_IMAGE_REPO="registry.cn-hangzhou.aliyuncs.com/google_containers"

function create_dir (){
    mkdir -p \
        ${KERNEL_RPM_DIR} \
        ${CHRONY_RPM_DIR} \
        ${DEPENDENCE_RPM_DIR} \
        ${CONTIANERD_RPM_DIR} \
        ${IMAGE_DIR}
}

function config_yum_repo () {
    # kernel
    log::info "配置 kernel repo"
    cat > /etc/yum.repos.d/linux-kernel.repo <<EOF
[kernel-longterm-4.19]
name=kernel-longterm-4.19
baseurl=https://copr-be.cloud.fedoraproject.org/results/kwizart/kernel-longterm-4.19/epel-7-x86_64/
enabled=1
gpgcheck=0
EOF
    # docker
    log::info "配置 docker-ce repo"
    if [ ! -f /etc/yum.repos.d/docker-ce.repo ];then
        yum install -y yum-utils
        yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
    fi
    # kubernetes
    log::info "配置 kubernetes repo"
    cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=http://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=http://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg
http://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
    # yum clean all
    # yum makecache -y
}

function download_kernel_rpm (){
    log::info ">>>>>> 开始下载内核 rpm 包"
    yum install -y linux-firmware perl-interpreter
    yum --disablerepo="*" --enablerepo=kernel-longterm-4.19 install -y --downloadonly --downloaddir=${KERNEL_RPM_DIR} \
        kernel-longterm \
        kernel-longterm-core \
        kernel-longterm-devel \
        kernel-longterm-modules \
        kernel-longterm-modules-extra \
        kernel-longterm-cross-headers
    log::info "内核 rpm 包下载完成"
}

function download_chrony_rpm (){
    log::info ">>>>>> 开始下载 chrony rpm 包"
    yum install -y --downloadonly --downloaddir=${CHRONY_RPM_DIR} chrony
    log::info "chrony rpm 包下载完成"
}

function download_dependence_rpm (){
    log::info ">>>>>> 开始下载环境依赖 rpm 包"
    yum install -y --downloadonly --downloaddir=${DEPENDENCE_RPM_DIR} \
        conntrack \
        conntrack-tools \
        psmisc \
        nfs-utils \
        iscsi-initiator-utils \
        jq \
        socat \
        bash-completion \
        rsync \
        ipset \
        ebtables \
        ipvsadm \
        tree \
        git \
        systemd-devel \
        systemd-libs \
        libseccomp \
        libseccomp-devel \
        device-mapper-libs \
        iotop \
        htop \
        net-tools \
        sysstat \
        device-mapper-persistent-data \
        lvm2 \
        curl \
        yum-utils \
        nc \
        nmap-ncat \
        unzip \
        tar \
        btrfs-progs \
        btrfs-progs-devel \
        util-linux \
        libselinux-python \
        wget \
        audit \
        glib2-devel \
        irqbalance
    log::info "环境依赖 rpm 包下载完成"
}

function download_container_runtime_rpm (){
    log::info ">>>>>> 开始下载 containerd 依赖 libseccomp rpm 包"
    # download libseccomp，centos 7中yum下载的版本是2.3的，版本不满足我们最新containerd的需求，需要下载2.4以上的
    curl -fSLo ${CONTIANERD_RPM_DIR}/libseccomp-2.5.2-1.el8.x86_64.rpm https://rpmfind.net/linux/centos/8-stream/BaseOS/x86_64/os/Packages/libseccomp-2.5.2-1.el8.x86_64.rpm
    log::info "libseccomp rpm 包下载完成"
}

function download_containerd_binary (){
    log::info ">>>>>> 开始下载 containerd 二进制包"
    # containerd
    if [ ! -d ${BINARY_DIR}/containerd ];then
        cd /tmp
        curl -fSLO https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/cri-containerd-cni-${CONTAINERD_VERSION}-linux-amd64.tar.gz
        mkdir -p ${BINARY_DIR}/containerd
        tar zxf cri-containerd-cni-${CONTAINERD_VERSION}-linux-amd64.tar.gz -C ${BINARY_DIR}/containerd
        rm -rf ${BINARY_DIR}/containerd/opt/containerd
        rm -rf ${BINARY_DIR}/containerd/etc
        rm -f ${BINARY_DIR}/containerd/*.txt
    fi
    # # crictl
    # if [ ! -f ${BINARY_DIR}/crictl/crictl ];then
    #     cd /tmp
    #     curl -fSLO https://github.com/kubernetes-sigs/cri-tools/releases/download/v${CRICTL_VERSION}/crictl-v${CRICTL_VERSION}-linux-amd64.tar.gz
    #     mkdir -p ${BINARY_DIR}/crictl
    #     tar zxf crictl-v${CRICTL_VERSION}-linux-amd64.tar.gz -C ${BINARY_DIR}/crictl
    # fi
    log::info "containerd 二进制包下载完成"
}

function download_docker_binary (){
    log::info ">>>>>> 开始下载 docker 二进制包"
    if version_lt $KUBE_VERSION '1.24.0';then
        if [ ! -d ${BINARY_DIR}/docker ];then
            cd /tmp
            curl -fSLO https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz
            mkdir -p ${BINARY_DIR}/docker
            tar zxf docker-${DOCKER_VERSION}.tgz -C ${BINARY_DIR}
            yes | cp -a ${BINARY_DIR}/containerd/usr/local/sbin/runc ${BINARY_DIR}/docker/
            yes | cp -a ${BINARY_DIR}/containerd/usr/local/bin/containerd ${BINARY_DIR}/docker/
            yes | cp -a ${BINARY_DIR}/containerd/usr/local/bin/containerd-shim ${BINARY_DIR}/docker/
            yes | cp -a ${BINARY_DIR}/containerd/usr/local/bin/ctr ${BINARY_DIR}/docker/
        fi
    fi
    log::info "docker 二进制包下载完成"
}

function download_etcd_binary (){
    log::info ">>>>>> 开始下载 etcd 二进制包"
    if [ ! -d ${BINARY_DIR}/etcd ];then
        cd /tmp
        curl -fSLO https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-amd64.tar.gz
        mkdir -p ${BINARY_DIR}/etcd
        tar zxf etcd-v${ETCD_VERSION}-linux-amd64.tar.gz -C ${BINARY_DIR}/etcd --strip-components=1
        rm -rf ${BINARY_DIR}/etcd/Documentation
        rm -f ${BINARY_DIR}/etcd/*.md
    fi
    log::info "etcd 二进制包下载完成"
}

function download_kubernetes_binary (){
    log::info ">>>>>> 开始下载 kubernetes 二进制包"
    if [ ! -d ${BINARY_DIR}/kubernetes ];then
        cd /tmp
        curl -fSLO "https://dl.k8s.io/v${KUBE_VERSION}/kubernetes-server-linux-amd64.tar.gz"
        mkdir -p ${BINARY_DIR}/{kube_tmp,kubernetes}
        tar zxf kubernetes-server-linux-amd64.tar.gz -C ${BINARY_DIR}/kube_tmp --strip-components=3
        mv ${BINARY_DIR}/kube_tmp/kube* ${BINARY_DIR}/kubernetes
        rm -rf ${BINARY_DIR}/kube_tmp
        rm -f ${BINARY_DIR}/kubernetes/{*.docker_tag,*.tar,kube-aggregator,kubectl-convert}
    fi
    log::info "kubernetes 二进制包下载完成"
}

function download_helm_binary (){
    log::info ">>>>>> 开始下载 helm 二进制包"
    if [ ! -d ${BINARY_DIR}/helm ];then
        cd /tmp
        curl -fSLO "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz"
        mkdir -p ${BINARY_DIR}/helm
        tar zxf helm-v${HELM_VERSION}-linux-amd64.tar.gz -C ${BINARY_DIR}/helm --strip-components=1
        rm -f ${BINARY_DIR}/helm/LICENSE
        rm -f ${BINARY_DIR}/helm/README.md
    fi
    log::info "helm 二进制包下载完成"
}

function download_images (){
    log::info ">>>>>> 开始下载依赖基础镜像"
    if [ -f ${BINARY_DIR}/docker/docker ];then
        cp ${BINARY_DIR}/docker/docker /usr/local/bin/
        chmod 755 /usr/local/bin/docker
    else
        cd /tmp
        curl -fsSLO https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz
        tar xzvf docker-${DOCKER_VERSION}.tgz --strip 1 -C /usr/local/bin docker/docker
    fi
    # master nodes
    master_images="kube-apiserver:v${KUBE_VERSION} kube-scheduler:v${KUBE_VERSION} kube-controller-manager:v${KUBE_VERSION} etcd:${ETCD_VERSION}-0"
    for img in ${master_images};
    do
        docker pull ${KUBE_IMAGE_REPO}/${img}
    done
    docker pull ghcr.io/kube-vip/kube-vip:v${KUBE_VIP_VERSION}
    docker save -o ${IMAGE_DIR}/master.tar.gz \
        ${KUBE_IMAGE_REPO}/kube-apiserver:v${KUBE_VERSION} \
        ${KUBE_IMAGE_REPO}/kube-scheduler:v${KUBE_VERSION} \
        ${KUBE_IMAGE_REPO}/kube-controller-manager:v${KUBE_VERSION} \
        ${KUBE_IMAGE_REPO}/etcd:${ETCD_VERSION}-0 \
        ghcr.io/kube-vip/kube-vip:v${KUBE_VIP_VERSION}

    # all nodes
    docker pull ghcr.io/labring/lvscare:v${KUBE_LVSCARE_VERSION}
    docker pull ${KUBE_IMAGE_REPO}/kube-proxy:v${KUBE_VERSION}
    docker pull ${KUBE_IMAGE_REPO}/pause:${PAUSE_VERSION}
    docker pull ${KUBE_IMAGE_REPO}/coredns:v${COREDNS_VERSION}
    docker pull registry.k8s.io/dns/k8s-dns-node-cache:${DNS_NODE_CACHE_VERSION}
    docker save -o ${IMAGE_DIR}/all.tar.gz \
        ${KUBE_IMAGE_REPO}/kube-proxy:v${KUBE_VERSION} \
        ${KUBE_IMAGE_REPO}/pause:${PAUSE_VERSION} \
        ${KUBE_IMAGE_REPO}/coredns:v${COREDNS_VERSION} \
        ghcr.io/labring/lvscare:v${KUBE_LVSCARE_VERSION} \
        registry.k8s.io/dns/k8s-dns-node-cache:${DNS_NODE_CACHE_VERSION}

    # worker nodes
    docker pull registry.k8s.io/cpa/cluster-proportional-autoscaler:v${AUTOSCALER_VERSION}
    docker save -o ${IMAGE_DIR}/worker.tar.gz \
        registry.k8s.io/cpa/cluster-proportional-autoscaler:v${AUTOSCALER_VERSION}
    log::info "依赖基础镜像下载完成"
}

function version(){
    # kernel
    KERNEL_OFFLIE_VERSION=`yum --disablerepo="*" --enablerepo=kernel-longterm-4.19 list kernel-longterm --showduplicates | sort -r | grep kernel-longterm | head -1 | awk -F' ' '{print $2}' | awk -F'.el7' '{print $1}'`
    # kubernetes
    KUBE_VERSION=${k8sVersion:-`curl -sSf https://storage.googleapis.com/kubernetes-release/release/stable.txt | grep -v % | grep -oP "[0-9]\d*\.[0-9]\d*\.[0-9]\d*"`}
    # download kubeadm to get component version
    # curl -fSLO /tmp/kubeadm https://dl.k8s.io/v${KUBE_VERSION}/bin/linux/amd64/kubeadm
    log::info "下载 kubeadm 以获取集群组件版本"
    curl -fSLo /tmp/kubeadm https://storage.googleapis.com/kubernetes-release/release/v${KUBE_VERSION}/bin/linux/amd64/kubeadm
    chmod 755 /tmp/kubeadm
    # etcd
    # ETCD_VERSION=`curl -sSf https://github.com/etcd-io/etcd/tags | grep "releases/tag/" | grep -v "rc" | grep -v "alpha" | grep -v "beta" | head -n 1 | grep -oP "[0-9]\d*\.[0-9]\d*\.[0-9]\d*" | head -n 1`
    ETCD_VERSION=`/tmp/kubeadm config images list | grep etcd | cut -d':' -f2 | cut -d'-' -f1`
    # infrastructure pause image
    # PAUSE_VERSION=`curl -sSf https://github.com/kubernetes/kubernetes/blob/master/build/pause/CHANGELOG.md | grep "</h1>" | head -n 2 | grep [0-9]\d*.[0-9]\d* -oP | tail -n 1`
    PAUSE_VERSION=`/tmp/kubeadm config images list | grep pause | cut -d':' -f2`
    # coreDNS
    # COREDNS_VERSION=`curl -sSf https://github.com/coredns/coredns/tags | grep "releases/tag/" | head -n 1 | grep -oP "[0-9]\d*\.[0-9]\d*\.[0-9]\d*" | head -n 1`
    COREDNS_VERSION=`/tmp/kubeadm config images list | grep coredns | cut -d':' -f2 | grep -oP "[0-9]\d*\.[0-9]\d*\.[0-9]\d*"`
    # docker
    # https://kops.sigs.k8s.io/releases/1.20-notes/
    if [ `echo ${KUBE_VERSION} | cut -d'.' -f2` -le 16 ]; then
        DOCKER_VERSION=18.09.9
    elif [ `echo ${KUBE_VERSION} | cut -d'.' -f2` -le 20 ]; then
        DOCKER_VERSION=19.03.15
    elif [ `echo ${KUBE_VERSION} | cut -d'.' -f2` -le 23 ]; then
        DOCKER_VERSION=20.10.22
    else
        DOCKER_VERSION=`curl -sSf https://download.docker.com/linux/static/stable/x86_64/ | grep -e docker- | tail -n 1 | cut -d">" -f1 | grep -oP "[a-zA-Z]*[0-9]\d*\.[0-9]\d*\.[0-9]\d*"`
    fi
    # containerd
    if [ `echo ${KUBE_VERSION} | cut -d'.' -f2` -lt 24 ]; then
        CONTAINERD_VERSION=`curl -sSf https://download.docker.com/linux/centos/7/x86_64/stable/Packages/ | grep -e containerd| grep -oP "[a-zA-Z]*[0-9]\d*\.[0-9]\d*\.[0-9]\d*" | sort -rV | head -n 1`
    else
        CONTAINERD_VERSION=`curl -sSf https://github.com/containerd/containerd/tags | grep "releases/tag/" | grep -v "rc" | grep -v "alpha" | grep -v "beta" | grep -oP "[0-9]\d*\.[0-9]\d*\.[0-9]\d*" | head -n 1`
    fi
    # crictl
    # CRICTL_VERSION=`curl -sSf https://github.com/kubernetes-sigs/cri-tools/tags | grep "releases/tag/" | grep -v "rc" | grep -v "alpha" | grep -v "beta" | grep -oP "[0-9]\d*\.[0-9]\d*\.[0-9]\d*" | head -n 1`
    # helm
    HELM_VERSION=`curl -sSf https://github.com/helm/helm/tags | grep "releases/tag/" | grep -v "rc" | grep -v "alpha" | grep -v "beta" | grep -oP "[0-9]\d*\.[0-9]\d*\.[0-9]\d*" | head -n 1`
    # autoscaler
    AUTOSCALER_VERSION=`curl -sSf https://github.com/kubernetes-sigs/cluster-proportional-autoscaler/tags | grep "releases/tag/" | grep -v chart | grep -v "rc" | grep -v "alpha" | grep -v "beta" | grep -oP "[0-9]\d*\.[0-9]\d*\.[0-9]\d*" | head -n 1`
    # dns-node-cache
    DNS_NODE_CACHE_VERSION=`curl -sSf https://github.com/kubernetes/dns/tags | grep "releases/tag/" | grep -v "rc" | grep -v "alpha" | grep -v "beta" | grep -oP "[0-9]\d*\.[0-9]\d*\.[0-9]\d*" | head -n 1`
    # kube-vip
    KUBE_VIP_VERSION=`curl -sSf https://api.github.com/repos/kube-vip/kube-vip/releases | grep tag_name | head -n 1 | grep -oP "[0-9]\d*\.[0-9]\d*\.[0-9]\d*"`
    # kube-lvscare
    KUBE_LVSCARE_VERSION=`curl -sSf https://github.com/labring/sealos/tags | grep "releases/tag/" | grep -v "rc" | grep -v "alpha" | grep -v "beta" | grep -oP "[0-9]\d*\.[0-9]\d*\.[0-9]\d*" | head -n 1`

    log::info "内核版本: $KERNEL_OFFLIE_VERSION"
    log::info "etcd 版本: $ETCD_VERSION"
    log::info "kubernetes 版本: $KUBE_VERSION"
    log::info "containerd 版本: $CONTAINERD_VERSION"
    log::info "docker 版本: $DOCKER_VERSION"
    log::info "helm 版本: $HELM_VERSION"
    log::info "pause_version 版本: $PAUSE_VERSION"
    log::info "coreDns 版本: $COREDNS_VERSION"
    log::info "autoscaler 版本: $AUTOSCALER_VERSION"
    log::info "dns-node-cache 版本: $DNS_NODE_CACHE_VERSION"
    log::info "kube-vip 版本: $KUBE_VIP_VERSION"
    log::info "kube-lvscare 版本: $KUBE_LVSCARE_VERSION"
}

function set_resource(){
    echo kernel_offlie_version: ${KERNEL_OFFLIE_VERSION} > ${BASE_DIR}/resource.yml
    echo kube_version: ${KUBE_VERSION} >> ${BASE_DIR}/resource.yml
    echo etcd_version: ${ETCD_VERSION} >> ${BASE_DIR}/resource.yml
    echo containerd_version: ${CONTAINERD_VERSION} >> ${BASE_DIR}/resource.yml
    echo docker_version: ${DOCKER_VERSION} >> ${BASE_DIR}/resource.yml
    echo pause_version: ${PAUSE_VERSION} >> ${BASE_DIR}/resource.yml
    echo coredns_version: ${COREDNS_VERSION} >> ${BASE_DIR}/resource.yml
    echo helm_version: ${HELM_VERSION} >> ${BASE_DIR}/resource.yml

    echo kube_image_repository: ${KUBE_IMAGE_REPO} >> ${BASE_DIR}/resource.yml
    echo autoscaler_image: registry.k8s.io/cpa/cluster-proportional-autoscaler:v${AUTOSCALER_VERSION} >> ${BASE_DIR}/resource.yml
    echo dns_node_cache_image: registry.k8s.io/dns/k8s-dns-node-cache:${DNS_NODE_CACHE_VERSION} >> ${BASE_DIR}/resource.yml
    echo kube_vip_image: ghcr.io/kube-vip/kube-vip:v${KUBE_VIP_VERSION} >> ${BASE_DIR}/resource.yml
    echo kube_lvscare_image: ghcr.io/labring/lvscare:v${KUBE_LVSCARE_VERSION} >> ${BASE_DIR}/resource.yml
}

function version_lt() {
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1";
}

function download () {
    create_dir
    config_yum_repo
    version
    download_kernel_rpm
    download_chrony_rpm
    download_container_runtime_rpm
    download_dependence_rpm
    download_containerd_binary
    download_docker_binary
    download_helm_binary
    download_etcd_binary
    download_kubernetes_binary
    download_images
    set_resource
}

if [ -z ${k8sVersion} ];then
    log::warning "未定义 kubernetes 版本, 默认将下载最新版本!!"
else
    log::info "即将下载 v${k8sVersion} 版本 kubernetes 版本离线依赖!"
fi

download | tee download.log
