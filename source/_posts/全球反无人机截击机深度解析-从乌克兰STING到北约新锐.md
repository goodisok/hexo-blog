---
title: 全球反无人机截击机深度解析：从乌克兰 STING 到中国天穹，全球主流系统技术全览
date: 2026-03-28 21:00:00
categories:
  - 无人机
  - 技术前沿
tags:
  - 反无人机
  - 截击无人机
  - C-UAS
  - STING
  - GOBI
  - BLAZE
  - DroneHunter
  - Anvil
  - Skyhammer
  - Coyote
  - Iron Drone
  - Hunter Eagle
  - Cicada
  - 天穹
  - FK-3000
  - LW-30
  - SKYFEND
  - 无人机战争
  - 中国
  - 乌克兰
  - 北约
  - 防空
mathjax: false
---

> 当一枚造价 3.5 万美元的 Shahed 自杀无人机可以迫使防御方发射一枚数十万美元的防空导弹时，战争经济学就已经倒向了攻击方。截击无人机——用无人机拦截无人机——正在改写这一等式。本文基于公开资料、官方技术手册和战场验证数据，深度分析全球主流反无人机拦截系统，涵盖乌克兰、法国、美国、英国、以色列、拉脱维亚、德国、瑞士、中国等九个国家的产品。

---

## 一、为什么需要截击无人机

### 1.1 成本不对称困境

俄乌战争让一个残酷的数学问题摆上了每个防空指挥官的桌面：

| 攻击手段 | 单价 | 防御手段 | 单价 | 成本比 |
|---------|------|---------|------|--------|
| Shahed-136/Geran-2 | ~\$35,000 | IRIS-T SLM 导弹 | ~\$430,000 | 1:12 |
| 商用 FPV 无人机 | ~\$500 | Gepard 35mm 弹药（一个射击周期） | ~\$5,000 | 1:10 |
| Shahed-136 | ~\$35,000 | **STING 截击机** | **~\$2,100** | **17:1（防御方优势）** |

截击无人机将成本比**逆转**——用 2000 美元的消耗品击落 35000 美元的目标。2025 年 1 月，俄罗斯仅一个月就向乌克兰发射了超过 2,500 架无人机，传统防空系统根本无法承受如此规模的消耗战。

### 1.2 截击无人机的分类

按毁伤方式可分为三大类：

| 类别 | 毁伤方式 | 代表型号 | 优势 | 劣势 |
|------|---------|---------|------|------|
| **动能撞击** | 高速碰撞摧毁目标 | GOBI、Anvil | 无爆炸物、附带伤害小 | 需精确制导 |
| **战斗部杀伤** | 高爆/破片战斗部 | BLAZE、STING | 杀伤半径大、容错率高 | 有爆炸碎片坠落风险 |
| **捕获型** | 网枪/拖曳网 | DroneHunter F700 | 完整俘获、可重复使用 | 速度受限、仅适用于慢速目标 |

---

## 二、乌克兰 STING（毒刺）——战场验证之王

### 2.1 基本信息

| 项目 | 数据 |
|------|------|
| 研发方 | Wild Hornets（野蜂群），乌克兰 |
| 类型 | 四旋翼巡飞弹/截击无人机 |
| 首次服役 | 2024 年 |
| 单价 | ~\$2,100 |
| 月产能 | >10,000 架（2026 年 3 月） |

### 2.2 技术参数

| 参数 | 数值 |
|------|------|
| 最高速度 | 343 km/h（213 mph） |
| 巡航高度 | 3,000 m（10,000 ft） |
| 交战距离 | 25 km |
| 控制距离 | 2,000 km（通过 Hornet Vision 系统） |
| 机身 | 3D 打印子弹形气动外壳，四旋翼驱动 |
| 制导 | Kurbas-640 热成像相机（Odd Systems）+ AI 自动跟踪 |
| 毁伤方式 | 动能撞击 + 自身爆炸 |

### 2.3 实战表现

STING 是目前全球**实战数据最丰富**的截击无人机：

- 截至 2026 年 2 月，累计击落超过 **3,900 架** Geran 系列无人机
- 自 2025 年 10 月起连续 **7 个月**保持乌克兰反 Shahed 拦截量第一
- 2025 年 12 月首次成功击落喷气式 Geran-3（Shahed 的涡喷改型）
- 2026 年 4 月，STING 拦截了 **70%** 的喷气式 Shahed 变体
- 2025 年 10 月在丹麦成功向北约盟国进行了实弹演示

### 2.4 技术亮点

**3D 打印制造**：STING 的子弹形外壳采用 3D 打印，大幅缩短了制造周期，使月产能突破万架。这种制造方式极其适合战时的分布式生产——将打印机部署在多个隐蔽地点，降低被打击风险。

**Hornet Vision 控制系统**：操作员可以在 2,000 km 外通过卫星链路远程遥控 STING，这意味着操作员可以安全地驻扎在远离前线的后方。

**AI 热成像制导**：Kurbas-640 热成像相机配合 AI 目标识别算法，可在夜间自动锁定并追踪 Shahed 无人机的发动机热信号。这是 STING 在夜间大规模无人机袭击中高效拦截的关键。

---

## 三、法国 GOBI——极速轻量化拦截者

### 3.1 基本信息

| 项目 | 数据 |
|------|------|
| 研发方 | Harmattan AI，法国初创公司（2024 年 4 月成立） |
| 类型 | AI 驱动高速动能截击无人机 |
| 首次发布 | 2025 年 7 月 |
| 单价 | €5,000–7,000 |
| 首批订单 | 2025 年 7 月，某 NATO 成员国签署数百万欧元合同 |

### 3.2 技术参数

| 参数 | 数值 |
|------|------|
| 巡航速度 | 250 km/h（155 mph） |
| 最大速度 | 350 km/h（217 mph） |
| 拦截距离 | 5 km |
| 撞击动能 | >10,300 J |
| 从发射到击毁 | <1 分钟 |
| 起飞准备时间 | 0 秒（随时待命） |
| 尺寸 | 32 × 34 × 34 cm |
| 重量（含电池） | 2.2 kg（4.8 lbs） |
| 毁伤方式 | 纯动能撞击（无战斗部） |
| 最大可拦截目标重量 | 600 kg |

### 3.3 技术亮点

**极致轻量化**：2.2 kg 的全重让 GOBI 成为目前已知最轻的截击无人机之一。可由步兵班组携带，从紧凑型管式发射器或轻型车载导轨发射。

**纯动能毁伤**：GOBI 不携带任何爆炸物，完全依靠高速撞击产生的超过 10,300 焦耳动能摧毁目标。这大幅降低了附带损害风险，特别适合城市环境和关键基础设施周边防御。作为参照，10,300 焦耳约相当于一辆小汽车以 25 km/h 速度撞墙的能量。

