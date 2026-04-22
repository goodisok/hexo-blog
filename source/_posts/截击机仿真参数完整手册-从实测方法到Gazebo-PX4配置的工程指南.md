---
title: 截击机仿真参数完整手册：从实测方法到 Gazebo-PX4 配置的工程指南
date: 2026-04-22 18:00:00
categories:
  - 无人机
  - 仿真
tags:
  - 截击机
  - 仿真参数
  - 系统辨识
  - Gazebo
  - PX4
  - 转动惯量
  - 推力系数
  - 气动阻力
  - 三线摆
  - 测功台
  - SDF
  - MulticopterMotorModel
  - Sim-to-Real
  - 数字孪生
mathjax: true
---

> 截击机仿真的核心矛盾：参数不准，仿真就是在骗自己。但截击机不是实验室里的标准件——机体里塞满了 RK3588 计算板、数字图传模块、PX4 飞控板、电池和各种线缆，每一台的质量分布都不完全一样。本文基于多篇学术论文和工程实践，系统阐述截击机仿真所需的全部参数、每个参数的实测方法、以及如何填入 Gazebo + PX4 SITL 仿真框架。

---

## 一、参数体系总览

截击机仿真需要的参数可以按用途分为六层：

```
┌──────────────────────────────────────────────────┐
│  第六层：环境参数（风场、空气密度）                 │
├──────────────────────────────────────────────────┤
│  第五层：目标无人机参数（尺寸、速度、机动模式）     │
├──────────────────────────────────────────────────┤
│  第四层：感知参数（相机、雷达、检测算法）           │
├──────────────────────────────────────────────────┤
│  第三层：飞控与制导参数（PID、制导律、约束）        │
├──────────────────────────────────────────────────┤
│  第二层：动力系统参数（推力系数、扭矩系数、电机）   │  ← 仿真精度的核心
├──────────────────────────────────────────────────┤
│  第一层：刚体参数（质量、惯量、质心、几何）         │  ← 仿真精度的基础
└──────────────────────────────────────────────────┘
```

**关键认知**：仿真精度 80% 取决于第一层和第二层参数。传感器噪声、风场等高层参数的影响相对次要，可以先用默认值启动仿真，后续迭代优化。

---

## 二、第一层：刚体参数

### 2.1 整机质量

**填写位置**：SDF 文件 `<link><inertial><mass>`

**测量方法**：电子秤直接称重。

**关键要求**：必须是**完全装配状态**下的质量，包括：

- 机架结构件
- 全部电机和螺旋桨
- 电池（你实际使用的那块）
- PX4 飞控板 + 减震座
- RK3588 计算板 + 散热器
- 数图传模块 + 天线
- 所有线缆（电源线、信号线、USB、天线馈线）
- 紧固件（螺丝、螺母、扎带、热缩管、双面胶）
- 起落架 / 保护罩（如果有）

> **经验数据**：很多团队低估线缆和紧固件的质量。对于 3-5 kg 级多旋翼，这些"杂项"通常占总质量的 5-10%，即 150-500g，不可忽略。

### 2.2 质心位置

**填写位置**：SDF 文件 `<link><inertial><pose>`（质心相对于 link 原点的偏移）

**为什么 CAD 不够可靠**：CAD 模型中通常不包含线缆走线路径、扎带位置、胶水残留等。电池作为最重单体（占总质量 30-50%），其安装位置在 CAD 中可能与实际装配偏差 5-15mm，这会显著影响质心。Krznar 等人 [1] 的实验表明，即使精心建模的 CAD 与实测惯量也存在 8-15% 的偏差。

**推荐方法：称重法（Weighing Method）**

将飞行器放在 3-4 个精密电子秤上，通过力矩平衡计算质心：

```
           秤₁ (F₁)                     秤₂ (F₂)
            │                             │
  ──────────┼──────── ★ (质心) ──────────┼──────────
            │       x_cg                  │
          ←─ d₁ ──→  ←──── d₂ ──→
```

对于四旋翼，在四个电机位置下方各放一个秤：

$$x_{cg} = \frac{\sum_i F_i \cdot x_i}{\sum_i F_i}, \quad y_{cg} = \frac{\sum_i F_i \cdot y_i}{\sum_i F_i}$$

其中 $F_i$ 是第 $i$ 个秤的读数，$(x_i, y_i)$ 是第 $i$ 个秤的位置坐标。

Z 方向质心（高度方向）可通过将飞行器侧放再次称重获得，或用悬挂法。

**精度**：称重法可达 **±1-2mm**，远超 CAD 估算。

**实际意义**：如果质心不在电机平面的几何中心正上方，飞控需要在悬停时持续输出差分推力来补偿，消耗控制余量。可以通过调整电池前后位置来微调质心，让补偿量最小化。

### 2.3 转动惯量

**填写位置**：SDF 文件 `<link><inertial><inertia>`

```xml
<inertia>
  <ixx>0.029</ixx>
  <iyy>0.029</iyy>
  <izz>0.055</izz>
  <ixy>0</ixy>
  <ixz>0</ixz>
  <iyz>0</iyz>
</inertia>
```

转动惯量是仿真中**最难准确获取但对动态响应影响最大的参数**。它决定了飞行器在给定力矩下的角加速度响应：

$$\dot{\omega} = I^{-1} (\tau - \omega \times I\omega)$$

惯量偏大 → 仿真中飞行器响应迟钝；惯量偏小 → 响应过于灵敏。对于追求高机动性的截击机，惯量误差直接影响 PID 调参和制导算法验证的可靠性。

