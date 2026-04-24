---
title: 四旋翼动力学仿真验证方法论：Gazebo+PX4 从参数辨识到 97 m/s 阻力模型修正
date: 2026-04-24 00:00:00
categories:
  - 无人机
  - 仿真开发
  - 动力学建模
tags:
  - Sim-to-Real
  - Gazebo
  - PX4
  - 动力学验证
  - RMSE
  - 参数辨识
  - SITL
  - 四旋翼
  - Python
  - ULG
  - 仿真验证
  - 模型校准
  - 设定点回放
  - 高速截击机
---

> **本文做了什么**：在没有实机的前提下，用纯仿真（Gazebo+PX4）把 Sim-to-Real 动力学验证的完整工具链跑通——验证方法本身是否可行、找到方法的能力边界、修复仿真平台在高速下的结构性缺陷。
>
> **三层递进**：
> 1. **方法验证**（0-12 m/s）：用 twin experiment（x500 当"真值"、interceptor 当"仿真"）验证 setpoint replay + k_f 辨识 + 迭代修正这套流程能收敛——4 轮后 Vz RMSE 下降 48%，Pitch RMSE 下降 45%。
> 2. **高速极限诊断**（50-97 m/s）：用 x500_hp 和 Gobi 模型把速度推到 97 m/s，发现 Gazebo 线性阻力模型在 50+ m/s 完全失效（97 m/s 时误差达 4 倍），桨盘前进比效应在 70+ m/s 引入 20-50% 推力偏差。
> 3. **缺陷修复**：开发 `QuadraticDrag` 自定义插件实现物理正确的 v² 阻力，gobi_v2 验证了修复效果（最高速降低 14 m/s，符合推力-阻力平衡预期）。
>
> **核心价值**：这套方法和实机验证的工作流完全一致——外场飞完拿到 ULG → 提取设定点 → 回放到仿真 → 对比响应 → 修正参数。本文在买飞机之前，用纯仿真把整条流水线跑通，同时标明了 Gazebo 在高速域的能力边界和修复方案。
>
> **本文不是**：某一架真实截击机的数字孪生。文中所有模型（x500、interceptor、x500_hp、gobi、gobi_v2）都是方法验证平台，不替代任何特定飞机。文章提供的是方法论、工具链和工程路线图（§13），读者拿到自己的飞机后可以直接复用。

---

## 1. 实验设计

### 1.1 为什么是 Gazebo + PX4

选型逻辑很简单：

- **开源可控**：Gazebo Harmonic + PX4 v1.16.1，SDF 模型参数完全暴露，改一行 XML 就能改质量、惯量、推力系数。
- **Lockstep 同步**：PX4 SITL 与 Gazebo 之间走 lockstep 时间同步，不会出现物理步长漂移——这对动力学对比至关重要，否则两边时间轴对不齐，RMSE 算出来全是噪声。
- **SDF 参数直接映射物理量**：不像某些仿真器把参数藏在二进制配置里，Gazebo 的 SDF 就是一个结构清晰的 XML，`mass`、`inertia`、`motorConstant` 一目了然。

### 1.2 实验架构：设定点回放

```
┌───────────────────────────────────────────────────────────────┐
│                       实验流水线                                │
│                                                               │
│  ┌──────────────┐                                             │
│  │ Step 1: 采集  │                                             │
│  │ Gazebo+PX4   │  fly_mission.py                             │
│  │   x500       │ ──► 标准机动序列                              │
│  │  (真值飞机)   │ ──► x500_truth.ulg                          │
│  └──────┬───────┘                                             │
│         │ 提取 trajectory_setpoint                             │
│         ▼                                                     │
│  ┌──────────────┐                                             │
│  │ Step 2: 回放  │                                             │
│  │ Gazebo+PX4   │  setpoint_replay.py                         │
│  │ interceptor  │ ◄── 回放 x500 的位置/速度设定点                │
│  │ (待校准模型)  │ ──► interceptor_roundN.ulg                   │
│  └──────┬───────┘                                             │
│         │                                                     │
│         ▼                                                     │
│  ┌──────────────┐                                             │
│  │ Step 3: 对比  │                                             │
│  │ compare.py   │ ──► 时间对齐 → RMSE / R² → 对比图            │
│  └──────────────┘                                             │
│                                                               │
│  重复 Step 2-3，每轮修正一组参数，观察收敛                         │
└───────────────────────────────────────────────────────────────┘
```

**关键设计决策**：为什么不用"同脚本"方式（两架飞机跑同一个 `fly_mission.py`），而是用设定点回放？

因为**设定点回放和实机验证的工作流完全一致**。实际外场中，你拿到的是实机的 ULG——里面只有 PX4 记录的 trajectory_setpoint，你不可能让实机"再飞一遍一模一样的"。所以从一开始就按"从 ULG 提取设定点 → 回放到仿真"的流程设计实验，整条工具链可以无缝切换到实机。

### 1.3 标准机动序列

机动序列的设计原则是：**每个机动激励一个特定的动力学参数**。

| 阶段 | 机动 | 时长 | 目标参数 | 原理 |
|------|------|------|----------|------|
| Phase 3 | 悬停 5m | 10 s | mass | 推力 = mg，质量偏差直接体现为悬停油门偏差 |
| Phase 4-5 | Z 位置阶跃 5→7→5m | 10 s | motorConstant | 推力阶跃响应的爬升速度和超调量由推力系数决定 |
| Phase 6-7 | 前飞 3 m/s → 悬停 | 8 s | 阻力系数 | PX4 需 pitch 倾斜来产生前飞力，稳态 pitch 角反映阻力 |
| Phase 8 | 侧飞 2 m/s → 悬停 | 6 s | Ixx | 侧飞需要 roll 倾斜，roll 角加速度 ∝ 1/Ixx |
| Phase 9 | 前飞 2 m/s → 悬停 | 6 s | Iyy | 同理，pitch 角加速度 ∝ 1/Iyy |
| Phase 10 | 偏航 +90° → 回正 | 6 s | Izz | yaw 角加速度 ∝ 1/Izz |

### 1.4 参数偏差设定

Interceptor 的初始参数故意设置偏差，模拟"拿到一个新飞机、参数靠猜"的真实场景：

| 参数 | x500 真值 | Interceptor 初始值 | 偏差 |
|------|-----------|-------------------|------|
| mass | 2.0 kg | 2.3 kg | +15% |
| Ixx/Iyy | 0.02167 | 0.0249 | +15% |
| motorConstant | 8.549e-6 | 7.01e-6 | -18% |
| timeConstantUp | 0.0125 s | 0.020 s | +60% |

偏差幅度的选择参考了实际工程中常见的估计误差：质量称重误差一般在 10-20%，惯性矩用 CAD 估算误差在 15-30%，电机推力系数不上推力台根本不知道准不准。

---

## 2. 工程搭建

### 2.1 环境

- PX4 v1.16.1 + Gazebo Harmonic（gz-sim 8）
- MAVSDK-Python 2.x
- Python 3.10 + pyulog + numpy + matplotlib

### 2.2 自定义 interceptor 模型的坑

Gazebo SDF 写自定义模型有一个**文档里不说、但一定会踩的坑**：你不能用 `<include>` 引用 x500 基础模型然后 `<link>` override 参数。这样做会导致**重复 `base_link` 错误**——Gazebo 的 SDF parser 在 include 展开后不做 link 去重，直接报 `duplicate link name: base_link` 然后模型加载失败。

正确做法是**完整复制 x500 的 SDF，改名为 interceptor，然后直接改参数**。虽然丑，但可靠。

SDF 中核心参数修改位置：

```xml
<!-- model.sdf: interceptor 质量与惯性 -->
<link name="base_link">
  <inertial>
    <mass>2.3</mass>  <!-- x500 是 2.0 -->
    <inertia>
      <ixx>0.0249</ixx>   <!-- x500 是 0.02167 -->
      <iyy>0.0249</iyy>
      <izz>0.04</izz>
    </inertia>
  </inertial>
</link>

<!-- 电机推力系数（每个 rotor 的 plugin 里） -->
<plugin filename="gz-sim-multicopter-motor-model-system"
        name="gz::sim::systems::MulticopterMotorModel">
  <motorConstant>7.01e-06</motorConstant>  <!-- x500 是 8.549e-06 -->
  <timeConstantUp>0.020</timeConstantUp>    <!-- x500 是 0.0125 -->
  <timeConstantDown>0.025</timeConstantDown>
</plugin>
```

### 2.3 PX4 Airframe 注册

在 PX4 的 `ROMFS/px4fmu_common/init.d-posix/airframes/` 下新建 `4050_gz_interceptor`：

