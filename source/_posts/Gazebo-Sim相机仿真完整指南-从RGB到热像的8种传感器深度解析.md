---
title: Gazebo Sim 相机仿真完整指南：从 RGB 到热像的 8 种传感器深度解析
date: 2026-04-25 14:00:00
categories:
  - 无人机
  - 仿真开发
  - 传感器
tags:
  - Gazebo
  - 相机仿真
  - SDF
  - 深度相机
  - 热成像
  - 语义分割
  - 鱼眼相机
  - gz-sensors
  - gz-rendering
  - RGBD
  - 点云
  - Brown畸变
  - ROS2
  - 传感器模型
  - BoundingBox
  - 噪声模型
---

> Gazebo Sim（Harmonic/Ionic）内置了 **8 种相机传感器**，从最基础的 RGB 针孔相机到热成像、语义分割、目标检测包围盒，覆盖了机器人与无人机仿真中几乎所有的视觉感知需求。但 Gazebo 的官方文档分散在 `gz-sensors`、`gz-rendering`、`gz-sim` 三个库中，SDF 配置参数缺少系统性说明，很多开发者在实际使用时不知道"有哪些相机可以用"、"每种相机输出什么"、"参数该怎么填"。
>
> 本文系统梳理 Gazebo Sim 中全部 8 种相机传感器的**原理、SDF 配置、输出话题、工程用法与局限**，帮助你根据任务需求快速选型并正确配置。每种传感器都给出可直接粘贴到 SDF 文件中运行的完整配置示例。

---

## 一、Gazebo 相机传感器总览

### 1.1 8 种相机传感器一览

| # | SDF type | 中文名 | 输出数据 | 典型应用 |
|---|----------|--------|---------|---------|
| 1 | `camera` | RGB 相机 | 彩色图像 | 视觉导航、目标检测、SLAM |
| 2 | `depth_camera` | 深度相机 | 深度图 | 避障、三维重建 |
| 3 | `rgbd_camera` | RGBD 相机 | 彩色 + 深度 + 点云 | RGB-D SLAM、语义地图 |
| 4 | `thermal_camera` | 热成像相机 | 温度图（8/16-bit） | 搜救、反无人机、火灾检测 |
| 5 | `segmentation` | 分割相机 | 语义/实例/全景分割图 | 数据集生成、场景理解 |
| 6 | `boundingbox_camera` | 包围盒相机 | 2D/3D BBox + 类别 | 目标检测数据集 |
| 7 | `wideanglecamera` | 广角/鱼眼相机 | 畸变广角图像 | 全景感知、环视系统 |
| 8 | `triggered_camera` | 触发相机 | 按需拍摄的图像 | 间歇采集、事件触发 |

### 1.2 传感器系统前置配置

所有渲染类传感器（相机、深度、热像等）都需要在世界文件中加载 `Sensors` 系统插件：

```xml
<world name="camera_world">
  <!-- 必须：物理引擎 -->
  <plugin filename="gz-sim-physics-system"
          name="gz::sim::systems::Physics"/>
  <!-- 必须：渲染传感器系统 -->
  <plugin filename="gz-sim-sensors-system"
          name="gz::sim::systems::Sensors">
    <render_engine>ogre2</render_engine>
  </plugin>
  <!-- 推荐：场景广播（用于 GUI 可视化） -->
  <plugin filename="gz-sim-scene-broadcaster-system"
          name="gz::sim::systems::SceneBroadcaster"/>
  <!-- 推荐：用户交互命令 -->
  <plugin filename="gz-sim-user-commands-system"
          name="gz::sim::systems::UserCommands"/>
</world>
```

`render_engine` 默认为 `ogre2`（OGRE 2.x），是目前唯一支持全部传感器类型的渲染后端。

### 1.3 通用 SDF 参数

所有相机传感器共享以下基础参数：

```xml
<sensor type="camera" name="my_camera">
  <pose relative_to="link_frame">0.1 0 0.05 0 0 0</pose>
  <update_rate>30</update_rate>      <!-- Hz -->
  <always_on>true</always_on>
  <visualize>true</visualize>        <!-- GUI 中显示 -->
  <topic>camera/image</topic>        <!-- gz-transport 话题名 -->
  <camera name="cam">
    <horizontal_fov>1.047</horizontal_fov>   <!-- 弧度 = 60° -->
    <image>
      <width>640</width>
      <height>480</height>
      <format>R8G8B8</format>        <!-- 像素格式 -->
    </image>
    <clip>
      <near>0.1</near>              <!-- 近裁剪面（米） -->
      <far>100</far>                 <!-- 远裁剪面（米） -->
    </clip>
  </camera>
</sensor>
```

