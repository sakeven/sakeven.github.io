+++
title = "Kubernetes 调度器"
date = "2017-08-02T18:10:00+08:00"
tags = ["container", "scheduler"]
categories = ["Orchestration"]
+++

## 目标

公平：如何保证每个节点都能被分配资源  
资源高效利用：集群所有资源最大化使用  
效率：调度的性能要好，能够尽快地对大批量的 Pod 完成调度工作  
灵活：允许用户根据自己的需求控制调度的逻辑  

## 调度器的启动

1. 由各种配置生成 scheduler.Config，调度器的大部分操作由其提供。
2. 运行 HTTP 服务，主要包括 4 个： /healthz（健康检查），/configz（配置信息），/debug/pprof（调试）和 /metrics（监控指标）
3. 选举 leader，在主从模式下进行调度。

## 调度过程

1. 等待一个需要调度的 Pod；
2. 通过调度算法得出一个合适的 Node；
3. 在缓存中假定 Pod 已经在该 Node 上；
4. 异步地将 Pod 绑定到 Node 上。

## 调度算法

1. 可行性检查，即 predicate 过程，找到一批可用的 Node；
2. 计分，即 prioritize 过程，计算上一步筛选下来的 Node 的优先级。
3. 对最高分的 Node 使用类 round-robin 算法，获得唯一的 Node。

注：获得唯一 Node 原先是使用随机算法，后来改成 Round-Robin 算法的。但是由于每次对不同 Pod 计算出的最高分 Node，可能不同，且数量也不一样，所以 RR 是否会退化成近似随机呢？

### 可行性检查系列算法

#### NoVolumeZoneConflict -> VolumeZonePredicate

判断该 Pod 上 volume 的 zone-label 限制是否与 node 上的 zone-label 相等。仅对持久化 volume 有效。

#### MaxEBSVolumeCount、MaxGCEPDVolumeCount、MaxAzureDiskVolumeCount -> MaxPDVolumeCountChecker

检查某个 Node 上，现有的加上可能分配的、所有不同名的特定类型 volume 数量是否超过限制 。限制值由环境变量 KUBE_MAX_PD_VOLS 决定，默认值分别为 39，16，16。

#### MatchInterPodAffinity -> NewPodAffinityPredicate

1. 检查该 Pod 如果被分配到某个 Node 上，是否破坏相同 TopologyKey Node 上 Pod 的反亲和性（anti-affinity）规则。TopologyKey 由反亲和性规则指定。
2. 检查 Pod 本身的亲和性，如果部署到某个 Node 上，是否与已部署的相同亲和性的 Pod 所在的 Node 有相同的 TopologyKey。
3. 检查 Pod 本身的反亲和性，如果部署到某个 Node 上，其相同 TopologyKey 的 Node 上不能有同样反亲和性的 Pod。

#### NoDiskConflict -> NoDiskConflict

Pod 所声明的 Volume 不能在某个 Node 上已经存在。目前仅对 GCE，EBS，RBD, ISCSI 检查： 

1. GCE PD allows multiple mounts as long as they're all read-only 
2. AWS EBS forbids any two pods mounting the same volume ID 
3. Ceph RBD forbids if any two pods share at least same monitor, and match pool and image. 
4. ISCSI forbids if any two pods share at least same IQN, LUN and Target

#### GeneralPredicates -> GeneralPredicates

1. PodFitsResources： Pod 的资源请求是否满足 Node 的分配能力
2. EssentialPredicates: Host、Port、NodeSelector 检查

#### PodToleratesNodeTaints -> PodToleratesNodeTaints

检查一个 Pod 是否能容忍 Node 上的污点 （Taints），只关注 TaintEffectNoSchedule 和 TaintEffectNoExecute。

#### CheckNodeMemoryPressure -> CheckNodeMemoryPressurePredicate 

QOS 为 BestEffort 的 Pod 不应该放在有内存压力的 Node 上，因为一放上去就会被 kubelet 消灭掉。

