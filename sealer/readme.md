# 安装

## sealer 安装

```bash
wget https://github.com/sealerio/sealer/releases/download/v0.8.5/sealer-v0.8.5-linux-amd64.tar.gz && \
tar zxvf sealer-v0.8.5-linux-amd64.tar.gz && mv sealer /usr/bin
```

## 集群部署

手动安装 docker

```bash
sealer apply -f cluster.yaml --debug
```



sealer run labring/kubernetes:v1.18.20 \
  --masters 172.21.139.219,172.21.139.220,172.21.139.221 \
  --nodes 172.21.139.222 \
  --pk /root/.ssh/id_ed25519