**AI 自主末段制导**：嵌入式 AI 模型在机载处理器上运行，实现完全自主的目标识别和跟踪，不依赖外部数据链。这在电子战环境中至关重要——即使通信被干扰，GOBI 仍能完成拦截。

**从成立到交付仅 15 个月**：Harmattan AI 2024 年 4 月成立，2025 年 7 月即获得多百万欧元合同，计划 2025 年 10 月交付。这种极速研发节奏反映了当前反无人机需求的紧迫性。

### 3.4 已知部署

法国已在中东 Al Dhafra 空军基地（阿布扎比）部署了 GOBI 截击机，作为三重截击体系的一部分，用于防御伊朗 Shahed 无人机威胁。

---

## 四、拉脱维亚 BLAZE——北约标准化先锋

### 4.1 基本信息

| 项目 | 数据 |
|------|------|
| 研发方 | Origin Robotics，拉脱维亚 |
| 类型 | 单兵便携自主截击无人机 |
| 首次发布 | 2025 年 5 月 |
| 已交付国家 | 拉脱维亚、比利时、爱沙尼亚 |
| 北约编码 | 首个获得 NATO 编码的自主截击无人机 |

### 4.2 技术参数

| 参数 | 数值 |
|------|------|
| 重量 | <6 kg |
| 交战距离 | 10–20 km |
| 飞行时间 | ~20 分钟 |
| 战斗部 | 800g 高爆破片战斗部 |
| 毁伤方式 | 直接撞击引爆或空中爆破 |
| 首次发射准备 | <5 分钟 |
| 后续发射间隔 | <1 分钟 |
| 系统展开 | 无需工具，<10 分钟 |
| 检测 | 雷达探测 + AI 计算机视觉 |
| 人员控制 | 操作员监督自主模式（可随时中止） |

### 4.3 技术亮点

**双重引爆模式**：BLAZE 可以在直接撞击目标时引爆，也可以在接近目标时进行**空中爆破**（airburst），释放破片云覆盖目标。空中爆破模式提供更大的容错率，即使轻微偏差也能造成有效毁伤。

**NATO 编码认证**：BLAZE 是全球首个获得 NATO 编码的自主截击无人机，这意味着它可以无缝接入 NATO 的后勤补给和指挥控制体系，对于跨国联合作战至关重要。

**运输箱即发射站**：BLAZE 的运输箱兼具发射站和充电座功能，整个系统无需任何工具即可在 10 分钟内完成部署。单兵可携带，适合前线快速反应。

**BEAK 实战血统**：Origin Robotics 的前代产品 BEAK 无人机已在乌克兰和拉脱维亚军队中实战部署，积累了宝贵的实战经验。BLAZE 继承了 BEAK 的自主控制技术，并专门针对高速拦截进行了优化。

---

## 五、美国 Fortem DroneHunter F700——非致命捕获专家

### 5.1 基本信息

| 项目 | 数据 |
|------|------|
| 研发方 | Fortem Technologies，美国犹他州 |
| 类型 | 网枪捕获式反无人机拦截器 |
| 服役状态 | 多国实战部署 |
| 合同 | 2026 年 1 月获美国国防部 Replicator II 项目合同 |

### 5.2 技术参数

| 参数 | 数值 |
|------|------|
| 构型 | 六旋翼 VTOL |
| 重量 | ~18 kg（40 lbs） |
| 毁伤方式 | 网枪发射拖曳网捕获 |
| 空中捕获成功率 | ~85%（实战数据） |
| 首次闪避率 | ~15%（可追加第二次射网） |
| 拦截距离 | ~4 km |
| 发射准备时间 | <3 分钟 |
| 重装/再次出击 | <3 分钟 |
| 作战条件 | 全天候（雨/雪/雾）、日/夜 |
| 机载雷达 | TrueView R20（探测/跟踪/末段制导一体） |
| 可拦截目标 | Group 1–3 无人机（含 Shahed-136、Orlan-10） |

### 5.3 实战与部署

截至 2026 年 1 月，DroneHunter F700 已在全球实战部署中完成超过 **4,500 次**（接近 5,000 次）无人机捕获，部署地区包括乌克兰、中东、东亚等。

2026 年 1 月 13 日，美国国防部联合跨部门工作组 JATF-4001（2025 年 8 月成立，专项协调反小型无人机能力）宣布在 Replicator II 计划下首次采购，授予 Fortem 两套 DroneHunter F700 系统合同，预计 2026 年 4 月交付，用于增强本土防御。

### 5.4 技术亮点

**非致命完整俘获**：DroneHunter 的核心差异化在于**完整捕获**——通过网枪发射快速展开的拖曳网将目标无人机兜住，然后将其拖到安全区域降落。这意味着可以：
- 对敌方无人机进行**取证分析和情报提取**
- 在城市/机场等敏感区域执行任务时零碎片坠落风险
- 系统可**重装后再次出击**，无需消耗

**机载 TrueView R20 雷达**：每架 DroneHunter 自带微型 AESA 雷达，自主完成目标探测→跟踪→末段制导全流程，不依赖外部雷达站。可在雨、雪、雾等恶劣天气条件下全天候作战。

**AI 自主战术调整**：机载 AI 根据目标的位置、速度、方向和类型自主调整拦截战术。同时保留"人在环上"（human-on-the-loop）选项，操作员可随时手动接管。

---

## 六、美国 Anduril Anvil——硅谷式反无人机方案

### 6.1 基本信息

| 项目 | 数据 |
|------|------|
| 研发方 | Anduril Industries，美国 |
| 类型 | 自主动能截击无人机 |
| 变体 | Anvil（动能撞击）、Anvil-M（高爆战斗部） |
| 集成平台 | Lattice OS 指挥控制系统 |

### 6.2 技术参数

| 参数 | 数值 |
|------|------|
| 重量（Anvil） | ~5.3 kg（11.6 lbs） |
| 可拦截目标 | Group 1–2 无人机 |
| 毁伤方式 | 动能撞击（Anvil）/ 高爆战斗部（Anvil-M） |
| 发射方式 | Anvil Launch Box 地面发射箱 |
| 发射箱重量 | 115 kg（253 lbs） |
| 发射箱尺寸 | 160 × 117 × 76 cm |
| 发射箱容量 | 2 枚 Anvil |
| 制导 | 雷达 + 多光谱计算机视觉融合 |
| 计算平台 | NixOS 边缘计算，运行 CV/ML 算法 |
| 驱动 | 优化螺旋桨 + 高 KV 无刷电机 + 50V 电池 |

### 6.3 技术亮点

