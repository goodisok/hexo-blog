---
title: AirSim/Colosseum 四旋翼动力学建模源码深度解析：从 C++ 源码到自定义无人机建模
date: 2026-03-25 14:30:00
categories:
  - 无人机
  - 仿真开发
tags:
  - AirSim
  - Colosseum
  - 四旋翼
  - 飞行动力学
  - 源码分析
  - Sim-to-Real
  - 参数辨识
  - 系统辨识
  - FastPhysicsEngine
  - RotorActuator
  - PX4
  - 仿真验证
mathjax: true
---

> AirSim/Colosseum 的四旋翼仿真不是黑盒。本文基于 Colosseum 仓库 [1] 的 C++ 源码逐文件解析，**明确哪些参数硬编码在 C++ 中、哪些可以通过 `settings.json` 配置、哪些需要修改源码才能改变**，手把手讲解如何为自己的无人机建立仿真模型。

**前置阅读**：本文建立在以下两篇文章的基础上，建议先阅读：
- [无人机建模中的线性代数：从坐标变换到姿态控制的数学基础](/2026/04/21/无人机建模中的线性代数-从坐标变换到姿态控制的数学基础/)——旋转矩阵、四元数、特征值等数学工具
- [无人机飞行物理学：从牛顿力学到六自由度运动方程的完整推导](/2026/04/21/无人机飞行物理学-从牛顿力学到六自由度运动方程的完整推导/)——牛顿-欧拉方程、螺旋桨空气动力学、六自由度 ODE

---

## 一、AirSim 与 Colosseum：项目背景

AirSim 由微软研究院开发，2017 年开源 [8]。2022 年微软停止维护后，社区 fork 出 **Colosseum** [1] 继续开发，当前主分支支持 Unreal Engine 5.6。两者核心物理引擎代码一致，本文基于 Colosseum `main` 分支源码分析，同时适用于原版 AirSim。

**核心设计哲学**：AirSim 将物理仿真（AirLib）与渲染引擎（Unreal Engine）**完全解耦**。AirLib 是一个纯 C++ 头文件库（header-only），不依赖任何游戏引擎 API，可以独立编译运行。物理仿真在 `FastPhysicsEngine` 中完成后，将位姿结果同步给 Unreal 用于渲染和碰撞检测。

---

## 二、源码架构与目录结构

### 2.1 核心目录结构

以下目录结构来自 Colosseum 仓库 [1] 的 `main` 分支：

```
Colosseum/AirLib/
├── include/
│   ├── common/
│   │   ├── Common.hpp                    # 基础类型（real_T, Vector3r, Quaternionr）
│   │   ├── AirSimSettings.hpp            # settings.json 解析（重要！决定可配置项）
│   │   ├── Settings.hpp                  # JSON 解析封装（nlohmann::json）
│   │   ├── CommonStructs.hpp             # Wrench, Kinematics, CollisionInfo 等
│   │   ├── FirstOrderFilter.hpp          # 一阶低通滤波器
│   │   └── SteppableClock.hpp            # 仿真时钟
│   ├── physics/
│   │   ├── PhysicsBody.hpp               # 刚体基类（质量、惯性张量、碰撞）
│   │   ├── PhysicsBodyVertex.hpp         # 力作用点基类
│   │   ├── PhysicsEngineBase.hpp         # 物理引擎接口
│   │   ├── FastPhysicsEngine.hpp         # ★ 内置物理引擎（核心！）
│   │   ├── Kinematics.hpp                # 运动学状态容器
│   │   └── Environment.hpp               # 环境模型（重力/气压/磁场）
│   └── vehicles/multirotor/
│       ├── MultiRotorPhysicsBody.hpp     # ★ 多旋翼刚体
│       ├── MultiRotorParams.hpp          # ★ 参数定义 + 机型预设（硬编码）
│       ├── MultiRotorParamsFactory.hpp   # 根据 VehicleType 创建对应参数
│       ├── RotorActuator.hpp             # ★ 单个电机+桨执行器
│       ├── RotorParams.hpp               # ★ 螺旋桨/电机参数结构体（硬编码默认值）
│       └── firmwares/
│           ├── simple_flight/
│           │   └── SimpleFlightQuadXParams.hpp  # SimpleFlight 的 QuadX 参数
│           └── mavlink/
│               └── Px4MultiRotorParams.hpp      # PX4 的机型参数选择
```

多旋翼物理体的实现类是 **`MultiRotorPhysicsBody`**，定义在 `MultiRotorPhysicsBody.hpp` 中。

### 2.2 核心类关系

```
PhysicsBody                           # 刚体基类：质量、惯性、碰撞
  └── MultiRotorPhysicsBody           # 多旋翼物理体
        ├── has: RotorActuator[N]         # N 个电机执行器（作为 WrenchVertex）
        ├── has: PhysicsBodyVertex[6]     # 6 个阻力面（作为 DragVertex）
        ├── ref: MultiRotorParams*        # 参数引用
        └── ref: VehicleApiBase*          # 飞控 API

PhysicsBodyVertex                     # 力作用点基类
  └── RotorActuator                   # 电机+桨：接收控制信号，输出推力/扭矩

PhysicsEngineBase                     # 物理引擎接口
  └── FastPhysicsEngine               # ★ AirSim 自研引擎
        ├── getBodyWrench()               # 汇总所有 WrenchVertex 的力/力矩
        ├── getDragWrench()               # 汇总所有 DragVertex 的阻力
        └── getNextKinematicsNoCollision() # Velocity Verlet 积分

MultiRotorParams                      # 参数抽象基类
  ├── SimpleFlightQuadXParams          # SimpleFlight 默认参数（setupFrameGenericQuad）
  ├── Px4MultiRotorParams              # PX4 支持多机型选择
  └── ArduCopterParams                 # ArduCopter 参数
```

---

## 三、RotorParams：螺旋桨参数定义

### 3.1 源码原文（`RotorParams.hpp`）

`RotorParams` 结构体定义了螺旋桨和电机的所有参数，代码来自 `AirLib/include/vehicles/multirotor/RotorParams.hpp` [1]：

```cpp
// 文件: AirLib/include/vehicles/multirotor/RotorParams.hpp
struct RotorParams
{
    /*
    Ref: http://physics.stackexchange.com/a/32013/14061
    force in Newton = C_T * rho * n^2 * D^4
    torque in N.m = C_P * rho * n^2 * D^5 / (2*pi)
    
    We use values for GWS 9X5 propeller for which,
    C_T = 0.109919, C_P = 0.040164 @ 6396.667 RPM
    */
    real_T C_T = 0.109919f;              // 推力系数（UIUC 实测，GWS 9x5 桨）
    real_T C_P = 0.040164f;              // 功率系数（注意：不是 C_Q！）
    real_T air_density = 1.225f;         // 海平面空气密度 (kg/m³)
    real_T max_rpm = 6396.667f;          // 最大转速 (RPM)
    real_T propeller_diameter = 0.2286f; // 桨径 (m)，默认为 DJI Phantom 2 的桨
    real_T propeller_height = 1/100.0f;  // 桨旋转圆柱高度 (m)，用于阻力面积计算
    real_T control_signal_filter_tc = 0.005f; // ★ 控制信号低通滤波时间常数 (s)

    real_T revolutions_per_second;       // 由 calculateMaxThrust() 计算
    real_T max_speed;                    // 最大角速度 (rad/s)
    real_T max_speed_square;             // max_speed²
    real_T max_thrust = 4.179446268f;    // 最大推力 (N)，由公式计算
    real_T max_torque = 0.055562f;       // 最大扭矩 (N·m)，由公式计算

    void calculateMaxThrust()
    {
        revolutions_per_second = max_rpm / 60;
        max_speed = revolutions_per_second * 2 * M_PIf;
        max_speed_square = pow(max_speed, 2.0f);

        real_T nsquared = revolutions_per_second * revolutions_per_second;
        max_thrust = C_T * air_density * nsquared 
                   * static_cast<real_T>(pow(propeller_diameter, 4));
        max_torque = C_P * air_density * nsquared 
                   * static_cast<real_T>(pow(propeller_diameter, 5)) / (2 * M_PIf);
    }
};
```

