---
title: 基于 Blender + HDRI 的无人机检测合成数据集生成：从光照真实感到 YOLOv8 训练的完整管线
date: 2026-04-26 03:30:00
categories:
  - 无人机
  - 计算机视觉
tags:
  - Blender
  - Cycles
  - EEVEE
  - HDRI
  - IBL
  - 合成数据
  - 数据集生成
  - YOLOv8
  - 目标检测
  - 无人机检测
  - PBR
  - 图像渲染
  - 域随机化
  - Sim-to-Real
  - 3D模型
  - Python
  - bpy
  - ZMQ
  - 实时渲染
---

> 训练一个能在空中可靠检测无人机的 YOLOv8 模型，最大的瓶颈不是算法，而是**数据**。真实空对空无人机图像极难获取——你需要另一架无人机在空中拍摄，天气、光照、距离、姿态的组合几乎无穷无尽，而每张图片都需要人工标注 bounding box。
>
> 本文提出一种基于 **Blender Cycles 路径追踪 + HDRI 全景天空 + 3D 无人机模型**的全自动合成数据集生成管线，一条命令即可批量生产带 YOLO 格式标注的 1080p 图像。核心优势：**真实的图像级光照（IBL）**——无人机模型的光照、阴影、反射都由 HDRI 天空自然驱动，无需手动打灯，Sim-to-Real gap 远小于简单合成。

---

## 一、为什么不用 UE5 / Isaac Sim / 简单合成？

在开始之前，先说清楚**为什么选 Blender + HDRI** 这条路，而不是看似更"高端"的方案。

### 1.1 简单 2D 合成（OpenCV 抠图贴图）

把无人机图片抠出来贴到天空背景上，最常见的做法。问题在于：

- **光照不一致**：无人机上的光影方向与背景天空完全无关
- **边缘伪影**：抠图边缘有明显的色差和锯齿
- **无 3D 姿态变化**：同一张 2D 图片只能做仿射变换，无法生成真实的俯仰/滚转视角

实际测试中，用这种方法训练的检测器在真实图像上的 mAP 通常比 HDRI 渲染低 15-25%。

### 1.2 UE5 / Isaac Sim

Unreal Engine 5 的 Lumen/Nanite 渲染质量毫无疑问是最高的，但：

| 维度 | UE5 / Isaac Sim | Blender + HDRI |
|------|-----------------|----------------|
| 部署复杂度 | 需要完整 UE5 工程，100GB+ 磁盘 | 单脚本 + 便携版 Blender |
| 场景构建 | 需要 3D 艺术家制作天空盒/场景 | 直接用 Polyhaven 免费 HDRI |
| 编程接口 | C++ 或 UnrealCV Python 桥 | 原生 `bpy` Python API |
| 无头渲染 | 需要 GPU + 显示上下文 | `--background` 纯 CPU 可跑 |
| 学习曲线 | 陡峭 | 30 分钟上手 |

对于"空中无人机检测"这个特定任务——画面 95% 是天空，目标只有几十到几千像素——UE5 的超写实地表和建筑渲染完全用不上，**杀鸡用牛刀**。

### 1.3 3D Gaussian Splatting (3DGS)

3DGS 擅长从多视角照片重建真实场景，但：

- 需要先采集真实多视角数据（鸡生蛋问题）
- 动态目标重建困难
- 视角泛化能力有限，离训练视角太远会出现伪影

### 1.4 Blender + HDRI：精准打击

HDRI 全景天空本质上是一张**记录了全方位真实光照信息的 360° 照片**（HDR 格式，保留完整的辐射度量信息）。Blender Cycles 的 IBL（Image-Based Lighting）用这张全景图同时作为：

1. **背景**：相机看到的天空就是 HDRI 本身
2. **光源**：HDRI 中的太阳、云层的亮度直接照亮 3D 模型
3. **环境反射**：模型表面的反光也来自 HDRI

这意味着**模型的光照与背景天生一致**，不需要额外的灯光设置。

---

## 二、系统架构