#### CheckNodeDiskPressure -> CheckNodeDiskPressurePredicate 

检查磁盘压力

#### NoVolumeNodeConflict -> NewVolumeNodePredicate

PVC 绑定的一个 PV 的 TopologyKey 必须要与 Node 的一致，即 PV 的 Node 亲和性。

这些被选上的算法对每个 Pod 的调度都会使用，并且记录下出错的原因。
这样做效率可能会下降，实际上可以在判断出不合适后就可以返回。另外 predicateFuncs 是一个 map，每次迭代的顺序都不一样，可以改成数组。predicateFuncs 在一定顺序下依次执行，并且能够提前退出，效率会得到较大提升。具体可见 网易云基于 Kubernetes 的深度定制化实践 提到的 master 端的调度器。

```go
for predicateKey, predicate := range predicateFuncs {
	fit, reasons, err = predicate(pod, meta, info)
	if err != nil {
		return false, []algorithm.PredicateFailureReason{}, err
	}
	if !fit {
		failedPredicates = append(failedPredicates, reasons...)
	}
}
```

### 计分系列算法
每个算法对 Node 的评分在 0 ~ 10。

#### SelectorSpreadPriority -> NewSelectorSpreadPriority

Pod 分散优先，在同一个 services、RCs 或者 RSs 的 Pod 尽量分散在不同的 Node 上。首先计算每个 Node 上同质 Pod 的数量，同时计算每个 Zone 上同质 Pod 的数量。接着通过以下算法得出每个 Node 的分数。

```go
fScore := maxPriority
if maxCountByNodeName > 0 {
	fScore = maxPriority * ((maxCountByNodeName - countsByNodeName[node.Name]) / maxCountByNodeName)
}
	
// If there is zone information present, incorporate it
if haveZones {
	zoneId := utilnode.GetZoneKey(node)
	if zoneId != "" {
		zoneScore := maxPriority * ((maxCountByZone - countsByZone[zoneId]) / maxCountByZone)
		fScore = (fScore * (1.0 - zoneWeighting)) + (zoneWeighting * zoneScore)
	}
}
```

#### InterPodAffinityPriority -> NewInterPodAffinityPriority

Pod 亲和性、反亲和性优先，亲和性会使优先级提升，反亲和性使优先级下降。

#### LeastRequestedPriority -> LeastRequestedPriorityMap

Node 上请求的资源越少越优先。

```go
fScore = cpu((capacity - sum(requested)) * 10 / capacity) + memory((capacity - sum(requested)) * 10 / capacity) / 2
```

#### BalancedResourceAllocation -> BalancedResourceAllocationMap 

资源使用率越平衡越优先，这个算法必须与 LeastRequestedPriority 一起使用。

```go
fScore = 10 - abs(cpu(requested/capacity)-memory(requested/capacity))*10
```

#### NodePreferAvoidPodsPriority -> CalculateNodePreferAvoidPodsPriorityMap 

Node 避免特定的 ReplicationController 或者 ReplicaSet 的 Pods。如果使用该算法，该算法在所有算法中权重为 1000，以此覆盖其它算法。

#### NodeAffinityPriority -> CalculateNodeAffinityPriorityMap + CalculateNodeAffinityPriorityReduce

Node 亲和性优先，Node 匹配相应的 preferredSchedulingTerm，增加相应的权重，所以匹配的越多，分值越高。分值最后会被均化到 0~10。

#### TaintTolerationPriority -> ComputeTaintTolerationPriorityMap + ComputeTaintTolerationPriorityReduce 

首先计算出每个 node 的 intolerable taints of a pod with effect PreferNoSchedule，然后均化到 0~10。 

```go
fScore = (1.0 - float64(result[i].Score)/maxCountFloat) * 10
```

注： 1. TopologyKey 可以用于标记一组 Node，可以简单地认为一个可用区。

## 调度器扩展
调度器可以加入自定义 HTTP 组件来扩展。
配置文件：

