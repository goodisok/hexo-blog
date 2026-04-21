---
title: Gazebo + PX4 自定义截击机仿真建模与 Sim-to-Real 完整指南：从推力台架到蒙特卡洛验证
date: 2026-04-21 22:00:00
categories:
  - 无人机
  - 仿真开发
tags:
  - PX4
  - Gazebo
  - 截击机
  - 仿真建模
  - Sim-to-Real
  - 系统辨识
  - 数字孪生
  - SDF
  - SITL
  - 参数辨识
  - 域随机化
  - 推力台架
  - sysid.tools
  - 制导仿真
mathjax: true
---

> 当你的截击机是一款全新设计——Gazebo 里没有现成模型、没有气动数据、没有飞行记录——如何从零构建高保真仿真模型，并系统性地缩小 Sim-to-Real Gap？本文给出从推力台架实测到蒙特卡洛验证的完整工程流程。

**适用场景**：基于 PX4 飞控的自定义多旋翼/VTOL/Tailsitter 截击无人机，使用 Gazebo Harmonic/Jetty + PX4 SITL 进行制导算法验证。

---

## 一、为什么截击机仿真的 Sim-to-Real 问题特别棘手

普通无人机（航拍、物流）的仿真容错度很高：悬停或低速巡航时，气动阻力可忽略、电机工作在线性区、控制增益有大量安全裕度。截击机的工况完全不同：

| 维度 | 普通无人机 | 截击机 | 对仿真精度的影响 |
|------|----------|--------|----------------|
| 速度范围 | 0~15 m/s | 0~100+ m/s | 气动阻力 $\propto v^2$，100 m/s 时阻力可达推力的 30-50% |
| 电机工况 | 30~70% 油门 | 0~100% 全范围 | 推力曲线的非线性区间必须精确建模 |
| 机动过载 | <1g | 5~15g | 大姿态角下旋翼效率剧烈变化 |
| 螺旋桨效率 | 近似恒定 | 随前飞速度显著下降 | 需要进动比修正模型 |
| 任务结果判定 | 到达目标点 | 碰撞目标（误差 <1m） | 制导律对模型误差极度敏感 |
| 控制时间窗口 | 秒级 | 毫秒级末段 | 没有时间让控制器补偿模型误差 |

一句话：**普通无人机仿真中可以忽略的二阶效应，在截击机仿真中可能是主导误差源。**

---

## 二、总体工作流程

构建自定义截击机仿真并保证 Sim-to-Real 对齐，需要经过以下六个阶段：

```
阶段一：物理参数获取
├── CAD 建模 → 质量/惯量/几何
├── 推力台架实测 → 电机/螺旋桨特性
└── 数据手册 → ESC/电池特性

阶段二：Gazebo SDF 模型构建
├── 几何/视觉模型（STL/DAE 网格）
├── 惯性/碰撞模型
├── MulticopterMotorModel 插件配置
└── 气动插件配置（高速截击机必需）

阶段三：PX4 机架配置
├── 控制分配参数（CA_ROTOR_*）
├── 控制器增益初始值
└── 安全参数修改（速度限制/碰撞行为）

阶段四：飞行辨识与参数修正
├── sysid.tools 飞行数据辨识
├── 推力曲线 / 惯量 / 力矩系数迭代
└── 参数回填 SDF + PX4 配置

阶段五：定量验证
├── 悬停 / 阶跃响应 / 轨迹跟踪对比
├── 高速飞行工况验证
└── 量化 Sim-to-Real Gap 指标

阶段六：域随机化与鲁棒性验证
├── 蒙特卡洛参数扰动
├── 风场 / 传感器噪声注入
└── 制导算法在不确定性下的成功率统计
```

---

## 三、阶段一：物理参数获取

### 3.1 质量与转动惯量

**质量**直接用电子秤称量整机（含电池、载荷）。

**转动惯量**有三种获取路径，精度递增：

#### 方法 A：CAD 估算（误差 ~10-20%）

在 SolidWorks / Fusion 360 / FreeCAD 中建立完整装配体，赋予每个零件正确的材料密度，软件自动计算惯性张量。

需注意：
- 电池、飞控板、线束等密度不均匀的部件要单独设定
- CAD 模型通常省略线束和紧固件，实际惯量偏大

#### 方法 B：双线摆 / 三线摆实测（误差 ~3-5%）

双线摆原理：将飞机悬挂在两根等长线上，绕垂直轴扭转后释放，测量摆动周期 $T$，则绕该轴的转动惯量为：

$$I = \frac{m g d^2 T^2}{16 \pi^2 L}$$

其中 $m$ 为质量，$d$ 为两悬线间距，$L$ 为线长，$T$ 为周期。