```
┌─────────────────────────────────────────────┐
│                  输入层                       │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐ │
│  │ 3D 模型   │  │ HDRI 天空 │  │ 渲染参数   │ │
│  │ (.glb)   │  │ (.hdr 4K) │  │ (CLI args)│ │
│  └────┬─────┘  └────┬─────┘  └─────┬─────┘ │
└───────┼──────────────┼──────────────┼───────┘
        │              │              │
        ▼              ▼              ▼
┌─────────────────────────────────────────────┐
│              Blender bpy 场景               │
│                                             │
│  ┌─────────────────────────────┐            │
│  │  HDRI World Node Graph      │            │
│  │  TexCoord → Mapping →       │            │
│  │  TexEnvironment → Background │            │
│  └─────────────────────────────┘            │
│                                             │
│  ┌──────────────┐  ┌──────────────┐         │
│  │  DroneRoot   │  │   Camera     │         │
│  │  (Empty)     │  │  (FOV, 6DoF) │         │
│  │    └─ Mesh   │  └──────────────┘         │
│  └──────────────┘                           │
└──────────────────────┬──────────────────────┘
                       │
              ┌────────┴────────┐
              │  Cycles 渲染    │
              │  32 SPP + OIDN  │
              └────────┬────────┘
                       │
                       ▼
┌─────────────────────────────────────────────┐
│                  输出层                       │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐ │
│  │ JPEG 图像 │  │ YOLO 标注 │  │ dataset   │ │
│  │ 1920×1080│  │ (.txt)   │  │  .yaml    │ │
│  └──────────┘  └──────────┘  └───────────┘ │
│                                             │
│        train/  val/  test/  自动划分         │
└─────────────────────────────────────────────┘
```

---

## 三、环境搭建

### 3.1 安装 Blender（便携版，无需 sudo）

```bash
cd ~
wget https://mirror.clarkson.edu/blender/release/Blender4.2/blender-4.2.0-linux-x64.tar.xz
tar xf blender-4.2.0-linux-x64.tar.xz
export BLENDER=~/blender-4.2.0-linux-x64/blender
$BLENDER --version
```

WSL2 用户注意：Blender Cycles 在 WSL2 中通常无法使用 GPU（OptiX/CUDA），会自动回退到 CPU。这只影响速度（单帧约 2 秒），不影响画质。原生 Linux 或 Windows 下 RTX 4090 可以加速到 0.1-0.3 秒/帧。

### 3.2 准备 HDRI 天空

