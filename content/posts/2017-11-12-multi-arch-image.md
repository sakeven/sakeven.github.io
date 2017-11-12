+++
title = "多架构 Docker 镜像"
date = "2017-11-13T01:06:00+08:00"
tags = ["docker", "image"]
categories = ["Docker"]
draft = false
+++

目前，docker 有两“多”经常会被看到。

 一是多阶段构建（[multi-stage build](https://github.com/moby/moby/issues/31067)），这个功能是在今年年初提议，5 月份正式在 docker 17.05.0-ce 中发布的，早在 2016 年 4 月， DaoCloud 公有云上，本人就实现了类似的”二阶段构建“，即安全构建，主要解决用户源码泄漏的风险与构建时镜像过大的问题。不过这个不是今天的重点。

另一个即是多架构标签镜像（[multi-arch tag image](https://github.com/moby/moby/issues/15866)）。

# 多架构标签镜像

这个特性，可以让你在不同架构系统上拉取同一个标签的镜像，比如

```bash
docker pull golang:1.9.2
```

在 Linux 系统的就会拉取到一个可以在 Linux 上运行的 `golang` 镜像，而在 Windows 上则是一个大小与 `golang:1.9.2-windowsservercore` 相同（实际上就是同一个）的镜像。除此之外，我们还能在 `ppc64le`、`s390x`、`arm64`、`arm` 架构 Linux 拉取到对应平台的镜像。一行命令走天下，很不错吧！

### 群体

今年 9 月份，[Docker 正式宣布官方镜像是多平台的](https://blog.docker.com/2017/09/docker-official-images-now-multi-platform/)。谁会使用这个呢？很少有最终用户会直接创建多架构标签的镜像，因为一般一个业务要么是 Windows 平台，要么是 Linux 平台，谁会闲着在不同平台上，构建一个相同功能的应用呢？

看看 Docker 怎么说的：

> - Base operating system images like [Ubuntu](https://store.docker.com/images/ubuntu), [BusyBox](https://store.docker.com/images/busybox) and [Debian](https://store.docker.com/images/debian)
> - Ready-to-use build and runtime images for popular programming languages like [Go](https://store.docker.com/images/golang), [Python](https://store.docker.com/images/python) and [Java](https://store.docker.com/images/openjdk)
> - Easy-to-use images for data stores such as [PostgreSQL](https://store.docker.com/images/postgres), [Neo4j](https://store.docker.com/images/neo4j) and [Redis](https://store.docker.com/images/redis)
> - Pre-packaged software images to run [WordPress](https://store.docker.com/images/wordpress), [Ghost](https://store.docker.com/images/ghost) and [Redmine](https://store.docker.com/images/redmine) and many other popular open source projects

可以看出，使用这个的都是镜像提供商，包括各种操作系统，编程语言，数据存储，及预打包软件等。他们的产品是面向多平台的，供之后的终端用户使用。

### 实现

这个实现与 Docker 镜像在镜像仓库中存储方式有关。最原始的是，一个镜像名对应一个镜像描述文件（manifest）。之后加入了镜像摘要（digest），这个时候，我们就可以通过摘要来下载一个镜像。比如

```bash
docker pull golang@sha256:3011b5966a3d52b64433af0a784f09d12d7f245e7a2e6b93edab38decf11f5b9
```

`sha256:3011b5966a3d52b64433af0a784f09d12d7f245e7a2e6b93edab38decf11f5b9` 就是一个 digest。

所以如果我们每次都只是构建一个名为 `sample:latest` 的镜像，然后推送到仓库里，我们仍然能够通过 digest 来拉取之前的镜像：）。

一个镜像名对应多个真实镜像，与[这个提议](https://github.com/docker/distribution/pull/1068)有关，它最终导致描述文件列表（[mainfest list](https://github.com/docker/distribution/blob/master/docs/spec/manifest-v2-2.md#manifest-list)）的出现。

例如 microsoft/dotnet 镜像：

```json
{
    "schemaVersion": 2,
    "mediaType": "application/vnd.docker.distribution.manifest.list.v2+json",
    "manifests": [
    {
        "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
        "size": 1802,
        "digest": "sha256:f18c692963f43564ad3a665e30dd38277352a9b9bf83f221f50d3fa77802b3e6",
        "platform": {
            "architecture": "amd64",
            "os": "linux"
        }
    },
    {
        "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
        "size": 2614,
        "digest": "sha256:2cb0fbe43df96330e5fabd801979cbb68d57814743d1c2805a585525793b6b2e",
        "platform": {
            "architecture": "amd64",
            "os": "windows",
            "os.version": "10.0.14393.1770"
        }
    },
    {
        "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
        "size": 1783,
        "digest": "sha256:523527dd016bb7bd725797305e2e7f27517d2f0f64bf77338f2cb16dc3cb92b6",
        "platform": {
            "architecture": "amd64",
            "os": "windows",
            "os.version": "10.0.16299.19"
        }
    }
    ]
}
```

上面是一个包含三个平台（linux:amd64、windows:amd64:10.0.14393.1770 和 windows:amd64:10.0.16299.19 ）的描述文件列表。它有三个 manifest，针对不同版本的操作系统，每个 manifest 都有一个对应的 digest，我们可以直接在对应平台上通过 digest 拉取。比如在 Linux 上，通过 

``` bash
docker pull microsoft/dotnet
```

或者

````bash
docker pull \
microsoft/dotnet@sha256:f18c692963f43564ad3a665e30dd38277352a9b9bf83f221f50d3fa77802b3e6
````

得到的都是同一份镜像。

### 构造

既然我们可以这么拉取，那如何来构造一个多架构标签镜像呢？

目前没有官方的工具，来打包多个平台的镜像到同一个标签，docker 正在实现[相关命令行工具](https://github.com/docker/cli/pull/138)。

我自己实现了一个工具，名为 [manifest](https://github.com/sakeven/manifest)，可以查看（inspect）一个镜像的 manifest，创建（create）一个 manifest list。

```
Manifest is a tool for manager manifest of docker images

Usage:
  manifest [command]

Available Commands:
  annotate    annotate a manifest with platform spec
  create      create and push a manifest list
  help        Help about any command
  inspect     inspect an image repository

Flags:
      --cfg string        docker configure file to access docker repository 
                            (default "/Users/sake/.docker")
      --debug             debugmode
  -h, --help              help for manifest
      --password string   Password to access docker repository
      --username string   Username to access docker repository

Use "manifest [command] --help" for more information about a command.
```