分别绕三个轴测量即可得到 $I_{xx}$、$I_{yy}$、$I_{zz}$。交叉惯量 $I_{xy}$ 等通常可忽略（对称构型）或通过倾斜悬挂测量。

#### 方法 C：飞行数据辨识（误差 ~5-10%，见阶段四）

使用 sysid.tools，从飞行日志中辨识。无需额外设备，但需要先能飞起来。

### 3.2 电机-螺旋桨系统参数

这是整个建模过程中**最关键的环节**。截击机电机长期工作在高油门区间，推力曲线的非线性特征对仿真精度影响极大。

#### 推力台架实测（强烈推荐）

所需设备：

| 设备 | 用途 | 参考型号 |
|------|------|---------|
| 推力台架 | 测量推力/力矩/转速/功率 | RCBenchmark 1585、Tyto Robotics |
| 直流电源 | 提供稳定电压（模拟满电/半电） | 30V/30A 可编程电源 |
| 数据采集 | 记录传感器数据 | 台架自带 / Arduino + HX711 |

测量流程：

```
固定电机+螺旋桨到台架
├── 电压设定：满电电压 V_max（如 25.2V/6S）
├── 油门扫描：0% → 100%，步进 5%
├── 每个油门点稳定 3 秒后记录：
│   ├── 推力 T (N)
│   ├── 反扭力矩 Q (N·m)
│   ├── 转速 ω (RPM → 转换为 rad/s)
│   ├── 电流 I (A)
│   └── 电压 V (V)
├── 重复 3 次取平均
└── 在半电电压（如 21.0V）下重复，评估电压衰减影响
```

从实测数据提取 Gazebo 所需参数：

**推力常数** $k_T$（Gazebo 中叫 `motorConstant`）：

$$T = k_T \cdot \omega^2$$

对实测数据做最小二乘拟合：$k_T = \frac{\sum T_i \omega_i^2}{\sum \omega_i^4}$

**力矩常数** $k_M$（Gazebo 中叫 `momentConstant`）：

$$Q = k_M \cdot T$$

直接从实测数据计算每个油门点的 $Q/T$ 比值，取平均。

**最大角速度** $\omega_{max}$：

$$\omega_{max} = \text{KV} \times V_{max} \times \eta_{motor} \times \frac{2\pi}{60} \quad [\text{rad/s}]$$

其中 KV 为电机 KV 值，$\eta_{motor}$ 为电机效率（典型值 0.8~0.9），或直接取台架实测的最大转速。

**电机时间常数** $\tau$（Gazebo 中叫 `timeConstantUp` / `timeConstantDown`）：

给电机一个阶跃油门指令，测量转速从 10% 上升到 90% 的时间，除以 2.2 即为一阶时间常数。典型值 15~50 ms。

#### 无台架时的理论估算

如果暂时没有推力台架，可从厂商数据估算：

$$k_T = \frac{T_{max}}{\omega_{max}^2}$$

$$C_T = \frac{T}{\rho n^2 D^4}$$

$$C_Q = \frac{Q}{\rho n^2 D^5}$$

$$k_M = \frac{C_Q}{C_T} \cdot D$$

其中 $\rho = 1.225$ kg/m³（海平面空气密度），$n$ 为转速（rev/s），$D$ 为桨径（m）。

### 3.3 气动阻力参数

截击机**必须**建模机体气动阻力。需要以下参数：

| 参数 | 含义 | 获取方式 |
|------|------|---------|
| $C_{D,x}$ | 前向阻力系数 | 风洞测试 / CFD / 飞行辨识 |
| $C_{D,y}$ | 侧向阻力系数 | 同上 |
| $C_{D,z}$ | 垂向阻力系数 | 同上 |
| $A_{ref}$ | 参考面积 (m²) | CAD 测量迎风面积 |

无风洞时的估算：对于外形规则的多旋翼，$C_D \approx 1.0 \sim 1.5$（取决于外形流线程度），$A_{ref}$ 取最大截面积。

PX4 的 EKF2 内置多旋翼阻力模型，参数为：
- `EKF2_BCOEF_X`：X 轴弹道系数 = $m / (C_{D,x} \cdot A_{ref})$
- `EKF2_BCOEF_Y`：Y 轴弹道系数 = $m / (C_{D,y} \cdot A_{ref})$

---

## 四、阶段二：Gazebo SDF 模型构建

### 4.1 总体结构

Gazebo 的飞行器模型由 SDF（Simulation Description Format）文件定义。以 PX4 官方 x500 为模板修改：