| 参数 | 说明 | 注意事项 |
|------|------|---------|
| `<pose>` | 传感器相对父 link 的位姿 | 6DoF: x y z roll pitch yaw |
| `<update_rate>` | 更新频率（Hz） | 实际帧率受仿真步长和 GPU 性能限制 |
| `<horizontal_fov>` | 水平视场角（弧度） | 垂直 FOV 由宽高比自动计算 |
| `<clip>` | 渲染裁剪范围 | near 太小会导致 Z-fighting，far 太大影响精度 |
| `<format>` | 像素格式 | RGB: `R8G8B8`，深度: `R_FLOAT32`，热像: `L16` |

---

## 二、RGB 相机（`camera`）

### 2.1 概述

最基础的相机传感器，模拟针孔相机模型，输出标准 RGB 彩色图像。

### 2.2 完整 SDF 配置

```xml
<sensor type="camera" name="rgb_camera">
  <pose>0.15 0 0.1 0 0 0</pose>
  <update_rate>30</update_rate>
  <camera name="front_cam">
    <horizontal_fov>1.3962634</horizontal_fov>  <!-- 80° -->
    <image>
      <width>1920</width>
      <height>1080</height>
      <format>R8G8B8</format>
    </image>
    <clip>
      <near>0.1</near>
      <far>500</far>
    </clip>

    <!-- 镜头畸变（Brown 模型） -->
    <distortion>
      <k1>-0.25</k1>
      <k2>0.12</k2>
      <k3>0.0</k3>
      <p1>-0.00028</p1>
      <p2>-0.00005</p2>
      <center>0.5 0.5</center>
    </distortion>

    <!-- 图像噪声 -->
    <noise>
      <type>gaussian</type>
      <mean>0.0</mean>
      <stddev>0.007</stddev>
    </noise>

    <!-- 相机内参（可选，覆盖从 FOV 计算的默认值） -->
    <lens>
      <intrinsics>
        <fx>960.0</fx>
        <fy>960.0</fy>
        <cx>960.0</cx>
        <cy>540.0</cy>
        <s>0</s>
      </intrinsics>
    </lens>
  </camera>
  <always_on>true</always_on>
  <visualize>true</visualize>
  <topic>rgb_camera</topic>
</sensor>
```

### 2.3 输出话题

| 话题 | 消息类型 | 内容 |
|------|---------|------|
| `/rgb_camera` | `gz.msgs.Image` | RGB 图像数据 |
| `/rgb_camera/camera_info` | `gz.msgs.CameraInfo` | 内参、畸变系数 |

### 2.4 Brown 畸变模型详解

Gazebo 使用 Brown-Conrady 畸变模型，与 OpenCV `cv::calibrateCamera` 输出的系数完全兼容：

$$
x_d = x(1 + k_1 r^2 + k_2 r^4 + k_3 r^6) + 2p_1 xy + p_2(r^2 + 2x^2)
$$
$$
y_d = y(1 + k_1 r^2 + k_2 r^4 + k_3 r^6) + p_1(r^2 + 2y^2) + 2p_2 xy
$$

其中 $r^2 = x^2 + y^2$，$(x, y)$ 为归一化像素坐标，$(x_d, y_d)$ 为畸变后坐标。

| 系数 | 效果 | 典型值 |
|------|------|--------|
| k1 < 0 | 桶形畸变（鱼眼效应） | -0.1 ~ -0.5 |
| k1 > 0 | 枕形畸变 | 0.05 ~ 0.3 |
| p1, p2 | 切向畸变（安装偏心） | ±0.001 量级 |
| center | 畸变中心（归一化坐标） | (0.5, 0.5) 为图像中心 |

**工程建议**：如果有真实相机的标定结果（从 OpenCV 或 MATLAB 获得），直接将 k1-k3, p1-p2 填入即可实现与真实相机一致的畸变效果。

### 2.5 噪声模型

Gazebo 的 `gaussian` 噪声模型向每个像素每个通道添加独立高斯噪声：

$$
I_{\text{noisy}}(x,y,c) = I(x,y,c) + \mathcal{N}(\mu, \sigma^2)
$$

噪声参数以 **归一化值**（0-1 范围）指定。对于 8-bit 图像，`stddev=0.007` 对应约 **1.8 个灰度级**的噪声标准差。

| 场景 | 推荐 stddev | 说明 |
|------|------------|------|
| 理想相机 | 0.0 | 无噪声 |
| 高质量工业相机 | 0.003-0.005 | 低噪声 |
| 消费级相机 | 0.007-0.015 | 中等噪声 |
| 低光照场景 | 0.02-0.05 | 高噪声 |