### 3.2 关键公式与参数含义

最大推力和最大扭矩的计算公式（代码中 `calculateMaxThrust()`）：

$$
T_{\max} = C_T \cdot \rho \cdot n_{\max}^2 \cdot D^4
$$

$$
Q_{\max} = \frac{C_P \cdot \rho \cdot n_{\max}^2 \cdot D^5}{2\pi}
$$

其中 $n_{\max} = \text{max\_rpm} / 60$ 为最大每秒转数。

**注意源码中的命名**：代码中使用的是 **$C_P$（功率系数）而不是 $C_Q$（扭矩系数）**。两者关系为 $Q = P/(2\pi n)$，所以扭矩公式中出现了 $1/(2\pi)$ 因子。用默认参数代入验证：

$$
T_{\max} = 0.109919 \times 1.225 \times 106.611^2 \times 0.2286^4 \approx 4.179 \text{ N}
$$

与代码中 `max_thrust = 4.179446268f` 吻合。

### 3.3 所有默认值汇总表

| 参数 | 默认值 | 物理含义 | 是否可通过 settings.json 修改 |
|------|--------|---------|:---:|
| `C_T` | 0.109919 | 推力系数（GWS 9x5 桨 @ 6396.667 RPM） | **否** |
| `C_P` | 0.040164 | 功率系数 | **否** |
| `air_density` | 1.225 kg/m³ | 海平面空气密度 | **否** |
| `max_rpm` | 6396.667 | 最大转速 | **否** |
| `propeller_diameter` | 0.2286 m (9 英寸) | 桨直径 | **否** |
| `propeller_height` | 0.01 m | 桨旋转圆柱高度 | **否** |
| `control_signal_filter_tc` | 0.005 s | 控制信号滤波时间常数 | **否** |
| `max_thrust` | 4.179 N | 计算得出的最大推力 | **否** |
| `max_torque` | 0.05556 N·m | 计算得出的最大扭矩 | **否** |

> **注意**：`settings.json` 的 `VehicleSetting` 解析代码中**不存在对这些物理参数的读取逻辑**。要修改这些值，必须修改 C++ 源码并重新编译。

---

## 四、RotorActuator：电机执行器实现

### 4.1 执行器架构

每个 `RotorActuator` 继承自 `PhysicsBodyVertex`，是一个**力作用点**。它接收 0~1 的控制信号，经过低通滤波后，按比例输出推力和扭矩。源码核心逻辑（`RotorActuator.hpp`）[1]：

```cpp
// 文件: AirLib/include/vehicles/multirotor/RotorActuator.hpp

struct Output {
    real_T thrust;                   // 推力 (N)
    real_T torque_scaler;            // 反扭矩 (N·m)，含旋向符号
    real_T speed;                    // 当前转速 (rad/s)
    RotorTurningDirection turning_direction;
    real_T control_signal_filtered;  // 滤波后的控制信号 [0,1]
    real_T control_signal_input;     // 原始控制信号 [0,1]
};
```

### 4.2 推力/扭矩计算公式

源码中 `setOutput()` 的实现：

```cpp
static void setOutput(Output& output, const RotorParams& params, 
    const FirstOrderFilter<real_T>& control_signal_filter,
    RotorTurningDirection turning_direction)
{
    output.control_signal_input = control_signal_filter.getInput();
    output.control_signal_filtered = control_signal_filter.getOutput();
    
    // ★ 转速 = sqrt(滤波后控制信号 × 最大转速²)
    output.speed = sqrt(output.control_signal_filtered * params.max_speed_square);
    
    // ★ 推力 = 滤波后控制信号 × 最大推力
    output.thrust = output.control_signal_filtered * params.max_thrust;
    
    // ★ 扭矩 = 滤波后控制信号 × 最大扭矩 × 旋向(±1)
    output.torque_scaler = output.control_signal_filtered * params.max_torque 
                         * static_cast<real_T>(turning_direction);
    
    output.turning_direction = turning_direction;
}
```

**关键认识**：AirSim 的推力模型**不是**直接用 $T = C_T \rho n^2 D^4$ 在每步计算。而是：

1. 先在初始化时用 `calculateMaxThrust()` 预算出 $T_{\max}$
2. 运行时将控制信号 $u \in [0,1]$ 经过一阶低通滤波得到 $u_f$
3. 推力 = $u_f \times T_{\max}$

这意味着**推力与控制信号成正比**，而转速的计算是 $\omega = \sqrt{u_f} \times \omega_{\max}$，保证了 $T = k_T \omega^2$ 的物理一致性：

$$
T = u_f \cdot T_{\max} = u_f \cdot k_T \omega_{\max}^2 = k_T \cdot (u_f \omega_{\max}^2) = k_T \cdot (\sqrt{u_f}\omega_{\max})^2 = k_T \omega^2
$$

### 4.3 控制信号滤波（电机动态模型）

AirSim 使用 `FirstOrderFilter` 实现统一的一阶低通滤波器，时间常数为 `control_signal_filter_tc`（默认 0.005 s）：

$$
u_f(t) = u_f(t-\Delta t) + \frac{\Delta t}{\tau_c + \Delta t}\big(u(t) - u_f(t-\Delta t)\big)
$$

其中 $\tau_c = 0.005$ s。这意味着控制信号的带宽约为 $f_c = 1/(2\pi\tau_c) \approx 31.8$ Hz。

**物理意义**：该滤波模拟了电机+ESC 系统的响应延迟。$\tau_c = 0.005$ s 意味着约 5 ms 的响应时间（达到 63.2% 目标值），这对应高品质无刷电机的典型响应速度。

### 4.4 力/力矩到物理引擎的传递

`RotorActuator::setWrench()` 将计算出的推力和扭矩转化为 `Wrench`（力-力矩对），并乘以**空气密度比**：

```cpp
virtual void setWrench(Wrench& wrench) override
{
    Vector3r normal = getNormal();
    // 力和扭矩与空气密度成正比
    wrench.force = normal * output_.thrust * air_density_ratio_;
    wrench.torque = normal * output_.torque_scaler * air_density_ratio_;
}
```

其中 `air_density_ratio_ = ρ(h) / ρ_0`，`ρ_0 = 1.225` kg/m³。**这意味着高海拔时推力自动减小**——不需要额外配置，环境模型（`Environment`）会根据海拔自动更新空气密度。

---

## 五、MultiRotorPhysicsBody：多旋翼物理体

### 5.1 初始化流程

`MultiRotorPhysicsBody` 的构造函数展示了多旋翼物理模型的完整组装过程：

```cpp
// 文件: AirLib/include/vehicles/multirotor/MultiRotorPhysicsBody.hpp

void initialize(Kinematics* kinematics, Environment* environment)
{
    // 1. 用硬编码的 mass 和 inertia 初始化刚体基类
    PhysicsBody::initialize(params_->getParams().mass, 
                            params_->getParams().inertia, 
                            kinematics, environment);
    
    // 2. 根据 rotor_poses 创建 N 个 RotorActuator
    createRotors(*params_, rotors_, environment);
    
    // 3. 创建 6 个阻力面（六面体模型）
    createDragVertices();
    
    // 4. 初始化传感器
    initSensors(*params_, getKinematics(), getEnvironment());
}
```

### 5.2 WrenchVertex（力作用点）：旋翼

每个 `RotorActuator` 作为一个 `WrenchVertex`，提供各自位置上的推力和扭矩。`FastPhysicsEngine` 通过以下接口获取：

```cpp
// MultiRotorPhysicsBody 向物理引擎暴露的接口
virtual uint wrenchVertexCount() const override {
    return params_->getParams().rotor_count;    // 例如 4
}
virtual PhysicsBodyVertex& getWrenchVertex(uint index) override {
    return rotors_.at(index);                   // 返回第 i 个 RotorActuator
}
```

### 5.3 DragVertex（阻力面）：六面体气动阻力模型

AirSim 采用基于物理的**六面体面阻力模型**，而不是简单的线性阻力 $F_d = -k_d v$：

