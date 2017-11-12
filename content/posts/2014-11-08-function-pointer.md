+++
title = "函数指针"
date = "2014-11-08T21:00:00+08:00"
tags = ["c"]
categories = ["Program"]
+++

## 定义

函数指针是指向函数的指针。
函数指针的声明方法为：
```none
返回值类型 ( * 指针变量名) ([形参列表]);
```
如：

``` c++
int (*proc)(int); // 声明函数指针 proc 
```

## 使用

```c++
#include <stdio.h>

int add(int, int); // 函数 add 声明
 
int main(int argc, char const *argv[])
{
    int (*proc)(int, int); // 函数指针 proc 声明

    proc = add;   // 赋值
    
    proc(2, 2);    // 输出 4
    (*proc)(2, 1); // 输出 3

    add(2, 3);     // 输出 5
    (*add)(2, 4);  // 输出 6

    proc = &add;  // 赋值 
    
    proc(5, 5);    // 输出 10
    (*proc)(5, 6); // 输出 11
    
    return 0;
}

int add(int a, int b){ // 函数 add 定义
    printf("%d\n", a + b);
    return a + b;
} 
```

## 区别

1. 与指针函数的区别：函数指针指向函数，而指针函数的返回值是一个指针。

	指针函数声明如下：
    ```none
	 返回值类型 * 函数名([形参列表]);
    ```

2. 与函数名的区别：函数名也是一个函数指针，但是函数名是个常量，而函数指针通常是个变量。

## 作用

### 面向接口编程：
接口通常描述一个对象应该具有什么行为方法，是具有面向对象的特点的，而 C 语言是面向过程的。函数指针很好的解决这个问题。

```c++
#include <stdio.h>
#include <string.h>

#define MAXLEN 4096

void trim(char* str, int (*ptr)(char)) {
    int i = 0, j = 0;
    char newstr[MAXLEN];

    while(str[i]){
        if ( ptr(str[i]) != 1 ) {
            newstr[j++] = str[i];
        }
        i ++;
    }
    newstr[j] = 0;

    printf("%s\n", newstr);
}

int deleteSpace(char c) {
    if (c == ' ') {
        return 1;
    }
    return 0;
}

int deleteSharp(char c) {
    if ( c == '#') {
        return 1;
    }
    return 0;
}

int main() {
    char str[] = "Hello World#Yes ha";

    trim(str, deleteSharp);
    trim(str, deleteSpace);

    return 0;
}
```

上面程序 trim 函数根据输入的函数指针 ptr，删除特定的字符。函数 trim 并不关心 ptr 的实现，它仅仅关注它的行为，即参数个数为一个，参数类型为 char，并且返回值类型为 int 的一类函数。

这样一来：

* 分层设计，底层开发者不需要关注具体函数的实现，而由上层开发者实现。
* 松耦合，降低各层之间的耦合度。
* 面向接口开发，只要上层开发者提供函数 ptr 的实现，trim 函数就能正常工作。

### 回调函数（callback）

回调函数就是上层开发者对函数指针的实现。Windows 编程中有许多地方用到回调函数。
如，计时器中使用回调函数通知程序。