**局限**：Gazebo 原生噪声是均匀高斯噪声，不建模真实 CMOS 的泊松散粒噪声、固定图案噪声（FPN）和暗电流。如需更真实的噪声模型，需要自行在图像后处理中添加。

---

## 三、深度相机（`depth_camera`）

### 3.1 概述

输出浮点深度图，每个像素值代表该方向物体到相机光心的距离（单位：米）。

### 3.2 SDF 配置

```xml
<sensor type="depth_camera" name="depth_cam">
  <pose>0.15 0 0.1 0 0 0</pose>
  <update_rate>15</update_rate>
  <camera name="depth">
    <horizontal_fov>1.047</horizontal_fov>   <!-- 60° -->
    <image>
      <width>640</width>
      <height>480</height>
      <format>R_FLOAT32</format>
    </image>
    <clip>
      <near>0.3</near>       <!-- RealSense D435 最近 0.3m -->
      <far>10.0</far>        <!-- 有效深度范围 -->
    </clip>
    <noise>
      <type>gaussian</type>
      <mean>0.0</mean>
      <stddev>0.005</stddev>  <!-- 深度噪声 ~5mm -->
    </noise>
  </camera>
  <always_on>true</always_on>
  <topic>depth_camera</topic>
</sensor>
```

### 3.3 输出话题

| 话题 | 消息类型 | 内容 |
|------|---------|------|
| `/depth_camera` | `gz.msgs.Image` | 32-bit 浮点深度图 |
| `/depth_camera/points` | `gz.msgs.PointCloudPacked` | 点云数据 |

### 3.4 深度值的含义

Gazebo 深度相机输出的深度值有两种模式：

| 模式 | 描述 | 适用场景 |
|------|------|---------|
| **Z-buffer 深度**（默认） | 沿光轴方向的距离 | 与 ROS `sensor_msgs/Image` 兼容 |
| **欧几里得距离** | 到光心的直线距离 | 点云生成 |

超出 `<far>` 范围的像素值为 `+inf`，无效像素（无交点）也为 `+inf`。

### 3.5 模拟真实深度相机

不同深度相机的关键参数差异很大，配置时应对应：

| 真实设备 | 分辨率 | FOV | 范围 | 噪声 (1m处) |
|---------|--------|-----|------|------------|
| Intel RealSense D435 | 1280×720 | 86° | 0.3-10m | ~2mm |
| Intel RealSense D455 | 1280×720 | 86° | 0.6-6m | ~2mm |
| Microsoft Azure Kinect | 640×576 | 75° | 0.25-5.5m | ~3mm |
| Stereolabs ZED 2 | 2208×1242 | 110° | 0.3-20m | ~1mm (1m) |

---

## 四、RGBD 相机（`rgbd_camera`）

### 4.1 概述

RGBD 相机是 RGB 和 Depth 的组合传感器，**同时输出对齐的彩色图像和深度图**，以及可选的点云。这是模拟 Intel RealSense、Azure Kinect 等 RGB-D 传感器的首选方案。

### 4.2 SDF 配置

```xml
<sensor type="rgbd_camera" name="rgbd_sensor">
  <pose>0.15 0 0.1 0 0 0</pose>
  <update_rate>30</update_rate>
  <camera name="rgbd">
    <horizontal_fov>1.5009</horizontal_fov>   <!-- 86° -->
    <image>
      <width>1280</width>
      <height>720</height>
    </image>
    <clip>
      <near>0.3</near>
      <far>10.0</far>
    </clip>
    <noise>
      <type>gaussian</type>
      <mean>0.0</mean>
      <stddev>0.007</stddev>
    </noise>
    <depth_camera>
      <clip>
        <near>0.3</near>
        <far>10.0</far>
      </clip>
    </depth_camera>
  </camera>
  <always_on>true</always_on>
  <topic>rgbd</topic>
</sensor>
```

### 4.3 输出话题

| 话题 | 消息类型 | 内容 |
|------|---------|------|
| `/rgbd/image` | `gz.msgs.Image` | RGB 彩色图像 |
| `/rgbd/depth_image` | `gz.msgs.Image` | 深度图（R_FLOAT32） |
| `/rgbd/points` | `gz.msgs.PointCloudPacked` | 彩色点云 |
| `/rgbd/camera_info` | `gz.msgs.CameraInfo` | 相机内参 |

### 4.4 vs 分别使用 camera + depth_camera

