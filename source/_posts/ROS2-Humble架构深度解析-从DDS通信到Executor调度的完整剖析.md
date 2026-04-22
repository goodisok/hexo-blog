---
title: ROS2 Humble 架构深度解析：从 DDS 通信到 Executor 调度的完整剖析
date: 2026-04-22 10:00:00
categories:
  - 机器人
  - 软件架构
tags:
  - ROS2
  - Humble
  - DDS
  - FastDDS
  - CycloneDDS
  - Executor
  - Lifecycle
  - QoS
  - rclcpp
  - rmw
  - 中间件
  - Launch
  - 组件化
  - 零拷贝
  - Action
  - 参数系统
  - 回调组
  - 实时系统
  - MCAP
  - rosbag2
  - Foxglove
  - 机器人操作系统
mathjax: true
---

> ROS2 不是 ROS1 的简单升级，而是一次从通信层到执行模型的彻底重构。本文以 **ROS2 Humble Hawksbill**（2022 LTS，支持至 2027 年）为基准，深入剖析其核心架构——从 DDS 中间件的选型与 QoS 策略，到 Executor 的调度语义与实时性限制，再到 Lifecycle Node 的状态机设计和 Launch 系统的声明式编排。

---

## 一、ROS2 的架构设计哲学

### 1.1 ROS1 的根本性限制

ROS1 诞生于 2007 年，彼时的设计假设是：单台机器、单个操作员、实验室环境。这些假设带来了三个根本性限制：

| 限制 | 具体表现 | 后果 |
|------|---------|------|
| **中心化 Master** | 所有节点通过 `rosmaster` 注册和发现 | 单点故障——Master 崩溃则整个系统瘫痪 |
| **自定义传输** | TCPROS/UDPROS 专有协议 | 无法利用工业标准的 QoS、安全加密 |
| **非确定性调度** | 单线程 Spinner + 不可控回调顺序 | 无法满足实时系统的截止时间要求 |

### 1.2 ROS2 的解决方案

ROS2 的核心设计决策可以归结为三点：

1. **用 DDS 替代自定义传输**——借助 OMG 标准协议获得去中心化发现、QoS 策略、安全加密
2. **分层抽象**——通过 `rmw`（ROS Middleware Interface）隔离 DDS 供应商差异
3. **可组合的执行模型**——Executor + Callback Group 机制，为实时调度留出空间

### 1.3 分层架构总览

```
┌─────────────────────────────────────────────┐
│              用户应用（Your Code）            │
├─────────────────────────────────────────────┤
│  rclcpp (C++)  │  rclpy (Python)  │  rclc   │  ← 客户端库
├─────────────────────────────────────────────┤
│                  rcl (C)                     │  ← 核心库（语言无关）
├─────────────────────────────────────────────┤
│           rmw（ROS Middleware Interface）     │  ← 中间件抽象层
├──────────────┬──────────────┬───────────────┤
│ rmw_fastrtps │rmw_cyclonedds│ rmw_connextdds│  ← DDS 供应商适配
├──────────────┴──────────────┴───────────────┤
│    Fast DDS    │  Cyclone DDS  │ Connext DDS │  ← DDS 实现
└─────────────────────────────────────────────┘
```

关键洞察：**用户代码只依赖 `rclcpp`/`rclpy`，不直接调用 DDS API**。通过一个环境变量即可切换底层 DDS 实现：

```bash
# 切换到 Cyclone DDS
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp

# 切换到 Fast DDS（Humble 默认）
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
```

---

## 二、DDS 通信层：ROS2 的"神经系统"

### 2.1 什么是 DDS

DDS（Data Distribution Service）是 OMG（Object Management Group）定义的数据分发标准，广泛应用于航空航天、国防和金融领域。它提供：

- **去中心化发现**：通过 SPDP（Simple Participant Discovery Protocol）和 SEDP（Simple Endpoint Discovery Protocol），节点自动发现彼此，无需中心协调器
- **丰富的 QoS 策略**：22 种标准 QoS Policy，涵盖可靠性、持久性、截止时间等
- **安全扩展**：DDS-Security 规范提供认证、加密、访问控制

### 2.2 rmw：中间件抽象层

`rmw` 是 ROS2 最关键的抽象层之一。它定义了一组 C 语言接口，每个 DDS 供应商提供一个 `rmw` 实现：

```
rmw_create_node()           → 创建节点
rmw_create_publisher()      → 创建发布者
rmw_create_subscription()   → 创建订阅者
rmw_publish()               → 发布消息
rmw_take()                  → 接收消息
rmw_wait()                  → 等待事件（核心阻塞点）
rmw_create_guard_condition() → 创建守护条件
```

`rcl`（ROS Client Library）在 `rmw` 之上提供了 `rcl_wait_set_t`——一个统一的事件等待集合，Executor 正是围绕它来调度回调的。

### 2.3 Fast DDS vs Cyclone DDS

Humble 默认使用 Fast DDS（eProsima），但很多开发者发现 Cyclone DDS 在本地网络中表现更好：

| 特性 | Fast DDS (eProsima) | Cyclone DDS (Eclipse) |
|------|--------------------|-----------------------|
| 协议 | Apache 2.0 | Eclipse Public License 2.0 |
| **Humble 默认** | 是 | 否 |
| 发布模式 | 同步（默认） | 同步 |
| 共享内存 | 内置 SHM Transport | 通过 iceoryx 集成 |
| XML 配置 | 完整支持（Profiles） | YAML 配置 |
| 零拷贝 | Data Sharing + Loaned Messages | iceoryx + Loaned Messages |
| 本地延迟 | ~1-3ms（一般场景） | ~0.5-1ms（一般场景） |
| 大消息吞吐 | 更强（异步模式） | 中等 |
| 适用场景 | 复杂 QoS、跨网络 | 低延迟、嵌入式 |

**选择建议**：
- **单机或局域网内无人机仿真**：Cyclone DDS（延迟低、配置简单）
- **跨网络分布式多机器人系统**：Fast DDS（高级 QoS、XML Profile 灵活配置）

### 2.4 Fast DDS 在 rmw_fastrtps 中的特殊行为

`rmw_fastrtps` 默认会覆盖 Fast DDS 的某些配置：

| 参数 | rmw_fastrtps 默认值 | Fast DDS 原始默认值 |
|------|---------------------|---------------------|
| `publishMode` | `SYNCHRONOUS` | `SYNCHRONOUS` |
| `historyMemoryPolicy` | `PREALLOCATED_WITH_REALLOC` | `PREALLOCATED` |
| Data Sharing | `OFF` | `AUTO` |

如果你想使用 XML Profile 完全控制 Fast DDS 的行为，需要设置：

```bash
export RMW_FASTRTPS_USE_QOS_FROM_XML=1
```

但这有一个陷阱：如果 XML 中没有显式定义 `historyMemoryPolicy`，Fast DDS 会使用 `PREALLOCATED`——这与 ROS2 的变长消息类型不兼容，会导致运行时错误。因此 XML 中必须显式设置：

```xml
<data_writer profile_name="default_publisher">
  <historyMemoryPolicy>DYNAMIC</historyMemoryPolicy>
  <qos>
    <publishMode>
      <kind>ASYNCHRONOUS</kind>
    </publishMode>
  </qos>
</data_writer>
```

---

## 三、QoS 策略：精细控制通信行为

### 3.1 QoS 策略总览

ROS2 将 DDS 的 QoS 策略暴露给开发者，但做了简化。以下是 Humble 中可配置的核心策略：