从 [Polyhaven](https://polyhaven.com/hdris/skies) 下载免费的 4K 天空 HDRI（选择 `.hdr` 格式）：

```bash
mkdir -p hdri
cd hdri

# 示例：下载几张典型天空（晴天、多云、黄昏、日出等）
wget https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/4k/kloofendal_48d_partly_cloudy_4k.hdr
wget https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/4k/evening_road_01_puresky_4k.hdr
wget https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/4k/kiara_1_dawn_4k.hdr
# ... 建议至少准备 10+ 张不同天气/时间的天空
```

**为什么必须用 4K？** HDRI 是 360° 全景图，映射到 1080p 画面时只使用了一个锥形视角（约 30°-50°）。2K HDRI 展开后实际可用的像素密度太低，背景会糊。4K 是 1080p 输出的最低要求，8K 更佳。

### 3.3 准备 3D 无人机模型

推荐来源：
- [Sketchfab](https://sketchfab.com)（搜索 "drone"，筛选 "Downloadable"）
- [TurboSquid](https://www.turbosquid.com)
- 自建模型

下载 `.glb` 或 `.gltf` 格式（保留 PBR 材质信息）。本文以 DJI Mavic 3 模型为例：

```bash
mkdir -p models
# 将下载的模型放入 models/ 目录
ls models/
# dji_mavic_3.glb
```

---

## 四、核心代码解析

完整代码见 `render_cycles.py`，这里拆解关键模块。

### 4.1 HDRI 环境光照设置

这是整个方案的灵魂——用 Blender 的 Shader Node 把 HDRI 同时设为背景和光源：

```python
def setup_hdri(hdri_path: str, rotation_z: float = 0.0, strength: float = 1.0):
    world = bpy.context.scene.world
    if world is None:
        world = bpy.data.worlds.new("World")
        bpy.context.scene.world = world

    world.use_nodes = True
    tree = world.node_tree
    tree.nodes.clear()

    output_node = tree.nodes.new('ShaderNodeOutputWorld')
    bg_node = tree.nodes.new('ShaderNodeBackground')
    bg_node.inputs['Strength'].default_value = strength
    env_tex = tree.nodes.new('ShaderNodeTexEnvironment')
    env_tex.image = bpy.data.images.load(hdri_path)
    mapping_node = tree.nodes.new('ShaderNodeMapping')
    mapping_node.inputs['Rotation'].default_value = (0, 0, rotation_z)
    coord_node = tree.nodes.new('ShaderNodeTexCoord')

    tree.links.new(coord_node.outputs['Generated'], mapping_node.inputs['Vector'])
    tree.links.new(mapping_node.outputs['Vector'], env_tex.inputs['Vector'])
    tree.links.new(env_tex.outputs['Color'], bg_node.inputs['Color'])
    tree.links.new(bg_node.outputs['Background'], output_node.inputs['Surface'])
```

Node 链路：`TexCoord → Mapping(旋转) → TexEnvironment(加载HDRI) → Background(亮度) → World Output`

关键参数：
- **`rotation_z`**：每帧随机旋转 HDRI，相当于改变太阳方向，一张 HDRI 可以生成无数种光照条件
- **`strength`**：随机化光照强度（0.9~1.5），模拟不同曝光

### 4.2 3D 模型导入与标准化

不同来源的模型尺寸千差万别，必须统一归一化：

```python
def import_model(model_path: str, target_size: float = 3.5) -> list:
    ext = Path(model_path).suffix.lower()
    before = set(bpy.data.objects)

    if ext in ('.glb', '.gltf'):
        bpy.ops.import_scene.gltf(filepath=model_path)
    elif ext == '.obj':
        bpy.ops.wm.obj_import(filepath=model_path)
    elif ext == '.fbx':
        bpy.ops.import_scene.fbx(filepath=model_path)

    new_objects = list(set(bpy.data.objects) - before)
    mesh_objects = [o for o in new_objects if o.type == 'MESH']

    # 应用所有变换，确保 world 坐标准确
    bpy.ops.object.select_all(action='DESELECT')
    for obj in new_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = mesh_objects[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # 计算包围盒，归一化到 target_size 米
    all_coords = []
    for obj in mesh_objects:
        for v in obj.data.vertices:
            all_coords.append(obj.matrix_world @ v.co)

    xs = [c.x for c in all_coords]
    ys = [c.y for c in all_coords]
    zs = [c.z for c in all_coords]
    max_extent = max(max(xs)-min(xs), max(ys)-min(ys), max(zs)-min(zs))
    scale_factor = target_size / max_extent

    # 用 Empty 作为父节点统一管理
    root = bpy.data.objects.new("DroneRoot", None)
    bpy.context.collection.objects.link(root)
    for obj in new_objects:
        if obj.parent is None or obj.parent not in new_objects:
            obj.parent = root

    root.scale = (scale_factor, scale_factor, scale_factor)
    root.location = (-cx*scale_factor, -cy*scale_factor, -cz*scale_factor)
    return new_objects + [root]
```

**关键设计**：用 `DroneRoot` Empty 节点作为所有 mesh 的父节点，后续改变无人机姿态只需旋转这个 Empty，所有子 mesh 自动跟随。

### 4.3 观测构型随机化

真实场景中，相机与无人机的相对位置不是随机的——它遵循空气动力学和观测几何的约束。我们定义了 5 种典型观测构型，按概率加权采样：

```python
ENGAGEMENT_PROFILES = [
    {"name": "tail_chase",    "weight": 0.35,
     "azimuth": (-0.5, 0.5),   "elevation": (-0.15, 0.25),
     "distance": (30, 200),    "fov": (25, 50)},
    {"name": "side_approach", "weight": 0.25,
     "azimuth": (1.0, 2.14),   "elevation": (-0.1, 0.3),
     "distance": (40, 300),    "fov": (25, 50)},
    {"name": "head_on",       "weight": 0.15,
     "azimuth": (2.8, 3.48),   "elevation": (-0.1, 0.15),
     "distance": (50, 400),    "fov": (20, 45)},
    {"name": "above_rear",    "weight": 0.15,
     "azimuth": (-0.4, 0.4),   "elevation": (0.3, 0.7),
     "distance": (20, 150),    "fov": (25, 55)},
    {"name": "below_close",   "weight": 0.10,
     "azimuth": (-0.6, 0.6),   "elevation": (-0.4, -0.1),
     "distance": (20, 80),     "fov": (30, 55)},
]
```

每种构型定义了方位角、仰角、距离、FOV 的合理范围。`tail_chase`（尾追）权重最高，因为这是最常见的跟踪场景。

### 4.4 飞行姿态约束

无人机不会在空中任意翻转，真实飞行姿态有物理限制：

```python
# 滚转角：高斯分布，σ=3°，硬截断 ±8°
drone_roll = rng.gauss(0, math.radians(3))
drone_roll = max(math.radians(-8), min(math.radians(8), drone_roll))

# 俯仰角：均值 -2°（微前倾，模拟巡航），硬截断 -8°~+5°
drone_pitch = rng.gauss(math.radians(-2), math.radians(2))
drone_pitch = max(math.radians(-8), min(math.radians(5), drone_pitch))

# 偏航角：完全随机（任何朝向都合理）
drone_yaw = rng.uniform(0, 2 * math.pi)
```

### 4.5 2D Bounding Box 自动标注

渲染前通过 3D→2D 投影计算精确的 YOLO 格式 bbox：

```python
def get_bbox_2d(objects, scene, cam_obj, img_w, img_h):
    from bpy_extras.object_utils import world_to_camera_view

    min_x, min_y = float('inf'), float('inf')
    max_x, max_y = float('-inf'), float('-inf')
    found = False

    for obj in objects:
        if obj.type != 'MESH':
            continue
        for corner in obj.bound_box:
            co_world = obj.matrix_world @ mathutils.Vector(corner)
            co_cam = world_to_camera_view(scene, cam_obj, co_world)
            if co_cam.z > 0:  # 在相机前方
                min_x = min(min_x, co_cam.x)
                max_x = max(max_x, co_cam.x)
                min_y = min(min_y, co_cam.y)
                max_y = max(max_y, co_cam.y)
                found = True

    if not found:
        return None

    # 裁剪到画面内 + 转换为 YOLO 格式 (cx, cy, w, h)
    min_x, max_x = max(0.0, min_x), min(1.0, max_x)
    min_y, max_y = max(0.0, min_y), min(1.0, max_y)

    x1, y1 = int(min_x * img_w), int((1 - max_y) * img_h)
    x2, y2 = int(max_x * img_w), int((1 - min_y) * img_h)

    return {
        "bbox_yolo": [
            round((x1+x2)/2/img_w, 6), round((y1+y2)/2/img_h, 6),
            round((x2-x1)/img_w, 6), round((y2-y1)/img_h, 6),
        ],
        "pixel_area": (x2-x1) * (y2-y1),
    }
```

利用 `obj.bound_box`（8 个角点的包围盒）做 3D→2D 投影，比遍历所有顶点快 10-100 倍。

### 4.6 数据集自动划分

生成完毕后自动进行 train/val/test 划分，并输出 YOLOv8 可直接使用的 `dataset.yaml`：

```python
def write_dataset_yaml(output_dir: str, class_name: str):
    abs_dir = os.path.abspath(output_dir)
    yaml_content = f"""path: {abs_dir}
train: train/images
val: val/images
test: test/images

nc: 1
names:
  0: {class_name}
"""
    with open(os.path.join(output_dir, "dataset.yaml"), "w") as f:
        f.write(yaml_content)
```

---

## 五、一键生成数据集

### 5.1 离线批量生成

```bash
~/blender-4.2.0-linux-x64/blender --background --python render_cycles.py -- \
    --model models/dji_mavic_3.glb \
    --hdri-dir hdri \
    --output output/drone_dataset \
    --num 1500 \
    --width 1920 --height 1080 \
    --samples 32 \
    --min-pixels 100 \
    --train-ratio 0.8 \
    --val-ratio 0.15
```

输出目录结构：

```
output/drone_dataset/
├── images/         # 原始图像
├── labels/         # YOLO 标注文件
├── train/
│   ├── images/     # 80% 训练集
│   └── labels/
├── val/
│   ├── images/     # 15% 验证集
│   └── labels/
├── test/
│   ├── images/     # 5% 测试集
│   └── labels/
├── annotations.json  # 完整元数据（距离、FOV、姿态等）
└── dataset.yaml      # YOLOv8 配置文件
```

### 5.2 直接训练 YOLOv8

```bash
pip install ultralytics

yolo detect train \
    data=output/drone_dataset/dataset.yaml \
    model=yolov8n.pt \
    epochs=100 \
    imgsz=1080
```

### 5.3 性能参考

| 配置 | 单帧渲染时间 | 1500 张总耗时 |
|------|-------------|--------------|
| CPU (i7-12700) | ~2.0s | ~50 分钟 |
| GPU (RTX 4090, 原生 Linux) | ~0.15s | ~4 分钟 |
| CPU (WSL2, i7-12700) | ~2.5s | ~63 分钟 |

---

## 六、实时渲染模式

除了离线数据集生成，我们还实现了一个**实时渲染器** `render_eevee_realtime.py`，用于仿真回路测试。

### 6.1 设计目标

在 Hardware-in-the-Loop (HITL) 或 Software-in-the-Loop (SITL) 仿真中，动力学引擎（如 Gazebo/PX4）输出 6DoF 位姿，渲染器实时生成相机画面，供 YOLOv8 推理：

```
Gazebo/PX4 → [ZMQ 6DoF Pose] → Blender 渲染 → [ZMQ Frame] → YOLOv8
```

### 6.2 轨迹仿真

内置了一个 demo 模式的接近轨迹，模拟追踪无人机从 400m 外逐渐逼近到 15m 的过程：

```python
class InterceptionTrajectory:
    def __init__(self, duration: float = 15.0, seed: int = 42):
        self.initial_distance = 400.0
        self.final_distance = 15.0
        self.closing_speed = (self.initial_distance - self.final_distance) / duration
        self.initial_fov = 45.0
        self.final_fov = 25.0
        # 横向和纵向抖动，模拟气流扰动
        self.lateral_drift_amp = 8.0
        self.vertical_drift_amp = 5.0
        self.drift_freq = 0.3
```

随着距离缩短，FOV 自动缩小（模拟变焦锁定），横向抖动幅度也逐渐减小（越近跟踪越稳定）。

### 6.3 ZMQ 帧发布

渲染的每一帧通过 ZMQ PUB socket 发布，下游消费者可以是 YOLOv8 推理进程、录像工具或可视化界面：

```python
class FramePublisher:
    def __init__(self, port: int = 5555):
        import zmq
        self.ctx = zmq.Context()
        self.socket = self.ctx.socket(zmq.PUB)
        self.socket.bind(f"tcp://0.0.0.0:{port}")
        self.socket.setsockopt(zmq.SNDHWM, 2)  # 只保留最新 2 帧

    def publish(self, rgb_bytes, w, h, metadata):
        header = {**metadata, "w": w, "h": h, "channels": 3, "dtype": "uint8"}
        self.socket.send_json(header, flags=zmq.SNDMORE)
        self.socket.send(rgb_bytes, copy=False)
```

下游接收示例：

```python
import zmq, numpy as np, cv2

ctx = zmq.Context()
sub = ctx.socket(zmq.SUB)
sub.connect('tcp://127.0.0.1:5555')
sub.setsockopt(zmq.SUBSCRIBE, b'')

while True:
    header = sub.recv_json()
    buf = sub.recv()
    img = np.frombuffer(buf, dtype=np.uint8).reshape(header['h'], header['w'], 3)
    cv2.imshow('drone_cam', img[..., ::-1])
    cv2.waitKey(1)
```

### 6.4 渲染引擎自动降级

在不同硬件环境下自动选择最佳渲染引擎：

```
EEVEE (GPU, 实时) → Workbench (GPU, 极速) → Cycles-Low (CPU, 4SPP + 降噪)
```

WSL2 环境下 EEVEE 因缺少 Vulkan 上下文无法使用，会自动降级到 Cycles-Low（约 0.5 FPS）；原生 Linux + GPU 环境下 EEVEE 可达 30+ FPS。

### 6.5 运行 Demo

```bash
~/blender-4.2.0-linux-x64/blender --background --python render_eevee_realtime.py -- \
    --model models/dji_mavic_3.glb \
    --hdri-dir hdri \
    --mode demo \
    --duration 15 \
    --save-frames output/realtime_demo \
    --fallback cycles-low
```

---

## 七、域随机化策略

为了让合成数据训练的模型泛化到真实场景，我们在多个维度上做了域随机化：

| 维度 | 随机化方式 | 范围 |
|------|-----------|------|
| 天空背景 | 13 张 4K HDRI 轮换 | 晴天/多云/黄昏/日出/雾天 |
| 太阳方向 | HDRI 绕 Z 轴随机旋转 | 0° ~ 360° |
| 光照强度 | HDRI Background Strength | 0.9 ~ 1.5 |
| 观测距离 | 按构型分布 | 15m ~ 400m |
| 观测角度 | 5 种构型加权采样 | 尾追/侧方/迎头/上方/下方 |
| 相机 FOV | 按构型分布 | 20° ~ 55° |
| 目标姿态 | 受约束的高斯分布 | roll ±8°, pitch -8°~+5° |

---

## 八、与其他方案的详细对比

| | Blender+HDRI (本方案) | UE5/Isaac Sim | 3DGS | 2D 合成 |
|---|---|---|---|---|
| **光照真实感** | 物理准确的 IBL | 最高（Lumen） | 依赖采集质量 | 无 |
| **部署复杂度** | 低（单脚本） | 高（100GB+） | 中 | 低 |
| **标注方式** | 3D 投影，100% 准确 | 引擎内置 | 需额外工具 | 手动 |
| **场景多样性** | HDRI 数量决定 | 需 3D 建模 | 需多场景采集 | 背景图数量 |
| **CPU 可用** | 是 | 否 | 否 | 是 |
| **适用场景** | 天空背景目标检测 | 复杂地面场景 | 场景重建 | 快速原型 |
| **学习成本** | 30 分钟 | 数天~数周 | 数天 | 10 分钟 |

---

## 九、已知局限与未来改进

### 9.1 当前局限

1. **单目标**：当前只支持一个无人机，不支持多目标同时出现
2. **无运动模糊**：静态渲染，缺乏高速运动时的运动模糊效果
3. **无大气散射**：远距离目标应该有雾霾/大气衰减效果
4. **GPU 利用率**：WSL2 下 Cycles 无法使用 GPU，渲染速度受限

### 9.2 改进方向

- **多目标支持**：在场景中放置多个不同型号的无人机模型
- **大气效果**：通过 Blender 的 Volume Scatter 节点模拟大气散射
- **运动模糊**：启用 Cycles 的 Motion Blur，给无人机添加关键帧动画
- **分割标注**：除了 bbox，还可以利用 Cycles 的 Object Index pass 生成实例分割 mask
- **COCO 格式导出**：支持 COCO JSON 格式标注
- **Gazebo/PX4 对接**：实现 `server` 模式，通过 ZMQ 接收动力学引擎的实时位姿

---

## 十、完整文件清单

```
hdri-drone-render/
├── models/
│   └── dji_mavic_3.glb              # DJI Mavic 3 无人机模型
├── hdri/
│   ├── kloofendal_48d_partly_cloudy_4k.hdr
│   ├── evening_road_01_puresky_4k.hdr
│   ├── kiara_1_dawn_4k.hdr
│   └── ... (共 13 张 4K HDRI)
├── render_cycles.py                  # 离线数据集生成器
├── render_eevee_realtime.py          # 实时渲染器
└── output/                           # 生成的数据集
```

---

## 参考资料

- [Polyhaven HDRI 库](https://polyhaven.com/hdris) — 免费 CC0 协议的高质量 HDRI
- [Blender Python API (bpy)](https://docs.blender.org/api/current/) — Blender 官方 Python 接口文档
- [Sim2Air: Synthetic aerial dataset for UAV monitoring (CVPRW 2021)](https://arxiv.org/abs/2006.14064) — 使用 Blender+HDRI 生成空中无人机检测数据集的先驱工作
- [BlenderProc](https://github.com/DLR-RM/BlenderProc) — DLR 开源的 Blender 合成数据框架
- [YOLOv8 Documentation](https://docs.ultralytics.com/) — Ultralytics YOLOv8 官方文档
- [Image-Based Lighting (IBL)](https://en.wikipedia.org/wiki/Image-based_lighting) — 基于图像的光照技术原理