| 维度 | rgbd_camera | camera + depth_camera |
|------|------------|----------------------|
| 配置复杂度 | 单一传感器 | 两个独立传感器 |
| 像素对齐 | **自动保证** | 需手动对齐 |
| 时间同步 | **同一帧** | 可能不同步 |
| 点云输出 | 自带 | 需自行计算 |
| GPU 开销 | 一次渲染 | 两次渲染 |

**推荐**：优先使用 `rgbd_camera`，除非需要 RGB 和深度有不同的分辨率或帧率。

---

## 五、热成像相机（`thermal_camera`）

### 5.1 概述

模拟红外热成像传感器，输出场景的温度分布图。每个像素值对应物体表面的温度（开尔文），而非光学反射率。

### 5.2 SDF 配置

```xml
<sensor type="thermal_camera" name="ir_camera">
  <pose>0.15 0 0.1 0 0 0</pose>
  <update_rate>30</update_rate>
  <camera name="thermal">
    <horizontal_fov>0.5236</horizontal_fov>   <!-- 30° -->
    <image>
      <width>640</width>
      <height>512</height>
      <format>L16</format>     <!-- 16-bit 灰度 -->
    </image>
    <clip>
      <near>0.5</near>
      <far>3000</far>
    </clip>
  </camera>
  <always_on>true</always_on>
  <topic>thermal_camera</topic>
</sensor>
```

### 5.3 场景温度配置

热成像要工作，场景中的物体必须被赋予温度。

**（1）设置世界环境温度**

```xml
<atmosphere>
  <temperature>288.15</temperature>              <!-- 15°C -->
  <temperature_gradient>-0.0065</temperature_gradient>
</atmosphere>
```

**（2）为物体设置温度**

```xml
<model name="hot_target">
  <link name="body">
    <visual name="visual">
      <geometry><sphere><radius>0.2</radius></sphere></geometry>
    </visual>
  </link>
  <plugin filename="gz-sim-thermal-system"
          name="gz::sim::systems::Thermal">
    <temperature>333.15</temperature>   <!-- 60°C -->
  </plugin>
</model>
```

**（3）使用热签名纹理（Heat Signature）**

对于需要非均匀温度分布的物体（如无人机的电机比机壳更热）：

```xml
<plugin filename="gz-sim-thermal-system"
        name="gz::sim::systems::Thermal">
  <temperature>293.15</temperature>              <!-- 基准 20°C -->
  <heat_signature>textures/drone_thermal.png</heat_signature>
  <min_temp>293.15</min_temp>                    <!-- 纹理黑色 = 20°C -->
  <max_temp>353.15</max_temp>                    <!-- 纹理白色 = 80°C -->
</plugin>
```

热签名是一张灰度 PNG 纹理，灰度 0 对应 `min_temp`，灰度 255 对应 `max_temp`。

### 5.4 输出话题与数据解析

| 话题 | 消息类型 | 内容 |
|------|---------|------|
| `/thermal_camera` | `gz.msgs.Image` | 16-bit（L16）或 8-bit（L8）温度图 |

**数据解析**（16-bit 模式，默认分辨率 0.01K）：

```python
import numpy as np

def parse_thermal_16bit(data, width, height, resolution=0.01):
    """将 16-bit 热像数据转换为开尔文温度"""
    temp_raw = np.frombuffer(data, dtype=np.uint16).reshape(height, width)
    temp_kelvin = temp_raw.astype(np.float64) * resolution
    temp_celsius = temp_kelvin - 273.15
    return temp_celsius
```

### 5.5 8-bit vs 16-bit 模式

| 模式 | format | 分辨率 | 温度范围 | 用途 |
|------|--------|--------|---------|------|
| 16-bit | `L16` | 0.01 K | 0-655.35 K | 精确测温 |
| 8-bit | `L8` | 3.0 K | 0-765 K | 可视化、低精度检测 |

### 5.6 局限

| 局限 | 说明 |
|------|------|
| 无大气衰减 | 不模拟红外辐射在大气中的吸收 |
| 无 NETD 噪声 | 不模拟热探测器的固有噪声 |
| 均匀温度 | 未用 heat_signature 时整个模型温度一致 |
| 无遮挡温度叠加 | 被遮挡物体不会影响前景物体的表观温度 |
| 无反射 | 红外反射（如金属镜面）未建模 |

---

## 六、分割相机（`segmentation`）

### 6.1 概述

分割相机为每个像素输出**语义标签**，无需训练神经网络就能获得完美的分割 Ground Truth。支持三种分割模式：

| 模式 | SDF 值 | 说明 |
|------|--------|------|
| 语义分割 | `semantic` | 同类物体相同颜色/标签 |
| 实例分割 | `instance` | 每个物体实例不同颜色 |
| 全景分割 | `panoptic` | 同 instance（别名） |