#### 方法一：三线摆（Trifilar Pendulum） — 推荐

三线摆是多旋翼转动惯量测量的工业标准方法，被 NASA、多所大学和无人机厂商广泛使用 [2][3]。

**原理**：将被测物体悬挂在三根等长线上，使其绕垂直轴扭转振荡。通过测量振荡周期计算转动惯量。

```
            固定框架
          ╱    │    ╲
         ╱     │     ╲
     线₁       线₂      线₃
         ╲     │     ╱
          ╲    │    ╱
          ┌────┴────┐
          │ 被测飞行器 │  ←→ 扭转振荡
          └─────────┘
```

$$I_z = \frac{m g R^2 T^2}{4 \pi^2 L}$$

- $m$：被测物质量 (kg)
- $g$：重力加速度 (9.81 m/s²)
- $R$：悬挂点到旋转轴的距离 (m)
- $T$：扭转振荡周期 (s)
- $L$：悬挂线长度 (m)

**测量** $I_{xx}$ **和** $I_{yy}$：将飞行器旋转 90° 重新悬挂。对于对称四旋翼通常 $I_{xx} \approx I_{yy}$。

**操作要点**：

1. 使用不可伸缩的细线（钓鱼线、钢丝）
2. 初始扭转角度不超过 10°（保持小角度近似有效）
3. 测量 20 个以上完整周期取平均（减少误差）
4. 可以用飞行器自身 IMU 记录角速率数据，通过 FFT 提取周期 [1]
5. 先测空平台的惯量作为校验

**精度**：三线摆实测精度可达 **±3-5%** [2][3]，远好于 CAD 估算的 ±15-30%。

#### 方法二：双线摆（Bifilar Pendulum)

双线摆原理类似，适合测量绕特定轴的惯量：

$$I = \frac{m g d^2 T^2}{16 \pi^2 h}$$

- $d$：两线间距 (m)
- $h$：线长 (m)

Krznar 等人 [1] 展示了使用机载 IMU 传感器在线估计惯量的方法，可以在不拆机的情况下得到结果。

#### 方法三：飞行数据辨识

Eschmann 等人 [4] 提出了纯数据驱动的系统辨识方法：只需约 1 分钟的飞行数据（含三个简单机动动作），就能通过 MAP（最大后验概率）估计方法恢复惯量、推力曲线、扭矩系数和电机延迟。这个方法不需要任何额外设备。

适用于：已经能飞但想精调仿真参数的阶段。

#### 惯量积 $I_{xy}, I_{xz}, I_{yz}$

对于几何对称的多旋翼布局，惯量积理论上为零。实际中由于内部组件不完全对称会存在小量偏差，但其对飞行动力学的影响很小（通常 < 1%），仿真中可以设为 0。

---

## 三、第二层：动力系统参数

### 3.1 推力系数 $k_T$（motorConstant）

**填写位置**：SDF `<plugin> <motorConstant>`

**物理含义**：单个电机-螺旋桨组合产生的推力与转速平方的比例系数。

$$T = k_T \cdot \omega^2$$

其中 $T$ 为推力 (N)，$\omega$ 为角速度 (rad/s)。

**这是整个仿真中最关键的单个参数**。它直接决定了悬停油门、最大推力、推重比等核心性能。

#### 测量方法：测功台（Thrust Stand）

使用专用测功台（如 Tyto Robotics Series 1580/1585、RCbenchmark）或自制悬臂秤：

```
        电调 ──► 电机+桨
                   │
        力传感器 ──┤
                   │
        固定支架 ──┘

从 0% 到 100% 油门，每隔 10% 记录：
- PWM 值
- 转速 ω (RPM → rad/s)
- 推力 T (g → N)
- 扭矩 Q (如果能测)
- 电流 I (A)
- 电压 V (V)
```

数据处理：

```python
import numpy as np
from scipy.optimize import curve_fit

# 测功台数据 (示例)
omega_rad = np.array([...])  # rad/s
thrust_N  = np.array([...])  # N

# 拟合 T = kT * omega^2
def thrust_model(omega, kT):
    return kT * omega**2

popt, pcov = curve_fit(thrust_model, omega_rad, thrust_N)
kT = popt[0]
print(f"motorConstant (kT) = {kT:.6e} N/(rad/s)^2")
```

**没有测功台的替代方案**：

1. **厂家数据表**：许多电机厂商提供推力-转速表（如 T-Motor、KDE），可以直接用于拟合 $k_T$。需要注意数据表条件（电压、海拔）与你的实际使用条件一致。