```bash
#!/bin/sh
# 4050_gz_interceptor
. ${R}etc/init.d/rc.mc_defaults

param set-default SIM_GZ_EN 1
param set-default SIM_GZ_EC_FUNC1 101
param set-default SIM_GZ_EC_FUNC2 102
param set-default SIM_GZ_EC_FUNC3 103
param set-default SIM_GZ_EC_FUNC4 104
param set-default SIM_GZ_EC_MIN 150
param set-default SIM_GZ_EC_MAX 1000

param set-default CA_ROTOR_COUNT 4
param set-default CA_ROTOR0_PX 0.175
param set-default CA_ROTOR0_PY 0.175
param set-default CA_ROTOR0_KM 0.05
# ... 其余参数与 x500 一致
```

然后 `CMakeLists.txt` 加上 `4050_gz_interceptor`，重新编译 PX4。

### 2.4 设定点回放脚本

`setpoint_replay.py` 的工作流程：

1. **从 ULG 提取 trajectory_setpoint**：包含位置 (px, py, pz)、速度 (vx, vy, vz)、偏航角 (yaw)，以及对应的时间戳
2. **启动 PX4+Gazebo interceptor**，等待 GPS 就绪
3. **先用 `action.takeoff()` 起飞到稳定高度**——直接从地面 offboard 起飞大概率被 PX4 failsafe 拒绝
4. **切换到 offboard 模式**，按 ULG 时间戳逐条回放设定点
5. **回放完毕后着陆、上锁（disarm）**，PX4 自动保存 ULG

核心回放逻辑：

```python
replay_start = time.monotonic()
sp_start_time = setpoints.iloc[first_valid_idx]["t"]

for idx in range(first_valid_idx, last_valid_idx + 1):
    sp = setpoints.iloc[idx]
    target_wall_time = replay_start + (sp["t"] - sp_start_time)

    now = time.monotonic()
    if target_wall_time > now:
        await asyncio.sleep(target_wall_time - now)

    has_pos = not np.isnan(sp["px"])
    if has_pos:
        await drone.offboard.set_position_ned(
            PositionNedYaw(sp["px"], sp["py"], sp["pz"], yaw_deg))
    elif has_vel:
        await drone.offboard.set_velocity_ned(
            VelocityNedYaw(sp["vx"], sp["vy"], sp["vz"], 0.0))
```

关键细节：ULG 中的 `trajectory_setpoint` 有些时刻只有速度目标没有位置目标（NaN），脚本需要根据字段有效性动态切换 `PositionNedYaw` 和 `VelocityNedYaw`。

---

## 3. Round 1：初始猜测

### 3.1 数据采集与时间对齐

先用 `fly_mission.py` 让 x500 飞一遍标准机动序列，产生 `x500_truth.ulg`。然后设定 interceptor 为 Round 1 参数（全部偏差），启动 PX4+Gazebo interceptor，运行 `setpoint_replay.py` 将 x500 的 375 条 trajectory_setpoint 回放给 interceptor。

时间对齐策略：**检测三维位移首次超过 0.3m 的时刻作为 t=0**。

```python
def detect_takeoff_time(pos_df, threshold=0.3):
    x, y, z = pos_df["x"].values, pos_df["y"].values, pos_df["z"].values
    disp = np.sqrt((x - x[0])**2 + (y - y[0])**2 + (z - z[0])**2)
    idx = np.argmax(disp > threshold)
    return pos_df["timestamp_s"].iloc[idx]
```

为什么用位移阈值而不是速度阈值？因为 `action.takeoff()` 阶段 PX4 有缓慢的油门爬升过程，Vz 可能在离地前就超过小阈值。位移阈值 0.3m 能准确捕获飞机实际离地的时刻。

### 3.2 如何读懂本文的对比图

后续出现的每张对比图统一格式：**蓝色实线 = x500 真值，红色虚线 = interceptor 仿真**。每张图纵向排列 3 个子图（如 X / Y / Z 三个轴），横轴统一为起飞后的秒数。左上角的黄色标签是该通道的 RMSE。**两条线越重合说明模型越准，间隙越大说明参数偏差越大。**

两个核心指标：

- **RMSE（均方根误差）**：所有时刻误差的"平均大小"。是航空航天 V&V 领域最基础的定量验证指标，在 NASA-STD-7009、AIAA G-077-1998 等标准中均有定义。
- **R²（决定系数）**：取值范围 (-∞, 1]。R² = 1 表示完美拟合；R² = 0 表示仿真的预测力和"永远输出均值"一样差；**R² < 0 表示仿真还不如均值**——模型不仅不准，还在系统性地往错误方向偏。

### 3.3 Round 1 关键指标

| 通道 | RMSE | R² | 物理含义 |
|------|------|----|----------|
| Velocity Z | 0.686 m/s | -1.514 | 垂直速度偏差大，R²为负表示预测比均值还差 |
| Velocity X | 1.068 m/s | -0.471 | 前飞速度跟踪滞后 |
| Pitch | 4.271° | -2.674 | 俯仰角严重偏离，R² 深度为负 |
| Roll | 5.102° | -0.608 | 滚转响应失配 |
| Yaw | 54.30° | -0.635 | 偏航累积漂移（后面单独分析） |
| Pitch Rate | 0.242 rad/s | -2.275 | 俯仰角速度响应滞后 |
| Yaw Rate | 0.611 rad/s | -2.174 | 偏航角速度偏差大 |

### 3.4 Round 1 数据分析

**1. 速度通道 R² 全面为负。** 四个参数同时偏离导致 interceptor 的动力学响应与 x500 有系统性差异。质量偏大 15% + 推力系数偏小 18%，双重叠加导致推力余量不足；惯性矩偏大 15% + 电机时间常数偏大 60%，导致姿态响应迟钝。当 x500 的设定点要求"在 t=20s 到达 Z=-7m"时，interceptor 因推力不足爬得更慢，因惯性大转得更慢——不是跟踪得"差不多"，而是系统性地偏到另一个方向。

**2. 设定点回放 vs 同脚本的区别。** 同脚本方式下，两架飞机各自独立决定何时执行下一个机动——x500 飞到 5m 才开始下一步，interceptor 也是飞到 5m 才开始。而设定点回放是**强制时间对齐**——不管你飞到哪，t=20s 时就要开始跟踪 Z=-7m 的目标。这意味着参数偏差的影响会更加清晰和可量化。

![Round 1 速度对比：Vz 子图中红色虚线始终滞后蓝色实线，在 Z 阶跃段（20-30s）尤为明显——interceptor 推力不足导致上升/下降速度都慢于目标。](/images/gazebo-px4-dynamics/sp_round1_comparison_velocity.png)

![Round 1 姿态对比：Pitch 子图中，红色虚线的响应幅度和相位都与蓝色实线有明显偏差——惯性矩偏大导致角加速度不足，电机时间常数偏大导致响应迟钝。](/images/gazebo-px4-dynamics/sp_round1_comparison_attitude.png)

---

## 4. 迭代修正过程

### 4.1 Round 2：修正质量（2.3 → 2.0 kg）

质量是悬停推力平衡的**第一主因**。`推力 = mg` 这个关系决定了悬停油门——质量差 15% 意味着所需推力差 15%。

修正质量后的变化（以速度和姿态为主要指标）：

| 通道 | R1 RMSE | R2 RMSE | 变化 | 分析 |
|------|---------|---------|------|------|
| Velocity Z | 0.686 | 0.585 | **-15%** | 推力需求降低，Vz 跟踪改善 |
| Velocity X | 1.068 | 1.066 | -0.2% | 几乎无变化——质量对水平速度影响小 |
| Pitch | 4.271° | 3.794° | **-11%** | 质量减小后 PX4 不需要那么大的 pitch 来加速 |
| Roll | 5.102° | 5.127° | +0.5% | 基本不变——质量对 roll 影响很小 |
| Pitch Rate | 0.242 | 0.219 | **-9.5%** | 角速度响应小幅改善 |

**分析**：质量修正对 Z 轴动力学的效果立竿见影（Vz RMSE 降 15%），但对姿态通道的改善有限——因为姿态响应主要由惯性矩和推力系数决定，质量只是间接影响（通过改变所需悬停油门）。

### 4.2 Round 3：修正推力常数（7.01e-6 → 8.549e-6）

这一轮修正带来了**最大幅度的改善**：

| 通道 | R2 RMSE | R3 RMSE | 变化 | 分析 |
|------|---------|---------|------|------|
| Velocity Z | 0.585 | 0.357 | **-39%** | 推力系数对了，Z 轴响应精确度大幅提升 |
| Velocity Y | 0.556 | 0.426 | **-23%** | 侧飞跟踪改善 |
| Pitch | 3.794° | 2.332° | **-39%** | 推力系数正确后，PX4 给出的 pitch 指令更准确 |
| Roll | 5.127° | 4.221° | **-18%** | roll 通道也受益 |
| Yaw | 66.05° | 46.27° | **-30%** | 偏航跟踪改善 |
| Yaw Rate | 0.786 | 0.357 | **-55%** | 偏航角速度大幅改善 |

**为什么推力常数的影响如此之大？** 因为 `motorConstant` 是四旋翼推力模型的核心——`F = k_f × ω²`，它直接决定了"给定电机转速能产生多少力"。当 k_f 偏小 18% 时，PX4 控制器必须给出更高的电机转速来跟踪同样的位置目标，这扰乱了整个控制链路。修正 k_f 后，控制器输出的电机转速与实际需求匹配，所有通道都受益。