| QoS 策略 | 可选值 | 默认值 | 含义 |
|----------|--------|--------|------|
| **History** | `KEEP_LAST` / `KEEP_ALL` | `KEEP_LAST` | 保留最近 N 条还是全部消息 |
| **Depth** | 正整数 | 10 | 与 `KEEP_LAST` 配合的队列深度 |
| **Reliability** | `RELIABLE` / `BEST_EFFORT` | `RELIABLE` | 可靠传输 vs 尽力传输 |
| **Durability** | `TRANSIENT_LOCAL` / `VOLATILE` | `VOLATILE` | 新订阅者是否收到历史消息 |
| **Deadline** | Duration | ∞ | 两次发布之间的最大间隔 |
| **Lifespan** | Duration | ∞ | 消息的有效期 |
| **Liveliness** | `AUTOMATIC` / `MANUAL_BY_TOPIC` | `AUTOMATIC` | 存活检测策略 |

### 3.2 预定义 QoS Profile

ROS2 提供了几个预定义的 QoS Profile，覆盖常见场景：

```cpp
// 默认 QoS（类似 ROS1 行为）
auto qos_default = rclcpp::QoS(10); // KEEP_LAST, depth=10, RELIABLE, VOLATILE

// 传感器数据（允许丢包，追求实时性）
auto qos_sensor = rclcpp::SensorDataQoS();
// → KEEP_LAST, depth=5, BEST_EFFORT, VOLATILE

// 参数服务
auto qos_param = rclcpp::ParametersQoS();
// → KEEP_LAST, depth=1000, RELIABLE, VOLATILE

// 类似 ROS1 的 latched topic
auto qos_latched = rclcpp::QoS(1).transient_local();
// → KEEP_LAST, depth=1, RELIABLE, TRANSIENT_LOCAL
```

### 3.3 QoS 兼容性规则

发布者和订阅者的 QoS 必须兼容才能通信。规则如下：

| 发布者 | 订阅者 | 结果 |
|--------|--------|------|
| `RELIABLE` | `RELIABLE` | 兼容 |
| `RELIABLE` | `BEST_EFFORT` | 兼容 |
| `BEST_EFFORT` | `BEST_EFFORT` | 兼容 |
| `BEST_EFFORT` | `RELIABLE` | **不兼容**（静默失败） |

这是 ROS2 新手最常遇到的陷阱之一：发布者用了 `BEST_EFFORT`（如传感器数据），订阅者用了默认的 `RELIABLE`，结果一条消息都收不到——**且没有任何错误提示**。

诊断方法：

```bash
# 查看某个主题的 QoS 信息
ros2 topic info /scan --verbose
```

### 3.4 实际场景配置示例

```cpp
// 无人机 IMU 数据：400Hz 高频，允许偶尔丢包
auto imu_qos = rclcpp::QoS(rclcpp::KeepLast(1))
    .reliability(rclcpp::ReliabilityPolicy::BestEffort)
    .durability(rclcpp::DurabilityPolicy::Volatile);

auto imu_sub = this->create_subscription<sensor_msgs::msg::Imu>(
    "/imu/data", imu_qos, callback);

// 制导指令：必须可靠送达，带截止时间
auto cmd_qos = rclcpp::QoS(rclcpp::KeepLast(5))
    .reliability(rclcpp::ReliabilityPolicy::Reliable)
    .deadline(std::chrono::milliseconds(50)); // 50ms 截止时间

auto cmd_pub = this->create_publisher<geometry_msgs::msg::Twist>(
    "/cmd_vel", cmd_qos);
```

---

## 四、Action：长时间异步任务的通信模式

### 4.1 三大通信模式对比

ROS2 提供三种通信模式，各有适用场景：

| 模式 | 特点 | 典型场景 |
|------|------|---------|
| **Topic** | 单向、异步、多对多 | IMU 数据流、相机图像 |
| **Service** | 请求-响应、同步、一对一 | 参数查询、模式切换 |
| **Action** | 异步请求 + 进度反馈 + 可取消 | 导航到目标点、起飞/降落 |

Topic 和 Service 容易理解，Action 是 ROS2 中最复杂也最常被忽视的通信模式。

### 4.2 Action 的三通道架构

一个 Action 由三个独立的通信通道组成：

```
                Action Client                     Action Server
               ┌──────────┐                      ┌──────────┐
               │          │── Goal Request ──────►│          │
               │          │◄── Goal Response ─────│          │
               │          │                       │          │
               │          │◄── Feedback ──────────│          │
               │          │     (周期性)           │          │
               │          │                       │          │
               │          │◄── Result ────────────│          │
               │          │     (完成时)           │          │
               └──────────┘                      └──────────┘
```

- **Goal**：客户端发送目标请求，服务端返回是否接受（Service 模式）
- **Feedback**：服务端在执行过程中周期性发布进度（Topic 模式）
- **Result**：任务完成后返回最终结果（Service 模式）

底层实现上，一个 Action 实际上由 **2 个 Service + 1 个 Topic** 组合而成。

### 4.3 定义 Action

创建 `.action` 文件，格式为 Goal / Result / Feedback 三段，用 `---` 分隔：

```
# NavigateToPoint.action
# --- Goal ---
float64 target_x
float64 target_y
float64 target_z
float64 max_velocity
---
# --- Result ---
bool success
float64 total_time
float64 final_distance_error
---
# --- Feedback ---
float64 current_x
float64 current_y
float64 current_z
float64 distance_remaining
float64 estimated_time_remaining
```

`CMakeLists.txt` 中生成代码：

```cmake
find_package(rosidl_default_generators REQUIRED)
rosidl_generate_interfaces(${PROJECT_NAME}
    "action/NavigateToPoint.action"
)
```

### 4.4 Action Server 实现

```cpp
#include <rclcpp/rclcpp.hpp>
#include <rclcpp_action/rclcpp_action.hpp>
#include "my_interfaces/action/navigate_to_point.hpp"

using NavigateToPoint = my_interfaces::action::NavigateToPoint;
using GoalHandle = rclcpp_action::ServerGoalHandle<NavigateToPoint>;

class NavigationServer : public rclcpp::Node
{
public:
    NavigationServer() : Node("navigation_server")
    {
        action_server_ = rclcpp_action::create_server<NavigateToPoint>(
            this, "navigate_to_point",
            // 目标请求回调：决定是否接受
            [this](const rclcpp_action::GoalUUID &,
                   std::shared_ptr<const NavigateToPoint::Goal> goal)
            {
                RCLCPP_INFO(get_logger(), "Goal received: (%.1f, %.1f, %.1f)",
                            goal->target_x, goal->target_y, goal->target_z);
                return rclcpp_action::GoalResponse::ACCEPT_AND_EXECUTE;
            },
            // 取消请求回调
            [this](const std::shared_ptr<GoalHandle>)
            {
                RCLCPP_INFO(get_logger(), "Cancel requested");
                return rclcpp_action::CancelResponse::ACCEPT;
            },
            // 目标被接受后的执行回调
            [this](const std::shared_ptr<GoalHandle> goal_handle)
            {
                std::thread([this, goal_handle]() {
                    execute(goal_handle);
                }).detach();
            });
    }

private:
    void execute(const std::shared_ptr<GoalHandle> goal_handle)
    {
        auto goal = goal_handle->get_goal();
        auto feedback = std::make_shared<NavigateToPoint::Feedback>();
        auto result = std::make_shared<NavigateToPoint::Result>();
        rclcpp::Rate rate(10); // 10Hz 反馈

        while (rclcpp::ok()) {
            // 检查是否被取消
            if (goal_handle->is_canceling()) {
                result->success = false;
                goal_handle->canceled(result);
                return;
            }

            // 计算当前距离（简化示例）
            feedback->distance_remaining = compute_distance(goal);
            goal_handle->publish_feedback(feedback);

            if (feedback->distance_remaining < 0.5) {
                result->success = true;
                result->final_distance_error = feedback->distance_remaining;
                goal_handle->succeed(result);
                return;
            }
            rate.sleep();
        }
    }

    rclcpp_action::Server<NavigateToPoint>::SharedPtr action_server_;
};
```