**Lattice OS 生态集成**：Anvil 不是一个独立系统，而是 Anduril 端到端反无人机体系的"硬杀伤"最后一环。Lattice OS 融合多源传感器（被动红外 Wisp、主动雷达 Pulsar、Sentry 自主瞭望塔）数据，进行态势感知后引导 Anvil 拦截。

**抗毁设计**：所有关键飞行部件都被设计在远离撞击点的位置，最大程度降低撞击时自身受损导致拦截失败的风险。

**Anvil-M 战斗部变体**：基于实战反馈开发的 Anvil-M 携带高爆战斗部和火控模块，用于应对更快、更高价值的 Group 2 级别目标。

**实战评估**：2025 年 11 月在美国 Minot 空军基地进行了实战评估，模拟基地防御场景下的探测-识别-交战全流程。

---

## 七、法国 Alta Ares X-Wing & Black Bird——法乌联合研发

### 7.1 X-Wing（电动截击型）

| 参数 | 数值 |
|------|------|
| 研发方 | Alta Ares（法国）+ Tenebris（乌克兰）联合 |
| 构型 | VTOL 四旋翼 |
| 重量 | ~3.5 kg（不含战斗部） |
| 最大速度 | 300 km/h |
| 交战距离 | 15 km |
| 飞行时间 | 15 分钟 |
| 制导 | Pixel Lock AI 自主制导（无需 GNSS） |
| 实战拦截成功率 | ~54%（乌克兰战场数据） |

### 7.2 Black Bird（涡喷截击型）

| 参数 | 数值 |
|------|------|
| 构型 | 固定翼 + 涡喷发动机（推力 12 kg） |
| 重量 | ~6 kg（不含战斗部） |
| 最大速度 | 670 km/h |
| 交战距离 | 30 km |
| 飞行时间 | 20 分钟 |
| 制导 | AI 末段制导 |
| 状态 | 原型阶段，2026 年 2 月爱沙尼亚北极条件测试成功 |

### 7.3 Safe Protection Dome 系统

Alta Ares 的整体防御概念是 **Safe Protection Dome（安全防护穹）**，集成了：
- Thales / Echodyne 战术雷达
- X-Wing 四旋翼截击机（短距）
- Black Bird 涡喷截击机（远距，30 km）
- 毁伤距离覆盖 30 km 范围

该系统 2025 年 10 月 20 日通过 NATO 验证，**10 天后**即部署乌克兰，并在实战中首次成功击落俄方 Shahed 无人机。

### 7.4 技术亮点

**Pixel Lock 算法**：Alta Ares 自研的 AI 视觉锁定系统，直接嵌入截击机的机载计算机。可在无 GNSS 信号的环境下自主检测和锁定敌方无人机轮廓，对抗 GPS 干扰能力强。据称可将末段拦截精度提升 35%。

**法乌联合研发模式**：法国提供 AI 算法和系统集成能力，乌克兰提供战场数据和实战验证。这种"实验室-战场"快速迭代模式大幅加速了产品成熟度。

**670 km/h 的 Black Bird**：涡喷动力的 Black Bird 是目前公开信息中**速度最快**的截击无人机之一，专门针对俄罗斯新型喷气式 Geran-5 设计。2026 年 2 月在爱沙尼亚极地环境下完成测试。

---

## 八、瑞士 Destinus Hornet——从 VSHORAD 到 SHORAD 的补缺者

### 8.1 型号谱系

Destinus Hornet 采用渐进式发展路线，目前有三个主要变体：

| 变体 | 发布时间 | 射程 | 载荷 | 动力 | 速度 |
|------|---------|------|------|------|------|
| Hornet（原型） | FEINDEF 2025 | 20 km | 1.5 kg | 电动后推桨 | 250 km/h |
| Hornet 3 / Block 1 | WDS 2026 | >45 km | 1.5 kg | 涡喷 + 助推器 | 高亚音速 |
| Hornet Block 2 | BEDEX 2026 | >70 km | 3 kg | 电动 + 助推器 | — |

### 8.2 技术特点

**定位独特**：Destinus 将 Hornet 定位在 VSHORAD（极短程防空）和 SHORAD（短程防空）之间的空白地带。传统的弹炮系统射程有限（几百米到几公里），而短程防空导弹太贵不适合打无人机。Hornet 以 45-70 km 的射程填补这个空档。

**密封罐装发射**：采用密封发射管储存和发射，折叠弹翼+助推器发射。可以高密度装载在车辆、固定阵地或舰艇上。密封设计解决了储存和环境适应性问题。

**可对抗直升机**：Block 2 的 3 kg 载荷和 70 km 射程使其不仅限于反无人机，官方明确列出直升机也在目标清单中。

**AI 末段制导 + 电子战对抗**：机载 AI 导引头结合电子战干扰能力，可在复杂电磁环境下完成末段制导。

---

## 九、英国 Cambridge Aerospace Skyhammer——闪电采购的涡喷拦截弹

### 9.1 基本信息

| 项目 | 数据 |
|------|------|
| 研发方 | Cambridge Aerospace，英国（2024 年底成立） |
| 类型 | 管式发射涡喷拦截弹 |
| 首次飞行 | 2025 年 1 月开发，6 周内完成首飞 |
| 合同 | 2026 年 4 月英国国防部签署数百万英镑合同 |
| 首批交付 | 2026 年 5 月 |

### 9.2 技术参数

| 参数 | 数值 |
|------|------|
| 最大速度 | 700 km/h（Mach 0.7） |
| 射程 | >30 km |
| 重量 | ~18 kg（40 lbs） |
| 长度 | <1 m |
| 翼展 | 1.3 m |
| 动力 | 涡喷发动机 |
| 导引头 | X 波段雷达导引头（全天候） |
| 战斗部 | 爆破破片战斗部 |
| 可拦截目标 | Shahed 级自杀无人机、亚音速巡航导弹 |
| 构型 | 折叠半翼 + 倒 V 尾翼，管式储存/发射 |

### 9.3 技术亮点

**从零到交付仅 16 个月**：Cambridge Aerospace 2024 年底成立，2025 年 1 月开始研发 Skyhammer，6 周内完成首飞，2026 年 4 月获得英国国防部合同，5 月即开始交付。这是英国近代国防采购中最快的时间线之一。

**真正的"拦截弹"**：与大多数多旋翼截击无人机不同，Skyhammer 更接近微型导弹——涡喷推进、雷达制导、爆破破片战斗部。700 km/h 的速度让它可以拦截不仅是慢速 Shahed，还包括亚音速巡航导弹。

**X 波段雷达全天候能力**：X 波段主动雷达导引头使 Skyhammer 不依赖光电/红外传感器，可在雨、雾、沙尘暴等恶劣天气中工作。