### 4.3 Round 4：修正惯性矩 + 电机时间常数

吸取前几轮经验，这次把剩下两组参数一起修正：

- Ixx/Iyy：0.0249 → 0.02167（-13%，更接近真值，姿态响应更灵敏）
- timeConstantUp：0.020 → 0.0125 s（-38%，电机加速更快）

| 通道 | R3 RMSE | R4 RMSE | 变化 | 分析 |
|------|---------|---------|------|------|
| Velocity Z | 0.357 | 0.358 | +0.2% | 几乎无变化 |
| Velocity X | 0.969 | 0.970 | +0.1% | 几乎无变化 |
| Pitch | 2.332° | 2.331° | **-0.06%** | 几乎无变化 |
| Roll | 4.221° | 4.221° | **-0.003%** | 几乎无变化 |
| Pitch Rate | 0.139 | 0.139 | -0.2% | 几乎无变化 |
| Yaw Rate | 0.357 | 0.357 | 0% | 无变化 |

**Round 3 和 Round 4 几乎没有区别！** 这是本次实验最重要的发现之一：

**PX4 的闭环控制器遮蔽了惯性矩和电机时间常数的差异。** 原因是：

1. **PX4 的姿态控制器具有很强的鲁棒性**。Ixx/Iyy 偏差 15% 时，姿态环的 PID 控制器通过积分项补偿了力矩不足——稳态响应几乎不变，只是过渡响应稍有差异。
2. **设定点回放测量的是"控制器+动力学"整体**。控制器的补偿能力把参数差异"吃掉"了——从外部观测，两组参数的飞机行为几乎一样。
3. **电机时间常数（0.0125 vs 0.020s）的差异被 PX4 的 200Hz 控制频率覆盖**。在 5ms 的控制周期内，两种时间常数的电机响应差异微乎其微。

**对实际 Sim-to-Real 的启示**：如果你发现修正惯性矩后 RMSE 没有明显变化，不一定是测量不准——可能是 PX4 的控制器太强，设定点级别的比较根本看不出差异。此时需要**降低比较层级**（如用姿态设定点回放或执行器回放）来剥离控制器的遮蔽效应。

---

## 5. 收敛分析

### 5.1 选择正确的评价指标

设定点回放有一个**关键特性**：位置误差会累积漂移，但速度和姿态误差不会。

原因很直觉——假设 interceptor 在 t=5s 时因为推力不足，位置比 x500 低了 0.5m。接下来的所有设定点都是按 x500 的原始位置给的，interceptor 从一个"错误的起点"去追，后续的位置误差会越来越大。但**瞬时速度和姿态不受历史误差影响**——每个时刻的 Vz 只取决于当前的推力和重力，不取决于之前漂了多远。

所以本文的核心评价指标是**速度 RMSE 和姿态 RMSE**，而非位置 RMSE。

### 5.2 四维收敛总览

![4 轮参数修正的完整收敛图。左上：速度 RMSE——Vz 从 0.686 降到 0.358（-48%），最大降幅出现在 R3（修正 motorConstant）。右上：姿态 RMSE——Pitch 从 4.27° 降到 2.33°（-45%），同样在 R3 有最大跳降。左下：角速度 RMSE——pitchspeed 和 yawspeed 在 R3 大幅下降。右下：位置 RMSE——因累积漂移效应，X 位置反而从 5.96 升到 12.68，这是设定点回放方法的固有特征，不代表模型变差。](/images/gazebo-px4-dynamics/sp_convergence_full.png)

### 5.3 汇总表（速度 + 姿态）

| 轮次 | 修正参数 | Vz RMSE | Pitch RMSE | Roll RMSE | Yaw Rate RMSE | 累计修正 |
|------|----------|---------|------------|-----------|---------------|---------|
| R1 | 初始猜测 | 0.686 | 4.271° | 5.102° | 0.611 | 全部偏差 |
| R2 | 质量 | 0.585 (-15%) | 3.794° (-11%) | 5.127° | 0.786 | mass |
| R3 | 推力常数 | **0.357 (-39%)** | **2.332° (-39%)** | **4.221° (-18%)** | **0.357 (-55%)** | mass + k_f |
| R4 | 惯性矩+时间常数 | 0.358 (+0%) | 2.331° (-0%) | 4.221° (-0%) | 0.357 (0%) | 全部 |

### 5.4 灵敏度排序

**motorConstant（推力系数）>> mass（质量）>> Ixx/Iyy + timeConstant（被控制器遮蔽）**

| 修正操作 | 对 Vz RMSE 的影响 | 对 Pitch RMSE 的影响 | 对 Yaw Rate RMSE 的影响 |
|---------|-----------------|---------------------|------------------------|
| 修正 mass（R1→R2） | -0.101 (-15%) | -0.477° (-11%) | +0.175 (+29%) ⚠️ |
| 修正 k_f（R2→R3） | **-0.228 (-39%)** | **-1.462° (-39%)** | **-0.430 (-55%)** |
| 修正 Ixx/Iyy + τ（R3→R4） | +0.001 (+0%) | -0.001° (-0%) | 0.000 (0%) |

解读：

- **推力系数是动力学模型的核心参数**——修正它一步解决了 39% 的速度误差和 39% 的姿态误差，还有 55% 的偏航角速度误差。物理上很直觉：`F = k_f × ω²`，推力系数直接决定了"电机转速到力"的转换，错了整个控制链都会受影响。
- **质量对垂直通道有中等影响**（-15%），但对 yaw rate 反而有负面影响（+29%）。这是因为修正质量后改变了悬停油门需求，间接扰动了 yaw 通道的力矩平衡。
- **惯性矩和时间常数在设定点回放层面几乎不可观测**——PX4 的控制器鲁棒性把这两个参数的差异"吃掉"了。

### 5.5 Round 3 和 Round 4 的对比图

修正推力常数后（Round 3），速度和姿态的匹配度大幅提升：

![Round 3 速度对比：Vz 子图中，红色虚线与蓝色实线在阶跃段的响应速度已经接近一致。Vx 子图中前飞加速段的偏差明显缩小。](/images/gazebo-px4-dynamics/sp_round3_comparison_velocity.png)

![Round 3 姿态对比：Pitch 子图中两条线的振幅已经基本对齐。Roll 也有明显改善。注意 Yaw 子图虽然仍有较大偏差，但整体趋势已经比 Round 1 好很多。](/images/gazebo-px4-dynamics/sp_round3_comparison_attitude.png)

Round 4（修正惯性矩+时间常数后）的图和 Round 3 肉眼无法区分——这就是前面分析的"控制器遮蔽效应"的视觉体现：

![Round 4 速度对比：与 Round 3 几乎完全相同——进一步确认了 Ixx/Iyy 和 timeConstantUp 在设定点回放层面不可观测。](/images/gazebo-px4-dynamics/sp_round4_comparison_velocity.png)

![Round 4 姿态对比：与 Round 3 肉眼无法区分。PX4 控制器的鲁棒性完全吸收了惯性矩 15% 的偏差和时间常数 60% 的偏差。](/images/gazebo-px4-dynamics/sp_round4_comparison_attitude.png)

---

## 6. 残余误差分析

### 6.1 为什么 Roll 还有 4.2°、Pitch 还有 2.3°？

Round 4 所有参数都修正到了 x500 的真值，但速度和姿态 RMSE 并未归零。理解这些残余误差的来源至关重要——否则你会把方法的固有误差误判为"模型参数还没调好"。

| 误差来源 | 预估贡献 | 是否可消除 |
|---------|---------|-----------|
| 起飞时序差异 | ~2° | 可减小（更精确的 offboard 切换时机） |
| 控制器初始状态差异 | ~1.5° | 否（两个独立 PX4 各自从零开始积分） |
| EKF2 状态估计差异 | ~0.5° | 否（独立 EKF + 独立 IMU 噪声） |
| 设定点离散化 | ~0.2° | 可减小（更高频率的设定点采样） |

设定点回放有一个**固有的时序偏差问题**：x500 的 ULG 中 trajectory_setpoint 是从 PX4 启动、起飞、稳定后开始的，而回放时 interceptor 的 PX4 需要自己经历一遍起飞过程。`setpoint_replay.py` 的处理方式是先 `action.takeoff()` 到 2m，再切 offboard，然后从第一个有效设定点开始回放。这导致两架飞机在进入机动序列时的初始状态（高度、速度、姿态）不完全一致，这个差异会贡献约 2° 的基底误差。

### 6.2 位置 RMSE 为什么比 Round 1 还大？

| 通道 | R1 位置 RMSE | R4 位置 RMSE | 变化 |
|------|-------------|-------------|------|
| X | 5.96 m | 12.68 m | +113% |
| Y | 2.02 m | 3.23 m | +60% |
| Z | 3.24 m | 4.82 m | +49% |

这看起来很反直觉——参数修正了，位置误差反而增大了？

