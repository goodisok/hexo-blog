---
title: 解决自定义 OriginGeopoint 后 PX4 无法解锁：地磁与 getMagField 修正
date: 2026-02-09 14:30:00
categories:
  - 开发
tags:
  - AirSim
  - Colosseum
  - PX4
  - 仿真
  - 地磁
  - 磁力计
  - OriginGeopoint
  - WMM
---

在使用 AirSim/Colosseum 时，若在 `settings.json` 里配置了自定义的 **`OriginGeopoint`**（例如配合 Cesium 指定真实地理起点），有时会出现 **PX4 无法解锁** 的情况，并伴随 `Preflight Fail: heading estimate not stable`、`Yaw estimate error`、`GPS fix too low` 等告警。社区 [AirSim #5001](https://github.com/Microsoft/AirSim/issues/5001) 中有人遇到相同现象，并指出根本原因是 **磁力计读数与自定义起点位置不一致**。本文整理该问题的原因与解决方案：通过基于 **WMM（世界地磁模型）** 的库重写 `EarthUtils.hpp` 中的 **`getMagField`**（以及 `getMagDeclination`），使仿真中的磁力计输出与当前 `OriginGeopoint` 对应的真实地磁一致，从而消除航向估计错误、使 PX4 可正常解锁。

---

## 一、问题现象

### 1.1 复现条件

- 在 `settings.json` 中配置了 **`OriginGeopoint`**，例如：

```json
"OriginGeopoint": {
    "Longitude": 4.902346,
    "Latitude": 52.379172,
    "Altitude": 10
}
```

- 使用 **PX4** 作为飞控（SITL 或 HITL），并启用 GPS。
- 无 `OriginGeopoint` 时一切正常，一旦加上自定义起点，飞机**无法解锁（Arm 被拒绝）**。

### 1.2 典型 PX4 报错

- `WARN [health_and_arming_checks] Preflight: GPS fix too low`
- `WARN [health_and_arming_checks] Preflight Fail: ekf2 missing data`
- `WARN [health_and_arming_checks] Preflight Fail: Yaw estimate error`
- `WARN [health_and_arming_checks] Preflight Fail: heading estimate not stable`

这些告警会导致 PX4 的 Preflight 检查不通过，从而拒绝解锁。

---

## 二、原因分析

### 2.1 磁力计与航向估计

PX4 的 EKF（扩展卡尔曼滤波）使用 **磁力计（罗盘）** 参与航向估计。仿真里磁力计的数据由 AirLib 的 **`EarthUtils::getMagField`** 根据当前**地理点**（经纬度、高度）计算地磁矢量（北/东/地分量），再结合机体姿态得到“传感器读数”。

若 **`getMagField`** 给出的地磁与**真实该地点**的磁场不一致（例如仍按默认地点或粗糙查表），则：

- 磁偏角、磁倾角、磁场强度与真实不符；
- EKF 解算出的航向会持续偏离、抖动或不收敛；
- 触发 **Yaw estimate error**、**heading estimate not stable**，Preflight 不通过，无法解锁。

因此，**自定义 `OriginGeopoint` 后，必须按“该起点对应的经纬度、高度”计算地磁，磁力计仿真才正确。**

### 2.2 原有实现的不足

旧版 AirLib 的 `EarthUtils.hpp` 中：

- **磁偏角** 可能依赖静态 **`DECLINATION_TABLE`** 查表，分辨率与精度有限，且未与 WMM 等标准模型对齐；
- **`getMagField`** 若未按当前地理点使用 WMM 计算，则任意自定义起点下的磁力计读数都会偏离真实值。

一旦用户把 `OriginGeopoint` 设到阿姆斯特丹、北京等任意地点，仿真仍按“默认原点”或粗表给磁力计，就会导致上述 Preflight 失败。

### 2.3 关于 GPS fix too low

**GPS fix too low** 通常与“GPS 位置/高度是否与 Unreal 场景、Cesium 原点一致”有关，属于**位置对齐**问题，与地磁无直接关系。但 **heading estimate not stable** 的解决（见下文）能消除因磁力计错误导致的解锁障碍；若仍有 GPS 告警，需单独检查仿真中 GPS 与 `OriginGeopoint`、场景原点的一致性。

---

## 三、解决方案

### 3.1 思路

在 **`AirLib/include/common/EarthUtils.hpp`** 中，用基于 **WMM（World Magnetic Model）** 的库重写：

1. **`getMagDeclination(latitude, longitude, altitude)`**：根据经纬度、高度和年代，返回该点的**磁偏角**（度）。
2. **`getMagField(geo_point)`**：根据地理点（含高度）和年代，返回该点的**地磁矢量**（北/东/地分量，单位 Tesla），并可选输出 declination、inclination。

这样，无论 `OriginGeopoint` 设在哪里，磁力计仿真都使用**该地点、该年代**的真实地磁，PX4 的航向估计与 Preflight 检查才能通过。

### 3.2 推荐实现：geomag / XYZgeomag

社区中有人通过使用 [nhz2/XYZgeomag](https://github.com/nhz2/XYZgeomag) 修正 `getMagField` 解决了 **heading estimate not stable**。思路是：

- 使用 WMM 球谐系数（如 WMM2015、WMM2020、WMM2025）在 **ITRS（地固系）** 下计算指定位置、指定“十进制年”的磁场；
- 将结果转换为当地北/东/地分量及磁偏角、磁倾角，供 `getMagField` / `getMagDeclination` 返回。

在 Colosseum 中可采用**头文件版**实现：将 WMM 计算封装在 **`AirLib/include/common/geomag.hpp`** 中（与 XYZgeomag 同源或同思路），在 `EarthUtils.hpp` 中：

- `#include "common/geomag.hpp"`
- **`getMagDeclination`**：先 `geodetic2ecef` 得到 ECEF 位置，再 `GeoMag(dyear, ecef_position, WMM)` 得到地固系磁场，经 `magField2Elements` 得到 declination，返回即可。
- **`getMagField`**：同样经 `geodetic2ecef` → `GeoMag` → `magField2Elements`，取北/东/地分量（nT 转 Tesla）和 declination、inclination，填回 `Vector3r` 与输出参数。

这样，仿真中的磁力计与 PX4 的期望一致，**heading estimate not stable**、**Yaw estimate error** 即可消除。

### 3.3 涉及文件与依赖

| 文件 | 作用 |
|------|------|
| `AirLib/include/common/geomag.hpp` | WMM 球谐计算、ECEF 转换、磁要素转换（或等价实现） |
| `AirLib/include/common/EarthUtils.hpp` | 调用 geomag，实现 `getMagDeclination`、`getMagField` |

依赖：仅需 C++ 与数学库，无需额外网络或外部服务；WMM 系数可编译期写死在头文件中（如 WMM2020、WMM2025）。

---

## 四、小结

- **问题**：设置自定义 **`OriginGeopoint`** 后，PX4 报 **heading estimate not stable**、**Yaw estimate error** 等，无法解锁。
- **原因**：仿真中磁力计使用的 **`getMagField`**（及磁偏角）未按该起点经纬度、高度计算，与真实地磁不一致，导致 EKF 航向估计异常。
- **解决**：在 **`EarthUtils.hpp`** 中，用基于 WMM 的库（如 [nhz2/XYZgeomag](https://github.com/nhz2/XYZgeomag) 或头文件版 **geomag.hpp**）重写 **`getMagField`** 与 **`getMagDeclination`**，使磁力计输出与当前 `OriginGeopoint` 对应的真实地磁一致，即可消除上述 Preflight 失败，正常解锁。

**代码位置**：本文所述地磁修正（geomag.hpp + EarthUtils 改造）已在 Colosseum 分支 [goodisok/Colosseum](https://github.com/goodisok/Colosseum) 的 **`feature/jpeg-geomag-px4`** 中实现，可一并参考或拉取使用。