**英国-海湾双向部署**：该合同不仅面向英军，还包括向海湾合作伙伴供货，附带集成支持、技术援助和操作员培训。

---

## 十、美国 RTX/Raytheon Coyote 系列——美军 C-UAS 主力

### 10.1 型号谱系

Coyote 是美军 LIDS（低慢小无人机综合防御系统）的核心拦截弹，已发展出多个变体：

| 变体 | 毁伤方式 | 动力 | 速度 | 可回收 | 采购量 |
|------|---------|------|------|--------|-------|
| Block 2+ | 动能/破片战斗部 | 涡轮发动机 + 火箭助推 | 555–595 km/h | 否（消耗型） | ~6,700 枚 |
| Block 3NK | 非动能（电子战载荷） | 电动后推桨 | 较低（巡飞优化） | 是（可回收重用） | ~700 枚 |
| LE SR | 多用途发射效应 | 电动 | — | 否 | 原型阶段 |

### 10.2 技术参数（Block 2+）

| 参数 | 数值 |
|------|------|
| 重量 | 比 Block 1 的 5.9 kg 更重（具体保密） |
| 速度 | 555–595 km/h（345–370 mph） |
| 射程 | 10–15 km |
| 战斗部 | 破片战斗部（针对小型无人机优化） |
| 配套雷达 | KuRFS Ku 波段 AESA 雷达（可探测 9 mm 弹头大小目标） |
| 单价 | ~\$100,000/枚 |

### 10.3 技术亮点

**美军唯一成建制装备的 C-UAS 拦截弹**：Coyote 是美国陆军 M-LIDS 和 FS-LIDS 系统的标准配置拦截弹，已实战部署。2023-2029 年间计划采购约 6,700 枚。

**KuRFS 雷达配合**：Ku 波段射频传感器可探测 16 km 外的小型无人机，最小可探测 9 mm 弹头大小的目标，为 Coyote 提供精确引导。

**Block 3NK 非动能反蜂群**：2026 年 2 月美军演示中，Block 3NK 成功击败无人机蜂群。它使用电子战载荷而非物理碰撞来瘫痪目标，一架 Block 3NK 可对抗多架无人机，且可回收重装后再次使用，从根本上改变了反蜂群的经济学。

**多平台发射**：Coyote LE SR 变体已成功从 M2 Bradley 战车的 TOW 发射器和 Bell 407 直升机上发射，展示了跨平台适配能力。

---

## 十一、以色列 Iron Drone Raider——加沙战场验证的自主拦截器

### 11.1 基本信息

| 项目 | 数据 |
|------|------|
| 研发方 | Airobotics（Ondas Autonomous Systems 子公司），以色列 |
| 类型 | 八旋翼自主截击/捕获无人机 |
| 实战 | 加沙冲突中实战验证 |
| 状态 | 2025 年起进入美国国防市场 |

### 11.2 技术参数

| 参数 | 数值 |
|------|------|
| 构型 | 八旋翼（竞速无人机衍生） |
| 重量 | ~4 kg（8 lbs） |
| 速度 | 竞速无人机级别（极高机动性） |
| 载荷 | 1 kg 弹道网（含可选降落伞） |
| 可拦截目标 | Class-1 旋翼/固定翼无人机 |
| 拦截距离 | 数英里（~3-5 km） |
| 发射箱容量 | 3 架 Raider |
| 传感器 | 地面雷达 + 机载微型雷达 + 热成像/光学 + AI 视觉 |
| 操作 | 全自主（检测→发射→跟踪→捕获→返航全流程无人值守） |

### 11.3 技术亮点

**竞速无人机基因**：Iron Drone Raider 源自高速竞速无人机平台，具备极高的加速度和机动性，可追上大多数消费级和军用小型无人机。

**全自主闭环**：从目标检测、Raider 发射、飞向目标区域、机载传感器接管、AI 视觉锁定、发射捕获网、目标降落、Raider 返航、装填新网、重新待命——整个流程**全自主完成**，无需人工飞手。

**网+降落伞安全捕获**：捕获网将目标无人机缠绕后，可选降落伞减缓坠落速度，减少地面冲击。这使其特别适合城市上空、机场、监狱等敏感区域。

**加沙实战验证**：在哈马斯-以色列冲突中加速升级并实战部署，积累了宝贵的实战经验，是少数真正经历过热战考验的截击系统。

---

## 十二、以色列 Rafael Hunter Eagle & Ghost Hunter——从 Iron Dome 到无人机对无人机

### 12.1 Hunter Eagle（VTOL 动能截击型）

| 参数 | 数值 |
|------|------|
| 研发方 | Rafael（以色列） |
| 构型 | VTOL，十字形翼 + 翼尖电动机 |
| 高度 | 0.4–0.5 m |
| 重量 | 5–10 kg |
| 速度 | 估计 150–200 km/h |
| 射程 | 估计 10–15 km |
| 战斗部 | 无爆炸物（纯动能） |
| 制导 | 机鼻光电导引头 + AI 自主 |
| 蜂群能力 | 支持多机协同 |
| 状态 | 2025 年底演示，2026 年交付 |

### 12.2 Ghost Hunter（涡喷远程截击型）

| 参数 | 数值 |
|------|------|
| 构型 | 十字形三角翼 + 双涡喷发动机 |
| 高度 | 1.4–1.6 m |
| 重量 | 50–60 kg |
| 速度 | Hunter Eagle 的约 2 倍（估计 300-400 km/h） |
| 制导 | 机鼻 RF 雷达 + AI |
| 载荷 | 数公斤级战斗部 |
| 状态 | 2026 年底演示，2027 年量产交付 |

### 12.3 技术亮点

**Rafael 防空体系的延伸**：Rafael 是 Iron Dome（铁穹）的研发商。Hunter Eagle 和 Ghost Hunter 是 Rafael 将其防空能力向"反无人机"领域延伸的产物，与 Drone Dome（检测分类）、Lite Beam（10 kW 激光）共同构成分层 C-UAS 体系。

**无爆炸物的城市安全设计**：Hunter Eagle 不携带任何爆炸物，完全依靠动能撞击。如果拦截失败或任务取消，可自主返航垂直降落，避免"副作用"。这使它成为城市和人口密集区最安全的截击方案之一。

**Ghost Hunter 的涡喷双发设计**：50-60 kg 的起飞重量、双涡喷发动机、RF 雷达制导，Ghost Hunter 实质上是一枚微型空对空导弹，专门对付高速高价值无人机目标。

---

## 十三、德国 Diehl Cicada——IRIS-T 家族的反无人机延伸

### 13.1 基本信息

