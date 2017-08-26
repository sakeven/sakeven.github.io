+++
title = "ShadowSocks Analysis"
date = "2016-04-28T21:32:52+08:00"
tags = ["tcp"]
categories = ["Network"]
+++

## Socks5 协议

Socks5 是一种代理协议，常见的还有 http/https、socks4 代理。支持 TCP/UDP。

### 基于 TCP 的 socks5

#### 1. 客户端向代理发送请求进行协商认证：

| VER	| NMETHODS	| METHODS|
|-----|-----------|--------|
| 1	| 1	| 1-255|

1. VER：协议的版本号，0x05
2. NMETHODS：METHODS 部分的长度
3. METHODS：客户端支持的认证方式列表:
```
  0x00 不需要认证
  0x01 GSSAPI
  0x02 用户名、密码认证
  0x03 - 0x7F 由 IANA 分配（保留）
  0x80 - 0xFE 为私人方法保留
  0xFF 无可接受的方法
```

#### 2. 代理从客户端提供的认证方式中选择一个，并返回给客户端

| VER	| METHOD |
|-----|--------|
| 1	| 1 |

#### 3. 认证结束后，客户端与代理进行正常通信：

客户端请求格式：

| VER	| CMD | RSV | ATYP | DST ADDR | DST PORT|
|-----|-----|-----|------|----------|---------|
| 1	 | 1	| 0x00 | 1 | 动态 | 2 |

1. CMD：命令码，0x01（CONNECT请求），0x02（BIND请求），0x03（UDP转发）
2. RSV：保留字段，0x00
3. ATYP “DST ADDR”：根据 ATYP 的不同，DST ADDR（目的地址）长度也不一样
```
  0x01 IPv4 地址，DST ADDR 部分 4 字节长度
  0x03 域名，DST ADDR 第一个字节为域名长度，DST ADDR 剩余的内容为域名，没有\0结尾。
  0x04 IPv6 地址，16 个字节长度。
```
4. DST PORT：目的地址的端口（网络字节序，大端）

代理响应格式：

| VER	| REP | RSV | ATYP | BND ADDR | BND PORT|
|-----|-----|-----|------|----------|---------|
| 1	 | 1	| 0x00 | 1 | 动态 | 2 |

1. REP：响应状态
```
  0x00 表示成功
  0x01 普通SOCKS服务器连接失败
  0x02 现有规则不允许连接
  0x03 网络不可达
  0x04 主机不可达
  0x05 连接被拒
  0x06 TTL超时
  0x07 不支持的命令
  0x08 不支持的地址类型
  0x09 - 0xFF 未定义
```
2. ATYP “BND ADDR”：同 ATYP “DST ADDR”
3. BND PORT：代理服务器使用的端口（网络字节序，大端），BND PORT 和 BND PORT 最好应该返回 DST ADDR 和 DST PORT。

CONNECT
### UDP ASSOCIATE
基于 UDP 的 socks5

## ShadowSocks 协议

与 socks 协议相比，shadowsocks 协议没有握手过程，不需要对第一次请求进行确认。

### 1. 第一次请求格式

| IV | ATYP | DST ADDR | DST PORT |
|----|------|----------|----------|
| 动态 | 1 | 动态 | 2 |

1. IV：Initialization Vector 初始化向量，长度与加密方法有关，用于解密后面的数据。
2. 后三个 ATYP，DST ADDR，DST PORT 和 socks5 代理中的一样。

加密：
