+++
title = "从 Hello World 说起"
date = "2014-11-30T23:50:00+08:00"
tags = ["c", "compiler"]
categories = ["Program"]
+++

```c
#include <stdio.h>

static  __attribute__((constructor)) void before()
{
    printf("Hello");
}

static  __attribute__((destructor)) void after()
{
    printf(" World!\n");
}

int main(int args, char ** argv)
{
    return 0;
}
```

主函数没有任何函数调用，但是输出了 "Hello World!" 。Why?

Answer:

最近去看了下 printf 函数的定义，在 macOS 10.10 <stdio.h> 中是这样：

```c
int     printf(const char * __restrict, ...) __printflike(1, 2);
```

然后我在考虑这个： `__printflike(1, 2)` 是什么意思，函数为什么会一个小尾巴？
接着转到 __printflike 的定义处，可以看到在 <cdefs.h> 文件中如下：

```c
#define __printflike(fmtarg, firstvararg) \
        __attribute__((__format__ (__printf__, fmtarg, firstvararg)))
```

`__printflike(fmtarg, firstvararg)` 其实是一个宏定义，真正有用的是 `__attribute__`。


接着我们去看看 `__attribute__` 到底是啥。

其实 `__attribute__` 是 GNU C 特有的机制。它可以设置变量属性、函数属性和类型属性。

### 函数属性

函数属性可以把一些特性添加到函数声明中，使编译器在错误检查方面的功能更强大。
GNU C 需要使用 `–Wall` 编译器来激活该功能，这是控制警告信息的一个很好的方式。 

几个有用的属性：

1. format：
    它可以使编译器检查函数声明和函数实际调用参数之间的格式化字符串是否匹配。该功能十分有用，尤其是处理一些很难发现的 bug。
    format 的语法格式为：
    
    ```c
    format (archetype, string-index, first-to-check)
    ```

    * `archetype` 指定是哪种风格；
    * `string-index` 指定传入函数的第几个参数是格式化字符串；
    * `first-to-check` 指定从函数的第几个参数开始按上述规则进行检查。
    
    样例：
    ```c
    __attribute__((format(printf, m, n)))
    __attribute__((format(scanf, m, n)))
    ```
    
    其中参数 m 与 n 的含义为：
    
    m：第几个参数为格式化字符串 `format string`；

    n：参数集合中的第一个，即参数 `…` 里的第一个参数在函数参数总数排在第几。

2. noreturn：
    该属性通知编译器函数从不返回值。

3. const：
    该属性只能用于带有数值类型参数的函数上。对特定参数，编译器只调用一次该函数，以后不再调用。用于无副作用且函数返回值只依赖于传入参数，用于程序优化。

4. constructor/destructor：
    constructor 属性在 main 函数之前执行，destructor 在 main 函数结束后执行。
    这个很好解释了顶部 Hello World 程序。 

### 类型或变量属性

1. aligned (alignment) 设置最小对齐长度
2. packed 使用最小对齐长度
3. unused 表示该函数或变量可能不使用，这个属性可以避免编译器产生警告信息

And so on....