### 4.5 Action Client 实现

```cpp
class NavigationClient : public rclcpp::Node
{
public:
    NavigationClient() : Node("navigation_client")
    {
        client_ = rclcpp_action::create_client<NavigateToPoint>(
            this, "navigate_to_point");
    }

    void send_goal(double x, double y, double z)
    {
        auto goal = NavigateToPoint::Goal();
        goal.target_x = x;
        goal.target_y = y;
        goal.target_z = z;

        auto send_goal_options =
            rclcpp_action::Client<NavigateToPoint>::SendGoalOptions();

        // 目标响应回调
        send_goal_options.goal_response_callback =
            [this](const auto & goal_handle) {
                if (!goal_handle)
                    RCLCPP_ERROR(get_logger(), "Goal rejected");
                else
                    RCLCPP_INFO(get_logger(), "Goal accepted");
            };

        // 反馈回调
        send_goal_options.feedback_callback =
            [this](auto, const auto & feedback) {
                RCLCPP_INFO(get_logger(), "Distance remaining: %.2f",
                            feedback->distance_remaining);
            };

        // 结果回调
        send_goal_options.result_callback =
            [this](const auto & result) {
                if (result.result->success)
                    RCLCPP_INFO(get_logger(), "Navigation succeeded!");
                else
                    RCLCPP_WARN(get_logger(), "Navigation failed");
            };

        client_->async_send_goal(goal, send_goal_options);
    }

private:
    rclcpp_action::Client<NavigateToPoint>::SharedPtr client_;
};
```

### 4.6 Action 的关键设计决策

1. **可抢占**：新的 Goal 可以抢占正在执行的 Goal（由服务端决定策略）
2. **可取消**：客户端可随时发送取消请求
3. **多 Goal 并发**：服务端可以同时处理多个 Goal（需要自行管理）
4. **QoS 独立**：Goal/Result 使用 `RELIABLE`，Feedback 使用 `BEST_EFFORT`（可配置）

命令行使用：

```bash
# 查看可用 Action
ros2 action list

# 查看 Action 类型
ros2 action info /navigate_to_point

# 发送目标
ros2 action send_goal /navigate_to_point \
    my_interfaces/action/NavigateToPoint \
    "{target_x: 10.0, target_y: 5.0, target_z: 2.0}" \
    --feedback  # 显示反馈
```

---

## 五、参数系统：声明式节点配置

### 5.1 ROS1 vs ROS2 参数模型

| 特性 | ROS1 | ROS2 |
|------|------|------|
| 存储位置 | 全局参数服务器（`rosparam`） | 每个节点内部 |
| 作用域 | 全局命名空间 | 节点级隔离 |
| 声明 | 无需声明，随用随取 | 必须先 `declare_parameter` |
| 类型检查 | 无 | 有（声明时指定类型） |
| 修改回调 | 无 | `add_on_set_parameters_callback` |
| 持久化 | `rosparam dump/load` | YAML 文件 + Launch 参数 |

### 5.2 声明与使用

```cpp
class DroneController : public rclcpp::Node
{
public:
    DroneController() : Node("drone_controller")
    {
        // 声明参数（带默认值和描述）
        this->declare_parameter("control_rate", 400.0,
            rcl_interfaces::msg::ParameterDescriptor()
                .set__description("Control loop frequency in Hz")
                .set__floating_point_range({rcl_interfaces::msg::FloatingPointRange()
                    .set__from_value(50.0)
                    .set__to_value(1000.0)
                    .set__step(0.0)}));

        this->declare_parameter("max_velocity", 30.0);
        this->declare_parameter("pid_gains.kp", 1.2);
        this->declare_parameter("pid_gains.ki", 0.01);
        this->declare_parameter("pid_gains.kd", 0.5);

        // 读取参数
        double rate = this->get_parameter("control_rate").as_double();
        double kp = this->get_parameter("pid_gains.kp").as_double();

        // 批量读取
        auto params = this->get_parameters({"max_velocity", "pid_gains.kp"});

        // 注册参数修改回调
        param_callback_ = this->add_on_set_parameters_callback(
            [this](const std::vector<rclcpp::Parameter> & params)
            -> rcl_interfaces::msg::SetParametersResult
            {
                auto result = rcl_interfaces::msg::SetParametersResult();
                result.successful = true;

                for (const auto & param : params) {
                    if (param.get_name() == "control_rate") {
                        double new_rate = param.as_double();
                        if (new_rate < 50.0 || new_rate > 1000.0) {
                            result.successful = false;
                            result.reason = "control_rate must be 50-1000 Hz";
                            return result;
                        }
                        update_timer_period(new_rate);
                        RCLCPP_INFO(get_logger(),
                            "Control rate changed to %.0f Hz", new_rate);
                    }
                }
                return result;
            });
    }

private:
    rclcpp::node_interfaces::OnSetParametersCallbackHandle::SharedPtr
        param_callback_;
};
```

### 5.3 通过 YAML 文件加载参数

创建参数文件 `config/drone_params.yaml`：

```yaml
drone_controller:
  ros__parameters:
    control_rate: 400.0
    max_velocity: 30.0
    pid_gains:
      kp: 1.2
      ki: 0.01
      kd: 0.5
    safety:
      max_altitude: 120.0
      geofence_radius: 500.0
```

Launch 文件中加载：

```python
Node(
    package='drone_controller',
    executable='controller_node',
    name='drone_controller',
    parameters=[
        os.path.join(get_package_share_directory('drone_controller'),
                     'config', 'drone_params.yaml'),
        {'override_param': 999},  # 还可以额外覆盖
    ],
)
```

命令行加载：

```bash
ros2 run drone_controller controller_node \
    --ros-args --params-file config/drone_params.yaml
```

### 5.4 参数事件监听

ROS2 中每个节点的参数变化都会发布到 `/parameter_events` 话题，可以全局监听：

```bash
# 监听所有参数变化事件
ros2 topic echo /parameter_events

# 动态修改参数
ros2 param set /drone_controller control_rate 200.0

# 导出当前所有参数到 YAML
ros2 param dump /drone_controller > current_params.yaml

# 从 YAML 加载参数（覆盖当前值）
ros2 param load /drone_controller current_params.yaml
```

### 5.5 参数系统的设计哲学

ROS2 参数系统的"声明式"设计是刻意的约束：

- **声明即文档**：所有参数必须在代码中显式声明，阅读构造函数就知道节点接受哪些配置
- **类型安全**：声明时指定类型，运行时设置错误类型会被拒绝
- **范围约束**：可以指定 `IntegerRange` / `FloatingPointRange`，非法值在设置时就被拦截
- **修改可控**：通过回调函数，节点可以拒绝不合理的参数修改并返回原因

---

## 六、Executor：回调调度的核心

### 6.1 Executor 的职责

Executor 是 ROS2 中调度回调执行的核心组件。它负责：

1. 维护一个 `rcl_wait_set_t`，包含所有注册的订阅、定时器、服务、动作的文件描述符
2. 调用 `rmw_wait()` 阻塞等待任意事件就绪
3. 确定就绪事件对应的回调函数
4. 执行回调

### 6.2 三种 Executor 类型

#### SingleThreadedExecutor

最简单的实现。核心 `spin()` 循环只有几行代码：