```bash
# 复制模板
cp -r PX4-Autopilot/Tools/simulation/gz/models/x500 \
      PX4-Autopilot/Tools/simulation/gz/models/interceptor

# 同时复制 base 模型（如有共用部分）
cp -r PX4-Autopilot/Tools/simulation/gz/models/x500_base \
      PX4-Autopilot/Tools/simulation/gz/models/interceptor_base
```

SDF 模型的核心组成：

```xml
<model name="interceptor">
  <!-- 1. 视觉与碰撞几何（外观和物理边界） -->
  <link name="base_link">
    <visual>...</visual>
    <collision>...</collision>
    <inertial>...</inertial>
  </link>

  <!-- 2. 旋翼关节与电机模型（每个电机一组） -->
  <link name="rotor_0">...</link>
  <joint name="rotor_0_joint">...</joint>
  <plugin name="MulticopterMotorModel">...</plugin>

  <!-- 3. 传感器（IMU、GPS、气压计、摄像头等） -->
  <plugin name="imu_sensor">...</plugin>

  <!-- 4. 气动插件（截击机必需） -->
  <plugin name="AdvancedLiftDrag">...</plugin>
</model>
```

### 4.2 惯性模型

SDF 中的惯性定义直接使用阶段一获取的数据：

```xml
<inertial>
  <mass>2.5</mass>  <!-- 整机质量 kg -->
  <pose>0 0 0.02 0 0 0</pose>  <!-- 重心偏移（相对 link 原点）-->
  <inertia>
    <ixx>0.0347563</ixx>   <!-- 绕 X 轴转动惯量 -->
    <iyy>0.0458929</iyy>   <!-- 绕 Y 轴转动惯量 -->
    <izz>0.0977000</izz>   <!-- 绕 Z 轴转动惯量 -->
    <ixy>0</ixy>
    <ixz>0</ixz>
    <iyz>0</iyz>
  </inertia>
</inertial>
```

注意：Gazebo 使用 SI 单位（kg、m、kg·m²），**不要**混用 g 和 mm。

### 4.3 电机模型插件——MulticopterMotorModel

这是仿真精度的核心。Gazebo 的 `MulticopterMotorModel` 插件内部数学模型如下 [1]：

**电机转速动力学**（一阶滤波）：

$$\dot{\omega}_m = \frac{1}{\tau} (\omega_{ref} - \omega_m)$$

其中 $\omega_{ref}$ 为指令转速（来自 PX4 的电机输出），$\tau$ 为电机时间常数。

**推力计算**：

$$T = k_T \cdot \omega_m \cdot |\omega_m|$$

注意使用 $\omega_m \cdot |\omega_m|$ 而非 $\omega_m^2$，是为了保留旋转方向信息（支持反转旋翼）。

**反扭力矩**：

$$Q = k_M \cdot T$$

**旋翼阻力**（H-force）：

$$F_{drag} = C_{drag} \cdot \omega_m \cdot |\omega_m|$$

SDF 配置示例（每个电机一个插件实例）：

```xml
<plugin filename="gz-sim-multicopter-motor-model-system"
        name="gz::sim::systems::MulticopterMotorModel">
  <jointName>rotor_0_joint</jointName>
  <linkName>rotor_0</linkName>
  <turningDirection>ccw</turningDirection>

  <!-- 从推力台架实测得到的参数 -->
  <motorConstant>5.84e-06</motorConstant>          <!-- kT [kg·m/rad²] -->
  <momentConstant>0.06</momentConstant>             <!-- kM [m] (Q/T 比值) -->
  <maxRotVelocity>1100.0</maxRotVelocity>           <!-- ωmax [rad/s] -->
  <rotorDragCoefficient>2.5e-08</rotorDragCoefficient>
  <rollingMomentCoefficient>1.0e-06</rollingMomentCoefficient>

  <!-- 电机响应时间 -->
  <timeConstantUp>0.0125</timeConstantUp>           <!-- 加速时间常数 [s] -->
  <timeConstantDown>0.025</timeConstantDown>        <!-- 减速时间常数 [s] -->

  <!-- 仿真参数 -->
  <rotorVelocitySlowdownSim>10</rotorVelocitySlowdownSim>

  <!-- 接收 PX4 的电机指令话题 -->
  <commandSubTopic>command/motor_speed</commandSubTopic>
  <motorNumber>0</motorNumber>
  <motorType>velocity</motorType>
</plugin>
```

**关键参数的自检方法**：

$$T_{max} = k_T \times \omega_{max}^2$$

计算出的最大单电机推力应满足：$4 \times T_{max} > m \times g \times 2$（四旋翼推重比至少 2:1）。如果不满足，参数有误。

### 4.4 气动阻力建模（截击机必需）