| 项目 | 数据 |
|------|------|
| 研发方 | Diehl Defence，德国（IRIS-T 防空导弹制造商） |
| 类型 | 垂直起飞螺旋桨截击无人机 |
| 首次展示 | EnforceTac 2025（纽伦堡） |
| 计划上市 | 2026 年 |
| 集成系统 | Guardion / Sky Sphere / Garmr C-UAS |

### 13.2 技术参数

| 参数 | 数值 |
|------|------|
| 长度 | 700 mm |
| 直径 | 300 mm |
| 构型 | 圆柱机身 + X 形四三角翼（可折叠） |
| 动力 | 机鼻五叶电动螺旋桨 |
| 最大速度 | 200 km/h |
| 拦截距离 | 4–5 km |
| 飞行时间 | ~5 分钟 |
| 中段制导 | 无线电数据链 + 地面引导 |
| 末段制导 | 机载万向节主动雷达 |
| 战斗部 | 高爆破片（军用版）/ 捕获网（非致命版） |
| 可拦截目标 | Class 1-2 无人机（含 ~200 kg 级 Shahed-131） |

### 13.3 技术亮点

**IRIS-T 厂商背书**：Diehl Defence 是德国 IRIS-T SLM 防空导弹系统的制造商，该系统在乌克兰战场已大量拦截俄方导弹和无人机。Cicada 是 Diehl 将其防空经验向低成本反无人机领域的延伸。

**Garmr 系统集成**：Cicada 不是独立产品，而是 Diehl Garmr 移动 C-UAS 系统的一部分。Garmr SRS（短程）版本搭载 15 枚 Cicada，Garmr MRS（中程）版本则换装 4 枚 Destinus Hornet Block 2，形成短程+中远程分层。

**双模战斗部**：军用高爆破片版本用于硬杀伤，民用捕获网版本用于机场、核电站等需要"零碎片"的场景。网版可回收重装。

**主动雷达末制导**：机鼻的万向节主动雷达可以在末段自主锁定目标，不依赖光电传感器，在夜间和恶劣天气中仍然有效。

---

## 十四、以色列 SpearUAV Viper I——装甲车辆的"随身防空盾"

### 14.1 基本信息

| 项目 | 数据 |
|------|------|
| 研发方 | SpearUAV，以色列 |
| 类型 | 罐装发射拦截巡飞弹 |
| 定位 | 装甲车辆/固定阵地上层攻击防御 |
| 状态 | 系统集成阶段，即将交付 |

### 14.2 技术参数

| 参数 | 数值 |
|------|------|
| 发射重量 | 3.5 kg |
| 载荷 | 最大 1.3 kg（第三方战斗部） |
| 拦截距离 | 2 km |
| 构型 | 圆柱体机身，折叠旋翼臂，罐装发射 |
| 制导 | AI 高速目标跟踪 |
| 发射器 | Multi Canister Launcher（MCL），可载多枚 |
| 平台兼容 | IFV、MBT、UGV、4×4 车辆、舰船 |
| 开放架构 | 兼容第三方传感器、通信设备、战斗部 |

### 14.3 技术亮点

**车载一体化防空**：Viper I 的核心理念是让每辆装甲车都拥有自己的反无人机能力。MCL 发射器可以直接安装在步战车、主战坦克、无人地面车辆上，车辆行进中即可发射。

**与 Rafael Trophy 主动防护集成**：Viper I 可以与 Rafael Trophy APS（主动防护系统）集成，为装甲车辆提供从反坦克导弹到无人机的全方位防护。

**Viper 家族通用发射器**：同一个 MCL 发射器可以混装 Viper 300（侦察巡飞弹）和 Viper I（截击型），使一辆车同时拥有侦察和防空能力。

---

## 十五、中国反无人机体系——不同技术路线的全面布局

中国在反无人机领域的投入非常大，但**技术路线与西方有显著差异**：西方国家（尤其是乌克兰/北约）以"截击无人机"为主力，用无人机打无人机；中国则走了一条**"激光/微波定向能 + 微型拦截弹 + 综合体系"**的复合路线。

### 15.1 SKYFEND Thunder——中国出口型截击无人机

| 参数 | 数值 |
|------|------|
| 研发方 | SKYFEND（天御科技），深圳（2020 年成立） |
| 类型 | AI 自主截击无人机 |
| 首次展示 | World Defense Show 2026（利雅得） |
| 重量 | 3.5 kg（最大起飞重量 4 kg） |
| 最大速度 | 230 km/h |
| 巡航速度 | 100 km/h |
| 拦截距离 | 5 km |
| 升限 | 3 km |
| 飞行时间 | 7 分钟 |
| 尺寸（含桨） | 731 × 731 × 448 mm |
| 拦截成功率 | ≥90%（针对速度 ≤150 km/h 的巡飞目标） |
| 制导 | AI 自主导航，地面传感器引导 |

**技术特点**：Thunder 是目前公开信息中中国最接近西方"截击无人机"概念的产品。采用 AI 核心处理器进行智能数据处理，具备机器学习能力可适应新型威胁。由地面传感器引导后自主计算拦截航线，实现自主接近和拦截。

### 15.2 FK-3000——96 枚微型拦截弹的"弹药深度怪兽"

| 参数 | 数值 |
|------|------|
| 研发方 | 中国航天科工集团（CASIC） |
| 类型 | 车载短程防空系统 |
| 底盘 | 陕汽 SX2220 6×6 高机动卡车 |
| 微型拦截弹 | 40 mm，红外成像导引头，发射后不管 |
| 拦截弹速度 | ~600 m/s（2,160 km/h） |
| 拦截弹射程 | 0.3–5 km |
| 最大搭载量 | 96 枚微型拦截弹（纯反无人机构型） |
| 近防炮 | 30 mm 机关炮（空爆弹药，4 km） |
| 大型导弹 | FK-3000/L，射程 ~22 km（可选） |
| 交战距离 | 0.3–12 km（混合构型） |
| 反应时间 | 4–6 秒 |
| 拦截概率 | 85%（固定翼）/ 65%（小型制导弹药） |
| 附属车辆 | 可配 2 台无人辅助发射车（各 24 枚微弹） |
| 服役 | 2025 年 8 月解放军列装 |
| 单价 | 约 500 万美元 |

**技术特点**：FK-3000 的核心思路是**弹药深度**——一辆车装 96 枚红外自主制导微型拦截弹，可以应对大规模蜂群攻击而不会迅速耗尽弹药。微弹速度达 600 m/s（2,160 km/h），远超所有截击无人机，结合 30 mm 空爆机关炮和电子干扰器，形成弹、炮、电三层防御。

### 15.3 天穹（Skyshield）——出口 20 国的综合体系

