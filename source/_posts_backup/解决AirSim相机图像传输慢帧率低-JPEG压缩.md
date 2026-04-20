---
title: 解决 AirSim 相机图像传输慢、帧率低：可调质量 JPEG 压缩
date: 2026-03-14 20:00:00
categories:
  - 开发
tags:
  - AirSim
  - Colosseum
  - 仿真
  - Unreal Engine
  - UE5.7
  - JPEG
  - 图像压缩
  - RPC
  - WSL
---

在使用 **Colosseum**（AirSim 的继任仿真平台）做仿真时，相机图像通常通过 RPC（如 `simGetImages`）从 Unreal 端传到 Python 客户端。默认要么返回**原始 RGB 像素**，要么用 **PNG** 压缩。原始数据体积大（例如 1920×1080×3 ≈ 6MB/帧），PNG 虽能压缩但仍有明显体积和编码开销，在 **WSL** 或 **远程连接** 场景下容易成为瓶颈，帧率上不去。本文在 **Colosseum + Unreal Engine 5.7.2** 环境下增加了 **可调质量的 JPEG 压缩** 支持，在保证画质可接受的前提下减小传输体积、提高帧率。下面记录需求背景、设计思路和具体实现，方便日后维护。

---

## 一、为什么需要 JPEG 压缩？

### 1.1 问题场景

- **RPC 传输体积大**：每帧图像若以原始 RGB 或 PNG 形式通过 msgpack-RPC 传输，在 1080p 下数据量可达数 MB，网络或进程间拷贝成本高。
- **帧率受限**：传输时间占主导时，相机帧率上不去，影响实时控制、算法测试或数据采集。
- **WSL / 远程**：  
  - **WSL**：AirSim 跑在 Windows，Python 跑在 WSL，图像要跨 WSL 边界，带宽和延迟都敏感。  
  - **远程**：客户端与仿真不在同一台机器时，网络带宽往往是瓶颈。

### 1.2 方案选择

引入 **JPEG 压缩**，并增加一个 **质量参数**（1–100），在「体积」和「画质」之间可调：

- 质量 85–90：视觉上接近无损，体积通常比 PNG 小一个数量级。
- 质量 70–80：适合对画质要求不极致的场景，进一步减小体积、提高帧率。

同时保留原有行为：**不压缩（raw）** 和 **PNG**，通过同一套参数区分，避免破坏现有 API。

---

## 二、设计：`compress_quality` 语义

在原有 `ImageRequest` 的 `compress`（是否压缩）基础上，增加 **`compress_quality`**，用**一个整数**同时表示「是否压缩」和「压缩格式」：

| `compress_quality` | 含义 |
|-------------------|------|
| **0** | 不压缩，返回原始 RGB（BGR 顺序，每像素 3 字节） |
| **-1** | 使用 PNG 压缩（与原先 `compress=true` 时行为一致） |
| **1–100** | 使用 JPEG 压缩，数值为 JPEG 质量（1 最差、100 最好） |

这样客户端只需在构造 `ImageRequest` 时传入一个参数（例如 `85` 表示 JPEG 质量 85），无需额外布尔或枚举。

---

## 三、整体数据流

从「客户端发起请求」到「拿到压缩后的图像」的流程可以概括为：

1. **客户端**（如 Python）：构造 `ImageRequest(..., compress_quality=85)`，通过 RPC 发给 AirSim 服务端。
2. **AirLib**：解析请求，把 `compress_quality` 填入内部 `ImageCaptureBase::ImageRequest`，并传给 Unreal 插件。
3. **Unreal 插件**：  
   - 用 **Scene Capture** 把相机渲染到 RenderTarget，读回像素（`FColor` 数组）。  
   - 根据 `compress_quality` 分支：  
     - `> 0` → 调用 **JPEG 压缩**（UE 的 `IImageWrapper`），输出 JPEG 字节流；  
     - `== -1` 或 原有 `compress == true` → **PNG 压缩**；  
     - 否则 → **Raw**，按行拷贝 BGR。
4. 压缩结果（或 raw 数据）填回 `ImageResponse`，经 RPC 返回客户端。
5. **客户端**：收到的 `image_data_uint8` 在 JPEG 模式下已是 JPEG 文件字节流，用 OpenCV 或 PIL 解码即可得到 numpy 图像。

下面按「层」说明各处的具体修改。

---

## 四、修改点详解

### 4.1 AirLib：请求与响应结构（C++）

**文件**：`AirLib/include/common/ImageCaptureBase.hpp`

- 在 `ImageCaptureBase::ImageRequest` 中增加字段：
  - `int compress_quality = 0;  // 0=raw, -1=PNG, 1-100=JPEG quality`
- 构造函数中增加参数 `compress_quality_val`，并在初始化列表里赋值。

这样所有使用 `ImageRequest` 的 C++ 代码都能带上「压缩质量」信息。

---

### 4.2 RPC 适配层（msgpack 序列化）