原因是**累积漂移的模式改变了**。Round 1 时，interceptor 因推力不足整体"趴着飞"——位置偏差虽然大但相对稳定。Round 4 时，参数正确但初始状态微小差异被放大——两架飞机在长机动序列中各自走各自的轨迹，60 多秒下来位置漂移反而更大。

**这不是模型变差了——速度和姿态的 RMSE 一直在下降，这才是动力学匹配度的真实反映。** 位置 RMSE 在设定点回放方法中不是一个好的评价指标。

### 6.3 Yaw 为什么漂移严重（~46°）？

Yaw RMSE 在所有轮次中都保持在 46-66° 的高水平，这**不是模型参数问题**：

- **offboard 模式下 yaw 控制是"尽力而为"的**。PX4 在执行位置/速度指令时，内部优先级是 `位置 > 速度 > yaw`。水平机动需要 roll/pitch 来产生加速度，yaw 的控制带宽被压缩。
- **设定点回放的 yaw 目标与实际状态可能累积偏差**。x500 在 t=30s 的 yaw 可能是 45°，但 interceptor 此时 yaw 可能已经漂到 50°——之后每个设定点的 yaw 偏差都会叠加。

如果需要精确验证 yaw 动力学（Izz），应该设计专门的 yaw 阶跃测试：固定位置，只改变 yaw 目标，持续时间控制在 5 秒以内以避免积分漂移。

### 6.4 残余误差的实际意义

| 通道 | R4 RMSE | 典型仿真精度要求 | 是否满足 |
|------|---------|----------------|---------|
| Velocity Z | 0.358 m/s | ±0.5 m/s | ✅ |
| Velocity X | 0.970 m/s | ±1.5 m/s | ✅ |
| Pitch | 2.33° | ±5° | ✅ |
| Roll | 4.22° | ±5° | ✅ |
| Yaw | 46.8° | ±10° | ❌ 需专项测试 |

除了 Yaw 之外，所有通道的精度都满足典型的仿真精度要求——而且 Yaw 的大误差是方法固有的累积漂移，不是模型参数问题。

---

## 7. 为什么不用开环执行器回放？

### 7.1 执行器回放的理论优势

ULG 日志中记录了 PX4 控制链路各层的数据：

```
飞手/自主任务
    │
    ▼
┌─────────────────────────┐
│ 层级 3: 位置/速度设定点   │ ← trajectory_setpoint      ← 本文使用
├─────────────────────────┤
│ 层级 2: 姿态/推力设定点   │ ← vehicle_attitude_setpoint
├─────────────────────────┤
│ 层级 1: 执行器输出        │ ← actuator_motors           ← 理论金标准
└─────────┬───────────────┘
          │
          ▼
       电机 → 螺旋桨 → 气动力 → 飞机运动
```

层级 1（执行器回放）是**理论金标准**——同样的电机指令，实机飞出什么轨迹、仿真飞出什么轨迹，差别就是纯动力学模型的误差，完全绕过了控制器差异。

### 7.2 我们真的做了——飞机坠毁了

纸上谈兵不够，我们实际动手做了开环执行器回放实验：

1. 从 x500 ULG 提取 `actuator_outputs` 的完整电机指令序列（10Hz，687 条）
2. 启动独立 Gazebo（不经过 PX4），加载 interceptor 模型
3. 用 Python gz-transport 暂停仿真 → 发布电机指令 → 步进物理引擎 → 记录位姿

**结果：飞机在起飞约 5 秒后坠毁。**

```
[  0/687] sim_t= 0.1s  z=0.238  motors=[152,150,152,150]  ← 电机怠速
[ 50/687] sim_t= 5.1s  z=1.441  motors=[797,799,799,799]  ← 刚离地
[100/687] sim_t=10.1s  z=0.060  motors=[766,767,766,766]  ← 坠毁触地
[150/687] sim_t=15.1s  z=0.060  motors=[768,769,768,769]  ← 趴在地上
```

### 7.3 为什么失败

四旋翼是一个**本征不稳定系统（inherently unstable system）**。PX4 控制器的电机输出是轨迹特定的闭环校正信号：

- t=5s 时，x500 在 PX4 控制下正以 800 rpm 爬升至 5m
- 同一时刻，开环回放的 interceptor 才到 z=1.4m（因为没有控制器做实时校正）
- t=10s 时，x500 到达 5m 目标高度，PX4 减小油门到 767 以维持悬停
- 但此时 interceptor 不在 5m，767 rpm 不足以维持当前状态，直接坠落

**核心教训：闭环控制器的输出在脱离控制器后毫无意义。** 同样的电机指令，差 0.1 秒或差 0.1 米就会导致完全不同的结果。开环回放只适用于本征稳定的系统（如地面车辆）。

> 完整代码见仓库中的 `scripts/openloop_replay.py` 和 `worlds/openloop.sdf`。

---

## 8. 方法论溯源：我们站在谁的肩膀上

本文的每一步都有成熟的学术根基，不是新方法，而是经典方法在 Gazebo+PX4 上的工程落地。

### 8.1 孪生实验 (Twin Experiment)

"用已知参数的仿真代替真值"这个实验设计，在气象学中叫 **OSSE（Observing System Simulation Experiment）**，在航空航天中叫 **identical twin experiment**。核心思想是：先在全可控的环境里验证工具链的正确性，再切换到真实数据。我们的做法——用 x500 当"真机"、interceptor 当"仿真"——就是一个标准的 twin experiment。

### 8.2 飞行器系统辨识 (System Identification)

逐步修正参数、对比飞行数据的做法，属于**系统辨识**领域的基本操作。经典教科书包括 Tischler & Remple (2006)、Jategaonkar (2006)、Klein & Morelli (2006)。

专业的系统辨识用的是**输出误差法 (Output Error Method)** 或**最大似然估计 (Maximum Likelihood)**——可以同时辨识多个参数并给出置信区间。我们的"手动改一个参数跑一轮"本质上是最原始的试凑法，但优点是直觉清晰、便于展示每个参数的物理效应。

### 8.3 灵敏度分析 (Sensitivity Analysis)

我们的逐参数修正策略在学术上叫 **OAT（One-At-a-Time）灵敏度分析**。更严格的替代方案包括 Morris 方法、Sobol 全局灵敏度指数和蒙特卡洛采样。

### 8.4 模型 V&V (Verification & Validation)

"跑相同输入 → 比较输出 → 计算误差"是航空航天**模型验证与确认 (V&V)** 的标准流程。相关行业标准包括 NASA-STD-7009、AIAA G-077-1998、DoD VV&A。我们使用的 RMSE 和 R² 属于最基础的定量验证指标。

### 8.5 本文的定位

**本文不是方法论创新，而是经典方法的开源工程实现。** 价值在于：
1. 用全开源工具（Gazebo + PX4 + Python）替代了传统上依赖 MATLAB/Simulink 的工作流
2. 用设定点回放方法建立了与实机验证完全一致的工具链
3. 记录了教科书不会讲的工程踩坑（SDF 模型冲突、开环回放四旋翼不可行、控制器遮蔽效应）
4. 提供了可直接复现的代码和数据，降低了从零开始的门槛

---

## 9. 仿真到外场：制导算法能直接移植吗？

读者可能会问：在这个仿真环境中开发的截击/制导算法，调好参数后能不能直接部署到实机？

**简短回答：算法逻辑可以移植，但不能直接信任仿真中的性能指标。**

### 9.1 可以移植的部分

如果你的制导算法工作在**设定点层级**（输出位置/速度目标，通过 MAVSDK offboard 接口下发），那么算法代码可以不做修改地在实机上运行——因为 PX4 在 SITL 和实机硬件上跑的是同一份飞控代码，MAVSDK 接口完全一致。

### 9.2 仿真没有覆盖的关键差距

| 维度 | 本文仿真验证的范围 | 实际截击场景的需求 | 差距 |
|------|------------------|------------------|------|
| 速度 | 0-97 m/s（低速迭代 + HP 50 m/s + Gobi v2 97 m/s） | 30-80 m/s | 50+ m/s 需 v² 阻力插件（§10.9），70+ m/s 有前进比效应（§10.11） |
| 姿态角 | ±15°（低速）/ ±85°（Gobi 高速） | ±45° 以上 | 大迎角非线性效应已覆盖 |
| 传感器 | Gazebo 理想 IMU/GPS | 相机噪声、GPS 拒止、目标检测延迟 | 传感器模型完全缺失 |
| 环境扰动 | 无风 | 阵风、湍流 | 风场模型未添加 |
| 执行器 | 线性推力模型 `F = k_f × ω²` | 电机饱和、ESC 非线性、电池电压跌落 | 前进比效应 70+ m/s 开始影响（§10.11） |

特别值得警惕的是我们实验中的一个发现：**PX4 控制器在低速域有极强的鲁棒性**（Round 3→4 惯性矩偏差 15% 完全被遮蔽）。这意味着低速仿真中"看起来没问题"的参数偏差，在高速高机动时控制裕度缩小后可能突然暴露，导致失控。

