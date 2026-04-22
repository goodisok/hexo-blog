---
title: Gazebo Sim 源码深度解析：从 ECS 架构到仿真主循环的完整剖析
date: 2026-04-21 23:30:00
categories:
  - 仿真
  - 机器人
tags:
  - Gazebo
  - 源码分析
  - ECS
  - 仿真引擎
  - 物理引擎
  - 插件系统
  - SimulationRunner
  - EntityComponentManager
  - ROS2
  - PX4
  - SITL
  - SDF
  - 机器人仿真
---

> **源码版本**：Gazebo Sim 10 (Jetty)，对应仓库 [gazebosim/gz-sim](https://github.com/gazebosim/gz-sim)
> **参考**：[Zread - gz-sim 源码解读](https://zread.ai/gazebosim/gz-sim)，[Gazebo Sim API 文档](https://gazebosim.org/api/sim/10/)

---

## 一、为什么要读 Gazebo Sim 源码？

Gazebo Sim（原 Ignition Gazebo）是当前机器人仿真领域事实标准之一。它是 Gazebo Classic 的完全重写版本，积累了超过 16 年的机器人仿真经验。理解其源码对以下场景有直接价值：

- **自定义物理仿真**：需要修改物理步进逻辑、添加自定义力/力矩
- **高性能传感器开发**：编写自定义传感器插件（如事件相机、声纳阵列）
- **PX4/Ardupilot SITL 集成**：理解仿真端如何与飞控软件交互
- **Sim-to-Real 调优**：精确控制仿真步长、物理引擎参数、传感器噪声模型
- **分布式仿真**：理解多 Runner、网络同步的实现机制

本文将从源码层面逐层剖析 Gazebo Sim 的核心架构。

---

## 二、仓库结构总览

```
gz-sim/
├── src/                         # 核心源码
│   ├── Server.cc                # 仿真服务器入口
│   ├── ServerPrivate.cc         # Server 内部实现
│   ├── SimulationRunner.cc      # 仿真主循环（核心中的核心）
│   ├── SimulationRunner.hh      # Runner 头文件
│   ├── EntityComponentManager.cc # ECS 管理器实现
│   ├── SystemManager.cc         # System 生命周期管理
│   ├── SystemLoader.cc          # 插件动态加载
│   ├── SdfEntityCreator.cc      # SDF → Entity 转换
│   ├── LevelManager.cc          # 关卡/LOD 管理
│   ├── Barrier.cc               # 线程同步屏障
│   ├── network/                 # 分布式仿真网络层
│   │   ├── NetworkManagerPrimary.cc
│   │   └── NetworkManagerSecondary.cc
│   ├── gui/                     # GUI 相关源码
│   └── systems/                 # 60+ 内置 System 插件
│       ├── physics/             # 物理系统（核心）
│       ├── sensors/             # 传感器系统
│       ├── diff_drive/          # 差速驱动
│       ├── multicopter_motor_model/  # 多旋翼电机模型
│       ├── imu/                 # IMU 传感器
│       └── ...
├── include/gz/sim/              # 公共 API 头文件
│   ├── Server.hh
│   ├── System.hh                # System 接口定义
│   ├── EntityComponentManager.hh
│   ├── Entity.hh
│   ├── Types.hh
│   └── components/              # 所有 Component 类型定义
├── examples/                    # 示例
│   ├── plugin/                  # 插件示例
│   ├── standalone/              # 独立程序示例
│   └── worlds/                  # SDF 世界文件
├── test/                        # 测试套件
└── tutorials/                   # 70+ 教程文档
```

代码量约 92.2% C++，5.4% QML，其余为 CMake。

---

## 三、ECS 架构：Gazebo Sim 的设计哲学

Gazebo Sim 的核心设计模式是 **Entity-Component-System (ECS)**，这与游戏引擎（如 Unity DOTS、Unreal Mass）中广泛使用的架构一致。ECS 将数据与逻辑彻底分离，带来三个关键优势：

1. **内存局部性**：同类型 Component 连续存储，缓存友好
2. **并行性**：System 之间可独立执行，适合多线程
3. **可组合性**：通过组合不同 Component 创建任意实体，无需继承层次

### 3.1 三个核心概念

| 概念 | 源码位置 | 作用 |
|------|---------|------|
| **Entity** | `Entity.hh` | 纯 ID（`uint64_t`），无任何数据或行为 |
| **Component** | `components/*.hh` | 纯数据容器，挂载到 Entity 上 |
| **System** | `System.hh` | 纯逻辑，操作具有特定 Component 组合的 Entity |

### 3.2 Entity：一个 uint64_t 的 ID

Entity 的定义极其简单：

```cpp
// include/gz/sim/Entity.hh
using Entity = uint64_t;
const Entity kNullEntity = std::numeric_limits<Entity>::max();
```

Entity 本身不存储任何数据，只是一个标识符。仿真世界中的所有对象——World、Model、Link、Joint、Sensor、Visual——都是 Entity，区别仅在于它们挂载了不同的 Component。

### 3.3 Component：纯数据容器

Component 是类型化的数据容器。Gazebo Sim 预定义了大量 Component 类型：

```cpp
// 位置相关
components::Pose           // gz::math::Pose3d
components::WorldPose      // 世界坐标系下的位姿
components::LinearVelocity // 线速度
components::AngularVelocity // 角速度

// 物理相关
components::Inertial       // 惯性参数（质量、惯性矩阵、质心偏移）
components::Gravity        // 重力加速度向量
components::Physics         // 物理引擎参数（步长、RTF）

// 身份相关
components::Name           // 名称字符串
components::Model          // 标记为 Model
components::Link           // 标记为 Link
components::Joint          // 标记为 Joint
components::Sensor         // 标记为 Sensor
components::World          // 标记为 World
components::ParentEntity   // 父实体 ID

// 传感器相关
components::Imu            // IMU 传感器配置
components::Camera         // 相机传感器配置
components::GpuLidar       // GPU 激光雷达配置
```

Component 的核心特征是**无行为**——它只存储数据，所有逻辑都在 System 中实现。

### 3.4 EntityComponentManager（ECM）：ECS 的中枢

`EntityComponentManager` 是整个 ECS 的核心数据结构，管理所有 Entity 和 Component 的创建、查询、修改和删除。

**源码位置**：`src/EntityComponentManager.cc`（约 2343 行），头文件 `include/gz/sim/EntityComponentManager.hh`

#### 关键 API

```cpp
// 创建 Entity
Entity CreateEntity();

// 为 Entity 添加 Component
template<typename ComponentTypeT>
ComponentTypeT* CreateComponent(const Entity _entity,
                                const ComponentTypeT &_data);

// 查询 Entity 的 Component
template<typename ComponentTypeT>
const ComponentTypeT* Component(const Entity _entity) const;

// 按 Component 组合查找 Entity
template<typename... ComponentTypeTs>
Entity EntityByComponents(const ComponentTypeTs&... _desiredComponents) const;

// 遍历具有特定 Component 组合的所有 Entity
template<typename... ComponentTypeTs>
void Each(typename identity<std::function<bool(
    const Entity&, const ComponentTypeTs*...)>>::type _f) const;

// 删除 Entity
void RequestRemoveEntity(Entity _entity, bool _recursive = true);
```

#### Entity 层次图（Directed Graph）

ECM 内部维护一个有向图来表示 Entity 之间的父子关系：

```cpp
using EntityGraph = math::graph::DirectedGraph<Entity, bool>;

const EntityGraph& Entities() const;
std::unordered_set<Entity> Descendants(Entity _entity) const;
```

典型的 Entity 层次结构：

```
World (Entity 1)
├── Model "quadrotor" (Entity 2)
│   ├── Link "base_link" (Entity 3)
│   │   ├── Visual "body_visual" (Entity 4)
│   │   ├── Collision "body_collision" (Entity 5)
│   │   └── Sensor "imu_sensor" (Entity 6)
│   ├── Link "rotor_0" (Entity 7)
│   │   └── Joint "rotor_0_joint" (Entity 8)
│   ├── Link "rotor_1" (Entity 9)
│   ...
├── Model "ground_plane" (Entity 20)
│   └── Link "link" (Entity 21)
└── Light "sun" (Entity 30)
```

#### 状态变更追踪

ECM 精细追踪每个 Component 的变更状态，这对于高效的状态序列化和网络同步至关重要：

```cpp
enum class ComponentState
{
    NoChange = 0,        // 未改变
    PeriodicChange = 1,  // 持续变化（如位姿每帧都变）
    OneTimeChange = 2    // 一次性变化（如名称修改）
};
```

`ChangedState()` 方法只序列化变更过的 Component，大幅减少网络传输和日志记录的数据量。

#### 友元类设计

ECM 有几个特权友元类，它们可以调用 `protected` 方法来管理 Entity 生命周期：

```cpp
friend class GuiRunner;
friend class SimulationRunner;
friend class SystemManager;
friend class NetworkManagerPrimary;
friend class NetworkManagerSecondary;
```

这些方法包括 `ClearNewlyCreatedEntities()`、`ProcessRemoveEntityRequests()`、`SetAllComponentsUnchanged()` 等，普通 System 插件无法访问。

---

## 四、Server：仿真服务器的入口

**源码位置**：`src/Server.cc`

`Server` 是用户与 Gazebo Sim 交互的主要入口点。它的构造函数完成以下工作：

```cpp
Server::Server(const ServerConfig &_config)
{
    // 1. 初始化 Python 解释器（如果编译了 pybind11 支持）
    // 2. 配置 Fuel 客户端（模型下载）
    // 3. 设置 SDF 资源查找回调
    // 4. 解析 SDF 文件（先不下载模型，只获取世界名称）
    // 5. 创建 SimulationRunner（每个 World 一个）
    // 6. 建立 gz-transport 通信
    // 7. 后台下载仿真资源（模型、网格等）
}
```

### 4.1 启动流程

```
Server(config)
  │
  ├── 解析 SDF Root
  │     └── 获取所有 World 定义
  │
  ├── CreateSimulationRunners(sdfRoot)
  │     └── 每个 World → 一个 SimulationRunner
  │
  ├── SetupTransport()
  │     └── 建立 gz-transport 主题和服务
  │
  └── DownloadAssets(config)
        └── 后台线程下载 Fuel 模型资源
```

### 4.2 Server::Run()

```cpp
bool Server::Run(const bool _blocking, const uint64_t _iterations,
                 const bool _paused)
{
    // 设置每个 Runner 的初始暂停状态
    for (auto &runner : this->dataPtr->simRunners)
        runner->SetPaused(_paused);

    if (_blocking)
        return this->dataPtr->Run(_iterations);

    // 非阻塞模式：创建新线程运行仿真
    this->dataPtr->runThread = std::thread(
        &ServerPrivate::Run, this->dataPtr.get(), _iterations, &cond);
}
```

关键设计点：
- 支持**阻塞**和**非阻塞**两种运行模式
- 非阻塞模式在新线程中运行，通过 `condition_variable` 保证 `running` 标志在函数返回前被设置
- `RunOnce(_paused)` 是 `Run(true, 1, _paused)` 的便捷封装

---

## 五、SimulationRunner：仿真主循环的核心

**源码位置**：`src/SimulationRunner.cc`（约 1912 行）——这是整个 Gazebo Sim 最核心的文件。

### 5.1 核心成员变量

```cpp
class SimulationRunner {
    // ====== 管理器（注意声明顺序影响析构顺序）======
    std::unique_ptr<SystemManager> systemMgr;       // 必须先于 ECM 和 EventMgr 声明
    EventManager eventMgr;                          // 事件管理器
    std::unique_ptr<ParametersRegistry> parametersRegistry;
    EntityComponentManager entityCompMgr;            // 当前 ECM
    EntityComponentManager initialEntityCompMgr;     // 初始 ECM 副本（用于 Reset）
    std::unique_ptr<LevelManager> levelMgr;          // 关卡管理
    std::unique_ptr<NetworkManager> networkMgr;      // 网络管理（可选）

    // ====== 时间控制 ======
    std::chrono::steady_clock::duration updatePeriod{2ms};  // 默认 500Hz
    std::chrono::steady_clock::duration stepSize{10ms};     // 默认 100Hz 物理步长
    double desiredRtf{1.0};                                  // 期望实时因子
    double realTimeFactor{0.0};                              // 当前实时因子
    UpdateInfo currentInfo;                                  // 当前帧信息

    // ====== PostUpdate 并行 ======
    std::vector<std::thread> postUpdateThreads;
    std::unique_ptr<Barrier> postUpdateStartBarrier;
    std::unique_ptr<Barrier> postUpdateStopBarrier;

    // ====== gz-transport 通信 ======
    std::unique_ptr<transport::Node> node;
    transport::Node::Publisher statsPub;   // 世界统计信息
    transport::Node::Publisher clockPub;   // 时钟信息
};
```

### 5.2 构造函数：世界初始化

构造函数中有一段关键的 RTF 计算逻辑值得关注：

```cpp
SimulationRunner::SimulationRunner(const sdf::World &_world, ...)
{
    // 从 SDF 读取物理配置
    const sdf::Physics *physics = _world.PhysicsByIndex(0);
    
    // 步长：默认 10ms → 100Hz 物理步进
    this->stepSize = std::chrono::duration_cast<...>(
        std::chrono::duration<double>(physics->MaxStepSize()));
    
    // RTF 推导：
    // RTF = sim_time / real_time
    //     = (sim_it × step_size) / (it × period)
    // 无暂停时 sim_it = it，所以：
    // RTF = step_size / period
    // ∴ period = step_size / RTF
    this->desiredRtf = physics->RealTimeFactor();
    this->updatePeriod = std::chrono::nanoseconds(
        static_cast<int>(this->stepSize.count() / this->desiredRtf));
    
    // 创建 SystemManager
    this->systemMgr = std::make_unique<SystemManager>(
        _systemLoader, &this->entityCompMgr, &this->eventMgr, ...);
    
    // 创建 LevelManager
    this->levelMgr = std::make_unique<LevelManager>(this, ...);
    
    // 创建实体
    if (_createEntities) {
        this->SetWorldSdf(_world);
        this->SetCreateEntities();
        this->CreateEntities();
    }
    
    // 注册 gz-transport 服务
    this->node->Advertise("control", &SimulationRunner::OnWorldControl, this);
    this->node->Advertise("control/state", ...);
    this->node->Advertise("playback/control", ...);
}
```

### 5.3 Run()：主循环

`Run()` 方法是整个仿真的驱动心脏：

```cpp
bool SimulationRunner::Run(const uint64_t _iterations)
{
    this->running = true;
    
    // 建立 stats/clock 发布者
    this->statsPub = this->node->Advertise<msgs::WorldStatistics>("stats");
    this->clockPub = this->node->Advertise<msgs::Clock>("clock");
    
    uint64_t processedIterations{0};
    auto nextUpdateTime = std::chrono::steady_clock::now() + this->updatePeriod;
    
    while (this->running && 
           (_iterations == 0 || processedIterations < _iterations))
    {
        // 1. 创建待定实体
        if (this->createEntities) this->CreateEntities();
        
        // 2. 更新物理参数（步长、RTF 可能在运行时被修改）
        this->UpdatePhysicsParams();
        
        // 3. 更新时间信息
        this->UpdateCurrentInfo();
        
        // 4. 如果 Reset，恢复到初始 ECM 状态
        if (this->resetInitiated)
            this->entityCompMgr.ResetTo(this->initialEntityCompMgr);
        
        // 5. 执行仿真步
        this->Step(this->currentInfo);
        
        // 6. 精确时间控制（混合 sleep/busy-wait）
        if (!this->currentInfo.paused) {
            // sleep 到接近目标时间
            auto sleepTarget = nextUpdateTime - 200us;  // 200μs 提前量
            std::this_thread::sleep_until(sleepTarget);
            // busy-wait 最后的精确时刻
            while (std::chrono::steady_clock::now() < nextUpdateTime) { }
            nextUpdateTime += this->updatePeriod;
        }
    }
    return true;
}
```

**时间控制策略的精妙之处**：Gazebo Sim 采用**混合 sleep/busy-wait** 策略来实现精确的 RTF 控制。纯 `sleep_until` 会因 CPU C-state 省电模式导致唤醒延迟（通常 50-200μs），导致 RTF 偏低。因此在距离目标时间 200μs 时切换到 busy-wait，确保精确到达目标时刻。

### 5.4 Step()：单步执行

`Step()` 是每个仿真步的完整工作流：

```cpp
void SimulationRunner::Step(const UpdateInfo &_info)
{
    this->currentInfo = _info;
    
    // ① 处理 GUI 发来的新世界状态
    this->ProcessNewWorldControlState();
    
    // ② 发布统计信息（stats、clock）
    this->PublishStats();
    
    // ③ 更新关卡状态
    this->levelMgr->UpdateLevelsState();
    
    // ④ 处理待添加的 System
    this->ProcessSystemQueue();
    
    // ⑤ 处理需要重建的 Entity（先标记删除）
    this->ProcessRecreateEntitiesRemove();
    
    // ⑥ 处理待绑定 Entity 的 System
    this->systemMgr->ProcessPendingEntitySystems();
    
    // ⑦ ★ 更新所有 System（核心）
    this->UpdateSystems();
    
    // ⑧ 处理世界控制消息（play/pause/step）
    this->ProcessMessages();
    
    // ⑨ 清理新创建标记
    this->entityCompMgr.ClearNewlyCreatedEntities();
    
    // ⑩ 重建标记删除的 Entity
    this->ProcessRecreateEntitiesCreate();
    
    // ⑪ 处理 Entity 删除请求
    this->systemMgr->ProcessRemovedEntities(...);
    this->entityCompMgr.ProcessRemoveEntityRequests();
    
    // ⑫ 清理已删除的 Component
    this->entityCompMgr.ClearRemovedComponents();
    
    // ⑬ 重置所有 Component 变更标记
    this->entityCompMgr.SetAllComponentsUnchanged();
}
```

### 5.5 UpdateSystems()：三阶段更新

这是每个仿真步中最关键的函数——它按照三个阶段顺序执行所有 System：

```cpp
void SimulationRunner::UpdateSystems()
{
    // 如果触发了 Reset
    if (this->resetInitiated) {
        this->systemMgr->Reset(this->currentInfo, this->entityCompMgr);
        return;
    }

    // ===== 阶段 1: PreUpdate（顺序执行，按优先级排序）=====
    for (auto& [priority, systems] : this->systemMgr->SystemsPreUpdate())
    {
        for (auto& system : systems)
            system->PreUpdate(this->currentInfo, this->entityCompMgr);
    }

    // ===== 阶段 2: Update（顺序执行，按优先级排序）=====
    for (auto& [priority, systems] : this->systemMgr->SystemsUpdate())
    {
        for (auto& system : systems)
            system->Update(this->currentInfo, this->entityCompMgr);
    }

    // ===== 阶段 3: PostUpdate（并行执行）=====
    this->entityCompMgr.LockAddingEntitiesToViews(true);
    if (this->postUpdateStartBarrier && this->postUpdateStopBarrier)
    {
        MaybeGilScopedRelease release;  // 释放 Python GIL
        this->postUpdateStartBarrier->Wait();   // 启动所有 PostUpdate 线程
        this->postUpdateStopBarrier->Wait();    // 等待所有 PostUpdate 完成
    }
    this->entityCompMgr.LockAddingEntitiesToViews(false);
}
```

三阶段的设计：

```
┌─────────────────────────────────────────────────────────┐
│                    一个仿真步（Step）                      │
│                                                         │
│  ┌──────────┐   ┌──────────┐   ┌──────────────────┐    │
│  │ PreUpdate │ → │  Update  │ → │    PostUpdate     │    │
│  │ (顺序)    │   │ (顺序)   │   │    (并行)         │    │
│  │           │   │          │   │                   │    │
│  │ 读写 ECM  │   │ 读写 ECM │   │ 只读 ECM         │    │
│  │           │   │          │   │                   │    │
│  │ 控制信号  │   │ 物理步进 │   │ 传感器/控制器输出  │    │
│  │ 网络同步  │   │ 碰撞检测 │   │ 日志记录         │    │
│  │ 关节指令  │   │ 约束求解 │   │ 遥测发布         │    │
│  └──────────┘   └──────────┘   └──────────────────┘    │
│                                                         │
│  ←——————— 同一线程 ————————→     ←— 多线程并行 ——→      │
└─────────────────────────────────────────────────────────┘
```

---

## 六、System 接口：插件的四种"生命周期钩子"

**源码位置**：`include/gz/sim/System.hh`

### 6.1 接口定义

```cpp
class System {
public:
    using PriorityType = int32_t;
    constexpr static PriorityType kDefaultPriority = {0};
    constexpr static std::string_view kPriorityElementName = 
        {"gz:system_priority"};
};

class ISystemConfigure {
    virtual void Configure(
        const Entity &_entity,
        const std::shared_ptr<const sdf::Element> &_sdf,
        EntityComponentManager &_ecm,
        EventManager &_eventMgr) = 0;
};

class ISystemPreUpdate {
    virtual void PreUpdate(const UpdateInfo &_info,
                           EntityComponentManager &_ecm) = 0;
};

class ISystemUpdate {
    virtual void Update(const UpdateInfo &_info,
                        EntityComponentManager &_ecm) = 0;
};

class ISystemPostUpdate {
    virtual void PostUpdate(const UpdateInfo &_info,
                            const EntityComponentManager &_ecm) = 0;
};

class ISystemReset {
    virtual void Reset(const UpdateInfo &_info,
                       EntityComponentManager &_ecm) = 0;
};
```

注意 `PostUpdate` 的 ECM 参数是 `const` 引用——PostUpdate 只能读取状态，不能修改。

### 6.2 UpdateInfo 结构

```cpp
struct UpdateInfo
{
    std::chrono::steady_clock::duration simTime{0};   // 仿真时间
    std::chrono::steady_clock::duration realTime{0};  // 真实时间
    std::chrono::steady_clock::duration dt{0};        // 步长
    uint64_t iterations{0};                           // 迭代次数
    bool paused{true};                                // 是否暂停
};
```

**关于 simTime 的重要说明**：`simTime` 不是"当前时刻"，而是 PreUpdate 和 Update 执行**完成后**到达的时刻。如果仿真暂停（`paused = true`），时间不前进，`simTime` 保持不变。

### 6.3 优先级系统

System 的执行顺序由优先级控制，数值越小越先执行：

```cpp
namespace systems {
    constexpr System::PriorityType kUserCommandsPriority = -16384;
    constexpr System::PriorityType kPrePhysicsPriority = -128;
    constexpr System::PriorityType kPhysicsPriority = -64;
    constexpr System::PriorityType kPostPhysicsSensorPriority = -32;
    // kDefaultPriority = 0（大多数用户 System）
}
```

执行顺序：UserCommands (-16384) → 用户 PrePhysics (-128) → **Physics (-64)** → PostPhysicsSensor (-32) → 默认 System (0)

这保证了：
1. 用户指令先被处理
2. 物理引擎在用户控制信号之后执行
3. 传感器在物理更新之后采样

### 6.4 Physics System：物理引擎的桥接

**源码位置**：`src/systems/physics/Physics.hh`

Physics System 是 Gazebo Sim 中最重要的内置 System，它实现了 `ISystemConfigure`、`ISystemUpdate` 和 `ISystemReset` 接口：

```cpp
class Physics : public System,
                public ISystemConfigure,
                public ISystemConfigurePriority,
                public ISystemReset,
                public ISystemUpdate
{
    // Configure() - 加载物理引擎插件（DART/Bullet/TPE）
    // ConfigurePriority() - 返回 kPhysicsPriority (-64)
    // Update() - 执行物理步进
    // Reset() - 重置物理状态
};
```

Physics System 通过 `gz-physics` 库的 Feature 系统与具体物理引擎（DART、Bullet Featherstone、TPE）对接，使用的 Feature 包括：

```cpp
#include <gz/physics/ForwardStep.hh>           // 物理步进
#include <gz/physics/GetEntities.hh>           // 获取物理实体
#include <gz/physics/Joint.hh>                 // 关节
#include <gz/physics/Link.hh>                  // 链接
#include <gz/physics/Shape.hh>                 // 碰撞形状
#include <gz/physics/ContactProperties.hh>     // 接触属性
#include <gz/physics/FreeGroup.hh>             // 自由体组
#include <gz/physics/FixedJoint.hh>            // 固定关节
#include <gz/physics/mesh/MeshShape.hh>        // 网格碰撞
#include <gz/physics/heightmap/HeightmapShape.hh>  // 高度图
// ... 更多 Feature
```

### 6.5 PostUpdate 的并行执行机制

PostUpdate 是三个阶段中唯一并行执行的。源码中使用 Barrier 同步原语实现：

```cpp
// ProcessSystemQueue() 中为每个 PostUpdate System 创建一个工作线程
void SimulationRunner::ProcessSystemQueue()
{
    // ...
    unsigned int threadCount = 
        this->systemMgr->SystemsPostUpdate().size() + 1u;
    
    this->postUpdateStartBarrier = std::make_unique<Barrier>(threadCount);
    this->postUpdateStopBarrier = std::make_unique<Barrier>(threadCount);
    
    for (auto &system : this->systemMgr->SystemsPostUpdate())
    {
        this->postUpdateThreads.push_back(std::thread([&]()
        {
            while (this->postUpdateThreadsRunning)
            {
                this->postUpdateStartBarrier->Wait();  // 等待开始信号
                if (this->postUpdateThreadsRunning)
                    system->PostUpdate(this->currentInfo, this->entityCompMgr);
                this->postUpdateStopBarrier->Wait();   // 发送完成信号
            }
        }));
    }
}
```

每个 PostUpdate System 有自己的专属线程，通过两个 Barrier 实现"启动-等待"同步：

```
主线程:     ──┤ StartBarrier.Wait() ├────────────┤ StopBarrier.Wait() ├──
               │                                   │
PostUpdate 0:  ├─── PostUpdate() ──────────────────┤
PostUpdate 1:  ├─── PostUpdate() ──────────────────┤
PostUpdate 2:  ├─── PostUpdate() ──────────────────┤
```

**注意**：在 PostUpdate 并行执行期间，ECM 会锁定视图的实体添加（`LockAddingEntitiesToViews(true)`），防止并发修改。同时，如果编译了 Python 支持，主线程会释放 GIL（`MaybeGilScopedRelease`），允许 Python 编写的 PostUpdate System 在各自线程中获取 GIL。

---

## 七、插件加载机制

### 7.1 动态库加载

System 插件以共享库（`.so`/`.dll`）形式存在，通过 `SystemLoader` 动态加载：

```cpp
// src/SystemLoader.cc
SystemPluginPtr SystemLoader::LoadPlugin(const sdf::Plugin &_plugin)
{
    // 1. 查找插件共享库文件
    // 2. 使用 gz::plugin::Loader 加载
    // 3. 返回 SystemPluginPtr
}
```

### 7.2 插件注册

每个插件通过 `GZ_ADD_PLUGIN` 宏注册：

```cpp
// 示例：HelloWorld 插件
GZ_ADD_PLUGIN(
    hello_world::HelloWorld,
    gz::sim::System,
    hello_world::HelloWorld::ISystemPostUpdate)
```

### 7.3 SDF 中的插件配置

```xml
<world name="example">
  <plugin filename="gz-sim-physics-system"
          name="gz::sim::systems::Physics">
    <gz:system_priority>-64</gz:system_priority>
  </plugin>
  
  <plugin filename="gz-sim-sensors-system"
          name="gz::sim::systems::Sensors">
    <render_engine>ogre2</render_engine>
  </plugin>
  
  <model name="quadrotor">
    <plugin filename="gz-sim-multicopter-motor-model-system"
            name="gz::sim::systems::MulticopterMotorModel">
      <!-- 电机参数配置 -->
    </plugin>
  </model>
</world>
```

---

## 八、SDF → Entity 的转换过程

**源码位置**：`src/SdfEntityCreator.cc`

`SdfEntityCreator` 负责将 SDF 文件中的描述转换为 ECS 中的 Entity + Component：

```
SDF World
  │
  ├── <model> → Entity + {Model, Name, Pose, Static, ...}
  │     │
  │     ├── <link> → Entity + {Link, Name, Pose, Inertial, ...}
  │     │     │
  │     │     ├── <visual> → Entity + {Visual, Name, Geometry, Material, ...}
  │     │     ├── <collision> → Entity + {Collision, Name, Geometry, ...}
  │     │     └── <sensor> → Entity + {Sensor, Name, SensorType, ...}
  │     │
  │     └── <joint> → Entity + {Joint, Name, JointType, ParentLink, ChildLink, ...}
  │
  ├── <light> → Entity + {Light, Name, Pose, ...}
  │
  └── <physics> → Components on World Entity {Physics, Gravity, ...}
```

每个 SDF 元素被转换为一个 Entity，并挂载对应的 Component。`ParentEntity` Component 维护父子关系。

---

## 九、分布式仿真架构

Gazebo Sim 支持分布式仿真，通过 Primary/Secondary Runner 架构实现：

```
┌─────────────────────────────────┐
│        Primary Runner           │
│                                 │
│  ┌───────────────────────────┐ │
│  │ EntityComponentManager    │ │
│  │ (完整世界状态)             │ │
│  └───────────────────────────┘ │
│  NetworkManagerPrimary          │
│  - 同步状态到 Secondary        │
│  - 收集 Secondary 结果         │
└──────────┬──────────────────────┘
           │ gz-transport
    ┌──────┴──────┐
    ▼             ▼
┌──────────┐ ┌──────────┐
│Secondary │ │Secondary │
│Runner 1  │ │Runner 2  │
│(区域 A)  │ │(区域 B)  │
└──────────┘ └──────────┘
```

Primary Runner 通过 `NetworkManagerPrimary` 协调 Secondary Runner，每个 Secondary 负责仿真世界的一部分（通过 Performer/Level 系统划分）。状态变更通过 `ChangedState()` 序列化后经 gz-transport 传输。

---

## 十、关键设计模式与工程亮点

### 10.1 Reset 机制

Gazebo Sim 通过保存初始 ECM 副本实现 Reset：

```cpp
EntityComponentManager entityCompMgr;         // 当前状态
EntityComponentManager initialEntityCompMgr;  // 初始快照

// Reset 时
this->entityCompMgr.ResetTo(this->initialEntityCompMgr);
```

### 10.2 Entity 重建（Recreate）

对于需要"删除后重新创建"的 Entity（如重置模型位姿），Gazebo Sim 分两步处理：

1. `ProcessRecreateEntitiesRemove()` — 标记待重建的 Entity 为删除
2. System 在 UpdateSystems() 中处理删除
3. `ProcessRecreateEntitiesCreate()` — 克隆原始 Entity 创建新实例

这确保新旧 Entity 不会同时存在（避免名称冲突），同时保证 System 能正确清理旧 Entity 的状态。

### 10.3 Python GIL 管理

由于 Gazebo Sim 支持 Python 编写的 System 插件，PostUpdate 的并行执行需要特殊的 GIL 处理：

```cpp
struct MaybeGilScopedRelease {
    MaybeGilScopedRelease() {
        if (Py_IsInitialized() != 0 && PyGILState_Check() == 1)
            this->release.emplace();  // 释放 GIL
    }
    std::optional<pybind11::gil_scoped_release> release;
};
```

主线程在 PostUpdate 前释放 GIL，让各 PostUpdate 线程中的 Python System 可以独立获取 GIL 执行 Python 代码。

### 10.4 时间控制精度

RTF 公式推导：

$$RTF = \frac{sim\_time}{real\_time} = \frac{step\_size}{period}$$

$$\therefore period = \frac{step\_size}{RTF}$$

默认配置下：`step_size = 10ms`，`RTF = 1.0`，所以 `period = 10ms`（100Hz 更新频率）。

如果设置 `RTF = 2.0`，则 `period = 5ms`，仿真以双倍速运行。

---

## 十一、内置 System 一览

Gazebo Sim 包含 60+ 内置 System，按功能分类：

### 物理与运动

| System | 功能 | 阶段 |
|--------|------|------|
| `Physics` | 物理引擎步进 | Update |
| `DiffDrive` | 差速驱动控制 | PreUpdate |
| `AckermannSteering` | 阿克曼转向 | PreUpdate |
| `JointController` | 关节控制器 | PreUpdate |
| `JointPositionController` | 关节位置控制 | PreUpdate |
| `MulticopterMotorModel` | 多旋翼电机模型 | PreUpdate |
| `MulticopterVelocityControl` | 多旋翼速度控制 | PreUpdate |
| `Buoyancy` | 浮力 | PreUpdate |
| `Hydrodynamics` | 水动力 | PreUpdate |
| `LiftDrag` | 升力/阻力 | PreUpdate |
| `ApplyJointForce` | 施加关节力 | PreUpdate |
| `Thruster` | 推进器 | PreUpdate |
| `TrajectoryFollower` | 轨迹跟随 | PreUpdate |

### 传感器

| System | 功能 | 阶段 |
|--------|------|------|
| `Sensors` | 传感器管理（渲染传感器） | PostUpdate |
| `Imu` | IMU 传感器 | PostUpdate |
| `Altimeter` | 高度计 | PostUpdate |
| `AirPressure` | 气压传感器 | PostUpdate |
| `AirSpeed` | 空速传感器 | PostUpdate |
| `ForceTorque` | 力/力矩传感器 | PostUpdate |
| `NavSat` | GNSS/GPS 传感器 | PostUpdate |
| `Contact` | 接触传感器 | PostUpdate |

### 通信

| System | 功能 |
|--------|------|
| `AcousticComms` | 水下声学通信 |
| `RFComms` | 射频通信（含距离/噪声模型） |
| `PerfectComms` | 理想通信 |
| `CommsEndpoint` | 通信端点 |

### 工具与可视化

| System | 功能 |
|--------|------|
| `PosePublisher` | 位姿发布 |
| `SceneBroadcaster` | 场景状态广播 |
| `LogRecord` / `LogPlayback` | 日志记录/回放 |
| `UserCommands` | 用户指令处理 |
| `BatteryPlugin` | 电池建模 |
| `WindEffects` | 风场效果 |
| `DetachableJoint` | 可分离关节 |

---

## 十二、对无人机仿真开发者的实战指导

### 12.1 编写自定义 System 插件

最小可运行的自定义 System：

```cpp
#include <gz/sim/System.hh>
#include <gz/plugin/Register.hh>

namespace my_systems {

class CustomForce : public gz::sim::System,
                    public gz::sim::ISystemConfigure,
                    public gz::sim::ISystemPreUpdate
{
public:
    void Configure(const gz::sim::Entity &_entity,
                   const std::shared_ptr<const sdf::Element> &_sdf,
                   gz::sim::EntityComponentManager &_ecm,
                   gz::sim::EventManager &) override
    {
        this->entity = _entity;
        // 从 SDF 读取参数
        if (_sdf->HasElement("force_magnitude"))
            this->forceMag = _sdf->Get<double>("force_magnitude");
    }

    void PreUpdate(const gz::sim::UpdateInfo &_info,
                   gz::sim::EntityComponentManager &_ecm) override
    {
        if (_info.paused) return;
        
        // 通过 ECM 获取 Link 实体
        auto linkEntity = _ecm.EntityByComponents(
            gz::sim::components::Link(),
            gz::sim::components::ParentEntity(this->entity),
            gz::sim::components::Name("base_link"));
        
        if (linkEntity != gz::sim::kNullEntity) {
            // 在 Link 上施加力
            auto forceComp = _ecm.Component<
                gz::sim::components::ExternalWorldWrenchCmd>(linkEntity);
            // ... 设置力和力矩
        }
    }

private:
    gz::sim::Entity entity{gz::sim::kNullEntity};
    double forceMag{0.0};
};

}

GZ_ADD_PLUGIN(
    my_systems::CustomForce,
    gz::sim::System,
    my_systems::CustomForce::ISystemConfigure,
    my_systems::CustomForce::ISystemPreUpdate)
```

### 12.2 关键注意事项

1. **PreUpdate 和 Update 是顺序执行的**：不要在其中做耗时操作，否则会拖慢整个仿真
2. **PostUpdate 是并行执行且只读的**：传感器数据处理、日志记录、遥测发布应放在 PostUpdate
3. **Configure 时并非所有 Entity 都已加载**：如果需要访问插件父元素之外的 Entity，应在 PreUpdate 中延迟初始化
4. **Entity 删除是延迟的**：`RequestRemoveEntity()` 只是入队，实际删除在 Step 末尾的 `ProcessRemoveEntityRequests()` 中执行
5. **优先级很重要**：如果你的 System 需要在物理步进前应用力，确保优先级小于 `kPhysicsPriority`（-64）

### 12.3 PX4 SITL 集成的底层逻辑

在 Gazebo + PX4 SITL 仿真中：

1. PX4 通过 `gz-transport` 订阅传感器数据（IMU、GPS、气压计等——由各传感器 System 在 PostUpdate 阶段发布）
2. PX4 计算控制输出，通过 `gz-transport` 发布执行器指令
3. `MulticopterMotorModel` System 在 PreUpdate 阶段读取执行器指令，计算推力/力矩
4. `Physics` System 在 Update 阶段执行物理步进，应用所有力和力矩

```
PX4 SITL                                  Gazebo Sim
                                    
┌──────────┐                    ┌──────────────────────┐
│          │   actuator_cmds    │  PreUpdate:          │
│ 控制器    │ ─────────────────→ │  MulticopterMotor    │
│          │                    │  Model (读取指令,     │
│          │                    │  计算推力/力矩)       │
│          │                    │                      │
│          │                    │  Update:             │
│          │                    │  Physics (物理步进)   │
│          │                    │                      │
│          │   sensor_data      │  PostUpdate:         │
│ 状态估计  │ ←───────────────── │  IMU/GPS/Baro       │
│          │                    │  (发布传感器数据)     │
└──────────┘                    └──────────────────────┘
```

---

## 十三、性能关键路径分析

通过源码中的 `GZ_PROFILE` 宏标注，可以识别性能关键路径：

```
SimulationRunner::Run
  └── SimulationRunner::Step
        ├── PublishStats          （低开销）
        ├── ProcessSystemQueue    （仅在添加/删除 System 时触发）
        └── UpdateSystems         （★ 主要开销）
              ├── PreUpdate       （顺序，单线程）
              ├── Update          （顺序，单线程）
              │     └── Physics   （物理引擎步进 — 通常最耗时）
              └── PostUpdate      （并行，多线程）
                    ├── Sensors   （渲染传感器 — GPU 密集）
                    ├── IMU       （计算密集）
                    └── ...
```

**性能瓶颈**通常在：
1. **Physics Update**：碰撞检测和约束求解是 CPU 密集型
2. **Sensors PostUpdate**：渲染类传感器（相机、LiDAR）是 GPU 密集型
3. **ECM 查询**：大量 `Each()` 遍历在 Entity 数量很多时可能成为瓶颈

---

## 十四、与 Gazebo Classic 的架构对比

| 特性 | Gazebo Classic | Gazebo Sim |
|------|---------------|------------|
| 架构模式 | 面向对象（继承层次） | ECS（数据驱动） |
| 物理引擎 | 内置 ODE，可选 Bullet/DART/Simbody | 通过 gz-physics 抽象，插件化 |
| 渲染引擎 | OGRE 1.x | OGRE 2.x（通过 gz-rendering） |
| 传感器 | 内置于核心 | 独立库 gz-sensors |
| 通信 | 自定义 TCP | gz-transport（protobuf） |
| 分布式 | 不支持 | Primary/Secondary Runner |
| 插件 API | World/Model/Sensor Plugin | 统一的 System 接口 |
| Python 支持 | 有限 | 完整（pybind11） |
| 日志回放 | 有限 | 完整（序列化状态） |

---

## 十五、参考资源

1. **源码仓库**: [github.com/gazebosim/gz-sim](https://github.com/gazebosim/gz-sim)
2. **API 文档**: [gazebosim.org/api/sim/10/](https://gazebosim.org/api/sim/10/)
3. **Zread 源码解读**: [zread.ai/gazebosim/gz-sim](https://zread.ai/gazebosim/gz-sim)
4. **架构设计文档**: `doc/architecture_design.md`
5. **创建 System 插件教程**: `tutorials/creating_system_plugins.md`
6. **使用 Component 教程**: [gazebosim.org/api/sim/8/usingcomponents.html](https://gazebosim.org/api/sim/8/usingcomponents.html)
7. **gz-physics 库**: [github.com/gazebosim/gz-physics](https://github.com/gazebosim/gz-physics)
8. **gz-sensors 库**: [github.com/gazebosim/gz-sensors](https://github.com/gazebosim/gz-sensors)
9. **gz-transport 库**: [github.com/gazebosim/gz-transport](https://github.com/gazebosim/gz-transport)