| 参数 | 数值 |
|------|------|
| 研发方 | 中国电子科技集团（CETC）28 所 |
| 类型 | 综合反无人机作战体系 |
| 部署形态 | 固定式 / 机动式 / 便携式 / 一体式 |
| 探测手段 | 雷达、光电、电子侦测 |
| 拦截手段 | 电子干扰、导航诱骗、激光、微波、防空导弹、高炮 |
| 反应时间 | 15–20 秒（探测→锁定→打击） |
| 实战记录 | 沙特部署，21 发 21 中拦截胡塞无人机（2022 年） |
| 出口 | 约 20 个国家 |
| 配套系统 | "远谋"指控、"神眸"低空防护、"玄蜂"拦截无人机集群 |

**技术特点**：天穹不是单一武器而是**可配置的作战体系**，CETC 称之为"点菜式"——客户根据需求从雷达、光电、干扰器、激光、微波、导弹等模块中组合定制方案。配套的"玄蜂"拦截型无人机集群提供了无人机对无人机的能力。

### 15.4 光箭系列 + LW-30——激光反无人机

| 型号 | 杀伤方式 | 射程 | 特点 |
|------|---------|------|------|
| 光箭-11E | 软杀伤（脉冲激光致盲） | ~3 km | 集装箱形态，数秒锁定，专打光电传感器 |
| 光箭-21A | 硬杀伤（高能激光烧毁） | ~8 km | 车载行进间射击，相控阵雷达探测 >8 km |
| LW-30 | 硬杀伤（30 kW 激光） | ~4 km | 6×6 车载，分 4 档功率，拦截成本 <\$1/次 |

**关键数据**：
- LW-30 在中东累计拦截无人机超过 **76 架次**（截至 2025 年底）
- 巴基斯坦使用 LW-30 曾一天击落 **25 架**印度无人机
- 沙特 2026 年 3 月签署 **42 亿美元** 激光武器合作协议
- 2025 年阅兵首次公开的舰载 LY-1 激光系统已具备拦截超音速反舰导弹能力

### 15.5 中国路线 vs 西方路线对比

| 维度 | 西方/乌克兰路线 | 中国路线 |
|------|---------------|---------|
| 核心手段 | 截击无人机（以机制机） | 激光/微波 + 微型拦截弹 + 综合体系 |
| 代表产品 | STING、GOBI、Anvil | LW-30、光箭、FK-3000、天穹 |
| 单次拦截成本 | \$2,100–\$100,000 | <\$1（激光）/ 数千美元（微弹） |
| 蜂群应对 | 需数量对等的截击机 | 激光逐个点名 / 96 枚微弹饱和 |
| 弹药深度 | 受限（消耗型） | 激光"无限弹药" / FK-3000 96 枚 |
| 全天候能力 | AI 视觉/热成像（较强） | 激光受天气影响（弱点）/ 微弹不受限 |
| 实战验证 | 乌克兰大规模实战 | 中东（沙特、巴基斯坦等）实战 |
| 出口规模 | 快速增长 | 天穹已出口 ~20 国 |

**核心洞察**：中国走激光路线的逻辑很清晰——激光武器的单次拦截成本低于 1 美元，面对"用 500 美元无人机消耗 10 万美元拦截弹"的困境，激光是唯一能实现成本逆转且弹药不耗尽的方案。但激光受天气影响大（雨、雾、沙尘暴时衰减严重），所以中国同时发展了 FK-3000 微型拦截弹作为全天候补充。这种"激光为主、微弹为辅、体系集成"的思路，与西方"以机制机"的路线形成了鲜明对比。

---

## 十六、综合对比：全球主流反无人机拦截系统参数一览

| 型号 | 国家 | 速度 | 射程 | 重量 | 毁伤方式 | 单价 | 实战验证 |
|------|------|------|------|------|---------|------|---------|
| **STING** | 🇺🇦 乌克兰 | 343 km/h | 25 km | — | 动能+爆炸 | ~\$2,100 | 击落 3,900+ |
| **GOBI** | 🇫🇷 法国 | 350 km/h | 5 km | 2.2 kg | 纯动能 | €5,000-7,000 | 中东部署 |
| **BLAZE** | 🇱🇻 拉脱维亚 | — | 10-20 km | <6 kg | 800g 高爆破片 | — | 多国交付 |
| **DroneHunter F700** | 🇺🇸 美国 | — | ~4 km | 18 kg | 网枪捕获 | — | 4,500+ 次捕获 |
| **Anvil / Anvil-M** | 🇺🇸 美国 | 高速 | 短程 | 5.3 kg | 动能/高爆 | — | 军事评估 |
| **X-Wing** | 🇫🇷/🇺🇦 法乌联合 | 300 km/h | 15 km | 3.5 kg | AI 动能 | — | 乌克兰实战 |
| **Black Bird** | 🇫🇷/🇺🇦 法乌联合 | 670 km/h | 30 km | 6 kg | 涡喷+AI | — | 原型测试 |
| **Hornet Block 2** | 🇨🇭 瑞士 | 高亚音速 | >70 km | — | 高爆战斗部 | — | 展会展示 |
| **Skyhammer** | 🇬🇧 英国 | 700 km/h | >30 km | 18 kg | 雷达+破片 | 数百万£合同 | 2026.5 交付 |
| **Coyote Block 2+** | 🇺🇸 美国 | 555-595 km/h | 10-15 km | — | 破片战斗部 | ~\$100,000 | 实战部署 |
| **Coyote Block 3NK** | 🇺🇸 美国 | 巡飞优化 | 10-15 km | ~6 kg | 电子战（非动能） | — | 2026 演示 |
| **Iron Drone Raider** | 🇮🇱 以色列 | 竞速级 | 3-5 km | 4 kg | 网捕获 | — | 加沙实战 |
| **Hunter Eagle** | 🇮🇱 以色列 | 150-200 km/h | 10-15 km | 5-10 kg | 纯动能（无爆炸物） | — | 2026 交付 |
| **Ghost Hunter** | 🇮🇱 以色列 | ~300-400 km/h | — | 50-60 kg | RF 雷达+战斗部 | — | 2027 量产 |
| **Cicada** | 🇩🇪 德国 | 200 km/h | 4-5 km | — | 破片/捕获网 | — | 2026 上市 |
| **Viper I** | 🇮🇱 以色列 | 高速 | 2 km | 3.5 kg | 第三方战斗部 | — | 集成阶段 |
| **SKYFEND Thunder** | 🇨🇳 中国 | 230 km/h | 5 km | 3.5 kg | AI 截击 | — | WDS 2026 展示 |
| **FK-3000 微弹** | 🇨🇳 中国 | 2,160 km/h | 0.3-5 km | — | IR 制导微弹×96 | ~\$500 万/系统 | PLA 列装 |
| **LW-30** | 🇨🇳 中国 | 光速 | ~4 km | — | 30kW 激光烧毁 | <\$1/次 | 中东实战 76+ |
| **天穹体系** | 🇨🇳 中国 | — | 综合 | — | 激光/微波/导弹/干扰 | — | 出口 ~20 国 |

