+++
title = "Qemu 安装"
date = "2016-04-29T15:08:36+08:00"
tags = ["os"]
categories = ["Linux"]
+++

# qemu 在 ubuntu 14.04 下安装

qemu 的 README.md 写的安装方式过于简略。实际上 qemu 的编译安装比较麻烦，需要下载一些依赖。

以下是安装依赖，并配置编译安装 qemu 到 /usr/local/bin 

```bash
wget http://wiki.qemu-project.org/download/qemu-2.6.0-rc3.tar.bz2
tar jxvf qemu-2.6.0-rc3.tar.bz2 
cd qemu-2.6.0-rc3/
sudo apt-get insatll pkg-config libtool libsdl2-dev autoconf
./configure --disable-kvm --prefix=/usr/local --target-list="i386-softmmu x86_64-softmmu"
make && sudo make install
```
