+++
title = "/proc/locks"
date = "2018-04-21T20:00:00+08:00"
tags = ["linux", "/proc"]
categories = ["OS", "Linux"]
draft = false
+++

/proc 是由 Linux 内核提供的伪文件系统。

其中 `/proc/locks` 则是保存当前由内核锁定的文件的相关信息。

# 详解

```bash
$ cat /proc/locks
1: POSIX  ADVISORY  READ  4255 08:01:395841 128 128
2: POSIX  ADVISORY  READ  4255 08:01:395663 1073741826 1073742335
3: OFDLCK ADVISORY  WRITE 4254 08:01:395845 0 0
4: POSIX  ADVISORY  READ  4220 08:01:395841 128 128
5: POSIX  ADVISORY  READ  4220 08:01:395663 1073741826 1073742335
6: FLOCK  ADVISORY  WRITE 1291 00:1a:6 0 EOF
7: POSIX  ADVISORY  READ  2124 08:01:395841 128 128
8: POSIX  ADVISORY  READ  2124 08:01:395663 1073741826 1073742335
9: POSIX  ADVISORY  READ  4254 08:01:395841 128 128
10: POSIX  ADVISORY  READ  4254 08:01:395663 1073741826 1073742335
11: POSIX  ADVISORY  READ  4244 08:01:395841 128 128
12: POSIX  ADVISORY  READ  4244 08:01:395663 1073741826 1073742335
13: POSIX  ADVISORY  WRITE 857 00:17:584 0 EOF
14: FLOCK  ADVISORY  WRITE 861 00:17:576 0 EOF
```

`/proc/locks` 是一个只读文件，通过 cat 等命令可以读取内容。

第一列，为一个序号，表示第几个锁。

第二列，表示锁的类型，包括 POSIX，OFDLCK，FLOCK 等。

第三列，有两种值，分别为 `ADVISORY` 和 `MANDATORY`，表示建议锁，或者强制锁。

第四列，被锁定的文件的权限，表示锁的持有者是只能读文件还是可以写文件。

第五列，表示**锁的创建者的进程 ID**，需要注意的是，这里并非是锁的持有者。

1. 这个锁即使被创建者的子进程继承，这里也只会列出创建者的 Pid。
2. 这个锁的创建者即使已经退出，只要这个锁还被其他进程继承，仍会显示创建者的 Pid。

第六列，表示文件 ID，格式为 MAJOR-DEVICE:MINOR-DEVICE:INODE-NUMBER。

第七、八列，分别表示文件被锁定的范围起始位置和终止位置。EOF 就表示为文件末尾。

# 注意点

## Pid

我们先创建一个文件锁。

flock 命令可以用来创建文件锁。

如下，-x 表示这是一个独享锁，test 表示我们要锁定的文件，后面跟一个成功锁定文件后执行的命令。

```bash
$ flock -x test  sleep 100 &
[1] 93131
$ ps aux | grep -v "grep"| grep sleep
sake      93131  0.0  0.0  18600   752 pts/3    S    04:46   0:00 flock -x test sleep 100
sake      93132  0.0  0.0  14356   648 pts/3    S    04:46   0:00 sleep 100
```

上面我们可以看到，flock 和 sleep 进程的 Pid 分别为，93131 和 93132。

接着，我们看下 `/proc/locks` 的内容，有 93131（flock）进程但是无 93132（sleep）进程。

```bash
$ grep 93131 /proc/locks
7: FLOCK  ADVISORY  WRITE 93131 08:01:396420 0 EOF
$ grep 93132 /proc/locks
$
```

最后我们 kill 掉 flock 进程，看看 `/proc/locks` 的内容。

```bash
$ kill 93131
$ ps aux  | grep -v "grep" | grep sleep
sake      93132  0.0  0.0  14356   648 pts/3    S    04:46   0:00 sleep 100
[1]+  Terminated              flock -x test sleep 100
$ grep 93131 /proc/locks
7: FLOCK  ADVISORY  WRITE 93131 08:01:396420 0 EOF
$ grep 93132 /proc/locks
$
```

此时我们去拿锁，发现锁还被占着，因为 sleep 进程继承了 flock 持有的 test 文件的文件描述符，所以 sleep 进程拥有这把锁。

```bash
$ flock -nx test ls
$ echo $?
1
```

## ->

```bash
$cat /proc/locks
1: FLOCK  ADVISORY  WRITE 93268 08:01:396420 0 EOF
1: -> FLOCK  ADVISORY  WRITE 93270 08:01:396420 0 EOF
```

某些时候，看到 `/proc/locks` 内容是这样的，有一个 `->` 符号。
表示某个进程正在等待某个文件锁。

这里就是 1 号锁目前被 93268 进程持有，而进程 93270 只能被阻塞。

# 综述

在文件锁造成死锁的场景下，可以通过  `/proc/locks` 来判断，但是无法确切地知道某个文件锁到底被哪些进程持有。