```cpp
void SingleThreadedExecutor::spin()
{
    if (spinning.exchange(true)) {
        throw std::runtime_error("spin() called while already spinning");
    }
    RCPPUTILS_SCOPE_EXIT(this->spinning.store(false););

    while (rclcpp::ok(this->context_) && spinning.load()) {
        rclcpp::AnyExecutable any_executable;
        if (get_next_executable(any_executable)) {
            execute_any_executable(any_executable);
        }
    }
}
```

`get_next_executable()` 内部调用 `rmw_wait()` 等待事件，然后遍历 wait set 找到第一个就绪的回调。

**问题**：如果一个回调执行时间很长，所有其他回调都被阻塞。

#### MultiThreadedExecutor

创建一个线程池（默认线程数 = `std::thread::hardware_concurrency()`），每个线程独立运行：

```cpp
MultiThreadedExecutor::MultiThreadedExecutor(
    const rclcpp::ExecutorOptions & options,
    size_t number_of_threads,
    bool yield_before_execute,
    std::chrono::nanoseconds next_exec_timeout)
```

多个线程可以并行执行不同回调——但这引入了线程安全问题，需要配合 **Callback Group** 使用。

#### StaticSingleThreadedExecutor

优化版的单线程 Executor。与 `SingleThreadedExecutor` 的区别在于：它只在启动时扫描一次节点的订阅、定时器等实体，后续不再重新扫描。这减少了每次 `spin` 迭代的开销，适合实体拓扑不会动态变化的场景。

### 6.3 Callback Group：并发控制

Callback Group 是 ROS2 中控制回调并发执行的核心机制：

```cpp
// 互斥回调组：同一组内的回调不会并行执行
auto mutex_group = this->create_callback_group(
    rclcpp::CallbackGroupType::MutuallyExclusive);

// 可重入回调组：同一组内的回调可以并行执行
auto reentrant_group = this->create_callback_group(
    rclcpp::CallbackGroupType::Reentrant);
```

**规则**：
- **同一 MutuallyExclusive 组内**：回调严格串行
- **不同组之间**：回调可以并行（在 MultiThreadedExecutor 中）
- **同一 Reentrant 组内**：回调可以并行

实际使用示例：

```cpp
class DroneController : public rclcpp::Node
{
public:
    DroneController() : Node("drone_controller")
    {
        // 高频传感器回调放在可重入组——允许 IMU 和相机回调并行
        auto sensor_group = create_callback_group(
            rclcpp::CallbackGroupType::Reentrant);

        // 控制指令放在互斥组——保证指令不会并发执行
        auto control_group = create_callback_group(
            rclcpp::CallbackGroupType::MutuallyExclusive);

        rclcpp::SubscriptionOptions sensor_opts;
        sensor_opts.callback_group = sensor_group;

        imu_sub_ = create_subscription<sensor_msgs::msg::Imu>(
            "/imu", rclcpp::SensorDataQoS(), imu_callback, sensor_opts);

        image_sub_ = create_subscription<sensor_msgs::msg::Image>(
            "/camera", rclcpp::SensorDataQoS(), image_callback, sensor_opts);

        rclcpp::SubscriptionOptions control_opts;
        control_opts.callback_group = control_group;

        cmd_sub_ = create_subscription<geometry_msgs::msg::Twist>(
            "/cmd", 10, cmd_callback, control_opts);
    }
};
```

### 6.4 Executor 调度语义与实时性限制

ROS2 Executor 的调度语义是：**当回调处理速度跟得上消息到达速度时，近似 FIFO。当跟不上时，行为变为非 FIFO**。

这是因为 `rmw_wait()` 返回后，Executor 遍历 wait set 的顺序是固定的（定时器 → 订阅 → 服务 → 客户端 → 守护条件），而非按消息到达的时间排序。这意味着：

- **定时器总是比订阅优先执行**
- 同类型的多个订阅之间的顺序取决于注册顺序

学术界（Casini et al., ECRTS 2019）对此进行了形式化分析，结论是：**ROS2 默认 Executor 不适合硬实时场景**。对于有严格截止时间要求的无人机控制循环，建议：

1. 使用 `rclcpp::WaitSet` 直接等待特定订阅，绕过 Executor
2. 使用第三方实时 Executor（如 `rclc` 的 `rclc_executor`）
3. 将关键控制回路放在独立线程中，不走 Executor

### 6.5 使用模式总结

```cpp
// 模式一：最简单——单节点单线程
rclcpp::spin(node);
// 内部等价于：
// rclcpp::executors::SingleThreadedExecutor exec;
// exec.add_node(node);
// exec.spin();

// 模式二：多节点共享一个 Executor
rclcpp::executors::MultiThreadedExecutor exec;
exec.add_node(node1);
exec.add_node(node2);
exec.add_node(node3);
exec.spin();

// 模式三：不同节点用不同 Executor（最大隔离）
auto exec1 = std::make_shared<rclcpp::executors::SingleThreadedExecutor>();
auto exec2 = std::make_shared<rclcpp::executors::SingleThreadedExecutor>();
exec1->add_node(critical_node);
exec2->add_node(logging_node);
auto thread1 = std::thread([&]() { exec1->spin(); });
auto thread2 = std::thread([&]() { exec2->spin(); });
thread1.join();
thread2.join();

// 模式四：非阻塞 spin（集成到自己的主循环中）
while (running) {
    executor.spin_some(std::chrono::milliseconds(10));
    // 做其他事情...
}
```

---

## 七、Lifecycle Node：受管理的节点生命周期

### 7.1 为什么需要 Lifecycle

在 ROS1 中，节点启动后立即开始工作——发布、订阅、控制。这带来几个问题：

- **启动顺序依赖**：节点 B 依赖节点 A 的输出，但 A 可能还没准备好
- **无法优雅地暂停/恢复**：你只能杀死进程再重启
- **资源管理混乱**：传感器驱动可能在上层节点还没准备好时就开始发数据

### 7.2 状态机设计

ROS2 的 Lifecycle Node 实现了一个标准状态机：

```
                    ┌──────────────┐
            ┌──────│ Unconfigured │◄──────┐
            │      └──────┬───────┘       │
            │             │ configure     │ cleanup
            │             ▼               │
            │      ┌──────────────┐       │
            │      │   Inactive   │───────┘
            │      └──────┬───────┘
            │             │ activate
            │             ▼
            │      ┌──────────────┐
            │      │    Active    │
            │      └──────┬───────┘
            │             │ deactivate
            │             ▼
     shutdown│      ┌──────────────┐
            │      │   Inactive   │
            │      └──────────────┘
            │
            ▼
     ┌──────────────┐
     │  Finalized   │
     └──────────────┘
```

**四个主状态**（Primary States）：

| 状态 | 含义 | 节点行为 |
|------|------|---------|
| `Unconfigured` | 初始状态 | 节点存在但未配置，不做任何事 |
| `Inactive` | 已配置但未激活 | 资源已分配，但不处理数据 |
| `Active` | 正常运行 | 执行主要功能：发布、订阅处理等 |
| `Finalized` | 终止状态 | 节点即将被销毁 |

### 7.3 回调接口

继承 `rclcpp_lifecycle::LifecycleNode` 并重写相应回调：

