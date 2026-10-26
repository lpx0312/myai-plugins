---
name: kubekey-install
description: 用 KubeKey v4 离线包在内网 Kylin/麒麟等机器上装 k8s 集群（单 master / 多 master、外部 Harbor / 内置 Harbor、calico/cilium、nfs/openebs 存储类），以及集群起来后加节点、删节点、重置、换安装方式重装。当用户提到 kubekey、kk create cluster、离线包 kubekey-offline-*.tar.gz、inventory.yaml / config.yaml、k8s 装机、单 master、外部 Harbor 装 k8s、harbor.sktill.top 拉镜像、nfs-client / openebs-hostpath 存储类挂不上、calico 起不来、节点 NotReady、证书续期等场景时使用，即使没说"kubekey"三个字（例如"用离线包装一个 k8s 集群"）。
---

# KubeKey v4 离线装 k8s 集群

核心事实：**一次离线安装 = 4 个输入**，缺一不可，其它全是填参数。

| 输入 | 说明 |
|---|---|
| `kubekey-artifact.tgz` | 制品包（binary + charts + manifests），从离线包解出 |
| `kk` 二进制 | 从 `tools/amd64/kubekey-v*-linux-amd64.tar.gz` 解出 |
| `inventory.yaml` | 机器清单：IP、SSH 凭据、角色分组 |
| `config.yaml` | 集群参数：版本、HA 类型、CRI、CNI、存储类、镜像仓库 |

## 1. 制品来源（内网 mirrors）

文件服务器：`http://mirrors.lpx.com` = `http://192.168.0.180:8082` = 本机 `Z:` 盘，路径 `/soft/k8s/k8s_install/kubekey/`。

```
offline/<k8s版本>/<场景: k8s|k8s-ks>/<架构: amd64|arm64|all>/kubekey-offline-<ver>-<场景>-<架构>-<源:in|out>.tar.gz
configs/<k8s版本>-<安装方式>/ { config.yaml, inventory.yaml, harbor-config.yaml }
```

- `in` = 镜像已指向内网 Harbor；`out` = 公网源；`k8s` = 仅集群，`k8s-ks` = 带 KubeSphere
- 命名由 Jenkinsfile 参数（SCENE/ARCH/SOURCE）生成，见同目录 `Jenkinsfile` + `scripts/build-offline.sh`

## 2. 标准步骤（照抄）

```bash
cd /root
wget http://192.168.0.180:8082/soft/k8s/k8s_install/kubekey/offline/v1.31.14/k8s/amd64/kubekey-offline-v1.31.14-k8s-amd64-in.tar.gz
mkdir kubekey && tar -xf kubekey-offline-*.tar.gz -C kubekey && cd kubekey
# 取该安装方式的配置模板，按环境改 IP / 密码 / 存储类 / 仓库地址
wget http://192.168.0.180:8082/soft/k8s/k8s_install/kubekey/configs/v1.31.14-单master-外部Harbor/{config.yaml,inventory.yaml}
tar -xf tools/amd64/kubekey-v4.0.5-portfix-linux-amd64.tar.gz -C .
./kk create cluster -a kubekey-artifact.tgz -i inventory.yaml -c config.yaml
```

跑之前可先 `./kk precheck -i inventory.yaml -c config.yaml`（可选，省一次重装）。

## 3. 两种最关键的选择

**a) 镜像从哪来 → `spec.image_registry.type`**

| 值 | 含义 | 配套 |
|---|---|---|
| `""`（空） | 用已存在的外部仓库，不装 registry | `auth.registry/auth.username/auth.password` 必填，镜像须**事先**在仓库里 |
| `harbor` | kk 在 `image_registry` 组机器上装 Harbor | `ha_vip`（多机 HA）、`type: harbor`、harbor-config.yaml |

外部 Harbor 模式下，所有镜像地址会被重写成 `<auth.registry>/<上游项目名>/<镜像>:<tag>`，实测布局：
`harbor.sktill.top:7000/kubernetes/kube-apiserver:v1.31.14`、
`harbor.sktill.top:7000/calico/node:v3.30.5`、
`harbor.sktill.top:7000/openebs/provisioner-localpv:4.4.0`。
仓库里缺镜像就在本机用 dsync-cli 同步补齐（路径必须与上游一致），否则节点卡 `ImagePullBackOff`。
装有内网仓库的账号密码会自动写进 `/etc/containerd/config.toml` 的 `registry.configs.<host>.auth`（含 `insecure_skip_verify = true`）。