### 9.3 推荐的移植路径

```
仿真开发（本文） → 扩展仿真包线 → HIL 验证 → 低速实飞 → 逐步扩包线
     ✅              ↓               ↓          ↓           ↓
  参数调好了      加风场/传感器噪声  飞控硬件实时性   用 setpoint_replay  每步都对比
                 高速机动测试      计算约束验证     验证动力学匹配度    仿真 vs 实飞
```

**本文建立的 setpoint_replay 工具链在第 4 步（低速实飞验证）中可以直接使用**——这正是从一开始就选择设定点回放方法的原因。但前面三步不能跳过。

---

## 10. 高速场景验证：50 m/s 截击机动力学辨识

前面的实验在低速（<15 m/s）场景下验证了方法的有效性。但对于高速截击机（目标速度 50 m/s），高速下的气动效应会显著改变动力学特性。这一节通过创建高性能（T/W≈8）模型，验证 IMU-based 系统辨识方法在 0-50 m/s 全速域的适用性。

### 10.1 高性能模型设计

为模拟真实截击机的推重比和气动特性，创建了 `x500_hp` 模型：

| 参数 | 标准 x500 | x500_hp (截击机) | 倍率 |
|------|----------|------------------|------|
| motorConstant (k_f) | 8.54858×10⁻⁶ | 2.73×10⁻⁵ | 3.2× |
| maxRotVelocity | 1000 rad/s | 1200 rad/s | 1.2× |
| T/W ratio | ~2.5 | ~8 | 3.2× |
| velocity_decay (drag) | 0 | 0.3 | - |
| MPC_XY_VEL_MAX | 12 m/s | 50 m/s | 4.2× |
| MPC_TILTMAX_AIR | 45° | 75° | 1.7× |

### 10.2 多速度段飞行测试

飞行剖面包含：悬停基线 → sysid doublets → 5/15/30/50 m/s 前飞 → 各速度段减速制动 → 着陆。最高实测速度达到 **50.5 m/s**。

![高速飞行综合分析：包含速度剖面、电机指令、k_f 随速度变化、气动阻力估计等多维度数据。](/images/drone-dynamics/highspeed_comprehensive.png)

### 10.3 k_f 辨识结果：全速域精度

| 速度段 | 辨识 k_f | 真值 k_f | 误差 |
|--------|---------|---------|------|
| 0-2 m/s (悬停) | 3.31×10⁻⁵ | 2.73×10⁻⁵ | +21.3% |
| 2-5 m/s | 3.15×10⁻⁵ | 2.73×10⁻⁵ | +15.6% |
| 5-10 m/s | 3.01×10⁻⁵ | 2.73×10⁻⁵ | +10.2% |
| **10-15 m/s** | **2.82×10⁻⁵** | **2.73×10⁻⁵** | **+3.3%** |
| **15-25 m/s** | **2.84×10⁻⁵** | **2.73×10⁻⁵** | **+4.1%** |
| 25-40 m/s | 2.92×10⁻⁵ | 2.73×10⁻⁵ | +6.8% |
| 40-60 m/s | 2.99×10⁻⁵ | 2.73×10⁻⁵ | +9.6% |

![k_f 辨识精度随速度段的变化：10-25 m/s 为最佳辨识区间，误差仅 3-4%。](/images/drone-dynamics/hp_50ms_kf_vs_speed.png)

**关键发现：**

1. **最佳辨识区间在 10-25 m/s**，误差仅 3-4%。这是因为中等速度下电机工作在线性区间，气动效应可控
2. **低速段偏高**（+21%）：悬停时电机指令波动小、信噪比差，且 Gazebo 的 velocity_decay 在低速时产生不可忽略的附加阻力
3. **高速段略偏**（+9.6%）：50 m/s 下气动阻力显著，简单的 `F = k_f × ω²` 模型不再精确——实际推力被阻力消耗了一部分
4. **整体 15% 误差可通过中速段数据校准修正**：实际工程中建议采用 10-25 m/s 段的 k_f 作为最终参数

### 10.4 气动阻力辨识

通过分析不同速度下的水平推力-速度关系，估计了 Gazebo 中设定的线性阻力系数：

- **线性阻力系数 Cd_linear**: 0.302（Gazebo 设定值 0.3，辨识误差 <1%）
- **验证速度范围**: 3-50.5 m/s

### 10.5 Setpoint Replay 高速验证

使用 50 m/s 飞行日志的 setpoint 回放到同一 HP 模型：

| 指标 | 相对位置 X | 相对位置 Y | 相对位置 Z | 水平速度 |
|------|-----------|-----------|-----------|---------|
| R² | 0.906 | 0.967 | 0.941 | 0.112 |
| RMSE | 45.5 m | 71.4 m | 4.8 m | 14.7 m/s |

![高速 setpoint replay 位置对比：相对位置 R² > 0.9，轨迹整体形状高度一致。](/images/drone-dynamics/hp_replay_position.png)

![高速 setpoint replay 速度对比：速度 R² 较低主要因为加减速时序存在微小偏移。](/images/drone-dynamics/hp_replay_velocity.png)

相对位置 R² > 0.9 表明轨迹整体形状高度一致。速度 R² 较低主要因为飞行剖面中的加减速时序存在微小偏移——在 50 m/s 下，0.5 秒的时序差即可产生 25 m 的位移误差。

### 10.6 Gobi 类截击机：Gazebo 中扩展至 97 m/s

