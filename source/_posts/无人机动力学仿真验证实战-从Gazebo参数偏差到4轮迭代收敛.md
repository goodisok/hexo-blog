---
title: 无人机动力学仿真验证实战：从 Gazebo 参数偏差到 4 轮迭代收敛
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
---

> 核心问题：我手里有一个四旋翼动力学模型，参数是猜的，怎么验证它离"真实飞机"有多远？
>
> 本文用一个**纯仿真闭环实验**完整走通了 Sim-to-Real 动力学验证流程。实验方法是**设定点回放（Setpoint Replay）**——从"真值"飞机的 ULG 日志中提取 trajectory_setpoint，回放给"待校准"的仿真模型，比较两者在相同目标下的动力学响应差异。4 轮迭代参数修正后，垂直速度 RMSE 下降 48%，俯仰角 RMSE 下降 45%，偏航角速度 RMSE 下降 42%。
>
> 这套方法的核心价值在于：**它和实机验证的工作流完全一致**。外场飞完拿到 ULG → 提取设定点 → 回放到仿真 → 对比响应 → 修正参数。在买飞机之前，用纯仿真把整条流水线跑通。

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
5. **回放完毕后着陆、解锁**，PX4 自动保存 ULG

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

## 9. 推荐的实机验证流程

拿到实机后，参数辨识的优先级按灵敏度排序：

1. **推力台测试 → 修正 motorConstant**。本实验证明推力系数是最敏感的参数（贡献 ~39% 的 RMSE 下降）。单电机上推力台，记录油门-推力曲线，拟合 `F = k_f × ω²` 中的 k_f。
2. **称重 → 修正 mass**。最简单、影响第二大（贡献 ~15% 的 Vz RMSE 下降）。
3. **飞行测试 + 设定点回放验证**。让实机飞一套标准机动，从 ULG 提取 trajectory_setpoint，回放到仿真，算 RMSE。
4. **如需精确验证惯性矩**——降低比较层级。设定点回放无法观测 Ixx/Iyy 差异（被控制器遮蔽），需要用**姿态设定点回放**（从 ULG 提取 `vehicle_attitude_setpoint`）或摆振测试直接测量。

---

## 10. 仿真到外场：制导算法能直接移植吗？

读者可能会问：在这个仿真环境中开发的截击/制导算法，调好参数后能不能直接部署到实机？

**简短回答：算法逻辑可以移植，但不能直接信任仿真中的性能指标。**

### 10.1 可以移植的部分

如果你的制导算法工作在**设定点层级**（输出位置/速度目标，通过 MAVSDK offboard 接口下发），那么算法代码可以不做修改地在实机上运行——因为 PX4 在 SITL 和实机硬件上跑的是同一份飞控代码，MAVSDK 接口完全一致。

### 10.2 仿真没有覆盖的关键差距

| 维度 | 本文仿真验证的范围 | 实际截击场景的需求 | 差距 |
|------|------------------|------------------|------|
| 速度 | 0-3 m/s（低速悬停/平飞） | 10-30+ m/s | 高速气动力、螺旋桨入流效应未建模 |
| 姿态角 | ±15° | ±45° 以上 | 大迎角非线性效应未覆盖 |
| 传感器 | Gazebo 理想 IMU/GPS | 相机噪声、GPS 拒止、目标检测延迟 | 传感器模型完全缺失 |
| 环境扰动 | 无风 | 阵风、湍流 | 风场模型未添加 |
| 执行器 | 线性推力模型 `F = k_f × ω²` | 电机饱和、ESC 非线性、电池电压跌落 | 执行器边界行为未验证 |

特别值得警惕的是我们实验中的一个发现：**PX4 控制器在低速域有极强的鲁棒性**（Round 3→4 惯性矩偏差 15% 完全被遮蔽）。这意味着低速仿真中"看起来没问题"的参数偏差，在高速高机动时控制裕度缩小后可能突然暴露，导致失控。

### 10.3 推荐的移植路径

```
仿真开发（本文） → 扩展仿真包线 → HIL 验证 → 低速实飞 → 逐步扩包线
     ✅              ↓               ↓          ↓           ↓
  参数调好了      加风场/传感器噪声  飞控硬件实时性   用 setpoint_replay  每步都对比
                 高速机动测试      计算约束验证     验证动力学匹配度    仿真 vs 实飞
```

**本文建立的 setpoint_replay 工具链在第 4 步（低速实飞验证）中可以直接使用**——这正是从一开始就选择设定点回放方法的原因。但前面三步不能跳过。

---

## 11. 代码仓库与复现

仓库地址：[github.com/goodisok/gazebo-px4-sim](https://github.com/goodisok/gazebo-px4-sim)

```
gazebo-px4-sim/
├── PX4-Autopilot/                      # PX4 v1.16.1（.gitignore）
├── px4_custom/                         # PX4 中新增的自定义文件
│   ├── models/interceptor/             # interceptor SDF 模型
│   └── airframes/4050_gz_interceptor
├── scripts/
│   ├── fly_mission.py                  # x500 真值数据采集
│   ├── setpoint_replay.py             # ★ 设定点回放（核心实验脚本）
│   ├── extract_ulg.py                 # ULG → CSV
│   ├── compare.py                     # 时间对齐 + RMSE/R² + 对比图
│   ├── sensitivity.py                 # 多轮收敛分析
│   ├── sp_convergence_analysis.py     # 4 维收敛图生成
│   ├── update_interceptor_params.py   # 命令行修改 SDF 参数
│   ├── run_setpoint_replay_all_rounds.sh  # 4 轮自动化脚本
│   └── openloop_replay.py            # 开环回放（实验证伪用）
├── worlds/
│   └── openloop.sdf                   # 独立 Gazebo world（无 PX4）
├── data/flight_logs/                   # ULG 日志（.gitignore）
├── results/
│   ├── sp_round1/ ~ sp_round4/        # ★ 4 轮设定点回放结果
│   ├── sp_experiments.json            # 实验配置
│   ├── sp_convergence_full.png        # 4 维收敛图
│   ├── x500_truth_csv/               # 真值数据 CSV
│   ├── openloop_round4/              # 开环回放结果（证伪）
│   ├── convergence.png
│   └── sensitivity_table.txt
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
```

---

> 动力学验证没有捷径，但有方法。设定点回放让你在纯仿真中建立与实机验证完全一致的工具链——飞完就分析，代码不用改。