```cpp
#include <rclcpp_lifecycle/lifecycle_node.hpp>
#include <rclcpp_lifecycle/lifecycle_publisher.hpp>

class DroneDriver : public rclcpp_lifecycle::LifecycleNode
{
public:
    DroneDriver() : LifecycleNode("drone_driver") {}

    // 配置阶段：分配资源，但不启动
    CallbackReturn on_configure(const rclcpp_lifecycle::State &) override
    {
        imu_pub_ = create_publisher<sensor_msgs::msg::Imu>("/imu", 10);
        serial_port_.open("/dev/ttyUSB0", 921600);
        RCLCPP_INFO(get_logger(), "Configured: serial port opened");
        return CallbackReturn::SUCCESS;
    }

    // 激活阶段：开始工作
    CallbackReturn on_activate(const rclcpp_lifecycle::State & state) override
    {
        LifecycleNode::on_activate(state);  // 激活 LifecyclePublisher
        timer_ = create_wall_timer(
            2500us, [this]() { read_and_publish(); });
        RCLCPP_INFO(get_logger(), "Activated: publishing IMU data at 400Hz");
        return CallbackReturn::SUCCESS;
    }

    // 去激活：停止工作但保持资源
    CallbackReturn on_deactivate(const rclcpp_lifecycle::State & state) override
    {
        LifecycleNode::on_deactivate(state);
        timer_->cancel();
        RCLCPP_INFO(get_logger(), "Deactivated: stopped publishing");
        return CallbackReturn::SUCCESS;
    }

    // 清理：释放资源，回到 Unconfigured
    CallbackReturn on_cleanup(const rclcpp_lifecycle::State &) override
    {
        serial_port_.close();
        imu_pub_.reset();
        timer_.reset();
        RCLCPP_INFO(get_logger(), "Cleaned up: resources released");
        return CallbackReturn::SUCCESS;
    }

    // 关机
    CallbackReturn on_shutdown(const rclcpp_lifecycle::State &) override
    {
        serial_port_.close();
        RCLCPP_INFO(get_logger(), "Shutting down");
        return CallbackReturn::SUCCESS;
    }

    // 错误处理：任何状态转换中的未捕获异常都会触发
    CallbackReturn on_error(const rclcpp_lifecycle::State &) override
    {
        RCLCPP_ERROR(get_logger(), "Error occurred, attempting recovery");
        return CallbackReturn::SUCCESS; // 返回 SUCCESS → 回到 Unconfigured
    }

private:
    using CallbackReturn =
        rclcpp_lifecycle::node_interfaces::LifecycleNodeInterface::CallbackReturn;

    rclcpp_lifecycle::LifecyclePublisher<sensor_msgs::msg::Imu>::SharedPtr imu_pub_;
    rclcpp::TimerBase::SharedPtr timer_;
    SerialPort serial_port_;
};
```

### 7.4 外部控制

每个 Lifecycle Node 自动暴露以下服务接口：

```bash
# 查询当前状态
ros2 lifecycle get /drone_driver

# 触发状态转换
ros2 lifecycle set /drone_driver configure
ros2 lifecycle set /drone_driver activate
ros2 lifecycle set /drone_driver deactivate
ros2 lifecycle set /drone_driver cleanup
ros2 lifecycle set /drone_driver shutdown

# 查看所有可用的状态转换
ros2 lifecycle list /drone_driver
```

### 7.5 Lifecycle Manager：编排多节点启动

在复杂系统中，通常需要按顺序启动和配置多个 Lifecycle Node。Nav2（ROS2 导航框架）实现了一个 `LifecycleManager`：

```cpp
// Nav2 的 LifecycleManager 按顺序管理多个节点
std::vector<std::string> node_names = {
    "sensor_driver",
    "localization",
    "planning",
    "controller"
};

// 依次 configure → activate 每个节点
for (auto & name : node_names) {
    changeStateForNode(name, lifecycle_msgs::msg::Transition::TRANSITION_CONFIGURE);
    changeStateForNode(name, lifecycle_msgs::msg::Transition::TRANSITION_ACTIVATE);
}
```

这种模式保证了：传感器驱动先就绪，定位算法再启动，规划器最后激活——解决了 ROS1 中的启动顺序问题。

---

## 八、Launch 系统：声明式部署编排

### 8.1 从 roslaunch 到 ros2 launch

ROS1 的 `roslaunch` 基于 XML，功能相对简单。ROS2 的 Launch 系统是一个完整的编排框架，支持 **Python、XML、YAML** 三种格式。

### 8.2 Python Launch 文件

Python 是最灵活的格式，支持条件逻辑、动态参数：

```python
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, GroupAction, IncludeLaunchDescription
from launch.conditions import IfCondition
from launch.substitutions import LaunchConfiguration, PythonExpression
from launch_ros.actions import Node, ComposableNodeContainer
from launch_ros.descriptions import ComposableNode

def generate_launch_description():
    # 声明参数
    use_sim = DeclareLaunchArgument('use_sim', default_value='true')
    drone_id = DeclareLaunchArgument('drone_id', default_value='0')

    # 条件启动
    gazebo = IncludeLaunchDescription(
        'gz_sim.launch.py',
        condition=IfCondition(LaunchConfiguration('use_sim'))
    )

    # 普通节点
    controller = Node(
        package='drone_controller',
        executable='controller_node',
        name=['drone_', LaunchConfiguration('drone_id'), '_controller'],
        parameters=[{
            'drone_id': LaunchConfiguration('drone_id'),
            'control_rate': 400.0,
        }],
        remappings=[
            ('/imu', ['/drone_', LaunchConfiguration('drone_id'), '/imu']),
        ],
    )

    # 组件化节点（同一进程，零拷贝）
    perception_container = ComposableNodeContainer(
        name='perception_container',
        namespace='',
        package='rclcpp_components',
        executable='component_container_mt',
        composable_node_descriptions=[
            ComposableNode(
                package='image_proc',
                plugin='image_proc::RectifyNode',
                name='rectify',
                extra_arguments=[{'use_intra_process_comms': True}],
            ),
            ComposableNode(
                package='drone_detector',
                plugin='drone_detector::YoloDetector',
                name='detector',
                extra_arguments=[{'use_intra_process_comms': True}],
            ),
        ],
    )

    return LaunchDescription([
        use_sim,
        drone_id,
        gazebo,
        controller,
        perception_container,
    ])
```

### 8.3 XML Launch 文件

XML 更简洁，适合不需要复杂逻辑的场景：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<launch>
  <arg name="use_sim" default="true" />
  <arg name="drone_id" default="0" />

  <!-- 条件启动 Gazebo -->
  <include file="$(find-pkg-share gz_sim)/launch/gz_sim.launch.xml"
           if="$(var use_sim)" />

  <!-- 控制器节点 -->
  <node pkg="drone_controller" exec="controller_node"
        name="controller" namespace="drone_$(var drone_id)">
    <param name="control_rate" value="400.0" />
    <remap from="/imu" to="/drone_$(var drone_id)/imu" />
  </node>

  <!-- 组件化容器 -->
  <node_container pkg="rclcpp_components" exec="component_container_mt"
                  name="perception_container" namespace="">
    <composable_node pkg="drone_detector"
                     plugin="drone_detector::YoloDetector"
                     name="detector">
      <extra_arg name="use_intra_process_comms" value="true" />
    </composable_node>
  </node_container>
</launch>
```

### 8.4 Substitution 机制

Launch 系统的核心能力之一是 **Substitution**——在运行时动态解析的值：

| Substitution | 语法（XML） | 含义 |
|-------------|------------|------|
| `LaunchConfiguration` | `$(var arg_name)` | 引用 Launch 参数 |
| `EnvironmentVariable` | `$(env VAR_NAME)` | 读取环境变量 |
| `FindPackageShare` | `$(find-pkg-share pkg)` | 包的 share 目录路径 |
| `PythonExpression` | `$(eval '1 + 1')` | 计算 Python 表达式 |
| `Command` | `$(command 'date')` | 执行 Shell 命令 |

---

## 九、组件化与零拷贝通信

### 9.1 从 ROS1 Nodelet 到 ROS2 Component

ROS1 有两套 API：`Node`（独立进程）和 `Nodelet`（共享进程）。这导致同一个功能往往需要维护两份代码。

ROS2 统一了这两套 API——所有节点都写成 **Component**（编译为共享库），运行时可以：
- 加载到 `component_container` 中（共享进程，支持零拷贝）
- 也可以生成独立可执行文件（隔离进程，方便调试）

### 9.2 编写 Component

```cpp
#include <rclcpp/rclcpp.hpp>
#include <rclcpp_components/register_node_macro.hpp>
#include <sensor_msgs/msg/image.hpp>