---

## 十七、技术趋势与未来展望

### 17.1 六大发展趋势

**1. AI 自主化程度持续提升**

从 STING 的 AI 辅助热成像跟踪，到 GOBI 的完全自主末段制导，再到 Alta Ares 的无 GNSS Pixel Lock，截击无人机正快速走向"发射后不管"（fire-and-forget）。电子战环境下，不依赖外部数据链的自主能力将成为核心竞争力。

**2. 速度竞赛**

目标无人机在变快——俄罗斯 Geran-3 采用涡喷发动机，速度远超传统的活塞式 Shahed。截击机必须更快：Alta Ares Black Bird 达到 670 km/h，Skyhammer 达到 700 km/h（Mach 0.7），Destinus Hornet 3 采用涡喷达到高亚音速。速度已经从 200 km/h 级别跃升到 700 km/h 级别。

**3. 成本竞赛**

STING 的 \$2,100 设定了价格标杆。未来的截击机必须维持在目标无人机成本的 1/10 到同等水平，否则就失去了相对于传统防空导弹的经济优势。3D 打印、消费级电子元器件、开源 AI 模型的应用将继续压低成本。

**4. 分层防御体系**

没有单一系统能应对所有威胁。法国在中东已部署 GOBI + Alta Ares + Destinus 三重体系：
- **近程**（<5 km）：GOBI——快速反应、纯动能
- **中程**（15-30 km）：X-Wing / Black Bird——AI 自主、乌克兰战场验证
- **远程**（>45 km）：Hornet Block 1/2——填补 VSHORAD 到 SHORAD 空白

**5. 从专用走向通用平台**

Destinus Hornet Block 2 已将反直升机纳入目标清单（70 km 射程、3 kg 载荷）。Coyote LE SR 从 Bradley 战车和直升机上发射。未来截击无人机可能演变为通用化的低成本制导弹药平台。

**6. 非动能反蜂群成为新方向**

Coyote Block 3NK 的非动能电子战载荷开创了新范式——一架可回收的截击机通过电子战手段同时瘫痪多架敌方无人机。这从根本上改变了"一对一"消耗战的经济模型，使防御方在面对蜂群攻击时不再需要数量对等的拦截弹。

### 17.2 乌克兰战场的启示

乌克兰战争作为人类历史上首次大规模无人机战争，为截击无人机的发展提供了无可替代的实战数据：

- **量比质更重要**：乌克兰 2025 年生产了 10 万架截击无人机，STING 月产超过 1 万架。高技术、高成本的系统在面对饱和攻击时不如大批量、低成本的消耗品。
- **迭代速度决胜**：从发现问题到改进设计的周期缩短到周级别。STING 经历了多次迭代，持续改进热成像制导精度和飞行速度。
- **国际合作模式创新**：法国-乌克兰的 Alta Ares 模式——法方提供 AI 和系统集成，乌方提供战场测试和数据反馈——可能成为未来军事技术开发的典范。

---

## 十八、总结

反无人机拦截系统正在从一个新兴概念快速成长为现代防空体系的**核心组成部分**。本文梳理的系统涉及九个国家，展现了这一领域的多元化发展路径：

- **乌克兰 STING** 以 \$2,100 的单价和 3,900+ 的战绩证明了低成本大规模截击的可行性
- **法国 GOBI** 以 2.2 kg 的极致轻量化展示了步兵班组级反无人机的可能
- **拉脱维亚 BLAZE** 率先获得 NATO 编码，推动了标准化进程
- **美国 DroneHunter F700** 的网枪捕获方案为敏感区域防御提供了独特选择
- **英国 Skyhammer** 以 700 km/h 和 30 km 射程逼近了传统导弹的性能
- **美国 Coyote Block 3NK** 的非动能反蜂群方案打开了"一对多"的新范式
- **以色列 Rafael Hunter Eagle/Ghost Hunter** 将 Iron Dome 级别的防空思维带入了无人机对无人机领域
- **德国 Diehl Cicada** 与 Destinus Hornet 的组合展示了短程+中远程分层集成的方向
- **中国天穹+LW-30** 走了一条独特的"激光为主、微弹为辅、体系集成"路线，以不到 1 美元/次的激光拦截成本重新定义了反无人机经济学；FK-3000 的 96 枚微弹方案则提供了全天候硬杀伤补充

这场博弈的本质是**成本不对称之战**——谁能以更低的成本实现更高的拦截概率，谁就赢得了现代防空的主动权。有趣的是，全球出现了两种截然不同但殊途同归的解题思路：西方用"便宜的无人机打便宜的无人机"，中国用"近乎免费的激光打便宜的无人机"。2026 年的趋势表明，反无人机能力已不仅仅是乌克兰战场的特殊需求，它正在成为从波罗的海到波斯湾、从北极到中东的**全球性标准防御手段**。

---

## 参考来源