### 6.2 SDF 配置

```xml
<sensor type="segmentation" name="semantic_cam">
  <pose>0.15 0 0.1 0 0 0</pose>
  <update_rate>15</update_rate>
  <camera name="seg">
    <segmentation_type>semantic</segmentation_type>
    <horizontal_fov>1.5708</horizontal_fov>   <!-- 90° -->
    <image>
      <width>800</width>
      <height>600</height>
    </image>
    <clip>
      <near>0.1</near>
      <far>100</far>
    </clip>
    <save enabled="true">
      <path>segmentation_data/semantic</path>
    </save>
  </camera>
  <always_on>true</always_on>
  <topic>semantic_camera</topic>
</sensor>
```

### 6.3 输出话题

| 话题 | 消息类型 | 内容 |
|------|---------|------|
| `/semantic_camera/colored_map` | `gz.msgs.Image` | 彩色分割图 |
| `/semantic_camera/labels_map` | `gz.msgs.Image` | 标签 ID 图 |

### 6.4 自动数据集生成

当 `<save enabled="true">` 时，传感器自动将分割图保存到指定路径，格式与 Cityscapes / COCO 数据集兼容。这是**免标注生成训练数据**的利器。

### 6.5 为模型设置标签

物体的分割标签可通过 SDF 的 `<label>` 元素设置：

```xml
<visual name="visual">
  <geometry><box><size>1 1 1</size></box></geometry>
  <plugin filename="gz-sim-label-system"
          name="gz::sim::systems::Label">
    <label>1</label>   <!-- 标签 ID -->
  </plugin>
</visual>
```

---

## 七、包围盒相机（`boundingbox_camera`）

### 7.1 概述

自动为画面中的每个可见物体生成 **2D 或 3D 包围盒**标注。与分割相机类似，无需训练即可获得完美的目标检测 Ground Truth。

### 7.2 SDF 配置

```xml
<sensor type="boundingbox_camera" name="bbox_cam">
  <pose>0.15 0 0.1 0 0 0</pose>
  <update_rate>15</update_rate>
  <camera name="bbox">
    <horizontal_fov>1.5708</horizontal_fov>
    <image>
      <width>800</width>
      <height>600</height>
    </image>
    <clip>
      <near>0.1</near>
      <far>100</far>
    </clip>
    <box_type>2d</box_type>  <!-- 2d 或 3d -->
  </camera>
  <always_on>true</always_on>
  <topic>bbox_camera</topic>
</sensor>
```

### 7.3 输出话题

| 话题 | 消息类型 | 内容 |
|------|---------|------|
| `/bbox_camera` | `gz.msgs.Image` | 原始 RGB 图像 |
| `/bbox_camera/boxes` | `gz.msgs.AnnotatedAxisAligned2DBox` 或 `AnnotatedOriented3DBox` | 包围盒列表 |

### 7.4 2D vs 3D 包围盒

| 类型 | 内容 | 格式 |
|------|------|------|
| `2d` | 屏幕空间轴对齐矩形 | (x_min, y_min, x_max, y_max, label) |
| `3d` | 世界空间有向包围盒 | (center, size, orientation, label) |

### 7.5 应用场景

- **自动生成 YOLO / COCO 格式标注数据**：在仿真中批量渲染不同场景，自动获得标注
- **评估检测算法**：将算法输出与 Ground Truth 对比
- **数据增强**：与域随机化（Domain Randomization）结合

---

## 八、广角/鱼眼相机（`wideanglecamera`）

### 8.1 概述

支持 FOV 超过 90° 的广角镜头仿真，包括 180° 鱼眼和 360° 全景。采用**立方体贴图**渲染方案，先渲染 6 个面的立方体贴图，再通过镜头模型投影到目标图像。

### 8.2 SDF 配置

```xml
<sensor type="wideanglecamera" name="fisheye_cam">
  <pose>0 0 0.2 0 0 0</pose>
  <update_rate>15</update_rate>
  <camera name="fisheye">
    <horizontal_fov>3.1416</horizontal_fov>   <!-- 180° -->
    <image>
      <width>800</width>
      <height>800</height>
    </image>
    <clip>
      <near>0.1</near>
      <far>100</far>
    </clip>
    <lens>
      <type>stereographic</type>
      <scale_to_hfov>true</scale_to_hfov>
      <cutoff_angle>1.5708</cutoff_angle>        <!-- π/2 = 90° 半角 -->
      <env_texture_size>512</env_texture_size>   <!-- 立方体贴图分辨率 -->
    </lens>
  </camera>
  <always_on>true</always_on>
  <topic>fisheye_camera</topic>
</sensor>
```