```go
// URLPrefix at which the extender is available
URLPrefix string
// Verb for the filter call, empty if not supported. This verb is appended to the URLPrefix when issuing the filter call to extender.
FilterVerb string
// Verb for the prioritize call, empty if not supported. This verb is appended to the URLPrefix when issuing the prioritize call to extender.
PrioritizeVerb string
// The numeric multiplier for the node scores that the prioritize call generates.
// The weight should be a positive integer
Weight int
// Verb for the bind call, empty if not supported. This verb is appended to the URLPrefix when issuing the bind call to extender.
// If this method is implemented by the extender, it is the extender's responsibility to bind the pod to apiserver. Only one extender
// can implement this function.
BindVerb string
// EnableHttps specifies whether https should be used to communicate with the extender
EnableHttps bool
// TLSConfig specifies the transport layer security config
TLSConfig *restclient.TLSClientConfig
// HTTPTimeout specifies the timeout duration for a call to the extender. Filter timeout fails the scheduling of the pod. Prioritize
// timeout is ignored, k8s/other extenders priorities are used to select the node.
HTTPTimeout time.Duration
// NodeCacheCapable specifies that the extender is capable of caching node information,
// so the scheduler should only send minimal information about the eligible nodes
// assuming that the extender already cached full details of all nodes in the cluster
NodeCacheCapable bool
```

可以实现三个接口，分别为 Filter，Prioritize，Bind，其请求参数与响应参数都为 json 格式。其中 Bind 接口只能由一个扩展组件实现。

### Filter 接口

URL 由 FilterVerb 指定。

请求参数为：

```go
// ExtenderArgs represents the arguments needed by the extender to filter/prioritize
// nodes for a pod.
type ExtenderArgs struct {
	// Pod being scheduled
	Pod v1.Pod
	// List of candidate nodes where the pod can be scheduled; to be populated
	// only if ExtenderConfig.NodeCacheCapable == false
	Nodes *v1.NodeList
	// List of candidate node names where the pod can be scheduled; to be
	// populated only if ExtenderConfig.NodeCacheCapable == true
	NodeNames *[]string
}
```

响应参数为：

```go
// ExtenderFilterResult represents the results of a filter call to an extender
type ExtenderFilterResult struct {
	// Filtered set of nodes where the pod can be scheduled; to be populated
	// only if ExtenderConfig.NodeCacheCapable == false
	Nodes *v1.NodeList
	// Filtered set of nodes where the pod can be scheduled; to be populated
	// only if ExtenderConfig.NodeCacheCapable == true
	NodeNames *[]string
	// Filtered out nodes where the pod can't be scheduled and the failure messages
	FailedNodes FailedNodesMap
	// Error message indicating failure
	Error string
}
```

### Prioritize 接口
 
URL 由 PrioritizeVerb 指定。

请求参数为：

```go
// ExtenderArgs represents the arguments needed by the extender to filter/prioritize
// nodes for a pod.
type ExtenderArgs struct {
	// Pod being scheduled
	Pod v1.Pod
	// List of candidate nodes where the pod can be scheduled; to be populated
	// only if ExtenderConfig.NodeCacheCapable == false
	Nodes *v1.NodeList
	// List of candidate node names where the pod can be scheduled; to be
	// populated only if ExtenderConfig.NodeCacheCapable == true
	NodeNames *[]string
}
```

响应参数为：

```go
type HostPriorityList []HostPriority
```

### Bind 接口

URL 由 BindVerb 指定。

请求参数为：

```go
// ExtenderBindingArgs represents the arguments to an extender for binding a pod to a node.
type ExtenderBindingArgs struct {
	// PodName is the name of the pod being bound
	PodName string
	// PodNamespace is the namespace of the pod being bound
	PodNamespace string
	// PodUID is the UID of the pod being bound
	PodUID types.UID
	// Node selected by the scheduler
	Node string
}
```