**b) 控制面高可用 → `spec.kubernetes.control_plane_endpoint.type`**

| 值 | 场景 |
|---|---|
| `local` | 单 master（当前 kk-master/kk-work 这套）；worker 需能解析 master 主机名 |
| `kube-vip` | 多 master，配 `kube_vip.address`（VIP）+ `mode: ARP` |
| `haproxy` | 多 master，外部 LB/本地 haproxy |

## 4. 按需改的字段（其余保持默认）

| 字段 | 说明 |
|---|---|
| `kubernetes.cluster_name` | 集群名，避免测试环境撞名 |
| `kubernetes.kube_version` | 必须与制品包/目录版本一致 |
| `kubernetes.helm_version` | 随 kube_version 变：v1.31.14→v3.13.3，v1.32.13→v3.14.3 |
| `cri.container_manager` | `containerd`（默认）或 `docker` |
| `cni.type` | calico（默认，起 tigera-operator）/ cilium / flannel / kubeovn / hybridnet |
| `certs.*.date` | 模板给 876000h（100 年），别改小 |
| `kubernetes.certs.*` | 固定复用 `/root/kubekey/kubekey/kubekey/pki/*.crt`，`renew: true` 重装时换新证书 |
| `native.ntp.servers` | 填 inventory 里的主机名（自动取 internal_ipv4）或真实 NTP IP |
| `storage_class.local` / `nfs` | openebs-hostpath / nfs-subdir；`default` 只能有一个为 true |
| `dns.nodelocaldns.enabled` | 默认 true |

inventory 只有三件事：`hosts`（每台的 `internal_ipv4` + ssh connector）、`groups`（`kube_control_plane` / `kube_worker` / `etcd` / `image_registry`）、`k8s_cluster` 聚合组。**主机名要和 config 里引用的一致**（ntp servers、control_plane endpoint）。

## 5. 装完必做校验

```bash
kubectl get node -o wide          # 全部 Ready，VERSION 对得上
kubectl get pod -A | grep -v Running   # 应为空（Completed 除外）
kubectl get sc                    # 至少一个 (default)
kubectl get pod -A -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}' | sort -u
```

## 6. 常见坑（都踩过）

| 现象 | 原因 / 处理 |
|---|---|
| nfs-subdir-external-provisioner `ContainerCreating`，事件 `mount failed: exit status 32 / bad option; you might need a /sbin/mount.<type> helper` | 节点没装 NFS 客户端。**所有节点** `yum install -y nfs-utils`，pod 自动恢复（Kylin V10 自带源里就有） |
| 节点 `ImagePullBackOff` | 外部 Harbor 缺镜像或路径层级不对，按第 3(a) 节补同步 |
| `/var/lib/containerd`、`/var/lib/kubelet` 装完就快满 | 装机前先给这两个目录挂独立盘（见 linux-disk-manager），装完再挂会丢数据/要重装 |
| 重装报证书/etcd 残留 | `./kk delete cluster -i inventory.yaml` 或按节点 `kk delete node`，清 `/etc/kubernetes`、`/var/lib/etcd` |
| 单 master 用 `local` 后 worker 解析不到 master | 配 hosts 或改 `kube-vip`/hostname 解析，见 config 注释 |
| NTP 不生效 | `servers` 用主机名要有对应 inventory host + internal_ipv4 |

## 7. 扩容 / 缩容 / 重装

```bash
./kk add nodes    -i inventory.yaml -c config.yaml   # inventory 里加主机并归组后执行
./kk delete node <hostname> -i inventory.yaml        # 缩容
./kk delete cluster -i inventory.yaml                # 整集群卸载
./kk create config --with-kubernetes v1.31.14 -o config.yaml   # 生成全新模板再自己改
./kk artifact images -a kubekey-artifact.tgz ...     # 把制品包里的镜像推送到仓库
```

kk 版本实测 v4.0.5-portfix；`./kk <cmd> --help` 永远比文档准。

## 8. 已验证环境（参考基线）

kylin v10 (Halberd) x86_64 / containerd 1.7.13 / k8s v1.31.14 / calico v3.30.5 / 外部 harbor `harbor.sktill.top:7000` / 单 master `local` / nfs-client 默认 SC + openebs-hostpath。