**文件**：`AirLib/include/api/RpcLibAdaptorsBase.hpp`

- 在 RPC 用的 `ImageRequest` 适配结构体中增加：
  - `int compress_quality = 0;`
- 在 **MSGPACK_DEFINE_ARRAY** 中**在末尾追加** `compress_quality`（重要：若已有客户端只发 4 个字段，末尾加一个 int 可保持兼容，老客户端发 0 即 raw）。
- 在 `ImageRequest` 的「从 AirLib 转 RPC」和「从 RPC 转 AirLib」的构造函数 / `to()` 方法中，增加对 `compress_quality` 的读写。

这样 Python 或 C++ 客户端传入的 `compress_quality` 能正确在服务端被解析。

---

### 4.3 Unreal：渲染参数与三路分支

**文件**：  
- `Unreal/Plugins/AirSim/Source/RenderRequest.h`  
- `Unreal/Plugins/AirSim/Source/RenderRequest.cpp`

- **RenderParams**：增加成员 `int compress_quality;`，构造函数增加参数 `compress_quality_val = 0`。
- **UnrealImageCapture.cpp**：在构造 `RenderParams` 时传入 `requests[i].compress_quality`，这样渲染管线里每一帧请求都带上「要 JPEG / PNG / raw」的信息。

在 **RenderRequest.cpp** 的 `getScreenshot` 中，从 RenderTarget 读回像素后（已按 stride 处理成 `src_bmp`），对**非 float** 图像做分支：

```cpp
if (params[i]->compress_quality > 0) {
    // JPEG：质量 1–100
    UAirBlueprintLib::CompressImageArrayJPEG(w, h, src_bmp, results[i]->image_data_uint8, params[i]->compress_quality);
}
else if (params[i]->compress_quality == -1 || params[i]->compress) {
    // PNG 或原有「压缩」语义
    UAirBlueprintLib::CompressImageArray(w, h, src_bmp, results[i]->image_data_uint8);
}
else {
    // Raw：按行 BGR 拷贝到 image_data_uint8
    results[i]->image_data_uint8.SetNumUninitialized(w * h * 3, false);
    // ... 逐像素 B,G,R 写入
}
```

这样 **JPEG / PNG / raw** 三路清晰分离，且与 `compress_quality` 约定一致。

---

### 4.4 Unreal：JPEG 压缩实现（AirBlueprintLib）

**文件**：  
- `Unreal/Plugins/AirSim/Source/AirBlueprintLib.h`  
- `Unreal/Plugins/AirSim/Source/AirBlueprintLib.cpp`

- 在头文件中声明：
  - `static void CompressImageArrayJPEG(int32 width, int32 height, const TArray<FColor>& src, TArray<uint8>& dest, int32 quality = 90);`
- 在实现中：
  1. Unreal 的 `FColor` 是 BGRA，而 UE 的 `IImageWrapper::SetRaw` 常用 RGBA，因此先对 `src` 做 **R/B 互换**（或按引擎文档要求的格式）得到 RGBA。
  2. 用 **ImageWrapper 模块**（`FModuleManager::LoadModuleChecked<IImageWrapperModule>("ImageWrapper")`）创建 **JPEG** 类型的 `IImageWrapper`。
  3. 调用 `SetRaw(..., width, height, ERGBFormat::RGBA, 8)` 填入原始像素。
  4. 调用 **`GetCompressed(quality)`** 得到 JPEG 字节流，写入 `dest`。

**注意**：在 **Unreal Engine 5.7**（本文在 UE 5.7.2 下验证）中，应使用 **`GetCompressed(quality)`** 传入质量，不要依赖已废弃的 `SetQuality` 等接口，否则可能编译不过或行为异常。

---

### 4.5 Python 客户端

**文件**：`PythonClient/airsim/types.py`

- 在 `ImageRequest` 中增加：
  - 类属性：`compress_quality = 0  # 0=raw, -1=PNG, 1-100=JPEG quality`
  - `attribute_order` 中追加 `('compress_quality', int)`（顺序须与 C++ 端 MSGPACK 一致）。
- `__init__` 增加参数 `compress_quality=0`，并赋值给 `self.compress_quality`。

这样 Python 侧构造请求时即可指定 JPEG 质量，例如：

```python
req = airsim.ImageRequest("0", airsim.ImageType.Scene, False, False, 85)
```

---

## 五、使用示例（Python）

### 5.1 请求 JPEG 并解码

若脚本放在 Colosseum 的 `PythonClient/multirotor/` 等子目录下，需先设置路径并 `import setup_path`，再 `import airsim`，否则会找不到 `airsim` 模块：