1. Wild Hornets 官网. *STING – Shahed Interceptor*. [https://wildhornets.com/en/sting-interceptor](https://wildhornets.com/en/sting-interceptor)
2. Wikipedia. *Sting (drone)*. [https://en.wikipedia.org/wiki/Sting_(drone)](https://en.wikipedia.org/wiki/Sting_(drone))
3. Harmattan AI 官网. *GOBI High-Speed Drone Interceptor*. [https://www.harmattan.ai/systems/gobi/](https://www.harmattan.ai/systems/gobi/)
4. Army Recognition. *France's Harmattan AI Launches GOBI Drone*. 2025-07-18. [链接](https://armyrecognition.com/news/aerospace-news/2025/frances-harmattan-ai-launches-gobi-drone-to-revolutionize-counter-drone-warfare-with-ultra-fast-interception)
5. Origin Robotics 官网. *BLAZE*. [https://origin-robotics.com/blaze](https://origin-robotics.com/blaze)
6. Soldier Systems Daily. *Origin Robotics Unveils BLAZE*. 2025-09-10. [链接](https://soldiersystems.net/2025/09/10/origin-robotics-unveils-blaze-a-cost-effective-drone-interceptor-with-ai-powered-computer-vision/)
7. EDR Magazine. *DSEI 2025 - Origin Robotics counter-UAS interceptor Blaze*. [链接](https://www.edrmagazine.eu/dsei-2025-origin-robotics-counter-uas-interceptor-blaze)
8. Fortem Technologies 官网. *DroneHunter F700*. [https://www.fortemtech.com/products/dronehunter-f700/](https://www.fortemtech.com/products/dronehunter-f700/)
9. Fortem Technologies Blog. *The technology to safely stop drones already exists*. 2026-02-14. [链接](https://www.fortemtech.com/blog/discussions/2026-02-14-the-technology-to-safely-stop-drones-already-exists-the-u-s-government-is-buying-it-from-us/)
10. Anduril 官网. *Counter UAS / Anvil*. [https://www.anduril.com/counter-uas](https://www.anduril.com/counter-uas)
11. Defence Blog. *U.S. steps closer to fielding autonomous drone interceptor*. 2025-11-07. [链接](https://defence-blog.com/u-s-steps-closer-to-fielding-autonomous-drone-interceptor/)
12. Alta Ares 官网. [https://www.altaares.com/](https://www.altaares.com/)
13. UNITED24 Media. *Shahed Killers: Ukraine and France Launch Next-Gen Jet-Powered Interceptor Drones*. 2025-11-17. [链接](https://united24media.com/latest-news/shahed-killers-ukraine-and-france-launch-next-gen-jet-powered-interceptor-drones-13528)
14. Militarnyi. *France to Counter Iranian Shaheds With Three Types of Interceptor Drones*. [链接](https://militarnyi.com/en/news/france-counter-shaheds-interceptor-drones/)
15. Army Recognition. *Destinus Unveils Hornet Block2 Interceptor*. BEDEX 2026. [链接](https://www.armyrecognition.com/archives/archives-defense-exhibitions/2026-archives-news-defense-exhibitions/bedex-2026/destinus-unveils-hornet-block2-interceptor-as-a-european-quick-response-counter-drone-system)
16. Destinus 官网. *Hornet*. [https://www.destinus.com/page/hornet](https://www.destinus.com/page/hornet)
17. UK GOV. *UK start-up to supply interceptor missiles to UK military and Gulf partners*. 2026-04-10. [链接](https://www.gov.uk/government/news/uk-start-up-to-supply-interceptor-missiles-to-uk-military-and-gulf-partners)
18. Defence Blog. *UK orders Skyhammer drone interceptors from Cambridge Aerospace*. 2026-04-10. [链接](https://defence-blog.com/uk-orders-skyhammer-drone-interceptors-from-cambridge-aerospace/)
19. RTX/Raytheon 官网. *Coyote C-UAS*. [https://www.rtx.com/raytheon/what-we-do/integrated-air-and-missile-defense/coyote](https://www.rtx.com/raytheon/what-we-do/integrated-air-and-missile-defense/coyote)
20. Raytheon MediaRoom. *RTX's Raytheon's non-kinetic Coyote variant defeats multiple drone swarms*. 2026-02-11. [链接](https://raytheon.mediaroom.com/2026-02-11-RTXs-Raytheons-non-kinetic-Coyote-variant-defeats-multiple-drone-swarms)
21. Breaking Defense. *Iron Drone Raider is at the cutting edge of autonomous drone defense*. 2025-03. [链接](https://breakingdefense.com/2025/03/iron-drone-raider-is-at-the-cutting-edge-of-autonomous-drone-defense/)
22. Autonomy Global. *RAFAEL's New Counter-UAS Systems: The Hunter Eagle and Ghost Hunter*. [链接](https://www.autonomyglobal.co/rafaels-new-counter-uas-systems-the-hunter-eagle-and-ghost-hunter-interceptor-drones/)
23. Janes. *EnforceTac 2025: Diehl Defence presents Cicada UAV interceptor*. 2025-03-03. [链接](https://www.janes.com/osint-insights/defence-news/air/enforcetac-2025-diehl-defence-presents-cicada-uav-interceptor)
24. EDR Magazine. *Enforce Tac 2026 – Diehl Defence relaunches its Garmr counter-drone system*. [链接](https://www.edrmagazine.eu/enforce-tac-2026-diehl-defence-relaunches-its-garmr-counter-drone-system)
25. SpearUAV 官网. *VIPER I*. [https://spearuav.com/viper-family/viper-I/](https://spearuav.com/viper-family/viper-I/)
26. Next Gen Defense. *SpearUAV Launches Viper Top-Attack Drone Interceptor*. 2024-10-21. [链接](https://nextgendefense.com/spearuav-top-attack-drone-interceptor/)
27. Wikipedia. *Raytheon Coyote*. [https://en.wikipedia.org/wiki/Raytheon_Coyote](https://en.wikipedia.org/wiki/Raytheon_Coyote)
28. Unmanned Airspace. *Faster, further, more lethal: comparing worldwide kinetic intercept drone capabilities*. 2026. [链接](https://www.unmannedairspace.info/counter-uas-systems-and-policies/faster-further-more-lethal-comparing-kinetic-intercept-drone-capabilities-from-around-the-world/)
29. H I Sutton / Covert Shores. *Guide To Ukrainian Interceptor Drones*. [https://www.hisutton.com/Ukrainian-Interceptor-Drones.html](https://www.hisutton.com/Ukrainian-Interceptor-Drones.html)
30. Militarnyi. *Chinese SKYFEND Presents Thunder Interceptor Drone at World Defense Show*. 2026-02. [链接](https://militarnyi.com/en/news/skyfend-presents-thunder-interceptor-drone/)
31. Wikipedia. *FK-3000*. [https://en.wikipedia.org/wiki/FK-3000](https://en.wikipedia.org/wiki/FK-3000)
32. The War Zone. *Check Out China's Short-Range Air Defense Vehicle Capable Of Packing A Whopping 96 Mini Interceptors*. 2025-08. [链接](https://www.twz.com/land/check-out-chinas-short-range-air-defense-vehicle-capable-of-packing-a-whopping-96-mini-interceptors)
33. 中华网军事. *天穹综合反无人机防御系统有何特点*. 2025-06-30. [链接](https://military.china.com/news/13004177/20250630/48537253.html)
34. 央视新闻 / 观察者网. *边走边打、光速毁伤！揭秘我国反无人机激光武器战力*. 2026-03-25. [链接](https://www.guancha.cn/military-affairs/2026_03_25_811415.shtml)
35. 中新网. *"天穹"综合反无人机作战体系亮相航展*. 2024-11-17. [链接](https://www.chinanews.com/gn/2024/11-17/10320799.shtml)
36. Defense One. *China's counter-UAV efforts reveal more than technological advancement*. 2025-05. [链接](https://www.defenseone.com/technology/2025/05/chinas-counter-uav-efforts-reveal-more-technological-advancement/405031/)

---

**核心观点**：截击无人机不是传统防空的替代品，而是在"低成本/大规模无人机威胁"这个特定场景中的最优解。它与传统防空导弹、高射炮、电子战系统共同构成分层防御体系——让便宜的目标用便宜的手段对付，把昂贵的导弹留给真正有价值的目标。