```cpp
void createDragVertices()
{
    const auto& params = params_->getParams();

    // 桨面积和桨截面积
    real_T propeller_area = M_PIf * params.rotor_params.propeller_diameter 
                          * params.rotor_params.propeller_diameter;
    real_T propeller_xsection = M_PIf * params.rotor_params.propeller_diameter 
                              * params.rotor_params.propeller_height;

    // 机体盒子各方向的迎风面积
    real_T top_bottom_area = params.body_box.x() * params.body_box.y();
    real_T left_right_area = params.body_box.x() * params.body_box.z();
    real_T front_back_area = params.body_box.y() * params.body_box.z();
    
    // 阻力因子 = (面积 + 桨的遮挡面积) × 阻力系数 / 2
    Vector3r drag_factor_unit = Vector3r(
        front_back_area + rotors_.size() * propeller_xsection,     // x 方向
        left_right_area + rotors_.size() * propeller_xsection,     // y 方向
        top_bottom_area + rotors_.size() * propeller_area           // z 方向
    ) * params.linear_drag_coefficient / 2;

    // 创建 6 个阻力面（上下前后左右）
    drag_faces_.clear();
    drag_faces_.emplace_back(Vector3r(0,0,-params.body_box.z()/2), 
                             Vector3r(0,0,-1), drag_factor_unit.z());  // 顶面
    drag_faces_.emplace_back(Vector3r(0,0, params.body_box.z()/2), 
                             Vector3r(0,0, 1), drag_factor_unit.z());  // 底面
    // ... 左、右、前、后 共 6 个面
}
```

**阻力公式**（在 `FastPhysicsEngine::getDragWrench()` 中）：

$$
\mathbf{F}_{\text{drag},i} = -\hat{n}_i \cdot k_{\text{drag},i} \cdot \rho \cdot (v_{n,i})^2
$$

其中 $v_{n,i} = \hat{n}_i \cdot \mathbf{v}_{\text{body}}$ 是该面法向的速度分量，$k_{\text{drag},i}$ 是该面的阻力因子。只有当 $v_{n,i} > 0$（气流吹向该面）时才产生阻力——这实现了**背风面剔除**（face culling）。

**关键区别**：这比简单的 $F_d = -k_d v$ 模型更物理——阻力与**速度平方**成正比（符合高 Reynolds 数下的实际情况），且各方向阻力不同（侧面面积 ≠ 顶面面积）。

---

## 六、FastPhysicsEngine：物理引擎核心

### 6.1 主循环入口

`FastPhysicsEngine::updatePhysics()` 是每个仿真步的入口：

```cpp
void updatePhysics(PhysicsBody& body)
{
    TTimeDelta dt = clock()->updateSince(body.last_kinematics_time);
    body.lock();
    
    const Kinematics::State& current = body.getKinematics();
    Kinematics::State next;
    Wrench next_wrench;

    // 1. 无碰撞情况下的运动学更新
    getNextKinematicsNoCollision(dt, body, current, next, next_wrench, wind_, ext_force_);

    // 2. 碰撞检测与响应
    const CollisionInfo collision_info = body.getCollisionInfo();
    if (body.isGrounded() || collision_info.has_collided) {
        getNextKinematicsOnCollision(dt, collision_info, body, current, 
                                      next, next_wrench, enable_ground_lock_);
    }

    body.setWrench(next_wrench);
    body.updateKinematics(next);
    body.unlock();
}
```

### 6.2 力/力矩汇总流程

`getNextKinematicsNoCollision()` 中，力的汇总分为三部分：

```cpp
static void getNextKinematicsNoCollision(TTimeDelta dt, PhysicsBody& body, 
    const Kinematics::State& current, Kinematics::State& next, 
    Wrench& next_wrench, const Vector3r& wind, const Vector3r& ext_force)
{
    const real_T dt_real = static_cast<real_T>(dt);

    // 用半步速度估计（用于阻力计算）
    Vector3r avg_linear = current.twist.linear 
                        + current.accelerations.linear * (0.5f * dt_real);
    Vector3r avg_angular = current.twist.angular 
                         + current.accelerations.angular * (0.5f * dt_real);

    // ===== 第一部分：机体力（旋翼推力+反扭矩） =====
    const Wrench body_wrench = getBodyWrench(body, current.pose.orientation);

    // ===== 第二部分：气动阻力 =====
    const Wrench drag_wrench = getDragWrench(body, current.pose.orientation,
                                              avg_linear, avg_angular, wind);

    // ===== 第三部分：外力（API 设定的风力等） =====
    Wrench ext_force_wrench = Wrench::zero();
    ext_force_wrench.force = ext_force;

    // 合力合力矩
    next_wrench = body_wrench + drag_wrench + ext_force_wrench;
    // ...
}
```

`getBodyWrench()` 遍历所有 `WrenchVertex`（即 `RotorActuator`），汇总力和力矩：

```cpp
static Wrench getBodyWrench(const PhysicsBody& body, const Quaternionr& orientation)
{
    Wrench wrench = Wrench::zero();
    
    for (uint i = 0; i < body.wrenchVertexCount(); ++i) {
        const PhysicsBodyVertex& vertex = body.getWrenchVertex(i);
        const auto& vertex_wrench = vertex.getWrench();
        
        // 汇总力和扭矩
        wrench += vertex_wrench;
        
        // ★ 力臂产生的额外力矩：τ = r × F
        wrench.torque += vertex.getPosition().cross(vertex_wrench.force);
    }
    
    // 力从机体系转换到世界系，力矩保持在机体系
    wrench.force = VectorMath::transformToWorldFrame(wrench.force, orientation);
    
    return wrench;
}
```

**对照物理学文章**：这里的 `vertex.getPosition().cross(vertex_wrench.force)` 就是《线性代数》文章中叉积的工程应用——力臂 $\mathbf{r}$ 叉乘推力 $\mathbf{F}$ 得到力矩 $\boldsymbol{\tau} = \mathbf{r} \times \mathbf{F}$。

### 6.3 平动方程与加速度计算

```cpp
// 平动加速度 = 合力/质量 + 重力
next.accelerations.linear = (next_wrench.force / body.getMass()) 
                          + body.getEnvironment().getState().gravity;
```

**注意**：重力是在**世界系**中直接加到加速度上的（NED 系中 $\mathbf{g} = [0, 0, +9.81]^T$），而 `body_wrench.force` 已经在 `getBodyWrench()` 中被转换到了世界系。

### 6.4 转动方程（欧拉方程）

```cpp
// 角动量
const Vector3r angular_momentum = body.getInertia() * avg_angular;

// 角动量变化率 = 外力矩 - 陀螺效应项
// ★ 欧拉方程: I·ω̇ = τ - ω × (I·ω)
const Vector3r angular_momentum_rate = next_wrench.torque 
                                     - avg_angular.cross(angular_momentum);

// 角加速度
next.accelerations.angular = body.getInertiaInv() * angular_momentum_rate;
```

这正是《无人机飞行物理学》第四章推导的**欧拉旋转方程**在源码中的实现。

### 6.5 Velocity Verlet 积分

AirSim 使用 **Velocity Verlet 积分**（也叫 Störmer-Verlet），而非简单的一阶欧拉积分：

```cpp
// ★ Velocity Verlet: v(t+dt) = v(t) + 0.5*(a(t) + a(t+dt))*dt
next.twist.linear = current.twist.linear 
    + (current.accelerations.linear + next.accelerations.linear) * (0.5f * dt_real);

next.twist.angular = current.twist.angular 
    + (current.accelerations.angular + next.accelerations.angular) * (0.5f * dt_real);
```