对于飞行速度超过 20 m/s 的截击机，**必须**添加气动阻力插件。Gazebo 提供两种选择：

#### 方案 A：简单阻力模型（适用于多旋翼截击机）

在 `base_link` 上添加线性阻力：

```xml
<link name="base_link">
  <!-- 已有的 inertial/visual/collision 定义 -->

  <!-- 添加气动阻力 -->
  <enable_wind>true</enable_wind>
</link>
```

配合世界文件中的 `WindEffects` 插件（PR #130，2026 年 1 月合入）提供基础风场效应。但这只是被动风阻，不含速度相关的阻力模型。

更精确的做法是在自定义 Gazebo 插件中实现：

$$\mathbf{F}_{drag} = -\frac{1}{2} \rho \mathbf{v} |\mathbf{v}| \cdot C_D \cdot A_{ref}$$

#### 方案 B：AdvancedLiftDrag 插件（适用于 VTOL/Tailsitter 截击机）

如果截击机有固定翼面或升力体（如 Zerov-8 类 Tailsitter 构型），需要配置升力-阻力特性：

```xml
<plugin filename="gz-sim-advanced-lift-drag-system"
        name="gz::sim::systems::AdvancedLiftDrag">
  <link_name>wing</link_name>
  <air_density>1.2041</air_density>
  <area>0.12</area>              <!-- 翼面面积 m² -->
  <forward>1 0 0</forward>      <!-- 前进方向 -->
  <upward>0 0 1</upward>        <!-- 升力方向 -->
  <cla>4.752</cla>              <!-- 升力线斜率 dCL/dα [1/rad] -->
  <cda>0.6417</cda>             <!-- 阻力系数随攻角变化 -->
  <alpha_stall>0.3391</alpha_stall>  <!-- 失速攻角 [rad] -->
  <cla_stall>-3.85</cla_stall>
  <cda_stall>-0.9233</cda_stall>
  <cp>0 0 0.05</cp>             <!-- 压力中心 -->
</plugin>
```

### 4.5 传感器配置

截击机仿真通常需要以下传感器：

```xml
<!-- IMU -->
<sensor name="imu_sensor" type="imu">
  <always_on>true</always_on>
  <update_rate>250</update_rate>
  <imu>
    <angular_velocity>
      <x><noise type="gaussian"><stddev>0.009</stddev></noise></x>
      <y><noise type="gaussian"><stddev>0.009</stddev></noise></y>
      <z><noise type="gaussian"><stddev>0.009</stddev></noise></z>
    </angular_velocity>
    <linear_acceleration>
      <x><noise type="gaussian"><stddev>0.14</stddev></noise></x>
      <y><noise type="gaussian"><stddev>0.14</stddev></noise></y>
      <z><noise type="gaussian"><stddev>0.14</stddev></noise></z>
    </linear_acceleration>
  </imu>
</sensor>

<!-- 前向摄像头（用于视觉制导的截击机） -->
<sensor name="front_camera" type="camera">
  <always_on>true</always_on>
  <update_rate>30</update_rate>
  <camera>
    <horizontal_fov>1.047</horizontal_fov>  <!-- 60° -->
    <image>
      <width>640</width>
      <height>480</height>
    </image>
    <clip><near>0.1</near><far>1000</far></clip>
  </camera>
</sensor>
```

---

## 五、阶段三：PX4 机架配置

### 5.1 创建机架文件

在 `PX4-Autopilot/ROMFS/px4fmu_common/init.d-posix/airframes/` 下创建新文件：