namespace drone_detector {

class YoloDetector : public rclcpp::Node
{
public:
    explicit YoloDetector(const rclcpp::NodeOptions & options)
        : Node("yolo_detector", options)
    {
        // 使用 unique_ptr 发布，启用零拷贝
        pub_ = create_publisher<sensor_msgs::msg::Image>("/detection", 10);

        sub_ = create_subscription<sensor_msgs::msg::Image>(
            "/camera/image", rclcpp::SensorDataQoS(),
            [this](sensor_msgs::msg::Image::UniquePtr msg) {
                // msg 是 unique_ptr——零拷贝传入
                process(*msg);
                pub_->publish(std::move(msg)); // 零拷贝传出
            });
    }

private:
    rclcpp::Publisher<sensor_msgs::msg::Image>::SharedPtr pub_;
    rclcpp::Subscription<sensor_msgs::msg::Image>::SharedPtr sub_;
};

} // namespace drone_detector

RCLCPP_COMPONENTS_REGISTER_NODE(drone_detector::YoloDetector)
```

CMakeLists.txt 中注册组件：

```cmake
add_library(yolo_detector SHARED src/yolo_detector.cpp)
ament_target_dependencies(yolo_detector rclcpp rclcpp_components sensor_msgs)

# 同时注册为组件和独立可执行文件
rclcpp_components_register_node(yolo_detector
    PLUGIN "drone_detector::YoloDetector"
    EXECUTABLE yolo_detector_node)
```

### 9.3 零拷贝的条件

要实现真正的零拷贝，需要满足：

1. **使用 `std::unique_ptr<MessageT>` 进行发布和订阅**——`shared_ptr` 或 `const &` 不会触发零拷贝
2. **节点在同一进程中**（通过 `component_container` 加载）
3. **启用进程内通信**：`use_intra_process_comms: true`

验证方法：打印消息的内存地址，发布者和订阅者应该看到相同的地址：

```bash
ros2 run intra_process_demo two_node_pipeline
# 输出：
# Published message with value: 0, at address: 0x55a4b2c3d4e0
# Received message with value: 0, at address: 0x55a4b2c3d4e0  ← 同一地址！
```

### 9.4 运行时加载组件

除了通过 Launch 文件静态加载，还可以在运行时动态管理组件：

```bash
# 启动空容器
ros2 run rclcpp_components component_container

# 加载组件
ros2 component load /ComponentManager drone_detector drone_detector::YoloDetector

# 查看已加载的组件
ros2 component list /ComponentManager

# 卸载组件
ros2 component unload /ComponentManager 1
```

---

## 十、与 ROS1 的核心差异总结

| 维度 | ROS1 | ROS2 Humble | 影响 |
|------|------|-------------|------|
| **发现机制** | `rosmaster`（中心化） | DDS SPDP/SEDP（去中心化） | 无单点故障 |
| **传输协议** | TCPROS/UDPROS（专有） | DDS（OMG 标准） | 可配置 QoS、安全加密 |
| **安全** | 无 | SROS2（DDS-Security） | 认证+加密+访问控制 |
| **实时性** | 不支持 | Executor + 回调组 | 可控并发，接近实时 |
| **多语言** | roscpp/rospy（两套 API） | rcl → rclcpp/rclpy/rclc | 统一核心，多语言绑定 |
| **构建系统** | catkin | ament + colcon | 更灵活的包管理 |
| **进程模型** | Node vs Nodelet（两套 API） | 统一 Component | 运行时可选进程隔离或共享 |
| **参数** | 全局参数服务器 | 节点内参数（声明式） | 作用域隔离 |
| **日志** | `ROS_INFO` 等宏 | `RCLCPP_INFO` + 可配置后端 | 支持多日志后端 |
| **Latched Topic** | `Publisher(latch=True)` | `QoS(TRANSIENT_LOCAL)` | 通过 QoS 策略实现 |
| **生命周期** | 无 | Lifecycle Node | 确定性启动/停止 |
| **平台支持** | 仅 Linux（Ubuntu） | Linux/Windows/macOS | 跨平台 |
| **EOL 状态** | Noetic 2025 年 5 月终止 | Humble 支持至 2027 年 | 必须迁移 |

### 10.1 API 迁移对照

```cpp
// ============ ROS1 ============
#include <ros/ros.h>

int main(int argc, char** argv)
{
    ros::init(argc, argv, "my_node");
    ros::NodeHandle nh;

    auto pub = nh.advertise<std_msgs::String>("/topic", 10);
    auto sub = nh.subscribe("/topic", 10, callback);
    auto srv = nh.advertiseService("/service", handler);
    auto timer = nh.createTimer(ros::Duration(0.1), timerCb);

    ros::spin();
    return 0;
}

// ============ ROS2 Humble ============
#include <rclcpp/rclcpp.hpp>

class MyNode : public rclcpp::Node
{
public:
    MyNode() : Node("my_node")
    {
        pub_ = create_publisher<std_msgs::msg::String>("/topic", 10);
        sub_ = create_subscription<std_msgs::msg::String>(
            "/topic", 10,
            [this](std_msgs::msg::String::SharedPtr msg) { /* callback */ });
        srv_ = create_service<example_interfaces::srv::AddTwoInts>(
            "/service", handler);
        timer_ = create_wall_timer(100ms, [this]() { /* timer callback */ });
    }
};

int main(int argc, char** argv)
{
    rclcpp::init(argc, argv);
    rclcpp::spin(std::make_shared<MyNode>());
    rclcpp::shutdown();
    return 0;
}
```

核心变化：
- **面向对象**：节点是类，不是全局函数
- **无全局状态**：没有 `ros::NodeHandle`，一切通过节点实例
- **Lambda 友好**：回调推荐使用 lambda 或 `std::bind`
- **消息命名空间**：`std_msgs::String` → `std_msgs::msg::String`

---

## 十一、构建系统：ament + colcon

### 11.1 ament：包级构建

`ament` 是 ROS2 的包构建系统，分为两种类型：

- **ament_cmake**：C/C++ 包
- **ament_python**：纯 Python 包

`package.xml` 使用 format 3：

```xml
<?xml version="1.0"?>
<package format="3">
  <name>drone_controller</name>
  <version>0.1.0</version>
  <description>Drone flight controller node</description>
  <maintainer email="dev@example.com">Developer</maintainer>
  <license>Apache-2.0</license>

  <buildtool_depend>ament_cmake</buildtool_depend>
  <depend>rclcpp</depend>
  <depend>sensor_msgs</depend>
  <depend>geometry_msgs</depend>

  <test_depend>ament_lint_auto</test_depend>

  <export>
    <build_type>ament_cmake</build_type>
  </export>
</package>
```

### 11.2 colcon：工作空间构建

`colcon` 是工作空间级别的构建工具：

```bash
# 创建工作空间
mkdir -p ~/ros2_ws/src
cd ~/ros2_ws/src

# 克隆你的包
git clone https://github.com/your/drone_controller.git

# 构建
cd ~/ros2_ws
colcon build

# 仅构建特定包
colcon build --packages-select drone_controller

# 并行构建（默认已启用）
colcon build --parallel-workers 8