x500_hp 验证了 50 m/s 下的方法有效性，但对于类似 [Anduril Bolt / Gobi](https://www.anduril.com/) 的高速截击机（最高 350 km/h ≈ 97 m/s），动力学差距会进一步放大。为此，我们在 Gazebo 中创建了 Gobi 参数的高速模型：

| 参数 | x500_hp | Gobi 模型 | 说明 |
|------|---------|----------|------|
| 质量 | 2.0 kg | 2.2 kg | 更紧凑的机身 |
| 惯性矩 Ixx/Iyy | 0.0217 | 0.012 | 紧凑机身→更小惯性 |
| 惯性矩 Izz | 0.040 | 0.020 | 同上 |
| T/W | ~8 | **~10** | 更大推力余量 |
| motorConstant k_f | 2.73×10⁻⁵ | **3.75×10⁻⁵** | 更大电机 |
| MPC_XY_VEL_MAX | 50 m/s | **100 m/s** | 扩展速度包线 |
| MPC_TILTMAX_AIR | 75° | **85°** | 极端倾角 |
| velocity_decay | 0.3 | 0.3 | 线性阻力不变 |

飞行剖面覆盖 9 个速度段：5 → 10 → 15 → 25 → 40 → 50 → 70 → 85 → 97 m/s，每段含加速-匀速-减速全过程，总飞行时间约 170 秒。

![Gobi 多速度段飞行剖面：速度、电机指令、加速度的完整记录。最高速度达 90.6 m/s。](/images/drone-dynamics/gobi/gobi_speed_profile.png)

**实测最高速度 90.6 m/s**（命令 97 m/s），受限于 PX4 控制器的响应速度和 Gazebo 仿真步长。

### 10.7 Gobi k_f 辨识结果：高速段的诊断信号

| 速度段 | 平均速度 | 辨识 k_f | 真值 k_f | 误差 |
|--------|---------|---------|---------|------|
| 5 m/s | 5.1 m/s | 4.71×10⁻⁵ | 3.75×10⁻⁵ | +25.7% |
| 10 m/s | 9.8 m/s | 4.64×10⁻⁵ | 3.75×10⁻⁵ | +23.8% |
| 15 m/s | 14.6 m/s | 4.58×10⁻⁵ | 3.75×10⁻⁵ | +22.3% |
| 25 m/s | 24.1 m/s | 4.44×10⁻⁵ | 3.75×10⁻⁵ | +18.3% |
| 40 m/s | 47.3 m/s | 3.96×10⁻⁵ | 3.75×10⁻⁵ | **+5.6%** |
| 50 m/s | 48.1 m/s | 4.25×10⁻⁵ | 3.75×10⁻⁵ | +13.4% |
| 70 m/s | 64.8 m/s | 3.87×10⁻⁵ | 3.75×10⁻⁵ | **+3.1%** |
| 85 m/s | 66.2 m/s | 4.51×10⁻⁵ | 3.75×10⁻⁵ | +20.4% |
| 97 m/s | 77.9 m/s | 3.87×10⁻⁵ | 3.75×10⁻⁵ | **+3.2%** |

![Gobi k_f 辨识随速度变化：40-70 m/s 段辨识最准确（3-6%），但整体波动大于 x500_hp。](/images/drone-dynamics/gobi/gobi_kf_vs_speed.png)

与 x500_hp 的 50 m/s 实验对比，Gobi 的 k_f 辨识波动更大。这**不是方法退化**，而是 T/W=10 的高推力模型在不同速度段的加速度特征更剧烈，对 IMU 信噪比要求更高。

### 10.8 关键发现：线性阻力模型在 97 m/s 下彻底崩溃

这是本实验最重要的结论。Gazebo 的 `velocity_decay`（线性阻力 F = cv）与真实空气动力学（二次阻力 F = ½ρCdAv²）在高速下的偏差不是量级差，而是数量级差：

| 速度 | Gazebo 线性阻力 F=0.3v | 真实二次阻力 (CdA=0.020) | 倍率 |
|------|---------------------|----------------------|------|
| 10 m/s | 3.0 N | 1.2 N | 0.4× |
| 25 m/s | 7.5 N | 7.7 N | 1.0× ← 交叉点 |
| 50 m/s | 15.0 N | **30.6 N** | **2.0×** |
| 70 m/s | 21.0 N | **60.0 N** | **2.9×** |
| 97 m/s | 29.1 N | **115.3 N** | **4.0×** |

![阻力模型对比：线性 vs 二次模型。25 m/s 以上二次模型急剧超过线性模型，97 m/s 时差距达 4 倍。](/images/drone-dynamics/gobi/gobi_drag_analysis.png)

**然而，从 ULG 实测的阻力远小于两个模型的预测**（在 78 m/s 时仅约 1 N）。这说明 Gazebo 的 `velocity_decay` 参数并不是简单的 F = cv 力，而是一种数值阻尼机制，在高速下完全失去了物理意义。

![表观 CdA 随速度变化：如果将仿真中的阻力反算成等效 CdA，数值远小于物理预期值 0.020 m²。](/images/drone-dynamics/gobi/gobi_cda_vs_speed.png)

**这意味着：用 Gazebo 默认的线性阻力模型做 50 m/s 以上的截击机仿真是不可靠的。** 仿真中的飞机会比真实飞机快得多、阻力小得多，导致：
- 仿真中制导算法以为可以轻松达到的加速度/速度，真实飞机受阻力限制达不到
- 仿真中的能量消耗远低于真实值，续航预测过于乐观
- 减速制动距离在仿真中被严重低估

**工程建议**：
1. **50 m/s 以下**：Gazebo + velocity_decay 可用，结合 setpoint replay 做参数校准，本文方法完全适用
2. **50-97 m/s**：**必须**替换阻力模型 —— 使用本文提供的 `QuadraticDrag` 自定义插件实现 F = ½ρCdAv²（见 §10.9）
3. 如果项目对高速气动精度要求极高（含前进比、侧风等），可进一步考虑 JSBSim 等专业 FDM 框架

### 10.9 解决方案：QuadraticDrag 自定义 Gazebo 插件

Gazebo 内置的 `LiftDrag` 插件是为**机翼翼型**设计的——它基于攻角-升力/阻力曲线，不适合四旋翼钝体的**全向体阻力**。因此我们开发了一个极简的 C++ 系统插件 `QuadraticDrag`，直接在每个物理步中对 `base_link` 施加：

**F_drag = −½ρ · CdA · |v| · v**

其中 v 是世界系线速度，方向始终与运动方向相反。

**SDF 配置**（在 `model.sdf` 的 `<model>` 内添加）：

```xml
<plugin filename="QuadraticDrag" name="quadratic_drag::QuadraticDrag">
  <link_name>base_link</link_name>
  <CdA>0.020</CdA>           <!-- 阻力系数 × 迎风面积，m² -->
  <air_density>1.225</air_density>  <!-- 海平面标准大气 -->
</plugin>
```

**构建与运行**：

```bash
# 构建插件
cd plugins/quadratic_drag && mkdir -p build && cd build
cmake .. && make -j$(nproc)

# 启动仿真前设置插件搜索路径
export GZ_SIM_SYSTEM_PLUGIN_PATH="/path/to/gazebo-px4-sim/plugins/quadratic_drag/build"

# 用辅助脚本一键启动
bash scripts/run_gobi_v2_sitl.sh
```

> **关键**：使用 `QuadraticDrag` 时**不要**同时保留 `velocity_decay`，否则会重复计阻。`gobi_v2_base` 已去掉 `velocity_decay`。

插件源码约 100 行 C++，见仓库 `plugins/quadratic_drag/QuadraticDrag.cc`。核心逻辑是在 `PreUpdate` 中获取 link 世界系速度、计算 ½ρCdA|v|v、调用 `link.AddWorldForce()`。

### 10.10 Gobi v1（线性）vs v2（v² 阻力）同任务实测对比

使用**完全相同的多速度段飞行脚本**（5→10→15→25→40→50→70→85→97 m/s），对比两个 Gobi 模型在同一控制指令下的动力学响应：

| 指标 | Gobi v1 (velocity_decay) | Gobi v2 (QuadraticDrag CdA=0.02) |
|------|--------------------------|----------------------------------|
| 最高水平速度 | **90.6 m/s** | **76.4 m/s** |
| 速度差 | — | **−14.2 m/s (−15.7%)** |
| 阻力模型 | F = 0.3v（线性） | F = ½ρ·0.02·v²（二次） |
| 97 m/s 理论阻力 | 29.1 N | **115.3 N** |

![Gobi v1 vs v2 水平速度对比：相同 T/W=10、相同任务脚本，v2（v² 阻力）最高速显著低于 v1，更接近真实物理行为。](/images/drone-dynamics/gobi/gobi_v1_vs_v2_speed.png)

**v2 最高速 76.4 m/s 的物理含义**：在 CdA=0.02、最大倾角 85° 下，电机提供的水平推力分量（约 215 × sin85° ≈ 214 N）在 76 m/s 时被阻力（½ × 1.225 × 0.02 × 76² ≈ 70.8 N）加上维持高度所需的垂直推力共同消耗殆尽，达到了推力-阻力平衡。这比 v1 的"几乎无阻力飞到 90 m/s"合理得多。

![Gobi v2 速度剖面：高速段的加速时间明显变长，减速制动更快——与真实高速无人机的飞行特征一致。](/images/drone-dynamics/gobi/gobi_v2_speed_profile.png)

### 10.11 未建模效应：桨盘前进比

即使用了 v² 阻力，Gazebo 的 `MulticopterMotorModel` 仍然假设 **F = k_f · ω²**（静推力公式）。在高前飞速度下，这个假设会失效：

**桨盘前进比 J = V∞ / (n·D)**

其中 V∞ 是前飞速度，n 是转速（rev/s），D 是桨盘直径。当 J 升高时，桨叶的有效攻角改变，等效推力系数 η(J) 随之下降。

以 Gobi 参数估算（桨径 ~0.33 m，最大转速 ~1200/(2π) ≈ 191 rev/s）：

| 前飞速度 | J = V/(n·D) | 推力衰减（典型） |
|---------|-------------|---------------|
| 10 m/s | 0.16 | <5%，可忽略 |
| 50 m/s | 0.79 | ~10-15% |
| 70 m/s | 1.11 | ~20-30% |
| 97 m/s | 1.54 | **~35-50%** |

这意味着在 70+ m/s 时，仿真中的电机产生的推力可能比真实值高 20-50%。这是 **Gazebo 电机模型的第二层结构误差**（第一层是阻力模型，§10.9 已解决）。

**工程对策**：

1. **分速度段等效 k_f**（最简单）：在 §10.7 的辨识结果中，不同速度段已经给出了等效 k_f，可以直接用作对应速度段的仿真参数
2. **扩展电机插件**（最准确）：修改 `MulticopterMotorModel` 的推力公式为 F = k_f·ω²·η(J)，η(J) 通过推力台在风洞中实测的数据查表
3. **后处理修正**（最方便）：保持仿真不变，在数据分析阶段对推力和速度做 J 修正

> 本文选择的是**分速度段等效 k_f** + **v² 阻力插件**的组合，在不修改 Gazebo 内核的前提下，覆盖了高速截击机建模的两个最关键缺陷。对于要求更高精度的项目，推荐方案 2。

---

## 11. 方法论的能力边界：能修什么、不能修什么

### 11.1 参数误差 vs 结构误差

模型的"不准"分两个层面，本文的方法论对它们的处理能力完全不同：

```
┌─────────────────────────────────────────────────────────┐
│  参数误差（Parametric Error）                              │
│    k_f 偏了、mass 不对、inertia 猜错了                      │
│    ──► 本文方法可直接修正 ✓                                │
│        辨识 + 迭代 → 收敛到真值 ±5%                        │
├─────────────────────────────────────────────────────────┤
│  结构误差（Structural Error）                              │
│    推力模型假设不对、阻力公式形式错了、缺少物理效应             │
│    ──► 本文方法无法通过调参消除 ✗                           │
│    ──► 但可以被检测和诊断出来 ✓                            │
└─────────────────────────────────────────────────────────┘
```

**参数误差的例子**：k_f 设成了 3.0e-5 但真值是 2.73e-5。IMU 辨识能把它找回来——因为物理公式 `a_z = (4·k_f·ω²)/m - g` 的结构是对的，只是系数偏了。

**结构误差的例子**：模型用线性阻力 `F_drag = c·v`，但真实阻力是 `F_drag = ½ρCdA·v²`。50 m/s 时线性模型的阻力被低估约 2.5 倍——无论怎么调 k_f 和 c，都不可能让仿真同时在 10 m/s 和 50 m/s 上跟真值匹配。

### 11.2 高速实验数据恰好揭示了这一点

两轮高速实验的 k_f 辨识误差随速度的变化模式是一个关键的诊断信号：

| 速度段 | x500_hp k_f 误差 | Gobi k_f 误差 | 诊断含义 |
|--------|----------------|--------------|---------|
| 5-10 m/s | 10-16% | 24-26% | 低信噪比 + 低速阻力扰动 |
| 10-25 m/s | 3-4% | 18-22% | x500_hp 准确；Gobi T/W=10 更敏感 |
| 40-50 m/s | 7-10% | 6-13% | 阻力效应开始显现 |
| **70-97 m/s** | — | **3-20%** | **模型结构严重不足** |

如果模型结构完美，k_f 的辨识值在所有速度段应当一致。Gobi 实验的 k_f 随速度出现大幅波动（3-26%），而非单调漂移——这说明 Gazebo 的线性阻力模型在高速下引入了不可预测的系统误差，超出了参数辨识能"吸收"的范围。

**这不是辨识方法的失败，而是它的诊断价值**——告诉你"这个速度段的模型结构需要改进"。

### 11.3 遇到结构误差怎么办

当 k_f 辨识出现速度依赖性时，有三个改进方向：

1. **改进阻力模型**：将 `velocity_decay`（线性）替换为 Gazebo 的 `LiftDrag` 或自定义插件实现 ½ρCdA·v² 非线性阻力
2. **分速度段标定**：在不同速度区间使用不同的等效 k_f，本质上是用分段线性逼近非线性系统
3. **添加入流效应修正**：高前飞速度下桨盘推力衰减（advance ratio 效应），需要修正推力模型为 F = k_f·ω²·η(V_∞)，其中 η 是前飞速度 V_∞ 的递减函数

### 11.4 工程实践中的判据

| 指标 | 参数误差主导 | 结构误差主导 |
|------|------------|------------|
| k_f 辨识值在各速度段 | 基本一致（±5%） | 随速度单调变化 |
| Setpoint replay R² | 全速域 > 0.9 | 特定速度段骤降 |
| 残差分布 | 随机白噪声 | 有系统性偏差模式 |
| **对策** | 调参数 → 收敛 | 改模型结构 → 重新辨识 |

> 方法论不只给你参数估计值，还告诉你估计值在什么条件下可信。当诊断信号提示结构不足时，应优先改进模型结构，而非继续迭代参数。

---

## 12. 模型适用性说明：x500 不是你的截击机

读到这里，读者可能会问：你们用的 x500（包括 x500_hp）能代替我的真实截击机吗？

**答案是：不能。x500/x500_hp 是方法验证平台，不是任何特定截击机的数字孪生。**

### 12.1 实验中各模型的角色定位

| 模型 | 角色 | 速度范围 | 目的 |
|------|------|---------|------|
| x500 | 孪生实验的"真值端" | 0-12 m/s | 提供参数已知的基准飞行数据 |
| interceptor | 孪生实验的"待校准端" | 0-12 m/s | 验证参数偏差→辨识→修正的闭环流程 |
| x500_hp | 高速验证平台 | 0-50 m/s | 验证方法论在中高速域仍然有效 |
| gobi (v1) | 极高速测试 — 线性阻力 | 0-97 m/s | 揭示 Gazebo 线性阻力在 50+ m/s 的结构性失效 |
| **gobi_v2** | **极高速测试 — v² 阻力** | **0-97 m/s** | **使用 QuadraticDrag 插件修复阻力模型后的高速仿真平台** |

这五个模型存在的意义是**验证方法论本身**——证明 setpoint replay + k_f 辨识 + 迭代修正这套流程能工作，同时明确它的能力边界（v1 → v2 的演进也验证了阻力模型升级的效果）。它们不替代任何一架真实飞机。

### 12.2 PX4 生态中没有高速多旋翼模型

截至 PX4 v1.16，官方 Gazebo 仓库的全部多旋翼仅有 x500 一个基础型号（所有 x500_depth、x500_lidar 等变体动力学参数完全相同）。社区曾明确提出 racer/高速模型需求（[PX4-SITL_gazebo #729](https://github.com/PX4/PX4-SITL_gazebo/issues/729)），官方回复"No there is no racer model"，至今未解决。VTOL 模型（standard_vtol、quadtailsitter）虽然能高速飞行，但靠的是固定翼升力模式，与纯多旋翼截击机的飞行原理完全不同。

本文创建的 x500_hp（T/W≈8、50 m/s）、gobi / gobi_v2（T/W≈10、97 m/s，v2 带 v² 阻力插件）实际上是 **PX4+Gazebo 生态中仅有的高速纯多旋翼仿真模型**。

### 12.3 x500_hp 与真实截击机的差距

| 维度 | x500_hp | 真实截击机 | 影响 |
|------|---------|-----------|------|
| 质量 | 2.0 kg | 2-5 kg（含载荷） | 参数替换即可 |
| 惯性矩 | SDF 默认值 | 取决于质量分布 | 必须实测或 CAD 计算 |
| 臂长 | 0.174 m | 因机型而异 | 影响力矩臂 |
| 机身外形 | 开放式 X 框架 | 紧凑流线型 | 阻力面积 CdA 不同 |
| 阻力模型 | 线性 velocity_decay | F_drag = ½ρCdAv²（非线性） | **高速差距最大** |
| 电机特性 | 理想 F = k_f·ω² | 有饱和、温升、效率曲线 | 高油门段偏差 |
| 螺旋桨 | 通用 13" | 专用高速桨 | 推力系数完全不同 |

### 12.4 正确的使用方式

本文提供的是**方法论 + 工具链**，不是某一架飞机的参数。读者拿到自己的截击机后：

1. **以 x500_hp 的 SDF 结构为模板**：不需要从零建模，修改参数即可
2. **替换为实测参数**：mass（称重）、k_f（推力台）、inertia（摆测/CAD）、臂长（直接测量）
3. **用本文的 setpoint replay 工具链做验证和修正**

方法论是模型无关的——不管你飞的是 x500 还是自研截击机，setpoint replay + k_f 辨识 + 迭代修正的流程完全一样。

---

## 13. 外场截击机建模路线图

如果你的目标是为一架真实截击机建立高精度仿真模型，以下是完整的工程路径。

### Phase 1：物理测量（不需要飞行）

| 测量项 | 方法 | 精度要求 | 工具 |
|--------|------|---------|------|
| 总质量（含载荷） | 电子秤 | ±10 g | 厨房秤即可 |
| 质心位置 | 吊挂法（3 点悬挂） | ±5 mm | 细线 + 铅垂 |
| 惯性矩 Ixx/Iyy/Izz | 三线摆/双线摆 | ±10% | 参考 [Bouabdallah 2004] |
| 电机推力系数 k_f | 单电机推力台 | ±3% | 称重传感器 + ESC |
| 电机力矩系数 k_m | 推力台同时测反扭矩 | ±5% | 扭矩传感器 |
| 臂长 | 直接测量 | ±1 mm | 卷尺 |

本实验证明推力系数是最敏感的参数（贡献 ~39% 的 RMSE 下降），所以推力台测试应排在最高优先级。质量影响第二大（贡献 ~15% 的 Vz RMSE 下降）。惯性矩和电机时间常数在设定点回放层面不可观测（被控制器遮蔽），但对高速大机动场景仍然重要，建议用摆振测试直接测量。

### Phase 2：创建 SDF 模型

```
x500_hp 的 model.sdf（模板）
    │
    ├─ 替换 <mass>、<inertia> → Phase 1 实测值
    ├─ 替换 <motorConstant>  → Phase 1 推力台 k_f
    ├─ 替换 <momentConstant> → Phase 1 推力台 k_m
    ├─ 调整 rotor joint 位置 → Phase 1 臂长
    └─ 添加阻力模型（可选）  → 风洞数据或初始估计
```

### Phase 3：低速飞行验证（0-15 m/s）

1. 实机飞行标准机动序列，记录 ULG
2. 用本文的 `extract_ulg.py` 提取数据
3. IMU-based k_f 辨识，与推力台值交叉验证
4. Setpoint replay 到仿真模型，评估 RMSE / R²
5. 如果 R² < 0.9 → 迭代修正参数 → 回到步骤 4

### Phase 4：扩展速度包线（15-97 m/s）

1. 逐步提高飞行速度（15 → 25 → 35 → 50 → 70 → 97 m/s）
2. 每个速度段独立辨识 k_f，观察是否随速度漂移
3. 如果漂移 > 10%：阻力模型结构不足 → 改为非线性阻力
4. ✅ **已完成**：50 m/s 以上替换 velocity_decay → `QuadraticDrag` 自定义插件（§10.9），gobi_v2 模型验证了 v² 阻力的正确性（§10.10）
5. Setpoint replay 验证各速度段的匹配度
6. （可选进阶）扩展电机模型以包含前进比效应 η(J)（§10.11）

### Phase 5：算法部署

```
仿真验证通过（R² > 0.9 全速域）
    │
    ├─ 添加风场模型 → 鲁棒性验证
    ├─ 添加传感器噪声 → 感知误差验证
    ├─ HIL 测试 → 飞控硬件实时性
    └─ 外场低速试飞 → 逐步扩包线
```

### 每个阶段的验收标准

| 阶段 | 通过条件 | 不通过时的动作 |
|------|---------|--------------|
| Phase 3 | 速度 R² > 0.9，k_f 误差 < 5% | 检查 mass/k_f 是否正确替换 |
| Phase 4 | 全速域 k_f 漂移 < 10% | 改进阻力模型结构 |
| Phase 4 | Replay R² > 0.85 | 检查惯性矩、电机时间常数 |
| Phase 5 | 仿真-实飞速度 RMSE < 2 m/s | 回到 Phase 4 修正 |

> 本文建立的全部工具（k_f 辨识脚本、setpoint replay、RMSE/R² 对比、收敛分析）在 Phase 3-5 中可以直接复用，无需修改。这正是从一开始就选择"方法论验证"而非"特定机型建模"的原因。

---

## 14. 代码仓库与复现

仓库地址：[github.com/goodisok/gazebo-px4-sim](https://github.com/goodisok/gazebo-px4-sim)

```
gazebo-px4-sim/
├── PX4-Autopilot/                      # PX4 v1.16.1（.gitignore，需自行克隆）
├── px4_custom/                         # PX4 中新增的自定义文件
│   ├── models/interceptor/             # interceptor SDF 模型（基于 x500 修改）
│   ├── models/gobi/                    # Gobi v1 模型（线性阻力）
│   ├── models/gobi_v2/                 # Gobi v2 模型（QuadraticDrag 插件）
│   ├── models/gobi_base/               # Gobi v1 基础模型
│   ├── models/gobi_v2_base/            # Gobi v2 基础模型（无 velocity_decay）
│   └── airframes/                      # PX4 airframe 配置
│       ├── 4050_gz_interceptor
│       ├── 4097_gz_gobi_v2
│       ├── 4098_gz_gobi
│       └── 4099_gz_x500_hp
├── plugins/quadratic_drag/             # ★ v² 阻力自定义 Gazebo 插件
│   ├── QuadraticDrag.cc               #   ~100 行 C++，核心逻辑
│   ├── CMakeLists.txt                 #   构建配置（依赖 gz-sim8）
│   └── README.md                      #   使用说明
├── scripts/
│   ├── fly_mission.py                  # x500 真值数据采集
│   ├── setpoint_replay.py             # ★ 设定点回放（核心实验脚本）
│   ├── extract_ulg.py                 # ULG → CSV
│   ├── compare.py                     # 时间对齐 + RMSE/R² + 对比图
│   ├── sensitivity.py                 # 多轮收敛分析
│   ├── sp_convergence_analysis.py     # 4 维收敛图生成
│   ├── update_interceptor_params.py   # 命令行修改 SDF 参数
│   ├── run_setpoint_replay_all_rounds.sh  # 4 轮自动化脚本
│   ├── openloop_replay.py            # 开环回放（实验证伪用）
│   ├── create_hp_model.py            # 创建高性能 x500_hp 模型
│   ├── create_gobi_model.py          # 创建 Gobi v1 模型（线性阻力）
│   ├── create_gobi_v2_model.py       # ★ 创建 Gobi v2 模型（QuadraticDrag 插件）
│   ├── fly_multispeed.py             # 多速度段飞行测试（0-50 m/s）
│   ├── fly_gobi_multispeed.py        # Gobi 多速度段飞行（0-97 m/s）
│   ├── gobi_analysis.py              # Gobi 高速分析（k_f + 阻力辨识）
│   ├── compare_gobi_v1_v2.py         # ★ v1 vs v2 阻力模型对比
│   ├── run_gobi_v2_sitl.sh           # ★ 一键启动 gobi_v2 SITL（含插件路径）
│   ├── fly_sysid_maneuver.py         # 系统辨识激励机动
│   ├── imu_sysid.py                  # IMU-based k_f 辨识
│   ├── analyze_sysid_results.py      # 高速飞行分析
│   ├── comprehensive_analysis.py     # 全速域综合分析
│   ├── compare_ulg.py               # ULG 直接对比
│   ├── compare_replay_aligned.py     # 对齐后 replay 对比
│   ├── run_full_experiment.py        # 高速实验自动化（Python）
│   └── run_highspeed_experiment.sh   # 高速实验自动化（Shell）
├── worlds/
│   └── openloop.sdf                   # 独立 Gazebo world（开环实验用）
├── data/flight_logs/                   # ULG 日志（.gitignore）
├── results/
│   ├── sp_round1/ ~ sp_round4/        # ★ 4 轮设定点回放结果
│   ├── highspeed/                     # ★ 高速实验结果（0-50 m/s）
│   │   ├── analysis_x500/            #   x500 基准分析
│   │   ├── analysis_hp_*/            #   HP 模型各速度段分析
│   │   ├── comprehensive/            #   全速域综合分析
│   │   ├── replay_aligned/           #   对齐后 replay 对比
│   │   └── setpoint_replay_*/        #   高速 replay 结果
│   ├── gobi/                          # ★ Gobi 截击机实验结果（0-97 m/s）
│   │   ├── gobi_speed_profile.png    #   v1 全速域飞行剖面
│   │   ├── gobi_kf_vs_speed.png      #   v1 k_f 辨识 vs 速度
│   │   ├── gobi_drag_analysis.png    #   v1 线性/二次阻力对比
│   │   ├── gobi_cda_vs_speed.png     #   v1 表观 CdA 分析
│   │   ├── gobi_v2_speed_profile.png #   v2 全速域飞行剖面
│   │   ├── gobi_v2_kf_vs_speed.png   #   v2 k_f 辨识 vs 速度
│   │   ├── gobi_v2_drag_analysis.png #   v2 阻力分析
│   │   ├── gobi_v2_cda_vs_speed.png  #   v2 CdA 分析
│   │   └── gobi_v1_vs_v2_speed.png   #   ★ v1 vs v2 速度对比
│   ├── sysid_analysis/               # 系统辨识结果
│   ├── sp_experiments.json
│   └── x500_truth_csv/
└── README.md
```

### 复现步骤

```bash
# 1. 采集 x500 真值数据
cd PX4-Autopilot
HEADLESS=1 make px4_sitl gz_x500
# 另一个终端：
python3 scripts/fly_mission.py

# 2. 设定点回放（自动化 4 轮）
bash scripts/run_setpoint_replay_all_rounds.sh

# 3. 或手动单轮：修改参数 → 启动仿真 → 回放
python3 scripts/update_interceptor_params.py --mass 2.3 --motorConstant 7.01e-06
cd PX4-Autopilot && HEADLESS=1 make px4_sitl gz_interceptor
# 另一个终端：
python3 scripts/setpoint_replay.py \
    --ulg data/flight_logs/x500_truth.ulg \
    --output-dir results/sp_round1

# 4. 提取 ULG 并对比
python3 scripts/extract_ulg.py <interceptor_ulg> --output-dir results/sp_round1/interceptor_csv
python3 scripts/compare.py results/x500_truth_csv results/sp_round1/interceptor_csv \
    --output-dir results/sp_round1

# 5. 查看收敛趋势
python3 scripts/sensitivity.py results/sp_experiments.json

# 6. 高速实验（x500_hp 模型，需要先创建）
python3 scripts/create_hp_model.py
python3 scripts/run_full_experiment.py
python3 scripts/comprehensive_analysis.py

# 7. Gobi v1（线性阻力）97 m/s 实验
python3 scripts/create_gobi_model.py
cd PX4-Autopilot && make px4_sitl gz_x500
PX4_SYS_AUTOSTART=4098 PX4_GZ_MODEL=gobi HEADLESS=1 \
  build/px4_sitl_default/bin/px4 build/px4_sitl_default/etc
# 另一个终端：
python3 scripts/fly_gobi_multispeed.py
python3 scripts/gobi_analysis.py

# 8. 构建 QuadraticDrag 插件 + Gobi v2（v² 阻力）实验
cd plugins/quadratic_drag && mkdir -p build && cd build
cmake .. && make -j$(nproc)
cd ../../..
python3 scripts/create_gobi_v2_model.py
cd PX4-Autopilot && make px4_sitl gz_x500 && cd ..
# 用辅助脚本启动（自动设置插件路径）
bash scripts/run_gobi_v2_sitl.sh
# 另一个终端：
python3 scripts/fly_gobi_multispeed.py
python3 scripts/gobi_analysis.py results/gobi/gobi_v2_multispeed.ulg results/gobi gobi_v2

# 9. 对比 v1 vs v2 阻力效果
python3 scripts/compare_gobi_v1_v2.py
```