```python
import os
import sys

# 将 PythonClient 加入 path，便于下面 import setup_path 和 airsim
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import setup_path
import airsim
import cv2
import numpy as np

client = airsim.MultirotorClient()
client.confirmConnection()

# 请求 JPEG 质量 85
req = airsim.ImageRequest("0", airsim.ImageType.Scene, False, False, 85)
responses = client.simGetImages([req], vehicle_name="")

if responses and len(responses[0].image_data_uint8) > 0:
    # 返回的是 JPEG 编码的字节流
    jpeg_bytes = np.frombuffer(responses[0].image_data_uint8, dtype=np.uint8)
    img = cv2.imdecode(jpeg_bytes, cv2.IMREAD_COLOR)
    if img is not None:
        cv2.imshow("Scene", img)
        cv2.waitKey(0)
```

### 5.2 不同格式对比

（以下代码需在 `import setup_path` 与 `import airsim` 之后使用。）

```python
# Raw（不压缩）
req_raw = airsim.ImageRequest("0", airsim.ImageType.Scene, False, False, 0)

# PNG
req_png = airsim.ImageRequest("0", airsim.ImageType.Scene, False, True, -1)

# JPEG 质量 90
req_jpeg = airsim.ImageRequest("0", airsim.ImageType.Scene, False, False, 90)
```

- Raw：`image_data_uint8` 为 `height * width * 3` 的 BGR 像素，可直接 `img = np.frombuffer(..., dtype=np.uint8).reshape(h, w, 3)`。  
- PNG/JPEG：`image_data_uint8` 为编码后的字节流，需用 `cv2.imdecode` 解码。

---

## 六、修改文件汇总

| 层级 | 文件 | 修改内容 |
|------|------|----------|
| AirLib | `AirLib/include/common/ImageCaptureBase.hpp` | `ImageRequest` 增加 `compress_quality` 及构造函数参数 |
| AirLib | `AirLib/include/api/RpcLibAdaptorsBase.hpp` | RPC 用 `ImageRequest` 增加 `compress_quality`，MSGPACK 与转换逻辑 |
| Unreal | `Unreal/Plugins/AirSim/Source/RenderRequest.h` | `RenderParams` 增加 `compress_quality` |
| Unreal | `Unreal/Plugins/AirSim/Source/RenderRequest.cpp` | 根据 `compress_quality` 分支：JPEG / PNG / raw |
| Unreal | `Unreal/Plugins/AirSim/Source/AirBlueprintLib.h` | 声明 `CompressImageArrayJPEG` |
| Unreal | `Unreal/Plugins/AirSim/Source/AirBlueprintLib.cpp` | 实现 `CompressImageArrayJPEG`（R/B 互换 + ImageWrapper JPEG + GetCompressed(quality)） |
| Unreal | `Unreal/Plugins/AirSim/Source/UnrealImageCapture.cpp` | 构造 `RenderParams` 时传入 `requests[i].compress_quality` |
| Python | `PythonClient/airsim/types.py` | `ImageRequest` 增加 `compress_quality` 与 `attribute_order`、构造函数 |

---

## 七、注意事项

1. **MSGPACK 顺序**：Python 的 `attribute_order` 与 C++ 的 `MSGPACK_DEFINE_ARRAY` 字段顺序必须一致，且 `compress_quality` 放在末尾，便于兼容未传该字段的旧客户端（可视为 0）。
2. **UE 5.7.x**（含 5.7.2）：使用 `IImageWrapper::GetCompressed(quality)` 传质量，不要使用已废弃的 `SetQuality`。
3. **Stride**：渲染目标可能存在 stride（每行字节数大于 `width*4`），在压缩前已按行拷贝到紧凑的 `src_bmp`，避免 JPEG/PNG 压缩读到多余 padding。
4. **解码端**：JPEG 返回的是完整 JPEG 文件二进制，客户端用 `cv2.imdecode` 或 PIL 解码即可，无需再区分 RGB/BGR（OpenCV 的 `imdecode` 默认 BGR，与 OpenCV 其他接口一致）。
5. **Python 路径**：从 `PythonClient` 子目录（如 `multirotor/`）运行脚本时，需在 `import airsim` 前先 `import setup_path`（并视情况用 `sys.path.insert` 把 PythonClient 根目录加入路径），否则会报错。

---

## 八、小结

通过在 AirSim 中增加 **`compress_quality`** 参数，并在 Unreal 渲染管线中根据该参数在 **JPEG / PNG / raw** 三路中选择一路输出，我们实现了可调质量的 JPEG 压缩：在 WSL、远程或高分辨率场景下，能显著减小 RPC 传输体积、提高相机帧率，同时保持与原有 raw/PNG 行为的兼容。实现上主要涉及 AirLib 请求结构、RPC 适配、Unreal 渲染参数与压缩分支、以及 Python 客户端的字段与序列化顺序；JPEG 编码本身复用 UE 的 `IImageWrapper`，无需自实现 DCT/熵编码。

**代码位置**：本文所述 JPEG 压缩修改基于 **Colosseum + Unreal Engine 5.7.2**，已合入笔者的 Colosseum 分支，可在 [goodisok/Colosseum](https://github.com/goodisok/Colosseum) 的 **`feature/jpeg-geomag-px4`** 分支中查看或拉取。