# 构建后激活环境
source install/setup.bash
```

与 catkin 的关键区别：
- `devel/` → `install/`（直接安装，无 devel space）
- 支持 CMake、Python、Cargo 等多种构建系统
- 包之间的构建顺序自动推断

---

## 十二、Bag 数据记录：从 SQLite3 到 MCAP

### 12.1 ROS2 Bag 存储格式演进

ROS2 的 `ros2 bag` 工具用于记录和回放话题数据，是调试、数据分析和离线算法开发的核心工具。其存储格式经历了重要演进：

| 版本 | 默认格式 | 特点 |
|------|---------|------|
| ROS1 | `.bag`（自定义二进制） | 单文件、不支持索引重建 |
| ROS2 Foxy/Galactic | **SQLite3**（`.db3`） | 结构化查询，但大文件性能差 |
| ROS2 Humble+ | **SQLite3**（默认），**MCAP** 可选 | Humble 中 MCAP 作为可选插件 |
| ROS2 Iron/Jazzy+ | **MCAP**（默认） | 高性能、流式读写、自描述 |

### 12.2 什么是 MCAP

MCAP（读作 "em-cap"）是由 Foxglove 开发的开源数据容器格式，专为机器人和自动驾驶设计。其核心优势：

| 特性 | SQLite3 (.db3) | MCAP (.mcap) |
|------|----------------|--------------|
| **写入性能** | 中等（事务开销） | 极高（追加写入，无事务） |
| **读取性能** | 依赖索引，大文件慢 | 内置 Chunk 索引，O(1) 时间定位 |
| **文件损坏恢复** | 困难（SQLite WAL 损坏后难恢复） | 可恢复（Chunk 独立，损坏只影响局部） |
| **流式写入** | 不支持 | 支持（可边写边读） |
| **压缩** | 不支持 | 内置（LZ4/Zstd，按 Chunk 压缩） |
| **自描述** | 消息定义存在 schema 表中 | 完整 schema 嵌入文件（无需额外 `.msg` 文件） |
| **跨平台工具** | 需要 ROS2 环境才能读 | Foxglove Studio 直接打开、Python/C++/Go/Rust SDK |
| **文件大小** | 较大 | 压缩后通常减小 30-60% |

### 12.3 在 Humble 中使用 MCAP

Humble 中 MCAP 存储插件需要手动安装：

```bash
# 安装 MCAP 存储插件
sudo apt install ros-humble-rosbag2-storage-mcap
```

#### 录制为 MCAP 格式

```bash
# 指定存储格式为 mcap
ros2 bag record -a -s mcap

# 录制指定主题，使用 mcap 格式 + Zstd 压缩
ros2 bag record /imu /camera/image /cmd_vel \
    -s mcap \
    --compression-mode message \
    --compression-format zstd

# 指定输出目录和最大文件大小（自动分片）
ros2 bag record -a -s mcap \
    -o /data/flight_test_001 \
    --max-bag-size 1073741824  # 1GB 自动分片

# 录制时添加元数据
ros2 bag record -a -s mcap \
    -o /data/flight_test_001 \
    --custom-data "drone_id=3" \
    --custom-data "pilot=zhang"
```

#### 回放

```bash
# 回放 mcap 格式的 bag
ros2 bag play /data/flight_test_001

# 倍速回放
ros2 bag play /data/flight_test_001 --rate 2.0

# 从指定时间开始回放
ros2 bag play /data/flight_test_001 --start-offset 30

# 只回放特定主题
ros2 bag play /data/flight_test_001 --topics /imu /cmd_vel

# 循环回放
ros2 bag play /data/flight_test_001 --loop
```

#### 查看 Bag 信息

```bash
ros2 bag info /data/flight_test_001

# 典型输出：
# Files:             flight_test_001_0.mcap
# Bag size:          256.3 MiB
# Storage id:        mcap
# Duration:          120.5s
# Start:             Apr 22 2026 10:30:00.000
# End:               Apr 22 2026 10:32:00.500
# Messages:          4820000
# Topic information:
#   /imu              400000 msgs  : sensor_msgs/msg/Imu
#   /camera/image      3600 msgs  : sensor_msgs/msg/Image
#   /cmd_vel          12000 msgs  : geometry_msgs/msg/Twist
```

### 12.4 MCAP 文件结构

```
┌─────────────────────────────────────┐
│            Magic Bytes              │  ← 文件标识 0x89 M C A P 0x30 \r \n
├─────────────────────────────────────┤
│          Header Record              │  ← 文件级元数据
├─────────────────────────────────────┤
│      Schema Record (IMU)            │  ← 消息定义（自描述）
│      Schema Record (Image)          │
│      Channel Record (/imu)          │  ← 话题 → Schema 映射
│      Channel Record (/camera)       │
├─────────────────────────────────────┤
│  ┌───────────────────────────────┐  │
│  │   Chunk (LZ4/Zstd 压缩)      │  │  ← 一段时间内的消息集合
│  │   ├── Message Record          │  │
│  │   ├── Message Record          │  │
│  │   └── Message Record          │  │
│  └───────────────────────────────┘  │
│  Chunk Index → 指向上面的 Chunk     │  ← 快速定位
├─────────────────────────────────────┤
│  ┌───────────────────────────────┐  │
│  │   Chunk (下一时间段)           │  │
│  │   └── ...                     │  │
│  └───────────────────────────────┘  │
│  Chunk Index                        │
├─────────────────────────────────────┤
│      Statistics Record              │  ← 全局统计信息
│      Summary Section                │  ← 所有 Chunk Index 的汇总
│      Footer                         │
└─────────────────────────────────────┘
```

关键设计：
- **Chunk**：消息按时间段分组压缩，单个 Chunk 损坏不影响其他数据
- **Chunk Index**：紧跟每个 Chunk 后面，包含时间范围和偏移量，支持 O(1) 时间定位
- **Schema 嵌入**：消息的完整定义（`.msg` 文件内容）直接存储在文件中——拿到 `.mcap` 文件就能解析，无需安装对应的 ROS 包

### 12.5 用 Python 直接读取 MCAP

MCAP 的一个重要优势是不依赖 ROS2 环境即可读取——用纯 Python 就能解析：

```python
# pip install mcap mcap-ros2-support
from mcap_ros2.reader import read_ros2_messages

for msg in read_ros2_messages("/data/flight_test_001/flight_test_001_0.mcap"):
    if msg.channel.topic == "/imu":
        imu = msg.ros_msg
        print(f"t={msg.log_time_ns/1e9:.3f} "
              f"acc=({imu.linear_acceleration.x:.2f}, "
              f"{imu.linear_acceleration.y:.2f}, "
              f"{imu.linear_acceleration.z:.2f})")
```

也可以用 **Foxglove Studio**（开源桌面应用）直接打开 `.mcap` 文件进行可视化分析——支持时间序列图、3D 视图、图像回放等，无需启动 ROS2 环境。

### 12.6 SQLite3 → MCAP 转换

```bash
# 将已有的 db3 格式 bag 转换为 mcap
ros2 bag convert -i /old_bag -o /new_bag \
    --output-options "{uri: /new_bag, storage_id: mcap}"
```

### 12.7 选择建议

| 场景 | 推荐格式 |
|------|---------|
| Humble 日常开发/调试 | MCAP（安装插件后默认使用） |
| 需要 SQL 查询 bag 内容 | SQLite3 |
| 长时间飞行记录（>1GB） | MCAP（压缩 + 分片 + 损坏恢复） |
| 跨团队共享数据 | MCAP（自描述，无需 ROS 环境即可打开） |
| 与 Foxglove Studio 集成 | MCAP（原生支持） |

---

## 十三、ROS2 CLI 工具速查

### 13.1 核心命令

```bash
# ===== 节点 =====
ros2 node list                    # 列出所有活跃节点
ros2 node info /drone_controller  # 查看节点详细信息