### 8.3 镜头投影模型

Gazebo 支持 6 种镜头映射函数 $r = f(\theta)$（$\theta$ 为入射角，$r$ 为像面径向距离）：

| 类型 | 映射函数 | 特点 | 最大 FOV |
|------|---------|------|---------|
| `gnomonical` | $r = f \tan\theta$ | 针孔投影，直线保持直线 | < 180° |
| `stereographic` | $r = 2f \tan(\theta/2)$ | 保角投影，形状不变 | < 360° |
| `equidistant` | $r = f \theta$ | 等距投影，角度线性映射 | 360° |
| `equisolid_angle` | $r = 2f \sin(\theta/2)$ | 等立体角投影 | 360° |
| `orthographic` | $r = f \sin\theta$ | 正交投影 | 180° |
| `custom` | $r = c_1 f \cdot \text{fun}(\theta/c_2 + c_3)$ | 自定义映射函数 | 自定义 |

**自定义映射函数**配置示例：

```xml
<lens>
  <type>custom</type>
  <custom_function>
    <c1>1.05</c1>       <!-- 线性缩放 -->
    <c2>4</c2>          <!-- 角度缩放 -->
    <f>1.0</f>          <!-- 焦距参数 -->
    <fun>tan</fun>      <!-- sin | tan | id -->
  </custom_function>
  <scale_to_hfov>true</scale_to_hfov>
  <cutoff_angle>3.1416</cutoff_angle>
  <env_texture_size>512</env_texture_size>
</lens>
```

### 8.4 性能与质量权衡

| 参数 | 影响 | 建议 |
|------|------|------|
| `env_texture_size` | 越大越清晰，GPU 开销越高 | 512（快速）~ 2048（高质量） |
| `cutoff_angle` | 超出此角度的内容被裁剪 | 设为 FOV/2 或略大 |
| 图像尺寸 | 最终输出分辨率 | 鱼眼通常用正方形（如 800×800） |

**性能提示**：广角相机比普通相机**慢 6 倍以上**（需渲染 6 面立方体贴图），应谨慎使用高分辨率和高帧率。

---

## 九、触发相机（`triggered_camera`）

### 9.1 概述

触发相机不连续输出图像，而是等待外部触发信号后才拍摄一帧。适用于事件驱动的图像采集场景。

### 9.2 SDF 配置

```xml
<sensor type="triggered_camera" name="trigger_cam">
  <pose>0.1 0 0.1 0 0 0</pose>
  <update_rate>0</update_rate>   <!-- 0 = 不自动更新 -->
  <camera name="triggered">
    <horizontal_fov>1.047</horizontal_fov>
    <image>
      <width>1920</width>
      <height>1080</height>
    </image>
    <clip>
      <near>0.1</near>
      <far>100</far>
    </clip>
  </camera>
  <topic>triggered_camera</topic>
</sensor>
```

### 9.3 触发方式

通过 gz-transport 向触发话题发送空消息：

```bash
gz topic -t /triggered_camera/trigger -m gz.msgs.Boolean -p 'data: true'
```

或在代码中：

```python
from gz.transport13 import Node
from gz.msgs10.boolean_pb2 import Boolean

node = Node()
pub = node.advertise("/triggered_camera/trigger", Boolean)
msg = Boolean()
msg.data = True
pub.publish(msg)
```

### 9.4 应用场景

- 帧扫模式的光电转台（每转到一个方位拍一帧）
- 低带宽场景下的按需采集
- 与外部事件（如雷达告警）同步的图像捕获

---

## 十、相机内参与外参的精确控制

### 10.1 内参矩阵

Gazebo 支持通过 `<lens><intrinsics>` 直接指定相机内参矩阵 $K$：

$$
K = \begin{bmatrix} f_x & s & c_x \\ 0 & f_y & c_y \\ 0 & 0 & 1 \end{bmatrix}
$$

```xml
<lens>
  <intrinsics>
    <fx>554.25</fx>     <!-- 水平焦距（像素） -->
    <fy>554.25</fy>     <!-- 垂直焦距（像素） -->
    <cx>320.0</cx>      <!-- 主点 x（像素） -->
    <cy>240.0</cy>      <!-- 主点 y（像素） -->
    <s>0</s>            <!-- 倾斜系数 -->
  </intrinsics>
</lens>
```

**焦距与 FOV 的换算**：

$$
f_x = \frac{w}{2 \tan(\text{HFOV}/2)}, \quad f_y = \frac{h}{2 \tan(\text{VFOV}/2)}
$$