2. **UIUC 螺旋桨数据库**：[m-selig.ae.illinois.edu/props/propDB.html](https://m-selig.ae.illinois.edu/props/propDB.html) 包含大量螺旋桨的风洞测试数据（$C_T$, $C_Q$ vs 前进比 $J$），可以根据你的桨型号查找。

3. **悬臂秤 DIY 测试**：将电机固定在杆的一端，杆的支点在中间，另一端放在秤上。已知力臂长度即可从秤的读数计算推力。精度低于专业测功台但可用。

> **SDF 中的 motorConstant 数值量级**：对于常见 5 英寸桨，$k_T$ 约 $8 \times 10^{-6}$ N/(rad/s)²；对于 13-15 英寸桨（截击机级别），$k_T$ 约 $1 \times 10^{-4}$ 到 $5 \times 10^{-4}$ N/(rad/s)²。如果你填的值和这个量级差很多，需要检查单位。

### 3.2 扭矩系数 $k_Q$（momentConstant）

**填写位置**：SDF `<plugin> <momentConstant>`

**物理含义**：单个电机-螺旋桨组合产生的反扭矩与转速平方的比例系数。

$$Q = k_Q \cdot \omega^2$$

反扭矩是偏航控制的来源：CW 旋转的桨产生 CCW 扭矩，反之亦然。通过差分控制对角线电机组的扭矩实现偏航。

**注意**：Gazebo MulticopterMotorModel 中的 `momentConstant` 实际上是 $k_Q / k_T$ 的比值（无量纲），即：

$$\text{momentConstant} = \frac{k_Q}{k_T} = \frac{Q}{T}$$

单位为 m（因为 $Q$ [N·m] ÷ $T$ [N] = m）。

**测量方法**：

1. **测功台直接测量**：如果测功台能同时测量推力和扭矩，直接从数据中拟合 $k_Q$
2. **从螺旋桨数据计算**：

$$k_T = C_T \rho D^4, \quad k_Q = C_Q \rho D^5$$

$$\text{momentConstant} = \frac{C_Q \cdot D}{C_T}$$

其中 $C_T$、$C_Q$ 为螺旋桨推力和扭矩系数（无量纲），$D$ 为桨直径 (m)。

3. **经验估算**：对于常见螺旋桨，$k_Q/k_T$ 比值通常在 0.01-0.06 m 范围内。Martins 等人 [5] 在其 PX4-Gazebo 数字孪生工作中，通过厂家数据表直接拟合得到该比值。

### 3.3 最大转速 $\omega_{max}$（maxRotVelocity）

**填写位置**：SDF `<plugin> <maxRotVelocity>`，单位 **rad/s**

$$\omega_{max} = \frac{K_v \times V_{bat} \times \eta}{60} \times 2\pi$$

- $K_v$：电机 KV 值 (RPM/V)，来自电机规格书
- $V_{bat}$：电池满电电压 (V)
- $\eta$：效率系数（约 0.85-0.95，带载后转速下降）

**验证**：如果有测功台数据，直接取最大油门时的转速。

> **常见错误**：把 RPM 直接填入 SDF 而忘记转换为 rad/s。$1 \text{ RPM} = \frac{2\pi}{60} \approx 0.10472 \text{ rad/s}$。

### 3.4 电机时间常数（timeConstantUp / timeConstantDown）

**填写位置**：SDF `<plugin> <timeConstantUp>` / `<timeConstantDown>`

电机转速不是瞬间到达指令值的，而是遵循一阶系统响应：

$$\dot{\omega} = \frac{1}{\tau}(\omega_{cmd} - \omega)$$

$\tau_{up}$ 为加速时间常数，$\tau_{down}$ 为减速时间常数。减速通常比加速慢（FOC 电调的制动不如加速高效），Martins 等人 [5] 建议 $\tau_{down} \approx 1.2 \times \tau_{up}$。

**测量方法**：

1. **阶跃响应法**：发送阶跃 PWM 指令，用光电转速传感器或声学方法记录转速响应曲线。$\tau$ = 达到 63.2% 稳态值所需的时间。
2. **经验估算**：大多数无刷电机 $\tau_{up}$ 在 0.02-0.05s 范围内。

| 电机尺寸 | 典型 $\tau_{up}$ | 说明 |
|---------|-----------------|------|
| 5 英寸桨 (2204-2306) | 0.01-0.02s | 小桨惯量小 |
| 10-13 英寸桨 (3508-4010) | 0.02-0.04s | 中型 |
| 15-18 英寸桨 (4114-5010) | 0.03-0.06s | 大桨惯量大 |

### 3.5 其他电机插件参数

| SDF 参数 | 含义 | 典型值 | 来源 |
|---------|------|--------|------|
| `rotorDragCoefficient` | 旋翼旋转引起的面内阻力 | $10^{-4}$ ~ $10^{-3}$ | 经验值或保持默认 |
| `rollingMomentCoefficient` | 桨叶铰链处的滚转力矩系数 | $\sim 10^{-6}$ | 通常保持默认 |
| `rotorVelocitySlowdownSim` | 仿真中的转速缩放因子 | 10 | 仿真稳定性用，不影响物理 |

---

## 四、第三层：气动参数

### 4.1 为什么截击机必须考虑气动阻力

普通多旋翼悬停和低速飞行（< 5 m/s）时，气动阻力可以忽略。但截击机追击目标时飞行速度可达 20-60 m/s，此时阻力成为主要的外力：

$$F_{drag} = \frac{1}{2} \rho v^2 C_d A$$

以一个迎风面积 $A = 0.04$ m²、$C_d = 1.0$ 的截击机在 40 m/s 飞行为例：

$$F_{drag} = \frac{1}{2} \times 1.225 \times 40^2 \times 1.0 \times 0.04 = 39.2 \text{ N}$$

对于 3 kg 的截击机（重力 29.4 N），这个阻力已经**超过了自身重力**。如果仿真中忽略阻力，最大速度、加速性能和拦截弹道都会严重失真。

### 4.2 气动阻力系数 $C_d$

Hammer 等人 [6] 通过 CFD（StarCCM+）和 RWTH Aachen 亚音速风洞对多款小型多旋翼进行了系统测试，主要发现：

1. 多旋翼的 $C_d$ 在测试速度范围内（15-70 m/s）**基本不随速度变化**
2. 自由旋转的螺旋桨使阻力**增加高达 110%**
3. 增大机体俯仰角（即前倾飞行姿态）可以**降低阻力 40-85%**

| 配置 | $C_d$ 范围（0° 俯仰） | 说明 |
|------|---------------------|------|
| 机体 + 固定桨 | 0.6-1.2 | 取决于机体外形 |
| 机体 + 自由旋转桨 | 1.2-2.5 | 桨叶自转增加阻力 |
| 机体 + 驱动桨（实际飞行） | 0.8-1.5 | 驱动桨的气流与阻力耦合 |
| 前倾 30°-45°（实际高速飞行） | 0.3-0.8 | 迎风面积减小 |

**获取方法（按可靠性排序）**：

1. **风洞测试**（±5%）：最可靠，但需要设备
2. **CFD 仿真**（±10-20%）：用 OpenFOAM 或 StarCCM+，需要精确的 3D 模型
3. **飞行数据反推**（±10-15%）：从匀速飞行段的 PX4 日志中反推

**飞行数据反推方法**：

在无风环境中让截击机以恒定速度水平飞行（油门固定），从 PX4 日志提取：
- 飞行速度 $v$（GPS 或光流）
- 俯仰角 $\theta$（IMU）
- 总推力 $T$（从油门和推力曲线计算）

匀速飞行时力平衡：

$$T \sin\theta = F_{drag} = \frac{1}{2}\rho v^2 C_d A$$

$$C_d = \frac{2 T \sin\theta}{\rho v^2 A}$$

### 4.3 迎风面积 $A$

迎风面积可以从 CAD 模型中准确获取（投影面积测量对 CAD 模型的精度要求不高）。

对于三轴阻力模型：

| 方向 | 面积来源 | 典型值（5 英寸穿越机级） |
|------|---------|----------------------|
| $A_x$（正面） | 正面投影 | 0.02-0.06 m² |
| $A_y$（侧面） | 侧面投影 | 0.02-0.06 m² |
| $A_z$（顶面） | 俯视投影 | 0.05-0.15 m² |

### 4.4 Gazebo 中配置气动阻力

Gazebo Sim 没有内置的多旋翼机体阻力模型，需要通过自定义 System 插件或使用 `gz-sim-force-system` 添加：

```xml
<!-- SDF 中添加简单阻力 -->
<plugin filename="gz-sim-force-system"
        name="gz::sim::systems::ApplyJointForce">
  <!-- 或通过自定义插件实现 -->
</plugin>
```

更常见的做法是在 PX4 中配置气动参数，或编写一个简单的 Gazebo System 插件计算并施加阻力。

---

## 五、第四层：传感器参数

### 5.1 IMU 参数

| 参数 | SDF 标签 | 典型值（MPU6050 级） | 典型值（ICM-42688-P 级） | 获取方法 |
|------|---------|-------------------|----------------------|---------|
| 加速度计噪声密度 | `noise.stddev` | 0.04 m/s²/√Hz | 0.007 m/s²/√Hz | 数据手册 |
| 陀螺仪噪声密度 | `noise.stddev` | 0.005 °/s/√Hz | 0.002 °/s/√Hz | 数据手册 |
| 加速度计零偏不稳定性 | - | 0.05 mg | 0.02 mg | Allan 方差 |
| 陀螺仪零偏不稳定性 | - | 5 °/hr | 1.5 °/hr | Allan 方差 |

```xml
<!-- SDF IMU 配置 -->
<sensor name="imu_sensor" type="imu">
  <always_on>true</always_on>
  <update_rate>400</update_rate>
  <imu>
    <angular_velocity>
      <x><noise type="gaussian"><mean>0</mean><stddev>0.002</stddev></noise></x>
      <y><noise type="gaussian"><mean>0</mean><stddev>0.002</stddev></noise></y>
      <z><noise type="gaussian"><mean>0</mean><stddev>0.002</stddev></noise></z>
    </angular_velocity>
    <linear_acceleration>
      <x><noise type="gaussian"><mean>0</mean><stddev>0.017</stddev></noise></x>
      <y><noise type="gaussian"><mean>0</mean><stddev>0.017</stddev></noise></y>
      <z><noise type="gaussian"><mean>0</mean><stddev>0.017</stddev></noise></z>
    </linear_acceleration>
  </imu>
</sensor>
```

**实话说**：对于截击机仿真的初始阶段，Gazebo/PX4 的默认 IMU 噪声参数完全够用。IMU 噪声对飞行动力学的影响远小于推力系数和惯量的误差。待仿真与实飞基本对齐后，再根据你实际使用的 IMU 芯片精调。

### 5.2 前视相机参数

这是截击机仿真**区别于普通多旋翼仿真**的关键传感器。参数必须与你的实际相机一致：

| 参数 | SDF 标签 | 必须与实机一致 | 说明 |
|------|---------|-------------|------|
| 分辨率 | `<width>` `<height>` | ✅ | 影响检测距离和精度 |
| 视场角 FOV | `<horizontal_fov>` | ✅ | 影响搜索范围和目标像素大小 |
| 帧率 | `<update_rate>` | ✅ | 影响跟踪时效性 |
| 安装位置 | `<pose>` | ✅ | 相对质心的偏移和朝向 |
| 近/远裁剪 | `<clip><near>` `<far>` | 建议一致 | 渲染范围 |
| 畸变参数 | `<distortion>` | 可选 | 视觉算法若需要可加 |

```xml
<sensor name="front_camera" type="camera">
  <always_on>true</always_on>
  <update_rate>60</update_rate>
  <camera>
    <horizontal_fov>2.094</horizontal_fov>  <!-- 120° -->
    <image>
      <width>1920</width>
      <height>1080</height>
      <format>R8G8B8</format>
    </image>
    <clip>
      <near>0.1</near>
      <far>500</far>
    </clip>
  </camera>
</sensor>
```

### 5.3 GPS 参数

| 参数 | 典型值 | 说明 |
|------|--------|------|
| 更新率 | 10-20 Hz | 多数 GPS 模块的实际能力 |
| 水平精度 CEP | 1.0-2.5 m | RTK 可达 0.02 m |
| 垂直精度 | 2-5 m | 气压计通常更精确 |
| 速度精度 | 0.1-0.3 m/s | GPS 测速精度较高 |

---

## 六、第五层：截击机特有参数

### 6.1 性能包线参数

这些参数定义了截击机的运动能力边界，需要在 PX4 参数中配置：

| 参数 | PX4 参数名 | 普通多旋翼 | 截击机 | 说明 |
|------|-----------|-----------|--------|------|
| 最大倾斜角 | `MPC_TILTMAX_AIR` | 35° | 55-75° | 决定最大水平加速度 |
| 最大 Roll 角速率 | `MC_ROLLRATE_MAX` | 220 °/s | 360-720 °/s | 决定滚转机动性 |
| 最大 Pitch 角速率 | `MC_PITCHRATE_MAX` | 220 °/s | 360-720 °/s | 决定俯仰机动性 |
| 最大 Yaw 角速率 | `MC_YAWRATE_MAX` | 200 °/s | 200-400 °/s | 偏航通常不需要太快 |
| 最大水平速度 | `MPC_XY_VEL_MAX` | 12 m/s | 30-60 m/s | 需要和阻力模型匹配 |
| 最大爬升率 | `MPC_Z_VEL_MAX_UP` | 3 m/s | 10-20 m/s | 取决于推重比 |
| 最大下降率 | `MPC_Z_VEL_MAX_DN` | 1.5 m/s | 5-15 m/s | 追击俯冲时需要 |

### 6.2 推重比验算

截击机的推重比通常要求 > 3:1（普通航拍机约 2:1）：

$$\text{推重比} = \frac{N \times T_{max,single}}{m \times g}$$

其中 $N$ 为电机数量，$T_{max,single} = k_T \times \omega_{max}^2$。

推重比决定了最大可用加速度：

$$a_{max,horizontal} = g \times \tan(\theta_{max})$$

$$a_{max,vertical} = g \times (\text{推重比} - 1)$$

### 6.3 制导律参数

如果截击机使用比例导引（Proportional Navigation）制导律，需要配置：

| 参数 | 符号 | 典型值 | 说明 |
|------|------|--------|------|
| 导引比 | $N$ | 3-5 | $N=3$ 是经典值，更大的 $N$ 追击更激进但对噪声更敏感 |
| 截获判定半径 | $r_{kill}$ | 0.5-3.0 m | 弹目距离小于此值判定拦截成功 |
| 最大视线角速率 | $\dot\lambda_{max}$ | - | 受限于传感器 FOV 和跟踪算法 |

---

## 七、第六层：环境与目标参数

### 7.1 风场

```xml
<!-- Gazebo Sim 风场插件 -->
<plugin filename="gz-sim-wind-effects-system"
        name="gz::sim::systems::WindEffects">
  <force_approximation_scaling_factor>1.0</force_approximation_scaling_factor>
  <horizontal>
    <magnitude>
      <time_for_rise>10</time_for_rise>
      <sin><amplitude_percent>0.1</amplitude_percent><period>60</period></sin>
      <noise type="gaussian"><mean>0</mean><stddev>0.5</stddev></noise>
    </magnitude>
    <direction>
      <time_for_rise>30</time_for_rise>
      <sin><amplitude>0.1</amplitude><period>120</period></sin>
      <noise type="gaussian"><mean>0</mean><stddev>0.05</stddev></noise>
    </direction>
  </horizontal>
  <vertical>
    <noise type="gaussian"><mean>0</mean><stddev>0.1</stddev></noise>
  </vertical>
</plugin>
```

### 7.2 目标无人机模型

仿真中需要一个可控的目标无人机。最简做法是用 Gazebo 中的另一个多旋翼模型，通过脚本控制其飞行轨迹：

| 参数 | 初期简化值 | 进阶值 | 说明 |
|------|-----------|--------|------|
| 目标尺寸 | 0.35-0.5m（DJI Mini 级） | 0.2-1.5m | 决定视觉检测距离 |
| 目标速度 | 5-15 m/s | 10-40 m/s | 从慢到快逐步测试 |
| 目标轨迹 | 直线/悬停 | 蛇形/随机规避 | 从简单到复杂 |
| 目标外观 | 简单立方体 + 桨叶 | 精细 3D 模型 | 影响视觉检测 |

---

## 八、参数获取路线图

### 8.1 优先级矩阵

| 优先级 | 参数 | 对仿真精度影响 | 获取难度 | 所需时间 |
|--------|------|-------------|---------|---------|
| **P0** | 整机质量 $m$ | 极高 | 极低 | 10 分钟 |
| **P0** | 推力系数 $k_T$ | 极高 | 中 | 半天-1天 |
| **P0** | 电机位置 $(x,y,z)$ | 极高 | 低 | 1 小时 |
| **P1** | 转动惯量 $I_{xx},I_{yy},I_{zz}$ | 高 | 中 | 半天 |
| **P1** | 扭矩系数 $k_Q$ | 高 | 中 | 随 $k_T$ 一起测 |
| **P1** | 最大转速 $\omega_{max}$ | 高 | 低 | 随 $k_T$ 一起测 |
| **P1** | 质心位置 | 高 | 低 | 1 小时 |
| **P2** | 电机时间常数 $\tau$ | 中 | 中 | 2 小时 |
| **P2** | 前视相机参数 | 中（感知层面高） | 低 | 查手册 |
| **P3** | 气动阻力 $C_d$ | 中（高速时高） | 高 | 需实飞 |
| **P3** | IMU 噪声参数 | 低 | 低 | 查手册 |
| **P4** | 风场参数 | 低 | - | 用默认值 |
| **P4** | 电池放电曲线 | 低（短时任务） | 低 | 可忽略 |

### 8.2 实操步骤

```
阶段一：最小可用仿真（1-2 天）
  ├── 称重 → m
  ├── 量电机位置 → (x,y,z)
  ├── 查电机数据表或测功台 → kT, kQ, ωmax
  ├── 用 CAD 估算惯量 → Ixx, Iyy, Izz（粗估）
  ├── 建 SDF → 跑 Gazebo + PX4 SITL
  └── 验证：能悬停、能定点飞 → ✅

阶段二：提升精度（2-3 天）
  ├── 三线摆测惯量 → 修正 Ixx, Iyy, Izz
  ├── 称重法测质心 → 修正质心偏移
  ├── 测电机阶跃响应 → τ_up, τ_down
  ├── 配置前视相机参数
  ├── 加入目标无人机模型
  └── 验证：高速飞行响应合理 → ✅

阶段三：Sim-to-Real 闭环（持续迭代）
  ├── 实飞 → 采集 PX4 日志
  ├── 对比仿真 vs 实飞的姿态/速度响应
  ├── 飞行数据辨识 → 修正全部参数 [4]
  ├── 高速飞行反推阻力 → 修正 Cd
  ├── 添加风场模型
  └── 验证：仿真与实飞行为一致 → ✅
```

---

## 九、SDF 模型文件完整示例

以下是一个截击机的 SDF 模型骨架，标注了每个参数的来源：

```xml
<?xml version="1.0"?>
<sdf version="1.9">
  <model name="interceptor_x500">
    <pose>0 0 0.24 0 0 0</pose>

    <!-- 主机体 -->
    <link name="base_link">
      <inertial>
        <!-- P0: 电子秤称重 -->
        <mass>3.2</mass>
        <!-- P1: 称重法实测 -->
        <pose>0.005 -0.003 0.02 0 0 0</pose>
        <!-- P1: 三线摆实测 -->
        <inertia>
          <ixx>0.032</ixx>
          <iyy>0.033</iyy>
          <izz>0.058</izz>
          <ixy>0</ixy>
          <ixz>0</ixz>
          <iyz>0</iyz>
        </inertia>
      </inertial>

      <!-- 碰撞和视觉几何 -->
      <collision name="collision">
        <geometry><box><size>0.4 0.4 0.12</size></box></geometry>
      </collision>
      <visual name="visual">
        <geometry><mesh><uri>model://interceptor/meshes/body.dae</uri></mesh></geometry>
      </visual>

      <!-- 前视相机 -->
      <sensor name="front_camera" type="camera">
        <!-- P2: 查相机手册 -->
        <pose>0.12 0 -0.03 0 0.15 0</pose>
        <always_on>true</always_on>
        <update_rate>60</update_rate>
        <camera>
          <horizontal_fov>2.094</horizontal_fov>
          <image><width>1920</width><height>1080</height></image>
          <clip><near>0.1</near><far>500</far></clip>
        </camera>
      </sensor>

      <!-- IMU -->
      <sensor name="imu" type="imu">
        <always_on>true</always_on>
        <update_rate>400</update_rate>
      </sensor>
    </link>

    <!-- 电机 0: 右前 CW -->
    <link name="rotor_0">
      <pose relative_to="base_link">0.18 -0.18 0.06 0 0 0</pose>
      <inertial>
        <mass>0.015</mass>
        <inertia><ixx>5e-5</ixx><iyy>5e-5</iyy><izz>1e-4</izz></inertia>
      </inertial>
    </link>
    <joint name="rotor_0_joint" type="revolute">
      <parent>base_link</parent><child>rotor_0</child>
      <axis><xyz>0 0 1</xyz></axis>
    </joint>

    <!-- MulticopterMotorModel 插件 (电机 0) -->
    <plugin filename="gz-sim-multicopter-motor-model-system"
            name="gz::sim::systems::MulticopterMotorModel">
      <jointName>rotor_0_joint</jointName>
      <linkName>rotor_0</linkName>
      <turningDirection>cw</turningDirection>

      <!-- P0: 测功台实测 kT -->
      <motorConstant>0.000285</motorConstant>
      <!-- P1: 测功台实测 kQ/kT -->
      <momentConstant>0.0245</momentConstant>
      <!-- P1: 查电机手册 + 电池电压计算 -->
      <maxRotVelocity>1047</maxRotVelocity>
      <!-- P2: 阶跃响应实测 -->
      <timeConstantUp>0.030</timeConstantUp>
      <timeConstantDown>0.036</timeConstantDown>

      <rotorDragCoefficient>5e-4</rotorDragCoefficient>
      <rollingMomentCoefficient>1e-6</rollingMomentCoefficient>
      <rotorVelocitySlowdownSim>10</rotorVelocitySlowdownSim>

      <motorType>velocity</motorType>
      <commandSubTopic>command/motor_speed</commandSubTopic>
    </plugin>

    <!-- 电机 1/2/3 类似配置，修改位置和旋转方向 -->
    <!-- ... -->

  </model>
</sdf>
```

---

## 十、三维模型文件

截击机仿真中三维模型承担两个不可替代的职责：**视觉渲染**和**碰撞检测**。如果要用真实截击机模型进行仿真，需要完成从 CAD 到 SDF 的完整工作流。

### 10.1 模型文件在 SDF 中的角色

SDF 中每个 `<link>` 包含独立的视觉和碰撞几何体：

```xml
<link name="base_link">
  <!-- 渲染用：决定 Gazebo 界面中的外观 -->
  <visual name="body_visual">
    <geometry>
      <mesh>
        <uri>model://interceptor/meshes/body.dae</uri>
        <scale>0.001 0.001 0.001</scale>  <!-- mm → m -->
      </mesh>
    </geometry>
    <material>
      <ambient>0.15 0.15 0.15 1</ambient>
      <diffuse>0.2 0.2 0.2 1</diffuse>
    </material>
  </visual>

  <!-- 碰撞检测用：用简化几何体，计算量小 -->
  <collision name="body_collision">
    <geometry>
      <box><size>0.38 0.38 0.10</size></box>
    </geometry>
  </collision>
</link>
```

**关键原则**：`<visual>` 用精细 mesh 保证外观真实；`<collision>` 用简化的几何体（box / cylinder / 凸包）保证物理引擎计算效率。不要把几十万面的 mesh 直接用于碰撞检测，会严重拖慢仿真速度。

### 10.2 模型制作工作流

```
CAD 软件（SolidWorks / Fusion 360 / FreeCAD）
    │
    │  导出 STEP / IGES
    ▼
Blender / MeshLab（网格处理）
    │
    │  ① 减面（Decimate）：10万面 → 1-3万面
    │  ② 拆分部件：机身、机臂、电机座、起落架 → 独立 mesh
    │  ③ 坐标系对齐：原点 = 质心，Z 轴向上
    │  ④ 单位统一：确认为米制
    │  ⑤ 赋材质/UV（可选，影响外观）
    │
    │  导出 DAE / OBJ / STL
    ▼
Gazebo SDF 引用
```

#### 步骤详解

**① CAD 导出**

从你的机械设计 CAD 中导出整机模型。推荐导出 STEP 格式（精度无损，通用性好）：

- SolidWorks：文件 → 另存为 → `.step`
- Fusion 360：导出 → `.step`
- FreeCAD：文件 → 导出 → `.step`

**② Blender 网格处理**

安装 Blender（免费开源）后导入 STEP（需要 FreeCAD-Blender 桥接，或先用 FreeCAD 转为 `.obj`）：

```
# FreeCAD 命令行转换（批处理）
freecadcmd -c "import Part; Part.open('interceptor.step'); \
  import Mesh; Mesh.export([FreeCAD.ActiveDocument.Objects[0]], 'interceptor.obj')"
```

在 Blender 中进行处理：

- **减面**：选中模型 → Modifier → Decimate → 设置 Ratio 到面数降至 1-3 万。仿真不需要渲染级别的精度，1 万面足以呈现清晰外形
- **拆分部件**：将机身、机臂、电机座拆成独立 mesh 文件。原因是每个电机需要独立的 `<link>` 和旋转关节
- **坐标系**：将原点移到飞行器质心位置（与你实测的质心对齐），Z 轴向上，X 轴向前
- **检查法线**：确保法线朝外（Blender 中 Shift+N 重新计算法线方向），否则渲染会出现面片翻转

**③ 导出格式选择**

| 格式 | 优点 | 缺点 | 推荐场景 |
|------|------|------|---------|
| `.dae`（Collada） | 支持材质、颜色、UV 贴图 | 文件较大 | **首选**，Gazebo 原生支持好 |
| `.obj` + `.mtl` | 简单通用 | 材质支持有限 | 无复杂材质时可用 |
| `.stl` | 最简单 | 无颜色、无材质 | 碰撞几何体或纯形状 |
| `.glb` / `.gltf` | 现代格式，支持 PBR 材质 | Gazebo Sim 较新版本才支持 | Gazebo Harmonic+ |

**④ 文件组织结构**

```
interceptor/
├── model.config          # Gazebo 模型描述文件
├── model.sdf             # SDF 模型定义
└── meshes/
    ├── body.dae           # 机身主体
    ├── arm.dae            # 机臂（可复用，通过 SDF 中 pose 旋转）
    ├── motor_mount.dae    # 电机座
    ├── propeller_cw.dae   # 顺时针螺旋桨
    ├── propeller_ccw.dae  # 逆时针螺旋桨
    ├── landing_gear.dae   # 起落架
    └── camera_housing.dae # 前视相机外壳
```

### 10.3 螺旋桨模型的特殊处理

螺旋桨需要作为独立 `<link>` 挂载在电机关节上，仿真中会旋转：

```xml
<link name="rotor_0">
  <pose relative_to="base_link">0.18 -0.18 0.06 0 0 0</pose>
  <inertial>
    <mass>0.015</mass>
    <inertia>
      <ixx>5e-5</ixx><iyy>5e-5</iyy><izz>1e-4</izz>
    </inertia>
  </inertial>
  <visual name="propeller_visual">
    <geometry>
      <mesh>
        <uri>model://interceptor/meshes/propeller_cw.dae</uri>
      </mesh>
    </geometry>
  </visual>
  <!-- 螺旋桨碰撞用圆柱近似 -->
  <collision name="propeller_collision">
    <geometry>
      <cylinder><radius>0.127</radius><length>0.005</length></cylinder>
    </geometry>
  </collision>
</link>
```

螺旋桨的 **惯量参数** 同样需要填写，它影响电机加减速的动态响应。可以用简单的薄板公式近似：

$$I_{zz,prop} \approx \frac{1}{12} m_{prop} L_{prop}^2$$

其中 $m_{prop}$ 为桨叶质量，$L_{prop}$ 为桨的直径。

### 10.4 目标无人机模型

截击机仿真中同样需要目标无人机的三维模型，尤其是视觉检测算法的验证依赖目标外观的真实性：

- **尺寸必须准确**：决定了不同距离下目标在图像中占多少像素，直接影响检测距离
- **外形轮廓要合理**：YOLO 等检测器学习的是目标的形状特征
- **颜色和材质**：影响不同光照条件下的检测效果

可以从 [Gazebo Fuel](https://app.gazebosim.org/fuel) 搜索现有的无人机模型，或用类似工作流从 CAD 制作。如果目标是常见消费级无人机（如 DJI 系列），网上有大量可用的 3D 模型资源（Sketchfab、GrabCAD）。

### 10.5 常见问题

| 问题 | 原因 | 解决方法 |
|------|------|---------|
| 模型加载后巨大或极小 | CAD 导出单位是 mm，SDF 默认 m | 在 `<mesh>` 中添加 `<scale>0.001 0.001 0.001</scale>` |
| 模型表面黑色 / 透明 | 法线方向反了 | Blender 中 Shift+N 重新计算法线 |
| 仿真巨卡 | 碰撞体用了高面数 mesh | 碰撞用简化几何体，不要用原始 mesh |
| 模型位置偏移 | CAD 原点与 SDF 原点不一致 | Blender 中调整原点到质心 |
| 螺旋桨不转 | joint 类型或轴向配置错误 | 检查 `<joint type="revolute">` 和 `<axis><xyz>` |

---

## 十一、参考文献

1. **Krznar M, Kotarski D, Piljek P, et al.** On-line Inertia Measurement of Unmanned Aerial Vehicles Using On-board Sensors and Bifilar Pendulum. *Engineering Review*, 2018, 38(2): 151-160. [doi:10.30765/er.38.2.4](https://hrcak.srce.hr/file/291022)
2. **Jardin M, Mueller E R.** Optimized Measurements of Unmanned-Air-Vehicle Mass Moment of Inertia with a Bifilar Pendulum. *Journal of Aircraft*, 2009, 46(3): 763-775.
3. **Cieśluk J, Gosiewski Z.** Determining Moments of Inertia of UAV Using Trifilar Pendulum. *Energies*, 2022, 15(19): 7136. [mdpi.com/1996-1073/15/19/7136](https://www.mdpi.com/1996-1073/15/19/7136)
4. **Eschmann J, Albani D, Loianno G.** Data-Driven System Identification of Quadrotors Subject to Motor Delays. arXiv:2404.07837, 2024. [arxiv.org/abs/2404.07837](https://arxiv.org/abs/2404.07837)
5. **Martins A, et al.** Bridging Theory and Simulation: Parametric Identification and Validation for a Multirotor UAV in PX4—Gazebo. *MDPI Engineering Proceedings*, 2025, 115(1): 12. [mdpi.com/2673-4591/115/1/12](https://www.mdpi.com/2673-4591/115/1/12)
6. **Hammer M, et al.** Free Fall Drag Estimation of Small-Scale Multirotor Unmanned Aircraft Systems Using CFD and Wind Tunnel Experiments. *CEAS Aeronautical Journal*, 2024, 15: 269-282. [doi:10.1007/s13272-023-00702-w](https://link.springer.com/article/10.1007/s13272-023-00702-w)
7. **Iz S A, Unel M.** Vision-Based System Identification of a Quadrotor. arXiv:2511.06839, 2025. [arxiv.org/abs/2511.06839](https://arxiv.org/abs/2511.06839)
8. **NASA.** Multirotor Test Bed Second Wind Tunnel Entry (MTB2) Data Report. NASA/TM-20250004795, 2025. [ntrs.nasa.gov](https://rotorcraft.arc.nasa.gov/Publications/files/MTB2_Data_Report_05222025.pdf)
9. **PX4 Gazebo Motor Model 参数讨论**: [github.com/PX4/PX4-SITL_gazebo-classic/issues/1014](https://github.com/PX4/PX4-SITL_gazebo-classic/issues/1014)
10. **MulticopterMotorModel 数学推导**: [github.com/ethz-asl/rotors_simulator/issues/422](https://github.com/ethz-asl/rotors_simulator/issues/422)
11. **PX4 Gazebo 自定义模型指南**: [github.com/Subhaaaash/Guide-to-add-new-model-to-PX4-SITL](https://github.com/Subhaaaash/Guide-to-add-new-model-to-PX4-SITL)
12. **PX4 官方 Gazebo 仿真文档**: [docs.px4.io/main/en/sim_gazebo_gz](https://docs.px4.io/main/en/sim_gazebo_gz/)