# ===== 主题 =====
ros2 topic list                   # 列出所有主题
ros2 topic info /imu --verbose    # 查看主题详情（含 QoS）
ros2 topic echo /imu              # 监听主题数据
ros2 topic hz /imu                # 查看发布频率
ros2 topic bw /camera/image       # 查看带宽占用
ros2 topic pub /cmd_vel geometry_msgs/msg/Twist \
    "{linear: {x: 1.0}, angular: {z: 0.5}}"  # 发布消息

# ===== 服务 =====
ros2 service list                 # 列出所有服务
ros2 service call /add_two_ints example_interfaces/srv/AddTwoInts \
    "{a: 1, b: 2}"               # 调用服务

# ===== 参数 =====
ros2 param list /drone_controller # 列出节点参数
ros2 param get /drone_controller control_rate   # 获取参数值
ros2 param set /drone_controller control_rate 200.0  # 设置参数

# ===== 动作 =====
ros2 action list                  # 列出所有动作服务器
ros2 action send_goal /navigate NavigateToPose \
    "{pose: {position: {x: 1.0, y: 2.0}}}"

# ===== 包管理 =====
ros2 pkg list                     # 列出所有已安装的包
ros2 pkg create my_pkg --build-type ament_cmake --dependencies rclcpp

# ===== 生命周期 =====
ros2 lifecycle list /drone_driver
ros2 lifecycle get /drone_driver
ros2 lifecycle set /drone_driver activate

# ===== 组件 =====
ros2 component list /ComponentManager
ros2 component load /ComponentManager my_pkg my_pkg::MyNode

# ===== 系统诊断 =====
ros2 doctor                       # 系统健康检查
ros2 wtf                          # 同上（别名）
```

### 13.2 调试技巧

```bash
# 查看计算图（需要 rqt_graph）
ros2 run rqt_graph rqt_graph

# 查看 TF 树
ros2 run tf2_tools view_frames

# 实时日志级别调整
ros2 service call /drone_controller/set_logger_level \
    rcl_interfaces/srv/SetLoggerLevel \
    "{logger_name: 'drone_controller', level: 10}"  # 10=DEBUG
```

---

## 十四、安全机制：SROS2

ROS1 没有任何安全机制——任何人都可以连接到 rosmaster 并发布控制指令。ROS2 通过 SROS2 提供了完整的安全框架。

### 14.1 安全架构

SROS2 基于 DDS-Security 标准，提供三层保护：

| 层级 | 能力 | 实现方式 |
|------|------|---------|
| **认证** | 验证节点身份 | X.509 证书 |
| **加密** | 保护通信内容 | AES-GCM-256 |
| **访问控制** | 限制节点权限 | 权限 XML 文件 |

### 14.2 快速启用

```bash
# 创建安全密钥库
ros2 security create_keystore ~/sros2_keystore

# 为节点生成证书
ros2 security create_enclave ~/sros2_keystore /drone_controller

# 启用安全模式
export ROS_SECURITY_KEYSTORE=~/sros2_keystore
export ROS_SECURITY_ENABLE=true
export ROS_SECURITY_STRATEGY=Enforce  # Enforce 或 Permissive

# 运行节点（自动使用安全配置）
ros2 run drone_controller controller_node \
    --ros-args --enclave /drone_controller
```

---

## 十五、性能优化实践

### 15.1 DDS 调优

```bash
# 使用 Cyclone DDS（本地低延迟）
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp

# 限制 DDS 发现范围（减少广播流量）
export ROS_LOCALHOST_ONLY=1

# 使用 Domain ID 隔离不同机器人
export ROS_DOMAIN_ID=42
```

### 15.2 减少序列化开销

```cpp
// 使用 TypeAdapted 消息避免不必要的类型转换
// 例如：直接使用 cv::Mat 而非 sensor_msgs::msg::Image
RCLCPP_COMPONENTS_REGISTER_NODE(my_node)

// 开启共享内存传输（Fast DDS）
// 在 Fast DDS XML Profile 中配置 SHM Transport
```

### 15.3 Executor 选择指南

| 场景 | 推荐 Executor | 原因 |
|------|--------------|------|
| 简单节点、低频回调 | `SingleThreadedExecutor` | 开销最小，无锁竞争 |
| 多订阅、计算密集 | `MultiThreadedExecutor` | 并行处理回调 |
| 拓扑固定、性能敏感 | `StaticSingleThreadedExecutor` | 避免重复扫描开销 |
| 硬实时控制 | 自定义 `WaitSet` | 绕过 Executor 的非确定性 |
| 多节点隔离 | 每节点独立 Executor + 线程 | 避免相互干扰 |

---

## 十六、总结与展望

### 16.1 ROS2 Humble 的核心价值

1. **DDS 标准化通信**：去中心化、QoS 可配、安全加密，满足生产环境需求
2. **灵活的执行模型**：Executor + Callback Group 提供可控的并发策略
3. **Lifecycle 管理**：确定性的启动/停止流程，适合复杂系统编排
4. **统一的组件化**：同一份代码既能独立运行也能进程内零拷贝共享
5. **声明式部署**：Launch 系统支持 Python/XML/YAML，参数化和条件启动

### 16.2 未来演进

- **Jazzy Jalisco（2024 LTS，支持至 2029）**：改进的类型适配、更好的 ROS 1 桥接
- **Kilted（2025 滚动发布）**：EventsExecutor 进入稳定版，更低的调度延迟
- **Executor 改革**：社区持续探索确定性调度方案（如 `rclc_executor`、`ros2_executor` 提案）
- **Rust 客户端库（rclrs）**：内存安全的 ROS2 客户端库逐步成熟

---

## 十七、参考资源

1. **ROS2 Humble 官方文档**: [docs.ros.org/en/humble](https://docs.ros.org/en/humble/)
2. **ROS2 设计文档**: [design.ros2.org](https://design.ros2.org/)
3. **Executor 概念文档**: [About Executors](https://docs.ros.org/en/humble/Concepts/Intermediate/About-Executors.html)
4. **QoS 策略文档**: [About QoS Settings](https://docs.ros.org/en/humble/Concepts/Intermediate/About-Quality-of-Service-Settings.html)
5. **Lifecycle Node 教程**: [Managed Nodes](https://docs.ros.org/en/humble/p/lifecycle/)
6. **组件化文档**: [About Composition](https://docs.ros.org/en/humble/Concepts/Intermediate/About-Composition.html)
7. **零拷贝通信 Demo**: [Intra-Process Communication](https://docs.ros.org/en/humble/Tutorials/Demos/Intra-Process-Communication.html)
8. **Fast DDS 配置**: [FastDDS in ROS2](https://fast-dds.docs.eprosima.com/en/latest/fastdds/ros2/ros2_configure.html)
9. **rmw_fastrtps 仓库**: [github.com/ros2/rmw_fastrtps](https://github.com/ros2/rmw_fastrtps)
10. **rclcpp 源码**: [github.com/ros2/rclcpp](https://github.com/ros2/rclcpp)
11. **Casini et al. ECRTS 2019**: Response-Time Analysis of ROS 2 Processing Chains Under Reservation-Based Scheduling
12. **ROS2 安全 (SROS2)**: [docs.ros.org/en/humble/Concepts/Intermediate/About-Security.html](https://docs.ros.org/en/humble/Concepts/Intermediate/About-Security.html)
13. **MCAP 格式规范**: [mcap.dev](https://mcap.dev/)
14. **rosbag2 存储插件**: [github.com/ros2/rosbag2](https://github.com/ros2/rosbag2)
15. **Foxglove Studio**: [foxglove.dev](https://foxglove.dev/)
16. **mcap Python 库**: [github.com/foxglove/mcap](https://github.com/foxglove/mcap)