| 参数 | 计算示例（640×480, 60° HFOV） |
|------|------------------------------|
| $f_x$ | $640 / (2 \times \tan 30°) = 554.26$ |
| $f_y$ | $480 / (2 \times \tan 22.5°) \approx 579.41$（非正方形像素） |
| $c_x$ | $640 / 2 = 320$ |
| $c_y$ | $480 / 2 = 240$ |

**注意**：当同时指定 `<horizontal_fov>` 和 `<intrinsics>` 时，`<intrinsics>` 优先。

### 10.2 外参（安装位姿）

传感器的安装位姿通过 `<pose>` 指定，格式为 `x y z roll pitch yaw`（欧拉角，弧度）：

```xml
<sensor type="camera" name="front_cam">
  <!-- 安装在 link 前方 0.15m，上方 0.05m，向下俯视 10° -->
  <pose>0.15 0 0.05 0 0.1745 0</pose>
  ...
</sensor>
```

多相机系统中，每个相机的 `<pose>` 决定了它们之间的相对位置关系（外参）。

---

## 十一、与 ROS2 集成

### 11.1 ros_gz_bridge

Gazebo 图像话题通过 `ros_gz_bridge` 桥接到 ROS2：

```bash
ros2 run ros_gz_bridge parameter_bridge \
  /rgb_camera@sensor_msgs/msg/Image@gz.msgs.Image \
  /rgb_camera/camera_info@sensor_msgs/msg/CameraInfo@gz.msgs.CameraInfo \
  /depth_camera@sensor_msgs/msg/Image@gz.msgs.Image \
  /rgbd/points@sensor_msgs/msg/PointCloud2@gz.msgs.PointCloudPacked
```

### 11.2 ROS2 话题映射

| Gazebo 话题 | ROS2 消息类型 | 说明 |
|------------|--------------|------|
| `*/image` | `sensor_msgs/msg/Image` | RGB / Depth / Thermal 图像 |
| `*/camera_info` | `sensor_msgs/msg/CameraInfo` | 内参（含畸变系数） |
| `*/points` | `sensor_msgs/msg/PointCloud2` | RGBD 点云 |
| `*/boxes` | 自定义 | 需自行编写桥接节点 |

### 11.3 在 launch 文件中集成

```python
from launch import LaunchDescription
from launch.actions import IncludeLaunchDescription
from launch_ros.actions import Node

def generate_launch_description():
    return LaunchDescription([
        # 启动 Gazebo
        IncludeLaunchDescription(
            # ... gz_sim launch ...
        ),
        # 桥接相机话题
        Node(
            package='ros_gz_bridge',
            executable='parameter_bridge',
            arguments=[
                '/rgb_camera@sensor_msgs/msg/Image@gz.msgs.Image',
                '/rgb_camera/camera_info@sensor_msgs/msg/CameraInfo@gz.msgs.CameraInfo',
            ],
            output='screen'
        ),
    ])
```

---

## 十二、性能优化指南

### 12.1 各传感器 GPU 开销对比

| 传感器 | 相对开销 | 瓶颈 |
|--------|---------|------|
| camera | 1× | 基准 |
| depth_camera | 1.2× | 深度 pass |
| rgbd_camera | 1.5× | RGB + Depth 两个 pass |
| thermal_camera | 1.3× | 温度 pass |
| segmentation | 1.3× | 分割 pass |
| boundingbox_camera | 1.5× | 分割 + BBox 计算 |
| wideanglecamera | **6×+** | 6 面立方体贴图 |

### 12.2 优化策略

| 策略 | 方法 | 效果 |
|------|------|------|
| **降低分辨率** | 训练时 640×480 足够 | 线性降低开销 |
| **降低帧率** | 非实时场景用 10-15 Hz | 直接减少渲染次数 |
| **减少相机数量** | rgbd 替代 camera + depth | 减少一次渲染 |
| **缩小裁剪范围** | far 从 1000 降到 100 | 减少渲染物体数 |
| **使用 triggered_camera** | 按需采集 | 大幅减少渲染频率 |
| **调低 env_texture_size** | 广角相机 256-512 | 降低立方体贴图开销 |
| **HEADLESS 模式** | `gz sim -s` 或 `HEADLESS=1` | 省去 GUI 渲染开销 |

### 12.3 多相机同步

当使用多个相机时，Gazebo 默认在同一仿真步内依次渲染所有传感器。如果传感器帧率之和超过 GPU 处理能力，仿真实时因子会下降。

建议：
- 不同传感器使用**不同的 update_rate**（如 RGB 30Hz，热像 15Hz，分割 5Hz）
- 使用 `<always_on>false</always_on>` + 外部触发来精确控制渲染时机