```bash
#!/bin/sh
#
# @name Interceptor Quadrotor
# @type Quadrotor x
# @class Copter
#
# @maintainer Your Name <your@email.com>
#

. ${R}etc/init.d/rc.mc_defaults

PX4_SIMULATOR=${PX4_SIMULATOR:=gz}
PX4_GZ_WORLD=${PX4_GZ_WORLD:=default}
PX4_SIM_MODEL=${PX4_SIM_MODEL:=interceptor}

# === 控制分配：电机几何 ===
param set-default CA_AIRFRAME 0          # 0=多旋翼
param set-default CA_ROTOR_COUNT 4

# 电机 0：右前（CCW）—— 位置相对重心 [m]
param set-default CA_ROTOR0_PX 0.18
param set-default CA_ROTOR0_PY -0.22
param set-default CA_ROTOR0_KM 0.05      # 力矩系数（CCW 正值）

# 电机 1：左后（CCW）
param set-default CA_ROTOR1_PX -0.18
param set-default CA_ROTOR1_PY 0.22
param set-default CA_ROTOR1_KM 0.05

# 电机 2：右后（CW）
param set-default CA_ROTOR2_PX -0.18
param set-default CA_ROTOR2_PY -0.22
param set-default CA_ROTOR2_KM -0.05     # CW 负值

# 电机 3：左前（CW）
param set-default CA_ROTOR3_PX 0.18
param set-default CA_ROTOR3_PY 0.22
param set-default CA_ROTOR3_KM -0.05

# === 电机输出映射 ===
param set-default PWM_MAIN_FUNC1 101     # Motor 1
param set-default PWM_MAIN_FUNC2 102     # Motor 2
param set-default PWM_MAIN_FUNC3 103     # Motor 3
param set-default PWM_MAIN_FUNC4 104     # Motor 4

# === 截击机专用参数调整 ===
# 解除速度限制（默认 12 m/s 太低）
param set-default MPC_XY_VEL_MAX 50.0    # 水平最大速度 [m/s]
param set-default MPC_Z_VEL_MAX_UP 20.0  # 最大上升速度
param set-default MPC_Z_VEL_MAX_DN 15.0  # 最大下降速度

# 悬停油门（根据推重比计算）
# hover_throttle ≈ 1 / 推重比²（粗略估算）
param set-default MPC_THR_HOVER 0.25

# 推力模型因子（补偿电池电压下降）
param set-default THR_MDL_FAC 0.3

# 阻力系数（用于 EKF2 速度估计）
param set-default EKF2_BCOEF_X 25.0      # X 轴弹道系数
param set-default EKF2_BCOEF_Y 25.0      # Y 轴弹道系数

# === 安全参数（截击机需要修改） ===
param set-default COM_DISARM_LAND -1     # 禁用着陆后自动解锁
param set-default NAV_DLL_ACT 0          # 数据链丢失：不执行返航
param set-default NAV_RCL_ACT 0          # 遥控丢失：不执行返航
param set-default COM_OBL_RC_ACT 0       # Offboard 丢失：位置保持
```

### 5.2 注册机架到编译系统

在 `PX4-Autopilot/ROMFS/px4fmu_common/init.d-posix/airframes/CMakeLists.txt` 中添加：

```cmake
px4_add_romfs_files(
    # ... 现有机架 ...
    4100_gz_interceptor
)
```

文件名格式：`<ID>_gz_<模型名>`，其中 ID 是唯一的 4-5 位数字。

### 5.3 启动仿真

```bash
cd PX4-Autopilot
make px4_sitl gz_interceptor
```

或使用独立模式（更灵活）：

```bash
PX4_SYS_AUTOSTART=4100 PX4_SIM_MODEL=gz_interceptor \
  ./build/px4_sitl_default/bin/px4
```

---

## 六、阶段四：飞行辨识与参数修正

如果截击机已经可以在真实环境中飞行（哪怕只是手动悬停和简单机动），可以使用飞行数据来辨识和修正仿真参数。这比纯理论计算精确得多。

### 6.1 sysid.tools 工具

sysid.tools [2] 是一个基于 IROS 2024 论文 [3] 的开源在线工具，从 PX4 ULog 飞行日志中辨识四旋翼动力学参数。

**工作原理**：

从牛顿-欧拉方程出发：

$$m \dot{\mathbf{v}} = \mathbf{R}(\mathbf{q}) \sum_{i=1}^{4} f_i \hat{\mathbf{r}}_{f_i} + m\mathbf{g}$$

$$\mathbf{J} \dot{\boldsymbol{\omega}} = \sum_{i=1}^{4} (\mathbf{r}_{p_i} \times f_i \hat{\mathbf{r}}_{f_i} + \tau_i \hat{\mathbf{r}}_{\tau_i}) - \boldsymbol{\omega} \times \mathbf{J} \boldsymbol{\omega}$$

其中 $f_i$ 为第 $i$ 个电机推力，$\tau_i$ 为反扭力矩。

推力曲线参数化为：

$$f_i = k_0 + k_1 u_i + k_2 u_i^2$$

其中 $u_i \in [0, 1]$ 为电机归一化指令。电机响应使用一阶延迟模型：

$$\dot{u}_m = \frac{1}{\tau_m}(u_{cmd} - u_m)$$

sysid.tools 使用**最大后验估计（MAP）**联合求解 $k_0, k_1, k_2, \tau_m$，然后利用角动力学方程辨识惯量矩阵 $\mathbf{J}$ 和力矩系数 $k_M$。

**操作步骤**：

1. **配置高速日志**：

```bash
# 在 PX4 中设置
param set SDLOG_PROFILE 19   # 高速率 + 系统辨识模式
```

需要记录的 uORB 话题：
- `vehicle_acceleration`（50~250 Hz）
- `vehicle_angular_velocity`（250~1000 Hz）
- `actuator_motors`（250 Hz）