响应参数为：

```go
// ExtenderBindingResult represents the result of binding of a pod to a node from an extender.
type ExtenderBindingResult struct {
	// Error message indicating failure
	Error string
}
```

## 调度器缓存
由于集群内 Pod 数量比较多，不可能每次都直接访问 API Server 来获取所有 Pod，故所有 Pod 信息都被缓存在一个 schedulerCache 中。

目前 k8s 没有实现 Node 列表的缓存，仅实现了 Node 上信息的缓存，可能是 Node 的数量级相对于 Pod 小很多，每次列出所有 Node 都需要访问 API Server。

注意调度器内部还有一个均类缓存（EquivalenceCache），用于调度算法。

Pod 在缓存内部的状态机：

```
   +-------------------------------------------+  +----+
   |                            Add            |  |    |
   |                                           |  |    | Update
   +      Assume                Add            v  v    |
Initial +--------> Assumed +------------+---> Added <--+
   ^                +   +               |       +
   |                |   |               |       |
   |                |   |           Add |       | Remove
   |                |   |               |       |
   |                |   |               +       |
   +----------------+   +-----------> Expired   +----> Deleted

```

Added 状态是指 Pod 已经被绑定到某个 Node 上。Assumed 则是假设 Pod 被绑定到某个 Node 上。

缓存需要实现的接口：

```go
type Cache interface {
	// AssumePod 假设一个 Pod 已经被调度， 并且把 pod 的信息聚合到对应的 Node 上。
	// 它的实现也决定了 Pod 在（通过接收 Add event)被确认前的过期策略。
	// 在过期后，它的信息会被删掉。
	AssumePod(pod *v1.Pod) error

	// FinishBinding 示意被假定的 Pod 的缓存可以被过期了。
	FinishBinding(pod *v1.Pod) error

	// ForgetPod 将一个被假定的 Pod 从缓存中移除。
	ForgetPod(pod *v1.Pod) error

	// AddPod 即确认了一个 Pod 是否假定了，如果它过期了还可以将它加回。
	// 如果被加回，Pod 的信息也会被加回。
	AddPod(pod *v1.Pod) error

	// UpdatePod 删除旧 Pod 的信息，加入新 Pod 的信息。
	UpdatePod(oldPod, newPod *v1.Pod) error

	// RemovePod 删除一个 Pod。Pod 的信息会从被分配的 Node 上删除。
	RemovePod(pod *v1.Pod) error

	// AddNode 添加一个 Node 的总体信息。
	AddNode(node *v1.Node) error

	// UpdateNode 更新 Node 的总体信息。
	UpdateNode(oldNode, newNode *v1.Node) error

	// RemoveNode 删除 Node 的总体信息。
	RemoveNode(node *v1.Node) error

	// UpdateNodeNameToInfoMap 将传入的 infoMap 更新到现有的缓存中。
	// Node 信息包括这个节点上已被调度或者假定的 Pod 聚合信息。
	UpdateNodeNameToInfoMap(infoMap map[string]*NodeInfo) error
	
	// 列出所有被缓存的 Pod （包括假定的）。
	List(labels.Selector) ([]*v1.Pod, error)
}
```

缓存中 Pod、Node 的添加、更新、删除，会被 Informer 的事件回调，与 API Server 保持一致，另一方面调度器会也会操作缓存，比如假定一个 Pod 被调度、示意被假定的 Pod 的缓存可以被过期了等等。

## 均类缓存

v1.8 alpha 特性：均类缓存

通过 --feature-gates=EnableEquivalenceClassCache=true 开启。
目前均类缓存：只缓存预选阶段的结果。

Node ——> predicateKey ——> Pod ——> Result

Pod 仅仅存一个 equivalenceHash，这个通过 Pod 的属性来计算一个哈希值，同属性的 Pod 会有相同的值。
Pod、Node、PV、PVC 的变化（添加、删除、更新）都会导致均类缓存中不同预选策略的失效。