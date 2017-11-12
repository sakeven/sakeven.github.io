+++
title = "Flannel 源码分析"
date = "2017-10-15T20:00:00+08:00"
tags = ["network", "docker", "flannel"]
categories = ["Network", "Docker"]
draft = false
+++

Flannel 是 CoreOS 公司针对 docker 和 kubernetes 设计的一个网络工具。本篇主要针对 flannel 源码分析。
以下都基于 v0.9.0 版本的 flannel。 

## 目录结构

<img src="/img/flannel/flannel-tree.png"  style="zoom:30%" alt="flannel tree" align=center />

Documentation 中是 flannel 相关的文档。  
backend 则是 flannel 后端网络实现，主要是 vxlan，hostgw，udp 及其它厂商的网络插件。  
network 主要是 IP 伪装相关的代码。  
subnet 主要是子网相关的数据模型，及与 etcdv2、kubernetes 存储集成。  
除此之外，主目录下还有一个 main.go 文件，flanneld 的入口。  

### main.go

1. 注册所有的 backend。

2. 解析命令行参数列表。
3. 找到外部接口。

    <img src="/img/flannel/main-external-face.png"  style="zoom:50%" alt="flannel external interface" align=center />      

4. 接着创建 subnetManager。subnetManager 主要是用于维护当前集群信息的状态，通知 subnet 的创建删除等等。

    <img src="/img/flannel/main-subnet-manager.png"  style="zoom:50%" alt="flannel subnet manager" align=center />

5. 获取虚拟网络的相关配置，并创建相应的 backend manager，以及注册网络。

    <img src="/img/flannel/main-backend-manager.png"  style="zoom:50%" alt="flannel backend manager" align=center />

6. 运行网络后端 backend。

    <img src="/img/flannel/main-backend.png"  style="zoom:50%" alt="flannel backend" align=center />

### subnet 库

<img src="/img/flannel/subnet-manager.png"  style="zoom:50%" alt="flannel subnet manager" align=center />

subnet manager 接口的实现目前就两个 etcdv2 和 kube。

* GetNetworkConfig 用于获取集群网络的配置信息
* AcquireLease 获取一段子网的使用权
* RenewLease 重新租用该子网
* WatchLease 监听某个子网的变化
* WatchLeases 监听所有子网的变化

### backend 库

<img src="/img/flannel/backend.png"  style="zoom:50%" alt="flannel backend" align=center />

Backend 接口主要用于注册网络。在创建 Backend 的时候，会创建相关网络设备，保存相关子网信息。

<img src="/img/flannel/network.png"  style="zoom:50%" alt="flannel network" align=center />

Network 接口需要实现 Lease 获得子网信息，MTU 最小传输单元大小，Run 运行该网络。

<img src="/img/flannel/backend-manager.png"  style="zoom:50%" alt="flannel backend manager" align=center />

Backend Manager 用于管理所有的 Backend。


## VXLAN

### VXLANBackend

VXLANBackend 的 RegisterNetwork 过程：

1. 创建 VXLAN 设备，名称即为 flannel.<vni>，vni 默认为0，所以一般看到都是 flannel.0。

    <img src="/img/flannel/vxlan-dev.png"  style="zoom:50%" alt="flannel vxlan dev" align=center />

    在创建过程中，有个函数名为 ensureLink，是实际上添加 VXLAN 设备的执行体。
    <img src="/img/flannel/vxlan-ensure-link.png"  style="zoom:50%" alt="flannel vxlan ensure link" align=center />

2. 从 subnet manager 获得一个子网。 

    <img src="/img/flannel/vxlan-acquire-lease.png"  style="zoom:50%" alt="flannel vxlan acquire lease" align=center />

3. 用获得的子网配置 vxlan 设备，ip 地址为子网的第一个地址，然后启动该设备。

    <img src="/img/flannel/vxlan-configure.png"  style="zoom:50%" alt="flannel vxlan configure and up" align=center />

4. 返回一个符合 backend.Network 接口的 netwrok 结构。

    <img src="/img/flannel/vxlan-new-network.png"  style="zoom:50%" alt="flannel vxlan network" align=center />


### network.RUN 网络的运行

上面说的第 4 步，返回了一个 network 结构，现在看看如何运行的吧。

1. 在 goroutine 里监听所有 subnet 的事件。

    <img src="/img/flannel/vxlan-watch-lease.png"  style="zoom:50%" alt="flannel vxlan watch lease" align=center />

2. 同时处理所有监听到的事件，由 handleSubnetEvents 完成。

    <img src="/img/flannel/vxlan-handle-events.png"  style="zoom:50%" alt="flannel vxlan handle events" align=center />

### subnet 事件的处理

1. subnet Added 事件，添加 ARP 表，FDB 表，替换路由。

    <img src="/img/flannel/vxlan-subnet-added.png"  style="zoom:50%" alt="flannel vxlan subnet added" align=center />

2. subnet Removed 事件，则与 Added 事件的行为刚好相反。

#### ARP 表

当应用访问 VXLAN 网络里的另一个应用时，我们只有一个 IP 地址，这时需要将 IP 转换成 MAC 地址，才能在数据链路层通信。  
所以 ARP 表记录的就是 IP 与 VTEP MAC 的映射。

#### FDB 表

当我们知道了 VTEP MAC 的地址后，我们仍不知道这个 VTEP 在那一台主机上，也不知道 VTEP 在哪个 VXLAN 网络（即 VNI、VXLAN Network Identifier 是否一样）内，仍然无法通信。  
这时候就需要记录，VTEP MAC 与 VTEP 的 UDP 地址，及该 VTEP 所属的 VNI。

#### directRouting

当主机位于同一个物理子网，可以直接路由而不需要经过 VXLAN，这样可以提高效率。与 host-gw 类似。
比如远程主机为`172.16.41.133`，我们可以通过如下拿到路由：
```
ip route get 172.16.41.133
```
得到：<img src="/img/flannel/vxlan-iproute.png"  style="zoom:50%" alt="flannel vxlan iproute" align=center /> 

两台主机直连判断方法为：仅有一条路由信息，且不存在网关。

<img src="/img/flannel/vxlan-direct-routing-ok.png"  style="zoom:50%" alt="flannel vxlan direct routing" align=center />