源码注释明确引用了 [Verlet integration](http://www.physics.udel.edu/~bnikolic/teaching/phys660/numerical_ode/node5.html)。Velocity Verlet 是**二阶精度**的辛积分器（symplectic integrator），能量守恒性优于简单欧拉法，而计算量仅为 RK4 的一半。

### 6.6 姿态更新（四元数积分）

```cpp
static void computeNextPose(TTimeDelta dt, const Pose& current_pose, 
    const Vector3r& avg_linear, const Vector3r& avg_angular, Kinematics::State& next)
{
    real_T dt_real = static_cast<real_T>(dt);
    
    // 位置更新
    next.pose.position = current_pose.position + avg_linear * dt_real;

    // 角速度到四元数增量
    real_T angle_per_unit = avg_angular.norm();
    if (Utils::isDefinitelyGreaterThan(angle_per_unit, 0.0f)) {
        // ★ 使用轴角表示，而非小角度近似
        AngleAxisr angle_dt_aa = AngleAxisr(angle_per_unit * dt_real, 
                                             avg_angular / angle_per_unit);
        Quaternionr angle_dt_q = Quaternionr(angle_dt_aa);
        
        // 新姿态 = 当前姿态 × 增量四元数
        // 证明: 如果 q0 是当前姿态, q1 是机体系中的旋转增量
        // 则新姿态 = q0 * q1
        next.pose.orientation = current_pose.orientation * angle_dt_q;
        next.pose.orientation.normalize();  // 归一化防止漂移
    }
    else
        next.pose.orientation = current_pose.orientation;
}
```

这里使用的是**精确的轴角表示**（`AngleAxisr`），而不是常见的小角度近似 $\Delta q \approx [1, \frac{\omega_x \Delta t}{2}, \frac{\omega_y \Delta t}{2}, \frac{\omega_z \Delta t}{2}]$。轴角转四元数的公式为：

$$
\Delta\mathbf{q} = \left[\cos\frac{\theta}{2},\ \hat{\mathbf{e}}\sin\frac{\theta}{2}\right]
$$

其中 $\theta = \|\boldsymbol{\omega}\|\Delta t$，$\hat{\mathbf{e}} = \boldsymbol{\omega}/\|\boldsymbol{\omega}\|$。这保证了四元数的单位性，精度优于小角度线性化。

### 6.7 速度安全裁剪

源码中有一个有趣的安全措施——速度不能超过光速：

```cpp
if (next.twist.linear.squaredNorm() > EarthUtils::SpeedOfLight * EarthUtils::SpeedOfLight) {
    next.twist.linear /= (next.twist.linear.norm() / EarthUtils::SpeedOfLight);
    next.accelerations.linear = Vector3r::Zero();
}
```

这不是物理精度的需要，而是防止控制器 bug 导致数值爆炸的安全机制。

### 6.8 完整仿真循环总结

```
┌──────────────────────────────────────────────────────────────┐
│                FastPhysicsEngine 每步执行流程                  │
│                                                               │
│  1. body.update()                                             │
│     └── 每个 RotorActuator.update()                           │
│         ├── 更新空气密度比                                      │
│         ├── 低通滤波控制信号: u_f = filter(u)                   │
│         ├── 计算推力: T = u_f × T_max × ρ_ratio               │
│         ├── 计算扭矩: Q = u_f × Q_max × direction × ρ_ratio   │
│         └── 计算转速: ω = sqrt(u_f) × ω_max                   │
│                                                               │
│  2. getBodyWrench()                                           │
│     ├── 遍历 4 个 RotorActuator 汇总 force + torque            │
│     ├── 力臂力矩: τ_i = r_i × F_i                             │
│     └── 力转换到世界系: F_world = R × F_body                   │
│                                                               │
│  3. getDragWrench()                                           │
│     ├── 遍历 6 个面，计算相对来流（考虑风速）                     │
│     ├── 面法向速度分量（背风面剔除）                             │
│     └── 阻力 ∝ v² × 面积 × ρ                                  │
│                                                               │
│  4. 合力合力矩 = body_wrench + drag_wrench + ext_force         │
│                                                               │
│  5. 平动: a = F/m + g                                         │
│  6. 转动: α = I⁻¹(τ - ω×Iω)     ← 欧拉方程                   │
│  7. Velocity Verlet 积分速度                                   │
│  8. 轴角法更新四元数姿态                                        │
│  9. 碰撞检测与响应                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## 七、MultiRotorParams：机体参数定义与预设

### 7.1 参数结构体

`MultiRotorParams::Params` 定义了多旋翼的**所有**物理参数：

```cpp
// 文件: AirLib/include/vehicles/multirotor/MultiRotorParams.hpp
struct Params {
    /*********** required parameters ***********/
    uint rotor_count;                    // 旋翼数量
    vector<RotorPose> rotor_poses;       // 每个旋翼的位置+法线+旋向
    real_T mass;                         // 总质量 (kg)
    Matrix3x3r inertia;                  // 惯性张量 (kg·m²)
    Vector3r body_box;                   // 机体盒子尺寸 (m)，用于阻力计算

    /*********** optional parameters with defaults ***********/
    real_T linear_drag_coefficient = 1.3f / 4.0f;  // 线性阻力系数
    real_T angular_drag_coefficient = linear_drag_coefficient;
    real_T restitution = 0.55f;          // 碰撞恢复系数（1=完全弹性）
    real_T friction = 0.5f;              // 碰撞摩擦系数
    RotorParams rotor_params;            // 旋翼参数（见第三章）
};
```

### 7.2 GenericQuad 默认值（SimpleFlight 使用的机型）

当你使用 `"VehicleType": "SimpleFlight"` 时，参数由 `SimpleFlightQuadXParams::setupParams()` 设定，它调用 `setupFrameGenericQuad()`：

```cpp
void setupFrameGenericQuad(Params& params)
{
    // 旋翼数量
    params.rotor_count = 4;
    
    // 臂长：F450 机架，0.2275 m
    std::vector<real_T> arm_lengths(params.rotor_count, 0.2275f);

    // ★ 质量：硬编码 1.0 kg
    params.mass = 1.0f;

    // 电机组件重量：MT2212 电机，0.055 kg
    real_T motor_assembly_weight = 0.055f;
    real_T box_mass = params.mass - params.rotor_count * motor_assembly_weight;

    // 使用 RotorParams 默认值
    params.rotor_params.calculateMaxThrust();

    // ★ 机体盒子尺寸：硬编码
    params.body_box.x() = 0.180f;  // 18 cm
    params.body_box.y() = 0.11f;   // 11 cm
    params.body_box.z() = 0.040f;  // 4 cm
    real_T rotor_z = 2.5f / 100;   // 2.5 cm

    // 初始化 QuadX 布局（45° 旋转）
    initializeRotorQuadX(params.rotor_poses, params.rotor_count, 
                          arm_lengths.data(), rotor_z);

    // ★ 惯性张量：由 computeInertiaMatrix 自动计算
    computeInertiaMatrix(params.inertia, params.body_box, params.rotor_poses, 
                          box_mass, motor_assembly_weight);
}
```

### 7.3 惯性张量的自动计算

`computeInertiaMatrix()` 使用**长方体+点质量**模型计算惯性张量：

```cpp
static void computeInertiaMatrix(Matrix3x3r& inertia, const Vector3r& body_box,
    const vector<RotorPose>& rotor_poses, real_T box_mass, real_T motor_assembly_weight)
{
    inertia = Matrix3x3r::Zero();

    // 中心体视为均匀长方体
    // I_xx = m(b² + c²)/12, I_yy = m(a² + c²)/12, I_zz = m(a² + b²)/12
    inertia(0,0) = box_mass / 12.0f * (body_box.y()*body_box.y() + body_box.z()*body_box.z());
    inertia(1,1) = box_mass / 12.0f * (body_box.x()*body_box.x() + body_box.z()*body_box.z());
    inertia(2,2) = box_mass / 12.0f * (body_box.x()*body_box.x() + body_box.y()*body_box.y());

    // 每个电机作为点质量，用平行轴定理叠加
    for (size_t i = 0; i < rotor_poses.size(); ++i) {
        const auto& pos = rotor_poses.at(i).position;
        inertia(0,0) += (pos.y()*pos.y() + pos.z()*pos.z()) * motor_assembly_weight;
        inertia(1,1) += (pos.x()*pos.x() + pos.z()*pos.z()) * motor_assembly_weight;
        inertia(2,2) += (pos.x()*pos.x() + pos.y()*pos.y()) * motor_assembly_weight;
    }
}
```

用默认参数计算验证（`box_mass = 1.0 - 4×0.055 = 0.78 kg`，臂长 0.2275 m 经过 45° 旋转后电机位置约为 `(±0.161, ±0.161, -0.025)`）：

$$
I_{xx} \approx \frac{0.78}{12}(0.11^2 + 0.04^2) + 4 \times 0.055 \times (0.161^2 + 0.025^2) \approx 0.0068 \text{ kg·m}^2
$$

### 7.4 GenericQuad 所有默认值汇总

| 参数 | 默认值 | 含义 |
|------|--------|------|
| `mass` | 1.0 kg | 含电池总质量 |
| `rotor_count` | 4 | 四旋翼 |
| `arm_lengths` | 全部 0.2275 m | F450 机架 |
| `body_box` | 0.180 × 0.11 × 0.04 m | 中心体尺寸 |
| `rotor_z` | 0.025 m | 电机 z 轴偏移 |
| `motor_assembly_weight` | 0.055 kg | MT2212 电机 |
| `linear_drag_coefficient` | 0.325 (= 1.3/4) | 阻力系数 |
| `restitution` | 0.55 | 弹性系数 |
| `friction` | 0.5 | 摩擦系数 |
| `C_T` | 0.109919 | GWS 9x5 桨 |
| `C_P` | 0.040164 | GWS 9x5 桨 |
| `max_rpm` | 6396.667 | 最大转速 |
| `propeller_diameter` | 0.2286 m | 9 英寸桨 |

### 7.5 PX4 模式下的机型选择

使用 PX4 时，`Px4MultiRotorParams::setupParams()` 根据 `settings.json` 中的 `Model` 字段选择不同的预设机型：

```cpp
// 文件: firmwares/mavlink/Px4MultiRotorParams.hpp
virtual void setupParams() override
{
    auto& params = getParams();
    if (connection_info_.model == "Blacksheep") {
        setupFrameBlacksheep(params);     // TBS Discovery
    }
    else if (connection_info_.model == "Flamewheel") {
        setupFrameFlamewheel(params);     // DJI F450 变体
    }
    else if (connection_info_.model == "FlamewheelFLA") {
        setupFrameFlamewheelFLA(params);  // FLA 项目用的 F450
    }
    else if (connection_info_.model == "Hexacopter") {
        setupFrameGenericHex(params);     // 六旋翼
    }
    else if (connection_info_.model == "Octocopter") {
        setupFrameGenericOcto(params);    // 八旋翼
    }
    else {
        setupFrameGenericQuad(params);    // 默认 QuadX
    }
}
```

**Flamewheel 机型**的参数与 GenericQuad 的关键差异：

| 参数 | GenericQuad | Flamewheel |
|------|------------|------------|
| `mass` | 1.0 kg | 1.635 kg |
| `C_T` | 0.109919 | 0.11 |
| `C_P` | 0.040164 | 0.047 |
| `max_rpm` | 6396 | 9500 |
| `linear_drag_coefficient` | 0.325 | 1.3 (4×) |
| `arm_lengths` | 0.2275 m | 0.225 m |
| `body_box.z` | 0.04 m | 0.14 m |

---

## 八、settings.json 能配置什么、不能配置什么

### 8.1 settings.json 的实际解析逻辑

`AirSimSettings::load()` 从 JSON 中解析的多旋翼载具字段（`createVehicleSetting()`）[1]：

**可以通过 settings.json 配置的参数**：

| JSON 字段 | 含义 | 示例 |
|-----------|------|------|
| `VehicleType` | 载具类型 | `"SimpleFlight"`, `"PX4Multirotor"`, `"ArduCopter"` |
| `X`, `Y`, `Z` | 初始位置 (NED) | `0, 0, -1` |
| `Yaw`, `Pitch`, `Roll` | 初始姿态 (度) | `0, 0, 0` |
| `AutoCreate` | 自动创建 | `true` |
| `PawnPath` | UE Blueprint 路径 | `""` |
| `EnableCollisionPassthrogh` | 穿透碰撞 | `false` |
| `EnableCollisions` | 启用碰撞 | `true` |
| `IsFpvVehicle` | 第一人称视角 | `false` |
| `Cameras` | 相机配置 | 支持多相机 |
| `Sensors` | 传感器配置 | IMU/GPS/磁力计/气压计 |
| `RC` | 遥控器配置 | `RemoteControlID` |
| `Model`（仅 PX4） | 预设机型名称 | `"Blacksheep"`, `"Flamewheel"` |

**不能通过 settings.json 配置的参数**（必须修改 C++ 源码）：

| 参数 | 硬编码位置 | 默认值 |
|------|-----------|--------|
| 质量 `mass` | `MultiRotorParams::setupFrameGenericQuad()` | 1.0 kg |
| 惯性张量 `inertia` | `computeInertiaMatrix()` 自动计算 | 取决于机体尺寸和电机位置 |
| 机体尺寸 `body_box` | `setupFrameGenericQuad()` | 0.18×0.11×0.04 m |
| 臂长 `arm_lengths` | `setupFrameGenericQuad()` | 0.2275 m |
| 电机组件重量 | `setupFrameGenericQuad()` | 0.055 kg |
| 旋翼数量 `rotor_count` | `setupFrameGenericQuad()` | 4 |
| 旋翼布局角度 | `initializeRotorQuadX()` | QuadX 45° |
| 推力系数 `C_T` | `RotorParams` 默认值 | 0.109919 |
| 功率系数 `C_P` | `RotorParams` 默认值 | 0.040164 |
| 最大转速 `max_rpm` | `RotorParams` 默认值 | 6396.667 |
| 桨径 `propeller_diameter` | `RotorParams` 默认值 | 0.2286 m |
| 控制信号滤波时间常数 | `RotorParams` 默认值 | 0.005 s |
| 阻力系数 | `MultiRotorParams::Params` 默认值 | 0.325 |
| 碰撞恢复系数 | `MultiRotorParams::Params` 默认值 | 0.55 |
| 碰撞摩擦系数 | `MultiRotorParams::Params` 默认值 | 0.5 |

### 8.2 合法的 settings.json 示例

一个 SimpleFlight 多旋翼的配置示例如下：

```json
{
  "SettingsVersion": 1.2,
  "SimMode": "Multirotor",
  "PhysicsEngineName": "FastPhysicsEngine",
  "ClockSpeed": 1.0,

  "Wind": { "X": 0, "Y": 0, "Z": 0 },

  "Vehicles": {
    "Drone1": {
      "VehicleType": "SimpleFlight",
      "AutoCreate": true,
      "X": 0, "Y": 0, "Z": 0,
      "Yaw": 0,
      "EnableCollisions": true,

      "Sensors": {
        "Imu": {
          "SensorType": 2,
          "Enabled": true,
          "AngularRandomWalk": 0.3,
          "GyroBiasStabilityTau": 500,
          "GyroBiasStability": 4.6e-06,
          "VelocityRandomWalk": 0.24,
          "AccelBiasStabilityTau": 800,
          "AccelBiasStability": 36e-06
        },
        "Gps": {
          "SensorType": 3,
          "Enabled": true,
          "EphTimeConstant": 0.9,
          "EpvTimeConstant": 0.9
        },
        "Barometer": {
          "SensorType": 1,
          "Enabled": true
        },
        "Magnetometer": {
          "SensorType": 4,
          "Enabled": true
        }
      }
    }
  }
}
```

> **注意**：`settings.json` 中写入 `"Mass"`, `"Inertia"`, `"RotorParams"` 等字段不会报错（JSON 解析会忽略未知字段），但**这些参数不会生效**——`AirSimSettings.hpp` 中没有对应的解析逻辑。

---

## 九、坐标系约定：AirSim 的 NED 体系

### 9.1 坐标系定义

AirSim 全局使用 **NED 坐标系**（North-East-Down）[1]：

| 轴 | 惯性系含义 | 机体系含义 | 正方向 |
|----|----------|----------|--------|
| x | 北 | 机头 | 前进 |
| y | 东 | 右翼 | 右侧 |
| z | 地 | 下方 | 向下 |

源码中 `initializeRotorQuadX()` 的 `unit_z(0, 0, -1)` 表示推力方向为 z 轴负方向（向上），这与 NED 约定一致。

### 9.2 QuadX 电机布局

源码中 `initializeRotorQuadX()` 的注释明确了布局（NED 坐标系，从上方俯视）：

```
       x 轴 (机头方向)
  (2)CW  |  (0)CCW
         |
  -------|------- y 轴 (右侧)
         |
  (1)CCW |  (3)CW
```

电机 0 和 1 逆时针（CCW），电机 2 和 3 顺时针（CW）。所有臂先沿 y 轴排列，然后绕 z 轴旋转 45°（`M_PIf / 4`）得到 X 型布局。

### 9.3 旋向与反扭矩

```cpp
enum class RotorTurningDirection : int {
    RotorTurningDirectionCCW = -1,
    RotorTurningDirectionCW = 1
};
```

在 `RotorActuator::setOutput()` 中：

$$
Q_i = u_{f,i} \cdot Q_{\max} \cdot d_i
$$

其中 $d_i \in \{-1, +1\}$。CW 桨（$d_i = +1$）产生正 z 方向扭矩（NED 中指向下方），CCW 桨（$d_i = -1$）产生负 z 方向扭矩。对角线电机同旋向，悬停时偏航扭矩抵消。

### 9.4 四元数约定

AirSim 使用 Hamilton 四元数约定 $\mathbf{q} = [w, x, y, z]$（标量在前），与 Eigen 库一致。姿态更新为右乘：$\mathbf{q}_{t+1} = \mathbf{q}_t \otimes \Delta\mathbf{q}$。

### 9.5 与 ROS/ENU 的转换

$$
\mathbf{v}_{\text{ENU}} = \begin{bmatrix} 0 & 1 & 0 \\ 1 & 0 & 0 \\ 0 & 0 & -1 \end{bmatrix} \mathbf{v}_{\text{NED}}
$$

---

## 十、构建自己的无人机模型：正确的方法

### 10.1 核心认识：必须修改 C++ 源码

由于物理参数硬编码在 C++ 中，要为自己的无人机建模，有**三种方法**：

**方法 A：修改现有预设参数**（最简单）

直接修改 `MultiRotorParams.hpp` 中 `setupFrameGenericQuad()` 的硬编码值，然后重新编译。

**方法 B：创建新的机型预设**（推荐）

仿照 `setupFrameFlamewheel()` 创建新方法，然后在 `Px4MultiRotorParams` 中添加一个新的 Model 分支，这样可以通过 `settings.json` 的 `Model` 字段选择。

**方法 C：扩展 settings.json 解析逻辑**（工作量最大但最灵活）

修改 `AirSimSettings.hpp` 的 `VehicleSetting` 结构体，添加物理参数字段，然后在 `SimpleFlightQuadXParams::setupParams()` 中从 `vehicle_setting_` 读取这些字段。

### 10.2 方法 A 详解：修改 setupFrameGenericQuad

假设你要模拟一架 DJI F450（轴距 450mm，1.5 kg，10 英寸桨）：

```cpp
// 修改文件: AirLib/include/vehicles/multirotor/MultiRotorParams.hpp
// 在 setupFrameGenericQuad() 中修改以下值:

void setupFrameGenericQuad(Params& params)
{
    params.rotor_count = 4;
    std::vector<real_T> arm_lengths(params.rotor_count, 0.225f);  // F450: 225mm

    params.mass = 1.5f;  // ← 你的无人机质量

    real_T motor_assembly_weight = 0.080f;  // ← 你的电机+桨重量
    real_T box_mass = params.mass - params.rotor_count * motor_assembly_weight;

    // ★ 修改桨参数
    params.rotor_params.C_T = 0.1117f;   // ← 你的桨的推力系数
    params.rotor_params.C_P = 0.0477f;   // ← 你的桨的功率系数
    params.rotor_params.max_rpm = 9500;   // ← 你的电机最大转速
    params.rotor_params.propeller_diameter = 0.254f;  // ← 10 英寸
    params.rotor_params.calculateMaxThrust();  // ★ 必须调用！

    params.body_box.x() = 0.20f;   // ← 你的机身尺寸
    params.body_box.y() = 0.12f;
    params.body_box.z() = 0.08f;
    real_T rotor_z = 0.02f;

    initializeRotorQuadX(params.rotor_poses, params.rotor_count, 
                          arm_lengths.data(), rotor_z);
    computeInertiaMatrix(params.inertia, params.body_box, params.rotor_poses, 
                          box_mass, motor_assembly_weight);
}
```

修改后需要重新编译 AirLib 和 Unreal 插件。

### 10.3 方法 B 详解：创建新机型预设

**步骤 1**：在 `MultiRotorParams.hpp` 中添加新方法：

```cpp
void setupFrameMyDrone(Params& params)
{
    params.rotor_count = 4;
    std::vector<real_T> arm_lengths(params.rotor_count, 0.175f);
    
    params.mass = 2.0f;
    real_T motor_assembly_weight = 0.1f;
    real_T box_mass = params.mass - params.rotor_count * motor_assembly_weight;
    
    params.rotor_params.C_T = 0.15f;
    params.rotor_params.C_P = 0.06f;
    params.rotor_params.max_rpm = 8000;
    params.rotor_params.propeller_diameter = 0.3048f;  // 12 英寸
    params.rotor_params.calculateMaxThrust();
    
    params.linear_drag_coefficient = 0.5f;  // 较大阻力
    
    params.body_box.x() = 0.25f;
    params.body_box.y() = 0.15f;
    params.body_box.z() = 0.10f;
    real_T rotor_z = 0.03f;
    
    initializeRotorQuadX(params.rotor_poses, params.rotor_count,
                          arm_lengths.data(), rotor_z);
    computeInertiaMatrix(params.inertia, params.body_box, params.rotor_poses,
                          box_mass, motor_assembly_weight);
}
```

**步骤 2**：在 `Px4MultiRotorParams.hpp` 的 `setupParams()` 中添加分支：

```cpp
else if (connection_info_.model == "MyDrone") {
    setupFrameMyDrone(params);
}
```

**步骤 3**：在 `settings.json` 中选择：

```json
{
  "Vehicles": {
    "Drone1": {
      "VehicleType": "PX4Multirotor",
      "Model": "MyDrone"
    }
  }
}
```

### 10.4 非标准旋翼布局

源码提供了通用的 `initializeRotors()` 方法，支持任意旋翼数量和布局：

```cpp
static void initializeRotors(vector<RotorPose>& rotor_poses, 
    uint rotor_count, 
    real_T arm_lengths[],      // 每个臂的长度
    real_T arm_angles[],       // 每个臂的角度（度，相对前方）
    RotorTurningDirection rotor_directions[],  // 每个电机旋向
    real_T rotor_z)            // z 轴偏移
```

对于六轴、八轴或非对称布局，使用此方法即可。

---

## 十一、自定义建模需要的完整参数清单

### 11.1 必须测量/获取的参数

| 参数 | 对应代码字段 | 如何获取 | 精度要求 |
|------|------------|---------|---------|
| 起飞总质量 | `params.mass` | 电子秤称量（含电池） | ±5g |
| 电机到质心距离 | `arm_lengths` | 直尺/卡尺测量 | ±2mm |
| 电机组件重量 | `motor_assembly_weight` | 秤量（电机+桨+螺丝+座） | ±2g |
| 机身盒子尺寸 | `params.body_box` | 测量中心体（不含臂） | ±5mm |
| 电机 z 轴偏移 | `rotor_z` | 电机平面到质心高度差 | ±3mm |
| 推力系数 $C_T$ | `rotor_params.C_T` | 推力台架 / UIUC 数据库 [13] | 关键 |
| 功率系数 $C_P$ | `rotor_params.C_P` | 推力台架 / UIUC 数据库 | 关键 |
| 最大转速 | `rotor_params.max_rpm` | KV值 × 电压 / 电机数据手册 | ±5% |
| 桨直径 | `rotor_params.propeller_diameter` | 实测 | ±1mm |
| 阻力系数 | `linear_drag_coefficient` | 风洞/飞行数据拟合 | 可迭代 |

### 11.2 可以通过计算获得的参数

| 参数 | 计算方法 |
|------|---------|
| 惯性张量 | `computeInertiaMatrix()` 自动计算（长方体+点质量模型），或 CAD/双线摆实验 |
| 最大推力 | `calculateMaxThrust()` 自动计算 |
| 最大扭矩 | `calculateMaxThrust()` 自动计算 |
| 阻力面积 | `createDragVertices()` 根据 body_box 和桨面积自动计算 |

### 11.3 推力系数的获取方法

**方法 A：推力台架实测**（精度最高）

在不同转速下测量推力 $T$ 和转速 $n$ (rev/s)，拟合：

$$
C_T = \frac{T}{\rho \cdot n^2 \cdot D^4}
$$

**方法 B：UIUC 螺旋桨数据库 [13]**

访问 [https://m-selig.ae.illinois.edu/props/propDB.html](https://m-selig.ae.illinois.edu/props/propDB.html)，查找同型号桨的 $C_T$、$C_P$ 数据。注意 UIUC 的数据是在特定 RPM 和来流速度下测试的静态值。

**方法 C：悬停反推**

已知总重 $mg$ 和悬停转速 $\omega_h$（从飞行日志获取）：

$$
C_T = \frac{mg}{4 \rho n_h^2 D^4}
$$

其中 $n_h = \omega_h / (2\pi)$ 为每秒转数。

### 11.4 惯性张量的获取方法

**方法 A：使用 AirSim 自带的计算**

`computeInertiaMatrix()` 已经实现了长方体+点质量模型，只需提供准确的 `body_box`、`motor_assembly_weight` 和电机位置即可。对于大多数对称四旋翼，这个估计足够用。

**方法 B：双线摆实验**（精度最高）[4]

将无人机悬挂在两根等长线上，小角度摆动，测量周期 $T_{\text{osc}}$：

$$
I = \frac{m g d^2 T_{\text{osc}}^2}{16\pi^2 L_s}
$$

**方法 C：CAD 估算**

在 SolidWorks/Fusion 360 中建模，赋予各部件正确密度，软件自动计算惯性张量。

### 11.5 控制信号滤波时间常数

默认 `control_signal_filter_tc = 0.005 s`（5 ms），模拟电机+ESC 的响应延迟。

| 电机类型 | 建议时间常数 |
|---------|------------|
| 高品质无刷（竞速用） | 0.002 - 0.005 s |
| 普通无刷（航拍用） | 0.005 - 0.015 s |
| 有刷电机 | 0.02 - 0.05 s |

可以通过电机阶跃响应实验测量。给电机一个阶跃信号，测量转速达到 63.2% 稳态值的时间即为时间常数。

---

## 十二、Sim-to-Real 对齐：系统性校准方法

### 12.1 差异来源分析

| 差异来源 | 影响程度 | AirSim 建模情况 |
|---------|---------|----------------|
| 物理参数不准确 | **高** | 硬编码默认值，需修改源码 |
| 阻力模型简化 | 中 | 六面体 $v^2$ 阻力，无涡阻力 |
| 无地面效应 | 中（近地时） | **未建模** |
| 无桨叶拍打 | 低-中 | **未建模** |
| 无电池电压降 | 中 | **未建模** |
| 传感器噪声 | 中 | 可通过 settings.json 配置 |
| 风扰动 | 中 | API 可设置恒定风 |

### 12.2 悬停验证

悬停是最基本的验证——四桨等速，总推力等于重力：

$$
4 T_{\max} \cdot u_h = mg \quad \Rightarrow \quad u_h = \frac{mg}{4 T_{\max}}
$$

用默认参数：$u_h = \frac{1.0 \times 9.81}{4 \times 4.179} = 0.587$，即约 58.7% 油门。

**验证脚本**：

```python
import airsim
import time

client = airsim.MultirotorClient()
client.confirmConnection()
client.enableApiControl(True)
client.armDisarm(True)
client.takeoffAsync().join()

for _ in range(100):
    state = client.getMultirotorState()
    rotor_states = state.rotor_states
    print(f"z={state.kinematics_estimated.position.z_val:.3f}, "
          f"vz={state.kinematics_estimated.linear_velocity.z_val:.4f}")
    time.sleep(0.1)
```

如果仿真中无人机持续下沉或上升，说明 $T_{\max}$（由 $C_T$、$\rho$、$n_{\max}$、$D$ 决定）或质量参数不正确。

### 12.3 参数辨识流程

**第一步：推力系数辨识**

从 PX4 日志中提取悬停段电机 PWM → 转换为转速 → 代入公式计算 $C_T$。

**第二步：惯性矩验证**

设计单轴角速度阶跃实验，在纯滚转段（$\omega_y \approx \omega_z \approx 0$）：

$$
I_{xx} = \frac{\tau_x}{\dot{\omega}_x}
$$

多段数据最小二乘拟合。

**第三步：阻力系数**

自由减速段速度衰减：

$$
m\dot{v} = -k_d \rho v^2 A_{\text{eff}} / 2
$$

注意 AirSim 的阻力是 $v^2$ 模型，不是线性阻力。

### 12.4 对齐验证指标

| 验证实验 | 对比指标 | 可接受误差 |
|---------|---------|----------|
| 悬停稳定性 | 油门值 | < 5% |
| 俯仰阶跃响应 | 上升时间 / 超调量 | < 10% |
| 偏航角速度 | 稳态值 | < 15% |
| 前飞加速 | 达到目标速度时间 | < 15% |
| 自由下落 | 距离-时间曲线 | < 2% |

---

## 十三、高级话题：AirSim 未建模的物理效应

### 13.1 地面效应

桨盘距地面高度 $h < 2R$ 时，推力增加 [6]：

$$
\frac{T_{\text{IGE}}}{T_{\text{OGE}}} \approx \frac{1}{1 - (R/4h)^2}
$$

可通过修改 `RotorActuator::setWrench()` 添加，需要从 `Environment` 获取 AGL 高度。

### 13.2 电池电压降

实际飞行中 $\omega_{\max}(t) = K_V \cdot V_{\text{batt}}(t)$，可通过定期调用 `rotor_params.max_rpm = new_value; rotor_params.calculateMaxThrust();` 模拟。

### 13.3 风扰动

AirSim 支持通过 API 设置恒定风：

```python
wind = airsim.Vector3r(3, 0, 0)
client.simSetWind(wind)
```

`FastPhysicsEngine` 在 `getDragWrench()` 中用**相对风速**计算阻力：`relative_vel = linear_vel - wind_world`，风速在阻力面上产生额外的 $v^2$ 阻力。

### 13.4 碰撞模型

`FastPhysicsEngine` 实现了基于冲量的碰撞响应（含库仑摩擦）：

$$
j = -\frac{(1+e)\mathbf{v}_c \cdot \hat{n}}{1/m + [(\mathbf{I}^{-1}(\mathbf{r}\times\hat{n}))\times\mathbf{r}]\cdot\hat{n}}
$$

其中 $e$ = `restitution`（0.55），$\hat{n}$ 为碰撞法线。着陆时 $e$ 被设为 0（完全非弹性），摩擦设为 1，并触发**地面锁定**（ground lock）——清零线速度和角速度，锁定 roll/pitch 为 0。

---

## 十四、传感器模型配置

传感器参数是 `settings.json` 中**真正可配置**的物理参数。

### 14.1 IMU 噪声模型

```json
{
  "Sensors": {
    "Imu": {
      "SensorType": 2,
      "Enabled": true,
      "AngularRandomWalk": 0.3,
      "GyroBiasStabilityTau": 500,
      "GyroBiasStability": 4.6e-06,
      "VelocityRandomWalk": 0.24,
      "AccelBiasStabilityTau": 800,
      "AccelBiasStability": 36e-06
    }
  }
}
```

| 参数 | 物理含义 | 典型值（MEMS） |
|------|---------|--------------|
| `AngularRandomWalk` | 陀螺仪角度随机游走 (°/√h) | 0.1-0.5 |
| `GyroBiasStability` | 陀螺仪零偏稳定性 (rad/s) | 1e-6 ~ 1e-4 |
| `VelocityRandomWalk` | 加速度计速度随机游走 (m/s/√h) | 0.1-0.5 |
| `AccelBiasStability` | 加速度计零偏稳定性 (m/s²) | 1e-5 ~ 1e-3 |

### 14.2 环境模型

AirSim 的 `Environment` 类根据 `OriginGeopoint`（settings.json 可配置）和当前高度自动计算：
- **空气密度**：标准大气模型，影响推力和阻力
- **重力**：默认 9.81 m/s²
- **地磁场**：WMM 模型

---

## 十五、PX4 SITL 集成

### 15.1 数据流

```
PX4 SITL Firmware
    │ MAVLink (HIL_ACTUATOR_CONTROLS)
    ▼
AirSim MavLinkConnection
    │
    ▼
MultiRotorPhysicsBody.updateSensorsAndController()
    │ vehicle_api_->getActuation(i) → rotors_[i].setControlSignal()
    ▼
FastPhysicsEngine.updatePhysics()
    │
    ├── RotorActuator: 控制信号 → 推力/扭矩
    ├── getBodyWrench(): 汇总力/力矩
    ├── getDragWrench(): 气动阻力
    ├── 欧拉方程 + Velocity Verlet 积分
    └── 碰撞检测与响应
    │
    ▼
传感器模拟 (IMU 噪声, GPS 延迟, 磁力计)
    │ MAVLink (HIL_SENSOR, HIL_GPS)
    └──→ 发送回 PX4
```

### 15.2 机型选择

使用 PX4 时可以通过 `settings.json` 的 `Model` 字段选择预设机型：

```json
{
  "Vehicles": {
    "PX4Drone": {
      "VehicleType": "PX4Multirotor",
      "Model": "Flamewheel",
      "UseSerial": false,
      "UdpIp": "127.0.0.1",
      "UdpPort": 14560
    }
  }
}
```

可选 Model：`Generic`（默认）、`Blacksheep`、`Flamewheel`、`FlamewheelFLA`、`Hexacopter`、`Octocopter`。

---

## 十六、总结

### 16.1 核心要点

| 常见误解 | 源码中的实际实现 |
|-------------|----------------|
| 物理参数可以通过 settings.json 配置 | **不能**，必须修改 C++ 源码并重新编译 |
| 使用 `MultiRotor.hpp` | 实际类为 **`MultiRotorPhysicsBody.hpp`** |
| 推力每步实时计算 $T = C_T \rho n^2 D^4$ | 推力 = 滤波后控制信号 × 预计算的 $T_{\max}$ |
| 简单欧拉积分 | **Velocity Verlet**（二阶辛积分器）|
| 线性阻力 $F_d = -k_d v$ | **六面体面阻力**，$F \propto v^2$，含背风面剔除 |
| 电机动态用 `tau_up`/`tau_down` | 统一的一阶低通滤波 `control_signal_filter_tc` |
| 四元数更新用小角度近似 | **精确轴角法**（`AngleAxisr`） |

### 16.2 自定义建模核心步骤

1. **测量参数**：质量（电子秤）、臂长（卡尺）、桨径、电机 KV 值
2. **获取推力系数**：推力台架 / UIUC 数据库 / 悬停反推
3. **修改 C++ 源码**：`MultiRotorParams.hpp` 中的 `setupFrame*()` 方法
4. **重新编译**：编译 AirLib → 编译 Unreal 插件
5. **悬停验证**：对比仿真与实际悬停油门
6. **迭代校准**：阶跃响应对比 → 调整参数 → 重复

### 16.3 与本博客其他文章的关联

| 文章 | 关系 |
|------|------|
| 《线性代数》 | `getBodyWrench()` 中的叉积力矩、`computeNextPose()` 中的四元数旋转 |
| 《飞行物理学》 | `getNextKinematicsNoCollision()` 求解的欧拉方程和牛顿方程 |
| 《四旋翼飞行力学基础》 | QuadX 布局、混控矩阵、推力/反扭矩 |

---

## 参考文献

- **[1]** Colosseum 社区. *Colosseum: An open-source fork of AirSim*. GitHub. [https://github.com/CodexLabsLLC/Colosseum](https://github.com/CodexLabsLLC/Colosseum)
  本文所有源码分析基于此仓库 `main` 分支。核心文件：`RotorParams.hpp`、`RotorActuator.hpp`、`MultiRotorParams.hpp`、`MultiRotorPhysicsBody.hpp`、`FastPhysicsEngine.hpp`、`AirSimSettings.hpp`。

- **[2]** Microsoft Research. *AirSim: Open source simulator for autonomous vehicles*. GitHub. [https://github.com/microsoft/AirSim](https://github.com/microsoft/AirSim)
  AirSim 原始仓库（2022 年停止维护），核心物理引擎与 Colosseum 一致。

- **[3]** NOAA. *U.S. Standard Atmosphere, 1976*. [https://www.ngdc.noaa.gov/stp/space-weather/online-publications/miscellaneous/us-standard-atmosphere-1976/](https://www.ngdc.noaa.gov/stp/space-weather/online-publications/miscellaneous/us-standard-atmosphere-1976/)
  标准大气模型，AirSim Environment 类中空气密度随海拔变化的依据。

- **[4]** Jardin, M.R., and Mueller, E.R. "Optimized Measurements of UAV Mass Moment of Inertia with a Bifilar Pendulum." *AIAA Guidance, Navigation, and Control Conference*, 2007. DOI: 10.2514/6.2007-6822.
  双线摆法测量无人机惯性矩的标准方法。

- **[5]** Sadraey, M.H. *Design of Unmanned Aerial Systems*. Wiley, 2020. ISBN: 978-1119508700.
  无人机系统设计教材，包含从建模到验证的系统方法。

- **[6]** J. Gordon Leishman. *Principles of Helicopter Aerodynamics*, 2nd Edition. Cambridge University Press, 2006. ISBN: 978-0521858601.
  旋翼空气动力学标准教材，地面效应、桨叶拍打等。

- **[7]** Randal W. Beard, Timothy W. McLain. *Small Unmanned Aircraft: Theory and Practice*. Princeton University Press, 2012. [https://github.com/randybeard/uavbook](https://github.com/randybeard/uavbook)
  小型无人机建模与控制标准参考。

- **[8]** Shah, S., Dey, D., Lovett, C., and Kapoor, A. "AirSim: High-Fidelity Visual and Physical Simulation for Autonomous Vehicles." *Field and Service Robotics*, 2018. [https://arxiv.org/abs/1705.05065](https://arxiv.org/abs/1705.05065)
  AirSim 原始论文。

- **[9]** PX4 开发团队. *PX4 Autopilot User Guide - Simulation*. [https://docs.px4.io/main/en/simulation/](https://docs.px4.io/main/en/simulation/)
  PX4 SITL/HITL 仿真官方文档。

- **[10]** Ljung, L. *System Identification: Theory for the User*, 2nd Edition. Prentice Hall, 1999. ISBN: 978-0136566953.
  系统辨识经典教材。

- **[11]** Quan Quan. *Introduction to Multicopter Design and Control*. Springer, 2017. ISBN: 978-9811033810.
  多旋翼设计与控制教材。

- **[12]** Peter Corke. *Robotics, Vision and Control*, 3rd Edition. Springer, 2023. [https://github.com/petercorke/robotics-toolbox-python](https://github.com/petercorke/robotics-toolbox-python)
  机器人学综合参考。

- **[13]** UIUC Propeller Data Site. [https://m-selig.ae.illinois.edu/props/propDB.html](https://m-selig.ae.illinois.edu/props/propDB.html)
  螺旋桨性能数据库，$C_T$、$C_P$ 实测数据。

---

**核心思想**：AirSim 的仿真质量取决于两个层面——**物理引擎的正确性**（Velocity Verlet 积分 + 欧拉方程 + $v^2$ 阻力模型，已经相当好了）和**你喂进去的参数有多准确**（必须修改 C++ 源码，不能只改 JSON）。认清这个事实，才能高效地建立准确的仿真模型。