2. **执行激励飞行**（约 1 分钟）：

```
飞行 1：推力激励（~20 秒）
├── 悬停状态下快速上拉油门至 80-100%
├── 快速下放油门至 20-30%
├── 重复 3-5 次
└── 目的：覆盖推力曲线全范围

飞行 2：横滚/俯仰激励（~20 秒）
├── 手动模式下快速左右滚转
├── 快速前后俯仰
├── 幅度尽量大（但保持安全）
└── 目的：激励角加速度以辨识 Ixx、Iyy

飞行 3：偏航激励（~20 秒）
├── 手动模式下快速左右偏航
└── 目的：辨识 Izz 和力矩系数
```

3. **下载 ULog 文件**并上传到 [sysid.tools](https://sysid.tools/)（数据仅在浏览器本地处理）

4. **按界面引导选择激励时段**，工具自动输出：
   - 推力曲线参数 $k_0, k_1, k_2$
   - 电机时间常数 $\tau_m$
   - 转动惯量 $I_{xx}, I_{yy}, I_{zz}$
   - 力矩系数 $k_M$

### 6.2 参数回填

将辨识结果转换为 Gazebo SDF 参数：

```python
# 推力曲线 f = k0 + k1*u + k2*u^2
# Gazebo 的 motorConstant 对应二次项：
# T = motorConstant * omega^2
# 其中 omega = u * maxRotVelocity
# 因此：motorConstant = k2 / (maxRotVelocity^2)

motor_constant = k2 / (omega_max ** 2)
moment_constant = k_M  # 直接使用辨识值

# 时间常数直接使用
time_constant_up = tau_m   # 辨识值
time_constant_down = tau_m * 1.5  # 减速通常更慢
```

将辨识得到的惯量更新到 SDF：

```xml
<inertia>
  <ixx>辨识得到的 Ixx</ixx>
  <iyy>辨识得到的 Iyy</iyy>
  <izz>辨识得到的 Izz</izz>
</inertia>
```

---

## 七、阶段五：定量验证

参数填入后，必须做**仿真-真实对比验证**，量化 Sim-to-Real Gap。

### 7.1 验证测试矩阵

| 测试项 | 方法 | 合格指标 |
|--------|------|---------|
| 悬停油门 | 仿真与真机悬停时的油门百分比对比 | 误差 <5% |
| 横滚阶跃响应 | 给定 30° 横滚指令，对比角速率曲线 | 上升时间误差 <15%，超调量误差 <20% |
| 俯仰阶跃响应 | 同上 | 同上 |
| 偏航阶跃响应 | 给定 90° 偏航指令，对比偏航速率 | 稳态速率误差 <10% |
| 直线加速 | 从悬停到全速前飞，对比加速度曲线 | 最大速度误差 <10% |
| 8 字轨迹跟踪 | 同一航点序列，对比位置跟踪误差 | RMSE <0.5 m |
| 最大速度飞通 | 全速飞行 100 m 直线，对比速度曲线 | 误差 <10% |

### 7.2 对比分析工具

PX4 提供了 Flight Review 工具进行日志可视化：

```bash
# 仿真日志在 PX4-Autopilot/build/px4_sitl_default/rootfs/log/ 下
# 真机日志从飞控 SD 卡导出

# 上传到 Flight Review 对比
# https://review.px4.io/
```

也可以用 PlotJuggler 做精细对比：

```bash
sudo apt install ros-humble-plotjuggler-ros
plotjuggler
# 同时加载仿真和真机的 .ulg 文件，叠加对比曲线
```

### 7.3 常见偏差原因与修正

| 现象 | 可能原因 | 修正方法 |
|------|---------|---------|
| 仿真悬停油门偏高 | 推力常数 $k_T$ 偏小 | 增大 SDF 中 `motorConstant` |
| 仿真悬停油门偏低 | 推力常数 $k_T$ 偏大或质量偏小 | 减小 `motorConstant` 或校准质量 |
| 仿真横滚响应过快 | $I_{xx}$ 偏小 | 增大 SDF 中 `<ixx>` |
| 仿真偏航响应过慢 | 力矩系数 $k_M$ 偏小 | 增大 `momentConstant` |
| 仿真最大速度偏高 | 阻力模型缺失或偏小 | 添加/增大气动阻力系数 |
| 仿真电机响应太灵敏 | 时间常数太小 | 增大 `timeConstantUp/Down` |

**迭代修正**：每次只调一个参数，运行对比测试，确认改善后再调下一个。典型需要 3-5 轮迭代。

---

## 八、阶段六：域随机化与鲁棒性验证

即使仿真模型已经高度对齐，仍然存在不可建模的不确定性。**域随机化（Domain Randomization, DR）**的目标是让制导算法在参数扰动下依然可靠。

### 8.1 随机化参数范围

| 参数 | 标称值来源 | 随机化范围 | 物理原因 |
|------|----------|-----------|---------|
| 质量 $m$ | 称量 | ±10% | 不同电池重量、载荷变化 |
| 转动惯量 $I_{xx}, I_{yy}, I_{zz}$ | 辨识 | ±15% | 重心偏移、装配误差 |
| 推力常数 $k_T$ | 台架 | ±10% | 螺旋桨磨损、空气密度变化 |
| 力矩系数 $k_M$ | 辨识 | ±20% | 桨叶气动不确定性 |
| 电机时间常数 $\tau$ | 辨识 | ±30% | 温度、电池电压、ESC 响应 |
| 阻力系数 $C_D$ | 估算 | ±30% | 外形不确定性、附件影响 |
| 风速 | 0 | 0~10 m/s 均匀分布 | 外场风况不可预测 |
| 风向 | 0 | 0~360° 均匀分布 | 同上 |
| IMU 噪声 | 标称 | ×0.5~×2.0 | 真实传感器噪声通常更大 |
| GPS 精度 | 标称 | HDOP 1.0~3.0 | 多径效应、遮挡 |
| 目标速度 | 任务定义 | ±20% | 目标机动不确定性 |
| 目标机动策略 | 直线 | 直线/蛇形/随机转弯 | 非合作目标 |

### 8.2 蒙特卡洛仿真流程

```python
# 伪代码：蒙特卡洛截击仿真
import numpy as np

N_TRIALS = 1000
results = []

for trial in range(N_TRIALS):
    # 随机化参数
    mass = nominal_mass * np.random.uniform(0.9, 1.1)
    Ixx = nominal_Ixx * np.random.uniform(0.85, 1.15)
    kT = nominal_kT * np.random.uniform(0.9, 1.1)
    wind_speed = np.random.uniform(0, 10)
    wind_dir = np.random.uniform(0, 2*np.pi)
    target_speed = nominal_target_speed * np.random.uniform(0.8, 1.2)

    # 动态修改 SDF 参数（通过模板渲染）
    generate_sdf(mass, Ixx, kT, ...)

    # 启动仿真（加速运行）
    # PX4_SIM_SPEED_FACTOR=5 ./run_sim.sh
    result = run_intercept_simulation(
        interceptor_params=...,
        target_params=...,
        wind=(wind_speed, wind_dir)
    )

    results.append({
        'hit': result.miss_distance < 1.0,  # 1m 以内算命中
        'miss_distance': result.miss_distance,
        'intercept_time': result.time,
        'params': {mass, Ixx, kT, wind_speed, ...}
    })

# 统计分析
hit_rate = sum(r['hit'] for r in results) / N_TRIALS
mean_miss = np.mean([r['miss_distance'] for r in results])
p95_miss = np.percentile([r['miss_distance'] for r in results], 95)

print(f"命中率: {hit_rate*100:.1f}%")
print(f"平均脱靶量: {mean_miss:.2f} m")
print(f"95% 脱靶量: {p95_miss:.2f} m")
```

### 8.3 Gazebo 中的风场注入

使用 Gazebo 的 WindEffects 插件（需要 Gazebo Jetty 或带有 PR #130 的 Harmonic）：

```bash
# 在仿真运行时动态设置风速
gz topic -t "/world/default/wind/" -m gz.msgs.Wind \
  -p "linear_velocity: {x:8.0, y:3.0, z:0}, enable_wind: true"
```

在蒙特卡洛脚本中，每次试验前发布不同的风场参数即可。

### 8.4 合格标准

| 指标 | 合格标准 | 含义 |
|------|---------|------|
| 命中率（1m 内） | >90% | 在 1000 次随机化仿真中 |
| 95% 脱靶量 | <2m | 95% 的情况下脱靶量不超过此值 |
| 最差情况脱靶量 | <5m | 分析极端参数组合的影响 |
| 全工况覆盖率 | 100% | 所有速度/角度/风况组合都有测试 |

如果不满足标准，需要回到制导算法设计层面提升鲁棒性（增大导引比、增加自适应补偿等），而非单纯调整仿真参数。

---

## 九、进阶：截击机特有的建模挑战

### 9.1 高速前飞时的螺旋桨效率衰减

多旋翼螺旋桨在高速前飞时，由于进动比（advance ratio）增大，推力效率显著下降。Gazebo 默认的 MulticopterMotorModel **没有**建模这个效应。

进动比定义：

$$J = \frac{V_{\infty}}{n \cdot D}$$

其中 $V_{\infty}$ 为前飞速度，$n$ 为转速（rev/s），$D$ 为桨径。

当 $J > 0.1$ 时，推力系数开始下降。对于 10 寸桨在 100 m/s 前飞时，$J$ 可能达到 0.5 以上，推力可能衰减至静推力的 50% 以下。

**解决方案**：编写自定义 Gazebo 插件，将推力计算修正为：

$$T = k_T \cdot \omega^2 \cdot \eta(J)$$

其中 $\eta(J)$ 为效率修正因子，从螺旋桨性能数据（如 UIUC 螺旋桨数据库）查表插值获得。

### 9.2 碰撞检测与任务判定

截击机仿真的成功标准是**撞上目标**，而非避开障碍物。需要在 Gazebo 中配置碰撞回调：

```xml
<!-- 截击机碰撞体 -->
<collision name="interceptor_collision">
  <geometry>
    <box><size>0.4 0.4 0.15</size></box>
  </geometry>
</collision>

<!-- 目标机碰撞体 -->
<collision name="target_collision">
  <geometry>
    <box><size>0.6 0.6 0.2</size></box>
  </geometry>
</collision>
```

通过 Gazebo 的 Contact Sensor 或 gz-transport 话题检测碰撞事件，记录碰撞时刻的相对速度、角度等。

### 9.3 电池放电模型

截击机在大油门状态下电池放电极快，电压下降导致推力衰减。PX4 内置了电池补偿（`THR_MDL_FAC` 参数），但仿真中需要匹配：

```bash
# PX4 电池参数
param set-default BAT1_N_CELLS 6     # 6S 电池
param set-default BAT1_V_CHARGED 4.2 # 单节满电电压
param set-default BAT1_V_EMPTY 3.5   # 单节截止电压
param set-default BAT1_CAPACITY 2200 # 容量 mAh
```

---

## 十、完整文件结构参考

```
PX4-Autopilot/
├── ROMFS/px4fmu_common/init.d-posix/airframes/
│   └── 4100_gz_interceptor          # PX4 机架配置
│
├── Tools/simulation/gz/models/
│   ├── interceptor/
│   │   └── model.sdf               # 主模型文件
│   └── interceptor_base/
│       ├── model.sdf               # 基础模型（几何/惯性）
│       └── meshes/
│           ├── interceptor_body.stl # 机体 3D 网格
│           └── propeller.stl       # 螺旋桨 3D 网格
│
└── Tools/simulation/gz/worlds/
    └── intercept_test.sdf           # 自定义截击测试世界
```

---

## 参考文献

1. Gazebo MulticopterMotorModel 源码，gazebosim/gz-sim，[GitHub](https://github.com/gazebosim/gz-sim/tree/gz-sim7/src/systems/multicopter_motor_model)
2. sysid.tools — System Identification Utility for Quadrotors，[在线工具](https://sysid.tools/)
3. J. Eschmann, D. Albani, G. Loianno, "Data-Driven System Identification of Quadrotors Subject to Motor Delays," *IEEE/RSJ IROS 2024*，[arXiv:2404.07837](https://arxiv.org/abs/2404.07837)
4. PX4 官方文档 — Adding a Frame Configuration，[docs.px4.io](https://docs.px4.io/main/en/dev_airframes/adding_a_new_frame)
5. PX4 Gazebo Models 仓库，[GitHub](https://github.com/PX4/PX4-gazebo-models)
6. PX4 官方文档 — Gazebo Simulation，[docs.px4.io](https://docs.px4.io/main/en/sim_gazebo_gz/)
7. PX4 官方文档 — MC Filter Tuning & Control Latency，[docs.px4.io](https://docs.px4.io/main/en/config_mc/filter_tuning.html)
8. "Bridging Theory and Simulation: Parametric Identification and Validation for a Multirotor UAV in PX4—Gazebo," *MDPI Engineering Proceedings*, 2025，[DOI](https://doi.org/10.3390/engproc2025115012)
9. PX4 Control Allocation 参数定义，module.yaml，[GitHub](https://github.com/PX4/PX4-Autopilot/blob/main/src/modules/control_allocator/module.yaml)
10. R. Busetto et al., "Nonlinear System Identification for a Nano-drone Benchmark," *Control Engineering Practice*, 2026，[ScienceDirect](https://doi.org/10.1016/j.conengprac.2026.106871)
11. UIUC Propeller Data Site — 螺旋桨性能数据库，[UIUC](https://m-selig.ae.illinois.edu/props/propDB.html)
12. Gazebo WindEffects 插件 PR #130，PX4-gazebo-models，[GitHub](https://github.com/PX4/PX4-gazebo-models/pull/130)