---

## 十三、完整多相机配置示例

以下是一个无人机模型上搭载多种相机的完整 SDF 片段：

```xml
<link name="camera_link">
  <pose>0.1 0 0 0 0 0</pose>

  <!-- 前视 RGB 相机 -->
  <sensor type="camera" name="front_rgb">
    <pose>0 0 0 0 0 0</pose>
    <update_rate>30</update_rate>
    <camera>
      <horizontal_fov>1.3963</horizontal_fov>
      <image><width>1280</width><height>720</height><format>R8G8B8</format></image>
      <clip><near>0.3</near><far>500</far></clip>
      <noise><type>gaussian</type><mean>0</mean><stddev>0.007</stddev></noise>
    </camera>
    <always_on>true</always_on>
    <topic>drone/front_rgb</topic>
  </sensor>

  <!-- 下视 RGBD -->
  <sensor type="rgbd_camera" name="bottom_rgbd">
    <pose>0 0 -0.05 0 1.5708 0</pose>   <!-- 向下看 -->
    <update_rate>15</update_rate>
    <camera>
      <horizontal_fov>1.047</horizontal_fov>
      <image><width>640</width><height>480</height></image>
      <clip><near>0.3</near><far>20</far></clip>
    </camera>
    <always_on>true</always_on>
    <topic>drone/bottom_rgbd</topic>
  </sensor>

  <!-- 热成像 -->
  <sensor type="thermal_camera" name="ir">
    <pose>0 0 -0.03 0 0 0</pose>
    <update_rate>15</update_rate>
    <camera>
      <horizontal_fov>0.6109</horizontal_fov>  <!-- 35° -->
      <image><width>640</width><height>512</height><format>L16</format></image>
      <clip><near>1</near><far>3000</far></clip>
    </camera>
    <always_on>true</always_on>
    <topic>drone/thermal</topic>
  </sensor>

  <!-- 语义分割（用于生成训练数据） -->
  <sensor type="segmentation" name="seg">
    <pose>0 0 0 0 0 0</pose>
    <update_rate>5</update_rate>
    <camera>
      <segmentation_type>instance</segmentation_type>
      <horizontal_fov>1.3963</horizontal_fov>
      <image><width>640</width><height>480</height></image>
      <clip><near>0.3</near><far>100</far></clip>
    </camera>
    <always_on>true</always_on>
    <topic>drone/segmentation</topic>
  </sensor>
</link>
```

---

## 十四、8 种相机选型决策树

{% mermaid %}
graph TD
    A[你的仿真需要什么视觉数据?] --> B{需要温度信息?}
    B -->|是| C[thermal_camera<br>热成像]
    B -->|否| D{需要深度信息?}
    D -->|否| E{FOV > 90°?}
    D -->|是| F{同时需要 RGB?}
    F -->|是| G[rgbd_camera<br>RGBD 相机]
    F -->|否| H[depth_camera<br>深度相机]
    E -->|是| I[wideanglecamera<br>广角/鱼眼]
    E -->|否| J{需要标注数据?}
    J -->|否| K{需要连续拍摄?}
    J -->|是| L{需要逐像素标注?}
    L -->|是| M[segmentation<br>分割相机]
    L -->|否| N[boundingbox_camera<br>包围盒相机]
    K -->|是| O[camera<br>RGB 相机]
    K -->|否| P[triggered_camera<br>触发相机]
{% endmermaid %}

---

## 参考资料

1. [Gazebo Sim Sensors Tutorial](https://gazebosim.org/docs/harmonic/sensors/)
2. [Gazebo Sim Feature Comparison](https://gazebosim.org/docs/harmonic/comparison/)
3. [gz-sensors API (Harmonic)](https://gazebosim.org/api/sensors/9/)
4. [Thermal Camera in Gazebo Tutorial](https://gazebosim.org/api/sensors/9/thermalcameraigngazebo.html)
5. [Segmentation Camera in Gazebo Tutorial](https://gazebosim.org/api/sensors/9/segmentationcamera_igngazebo.html)
6. [Wide-Angle Camera Tutorial (Gazebo Classic)](https://classic.gazebosim.org/tutorials?tut=wide_angle_camera)
7. [Camera Distortion Tutorial (Gazebo Classic)](https://classic.gazebosim.org/tutorials?tut=camera_distortion)
8. [gz-rendering CameraLens API](https://gazebosim.org/api/rendering/10/classgz_1_1rendering_1_1CameraLens.html)
9. Brown, D.C., "Close-range camera calibration", Photogrammetric Engineering, 1971
