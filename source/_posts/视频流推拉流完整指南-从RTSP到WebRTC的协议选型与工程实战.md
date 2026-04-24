---
title: 视频流推拉流完整指南：从 RTSP 到 WebRTC 的协议选型与工程实战
date: 2026-04-16 20:00:00
categories:
  - 音视频
  - 流媒体
tags:
  - 推流
  - 拉流
  - RTSP
  - RTMP
  - SRT
  - WebRTC
  - WHIP
  - WHEP
  - HLS
  - FFmpeg
  - GStreamer
  - MediaMTX
  - NVENC
  - 硬件编码
  - H.264
  - H.265
  - 低延迟
  - 无人机
  - Jetson
  - 视频流
mathjax: true
---

> 视频流的"推"和"拉"是流媒体工程的两个基本动作。推流（Publish/Ingest）是把视频从源端送到服务器，拉流（Play/Egress）是从服务器取出视频播放。听起来简单，但协议选错延迟差十倍，编码选错 CPU 占满帧率减半。本文以 2026 年的技术现状为基准，系统梳理从协议选型到硬件编码到落地部署的完整链路。

---

## 一、推流与拉流：数据流动的两个方向

### 1.1 推流（Publish / Ingest）

推流是视频源（相机、编码器、OBS 等）主动将音视频数据发送到媒体服务器的过程。

```
相机/编码器 ──推流──► 媒体服务器
   (源端)              (中转/分发)
```

典型场景：
- OBS 推流到直播平台
- IP 摄像头推送到 NVR
- 无人机图传推流到地面站
- 编码器推流到 CDN 源站

### 1.2 拉流（Play / Subscribe / Egress）

拉流是客户端主动从媒体服务器请求并接收音视频数据的过程。

```
播放器/客户端 ──拉流──► 媒体服务器
   (观看端)               (中转/分发)
```

典型场景：
- VLC 播放 RTSP 流
- 浏览器播放 HLS 直播
- 地面站拉取无人机视频
- 监控大屏拉流解码显示

### 1.3 完整链路

```
采集 → 编码 → 推流 → 媒体服务器 → 拉流 → 解码 → 渲染

├─ 相机/传感器     ├─ 协议选择        ├─ 转封装/转码      ├─ 软/硬解码
├─ 采集 API        ├─ 硬件/软件编码    ├─ 多协议分发       ├─ 缓冲策略
└─ 色彩空间转换    └─ 码率控制         ├─ 录制存储         └─ 同步/渲染
                                       └─ 鉴权/加密
```

---

## 二、七大流媒体协议深度对比

### 2.1 总览

| 协议 | 传输层 | 延迟 | 推流/拉流 | 加密 | 浏览器 | 2026 定位 |
|------|-------|------|----------|------|--------|----------|
| **RTSP/RTP** | UDP/TCP | ~1-2s | 双向 | 无（默认） | 不支持 | IP 摄像头标准 |
| **RTMP** | TCP | 1-5s | 推流为主 | RTMPS(TLS) | 已死(Flash) | 推流事实标准（式微中） |
| **SRT** | UDP | 120ms-4s | 双向 | AES-256 | 不支持 | 专业广播贡献链路 |
| **WebRTC** | UDP(SRTP) | 200-500ms | 双向 | DTLS-SRTP | 原生支持 | 超低延迟交互 |
| **HLS** | HTTP/TCP | 6-30s | 拉流 | AES/DRM | 全平台 | 大规模分发 |
| **LL-HLS/CMAF** | HTTP/TCP | 2-5s | 拉流 | DRM | 现代浏览器 | 低延迟大规模分发 |
| **MPEG-DASH** | HTTP/TCP | 6-30s | 拉流 | DRM | 主流浏览器 | 跨平台 VOD/直播 |

### 2.2 RTSP/RTP — IP 摄像头的通用语

```
RTSP (Real Time Streaming Protocol)
├── 控制层：RTSP (TCP:554) — DESCRIBE/SETUP/PLAY/TEARDOWN
└── 数据层：RTP (UDP) — 实际音视频包
                 └── RTCP — 质量反馈
```

RTSP 是一个**控制协议**，本身不传输媒体数据。它通过 RTP 传输音视频，通过 RTCP 反馈丢包率和延迟。几乎所有 ONVIF 兼容的 IP 摄像头都输出 RTSP 流。

**拉流示例（FFmpeg）**：

```bash
# 拉取 RTSP 流并保存
ffmpeg -rtsp_transport tcp -i rtsp://admin:pass@192.168.1.100:554/stream1 \
    -c copy -f mp4 output.mp4

# 拉取并实时显示
ffplay -rtsp_transport tcp -i rtsp://192.168.1.100:554/stream1
```

**优点**：低延迟、工业标准、几乎所有摄像头支持

**缺点**：无加密、UDP 穿越防火墙困难、不支持浏览器

### 2.3 RTMP — 推流的事实标准（但正在被取代）

RTMP 基于 TCP，最初由 Macromedia 开发用于 Flash。虽然 Flash 已死，但 RTMP 作为推流协议的兼容性无人能及——OBS、vMix、Wirecast 和所有主流编码器都支持 RTMP 推流。

```
OBS ──RTMP──► 媒体服务器 ──HLS/WebRTC──► 观众
     (推流)    (转协议)                   (拉流)
```

**推流示例（FFmpeg）**：

```bash
# 推流到 RTMP 服务器
ffmpeg -re -i input.mp4 \
    -c:v libx264 -preset fast -b:v 4000k \
    -c:a aac -b:a 128k \
    -f flv rtmp://server:1935/live/stream_key
```

**优点**：编码器支持最广、CDN 支持完善、简单可靠

**缺点**：TCP 导致延迟 1-5s、不支持 H.265（FLV 容器限制，Enhanced RTMP 已解决）、无内置加密

### 2.4 SRT — 专业广播的新标准

SRT（Secure Reliable Transport）由 Haivision 开源，2017 年发布。基于 UDP，内建 ARQ 丢包重传和 AES-256 加密，专为不稳定网络设计。

```
SRT 的核心机制：
┌─────────────────────────────────────────┐
│  应用层数据                              │
│  ↓                                      │
│  AES-256 加密                           │
│  ↓                                      │
│  ARQ 选择性重传（不像 TCP 的全流重传）    │
│  ↓                                      │
│  可配置延迟缓冲（120ms ~ 4s）            │
│  ↓                                      │
│  UDP 传输                               │
└─────────────────────────────────────────┘
```

SRT 的延迟缓冲是可配置的：根据网络的 RTT 和丢包率，设置合适的缓冲窗口。缓冲越大越抗丢包，但延迟越高。

**推流示例（FFmpeg）**：

```bash
# SRT 推流（Caller 模式 → 远端 Listener）
ffmpeg -re -i input.mp4 \
    -c:v libx264 -b:v 5000k -g 60 \
    -c:a aac -b:a 128k \
    -f mpegts "srt://server:9000?mode=caller&latency=500000"

# SRT 接收（Listener 模式，等待推流端连接）
ffmpeg -i "srt://:9000?mode=listener&latency=500000" \
    -c copy output.ts
```

**两种连接模式**：

| 模式 | 说明 | 类比 |
|------|------|------|
| Listener | 监听端口，等待连接 | 服务端 |
| Caller | 主动连接远端 | 客户端 |

**优点**：UDP 低延迟、AES 加密、抗丢包、开源

**缺点**：浏览器不原生支持、需要中间服务器转协议才能给终端用户观看

### 2.5 WebRTC / WHIP / WHEP — 超低延迟的未来

WebRTC 是唯一能在浏览器中实现亚秒延迟的协议。2025 年，IETF 发布了 **WHIP**（RFC 9725）和 **WHEP** 标准，解决了 WebRTC 推拉流的信令碎片化问题：

```
WHIP (WebRTC-HTTP Ingestion Protocol) — 推流标准
  OBS/编码器 ──HTTP POST (SDP Offer)──► 媒体服务器
             ◄──HTTP 201 (SDP Answer)──
             ──DTLS/SRTP (媒体数据)───►

WHEP (WebRTC-HTTP Egress Protocol) — 拉流标准
  浏览器/播放器 ──HTTP POST (SDP Offer)──► 媒体服务器
                ◄──HTTP 201 (SDP Answer)──
                ◄──DTLS/SRTP (媒体数据)──
```

**推流示例（OBS Studio 30+）**：

1. 设置 → 流 → 服务：选择 **WHIP**
2. 服务器：`http://server:1985/rtc/v1/whip/?app=live&stream=mystream`
3. 编码设置：x264, Keyframe 1s, Profile baseline, Tune zerolatency
4. 点击开始推流

**拉流（浏览器 WHEP）**：

```
http://server:8080/players/whep.html
```

**优点**：亚秒延迟（200-500ms）、浏览器原生支持、强加密、支持 AV1/H.265

**缺点**：大规模分发需要 SFU、带宽效率不如 SRT

### 2.6 HLS — 大规模分发之王

HLS 将视频切成小片段（通常 6-10 秒），通过标准 HTTP/CDN 分发。天然支持自适应码率（ABR）。

```
编码器 → 切片器 → .m3u8 播放列表 + .ts 片段 → CDN → 播放器
```

延迟高（6-30 秒），但兼容性最好——所有浏览器、所有设备都支持。

**LL-HLS**（Low-Latency HLS）通过部分片段（Partial Segments）和预加载提示（Preload Hints）将延迟降到 2-5 秒。

### 2.7 协议选型决策树

```
你的场景是什么？
│
├── 需要亚秒级交互？（FPV、遥操作、拍卖）
│   └── WebRTC (WHIP/WHEP)
│
├── 需要在不稳定网络上可靠传输？（4G/5G、卫星）
│   └── SRT
│
├── 需要从编码器推流到服务器？
│   ├── 编码器支持 SRT → SRT（首选）
│   └── 不支持 → RTMP（兜底）
│
├── 需要大规模分发给终端用户？
│   ├── 延迟要求 < 5s → LL-HLS / CMAF
│   └── 延迟无所谓 → HLS
│
├── 接入 IP 摄像头？
│   └── RTSP/RTP
│
└── 多协议混合方案（推荐）
    └── SRT/RTMP 推流 → 媒体服务器 → WebRTC + HLS 拉流
```

---

## 三、分辨率、帧率与像素格式

### 3.1 分辨率标准

分辨率决定了画面的精细程度。以下是工程中常见的分辨率标准：

| 名称 | 分辨率 | 像素总数 | 宽高比 | 常见场景 |
|------|--------|---------|--------|---------|
| QVGA | 320×240 | 76,800 | 4:3 | 低端监控、嵌入式预览 |
| VGA | 640×480 | 307,200 | 4:3 | 传统摄像头、推理输入 |
| 720p (HD) | 1280×720 | 921,600 | 16:9 | 无人机图传、网络直播 |
| 1080p (FHD) | 1920×1080 | 2,073,600 | 16:9 | 主流直播、监控录像 |
| 2K (QHD) | 2560×1440 | 3,686,400 | 16:9 | 高清监控、电竞直播 |
| 4K (UHD) | 3840×2160 | 8,294,400 | 16:9 | 专业广播、医疗影像 |
| 8K (FUHD) | 7680×4320 | 33,177,600 | 16:9 | 超高清转播（极少） |

**未压缩数据量计算**：

$$\text{带宽} = \text{宽} \times \text{高} \times \text{每像素字节} \times \text{帧率}$$

以 1080p@30fps YUV 4:2:0 为例：

$$1920 \times 1080 \times 1.5 \times 30 = 93,312,000 \text{ Bytes/s} \approx 89 \text{ MB/s} \approx 712 \text{ Mbps}$$

这就是为什么视频**必须**编码压缩——原始数据在任何网络上都无法传输。

### 3.2 帧率

帧率（FPS, Frames Per Second）决定画面的流畅度：

| 帧率 | 体感 | 典型场景 |
|------|------|---------|
| 15fps | 略有卡顿 | 低带宽监控 |
| 24fps | 电影感 | 电影拍摄 |
| 25fps | PAL 标准 | 欧洲广播 |
| 30fps | 流畅 | 网络直播、无人机（标准） |
| 60fps | 非常流畅 | 电竞、高速运动、FPV |
| 120fps | 极致流畅 | 慢动作素材、VR |

帧率翻倍 ≈ 码率增加 40-70%（不是翻倍，因为帧间相似度高）。

### 3.3 色彩空间与像素格式

视频编码不使用 RGB，而使用 **YUV** 色彩空间：

- **Y**（亮度）：人眼对亮度最敏感
- **U/Cb**（蓝色色度）：色彩信息
- **V/Cr**（红色色度）：色彩信息

将色彩信息与亮度分离后，可以对色度进行降采样而不明显影响视觉质量：

```
YUV 4:4:4  — 每个像素都有完整的 Y、U、V
             数据量 = 宽 × 高 × 3 字节
             用途：专业调色、色彩关键场景

YUV 4:2:2  — 水平方向每 2 个像素共享一组 UV
             数据量 = 宽 × 高 × 2 字节
             用途：广播级、高端录制

YUV 4:2:0  — 每 2×2 的 4 个像素共享一组 UV
             数据量 = 宽 × 高 × 1.5 字节
             用途：绝大多数视频编码（H.264/H.265/AV1 默认）
```

```
YUV 4:2:0 的像素排列（4×4 示例）：

Y 平面（完整分辨率）:    UV 平面（1/2 分辨率）:
┌──┬──┬──┬──┐            ┌─────┬─────┐
│Y │Y │Y │Y │            │U V  │U V  │
├──┼──┼──┼──┤            ├─────┼─────┤
│Y │Y │Y │Y │            │U V  │U V  │
├──┼──┼──┼──┤            └─────┴─────┘
│Y │Y │Y │Y │
├──┼──┼──┼──┤
│Y │Y │Y │Y │
└──┴──┴──┴──┘
```

**位深**：

| 位深 | 亮度范围 | 总数据量比 | 用途 |
|------|---------|-----------|------|
| 8-bit | 256 级 | 1× | 标准视频（SDR） |
| 10-bit | 1024 级 | 1.25× | HDR、专业制作 |
| 12-bit | 4096 级 | 1.5× | 电影母版 |

FFmpeg 中的像素格式参数：

```bash
# 查看所有支持的像素格式
ffmpeg -pix_fmts

# 常用格式
# yuv420p  — 8-bit 4:2:0（最常用）
# yuv422p  — 8-bit 4:2:2
# yuv420p10le — 10-bit 4:2:0（HDR）
# nv12     — 4:2:0 半平面格式（硬件编码器常用）
# rgb24    — RGB 24-bit（非视频编码用）

# 指定像素格式
ffmpeg -i input -c:v libx264 -pix_fmt yuv420p output.mp4
```

---

## 四、视频编码原理

### 4.1 为什么能压缩

视频数据存在三类冗余：

| 冗余类型 | 含义 | 压缩方式 |
|---------|------|---------|
| **空间冗余** | 同一帧内相邻像素高度相似 | 帧内预测（Intra Prediction） |
| **时间冗余** | 相邻帧之间画面变化很小 | 帧间预测（Inter Prediction） |
| **视觉冗余** | 人眼对某些细节不敏感 | 量化（Quantization） |

编码器的核心工作就是**消除这三类冗余**。

### 4.2 帧类型：I 帧、P 帧、B 帧

| 帧类型 | 全称 | 编码方式 | 大小 | 作用 |
|--------|------|---------|------|------|
| **I 帧** | Intra Frame（关键帧） | 仅帧内预测，不参考其他帧 | 最大 | 随机访问入口点 |
| **P 帧** | Predicted Frame | 参考前面的 I 帧或 P 帧 | 中等 | 前向预测 |
| **B 帧** | Bi-directional Frame | 参考前后两个方向的帧 | 最小 | 双向预测，压缩率最高 |

```
时间轴 →
I ──► P ──► B ──► B ──► P ──► B ──► B ──► I ──► P ──► ...
│          ↑↓         │          ↑↓         │
│     前后参考        │     前后参考        │
└─── GOP (Group of Pictures) ───┘
```

**关键概念——GOP（图像组）**：

GOP 是从一个 I 帧到下一个 I 帧之前的所有帧的集合。

$$\text{GOP 大小} = \text{帧率} \times \text{关键帧间隔（秒）}$$

- **GOP = 30**（30fps, 1 秒）：适合低延迟直播、需要快速 seek
- **GOP = 60**（30fps, 2 秒）：标准直播
- **GOP = 250**（30fps, ~8 秒）：存储/点播，压缩率优先

B 帧对延迟的影响：

```
无 B 帧（-bf 0）：编码器不需要等待未来帧，延迟最低
├── 适用：低延迟直播、FPV、遥操作
└── 代价：压缩率降低 15-25%

有 B 帧（-bf 3）：编码器需要缓存 3 帧后才能编码
├── 适用：存储录像、点播、广播
└── 优势：压缩率提高 15-25%
```

### 4.3 编码流程

```
原始帧 → 色彩空间转换(RGB→YUV) → 帧间/帧内预测 → 残差计算
                                                      ↓
输出码流 ← 熵编码(CABAC/CAVLC) ← 量化(QP控制质量) ← DCT变换
```

各环节的作用：

1. **帧间/帧内预测**：用已编码的数据预测当前块，只编码"差异"（残差）
2. **DCT 变换**：将残差从空间域变换到频率域，能量集中到少数系数
3. **量化**：丢弃高频细节（人眼不敏感），QP 值越大丢弃越多→质量越低
4. **熵编码**：无损压缩最终的系数（CABAC 比 CAVLC 压缩率高 ~10%，但更慢）

### 4.4 编码格式深度对比

| 特性 | H.264/AVC | H.265/HEVC | AV1 |
|------|-----------|------------|-----|
| 标准发布年份 | 2003 | 2013 | 2018 |
| 压缩效率（vs H.264） | 1× | 1.5-2× | 1.5-2× |
| 最大编码块 | 16×16 (Macroblock) | 64×64 (CTU) | 128×128 (Superblock) |
| 帧内预测模式 | 9 种 | 35 种 | 57+ 种 |
| 运动补偿精度 | 1/4 像素 | 1/4 像素 | 1/8 像素 |
| 环路滤波 | 去块滤波 | 去块 + SAO | 去块 + CDEF + LR |
| 熵编码 | CABAC / CAVLC | CABAC | 多符号 ANS |
| 专利/版权费 | 需要（通过 MPEG-LA） | 需要（多个专利池） | 免版税 |
| 硬件编码支持 | 极广 | 广泛 | NVIDIA RTX 40+, Intel 12+, Apple M3+ |
| 硬件解码支持 | 极广 | 广泛 | 2022 年后的主流设备 |
| 软件编码速度 | 快（x264） | 慢（x265, 约 x264 的 1/3-1/5） | 极慢（SVT-AV1, 约 x264 的 1/10） |
| 编码复杂度 | 低 | 中 | 高 |

**选型建议**：

```
需要最大兼容性？（任何设备都能播）
└── H.264

需要节省带宽/存储，且设备支持？（4K/HDR）
└── H.265

面向 Web 分发，免版税？
└── AV1（编码慢，适合非实时/有硬编场景）
```

### 4.5 Profile 与 Level

Profile 定义编码器可以使用的功能集，Level 限制计算复杂度和分辨率上限。

**H.264 Profile**：

| Profile | 特性 | 用途 |
|---------|------|------|
| **Baseline** | 无 B 帧、无 CABAC、仅 I/P 帧 | 视频通话、低延迟、移动设备 |
| **Main** | B 帧、CABAC、加权预测 | 标准广播、中端设备 |
| **High** | 8×8 变换、自适应量化矩阵 | 高清广播、蓝光、存储 |
| **High 10** | 10-bit 色深 | HDR 内容 |

**H.264 Level（常用）**：

| Level | 最大分辨率@帧率 | 最大码率 |
|-------|---------------|---------|
| 3.0 | 720×480@30 | 10 Mbps |
| 3.1 | 1280×720@30 | 14 Mbps |
| 4.0 | 2048×1024@30 | 20 Mbps |
| 4.1 | 2048×1024@30 | 50 Mbps |
| 4.2 | 2048×1080@60 | 50 Mbps |
| 5.1 | 4096×2160@30 | 300 Mbps |

```bash
# FFmpeg 指定 Profile 和 Level
ffmpeg -i input -c:v libx264 \
    -profile:v high -level:v 4.2 \
    output.mp4

# 低延迟直播用 Baseline
ffmpeg -i input -c:v libx264 \
    -profile:v baseline -level:v 3.1 \
    -tune zerolatency \
    output.mp4
```

### 4.6 码率控制模式

码率控制决定编码器如何分配每一帧的比特预算：

| 模式 | 全称 | 控制方式 | 特点 | 适用场景 |
|------|------|---------|------|---------|
| **CBR** | Constant Bitrate | 固定码率 | 输出码率恒定，质量波动 | 直播推流（网络带宽固定） |
| **VBR** | Variable Bitrate | 可变码率 | 复杂场景码率高，简单场景低 | 录制存储（节省空间） |
| **CRF** | Constant Rate Factor | 恒定质量 | 质量恒定，码率波动 | 本地录制（质量优先） |
| **CQP** | Constant Quantization | 固定 QP 值 | 最简单，不控制码率 | 基准测试 |
| **ABR** | Average Bitrate | 平均码率 | VBR 的一种，保证长期平均码率 | 点播视频 |

```bash
# CBR —— 直播推流（码率稳定）
ffmpeg -i input -c:v libx264 \
    -b:v 4000k -minrate 4000k -maxrate 4000k -bufsize 4000k \
    output.mp4

# VBR —— 录制存储（画质优先）
ffmpeg -i input -c:v libx264 \
    -b:v 4000k -maxrate 6000k -bufsize 8000k \
    output.mp4

# CRF —— 本地转码（恒定质量，推荐 18-28）
ffmpeg -i input -c:v libx264 \
    -crf 23 \
    output.mp4
# CRF 值含义：0=无损, 18=视觉无损, 23=默认, 28=能看, 51=最差

# NVENC 的码率控制
ffmpeg -i input -c:v h264_nvenc \
    -rc cbr -b:v 4000k \     # CBR
    output.mp4

ffmpeg -i input -c:v h264_nvenc \
    -rc vbr -cq 23 \         # VBR + 恒定质量
    -b:v 4000k -maxrate 6000k \
    output.mp4
```

**码率控制选型**：

```
直播推流？
├── 是 → CBR（码率稳定，不会超过网络带宽）
└── 否 → 是否关心文件大小？
    ├── 不关心 → CRF（质量最佳）
    └── 关心 → VBR / ABR（质量和体积平衡）
```

### 4.7 码率参考表

| 分辨率 | 帧率 | H.264 推荐码率 | H.265 推荐码率 | 说明 |
|--------|------|---------------|---------------|------|
| 480p | 30fps | 1-2 Mbps | 0.7-1.5 Mbps | 低带宽监控 |
| 720p | 30fps | 2.5-4 Mbps | 1.5-2.5 Mbps | 无人机标准图传 |
| 720p | 60fps | 3.5-6 Mbps | 2-4 Mbps | 运动场景 |
| 1080p | 30fps | 4-6 Mbps | 2.5-4 Mbps | 主流直播 |
| 1080p | 60fps | 6-9 Mbps | 4-6 Mbps | 电竞/高速运动 |
| 2K | 30fps | 8-12 Mbps | 5-8 Mbps | 高清监控 |
| 4K | 30fps | 13-20 Mbps | 8-13 Mbps | 专业广播 |
| 4K | 60fps | 20-30 Mbps | 13-20 Mbps | 顶级广播 |

码率与分辨率的关系并非线性：4K 的像素数是 1080p 的 4 倍，但码率只需要 3-4 倍，因为更大的编码块能发现更多冗余。

### 4.8 关键编码参数详解

```bash
# H.264 编码完整参数说明
ffmpeg -i input -c:v libx264 \
    -preset fast \          # 编码速度 vs 质量权衡
                            # ultrafast > superfast > veryfast > faster > fast
                            # > medium(默认) > slow > slower > veryslow
                            # ultrafast 比 veryslow 快 10 倍，但码率高 50%+
    -tune zerolatency \     # 调优模式：
                            #   zerolatency — 禁用 B 帧和前瞻，低延迟
                            #   film — 电影类内容
                            #   animation — 动画
                            #   grain — 保留噪点
                            #   stillimage — 静态画面
    -profile:v high \       # baseline/main/high（见上文）
    -level:v 4.2 \          # 限制分辨率和码率上限
    -pix_fmt yuv420p \      # 像素格式（几乎总是 yuv420p）
    -b:v 4000k \            # 目标码率
    -maxrate 4500k \        # 最大码率
    -bufsize 8000k \        # VBV 缓冲（影响码率波动幅度）
    -g 60 \                 # GOP 大小（关键帧间隔帧数）
    -keyint_min 60 \        # 最小关键帧间隔
    -bf 0 \                 # B 帧数量（0=低延迟，3=高压缩）
    -refs 3 \               # 参考帧数量（1-16，越多越好但更慢）
    -rc-lookahead 0 \       # 前瞻帧数（0=低延迟，40=高质量）
    output.mp4
```

---

## 五、容器格式

容器格式（Container Format）不是编码格式——容器是**封装**，编码是**压缩**。同样的 H.264 视频可以装在 MP4、MKV、FLV 等不同容器中。

| 容器 | 扩展名 | 支持的视频编码 | 支持的音频编码 | 流媒体 | 典型用途 |
|------|--------|-------------|-------------|--------|---------|
| **MP4** | .mp4 | H.264, H.265, AV1 | AAC, MP3, Opus | 支持（fMP4） | 通用存储和分发 |
| **MKV** | .mkv | 几乎所有 | 几乎所有 | 有限 | 本地存储（灵活） |
| **FLV** | .flv | H.264（传统）, H.265（Enhanced RTMP） | AAC, MP3 | RTMP | 直播推流 |
| **TS** | .ts | H.264, H.265 | AAC, MP3, AC3 | HLS/广播 | 广播、HLS 切片 |
| **fMP4** | .m4s | H.264, H.265, AV1 | AAC, Opus | CMAF/DASH | 低延迟 HLS/DASH |
| **WebM** | .webm | VP8, VP9, AV1 | Vorbis, Opus | 支持 | Web 视频 |

```bash
# 容器转换（不重新编码，仅重新封装）
ffmpeg -i input.mp4 -c copy output.mkv
ffmpeg -i input.mp4 -c copy -f mpegts output.ts

# 查看容器和编码信息
ffprobe -v quiet -show_format -show_streams input.mp4
```

---

## 六、音频编码

视频流通常包含音频轨道，了解常用音频编码同样重要：

| 编码 | 码率范围 | 延迟 | 质量 | 适用场景 |
|------|---------|------|------|---------|
| **AAC** | 64-320 kbps | 中等 | 好 | 通用（MP4/FLV/HLS） |
| **Opus** | 6-510 kbps | 极低 | 极好 | WebRTC、低延迟通信 |
| **MP3** | 128-320 kbps | 中等 | 一般 | 兼容性 |
| **PCM** | ~1.4 Mbps | 无 | 无损 | 录音、编辑 |

```bash
# AAC 编码（最通用）
ffmpeg -i input -c:a aac -b:a 128k output.mp4

# Opus 编码（WebRTC 推荐）
ffmpeg -i input -c:a libopus -b:a 128k output.webm

# 查看音频流信息
ffprobe -v quiet -select_streams a -show_entries \
    stream=codec_name,sample_rate,channels,bit_rate input.mp4
```

---

## 七、硬件编码加速

### 7.1 为什么需要硬件编码

软件编码（x264）质量好但 CPU 占用极高。1080p@30fps 的 x264 medium 可以吃满 4 核 CPU。在嵌入式设备（Jetson、树莓派）上，软编根本不可行。

| 方案 | 平台 | 速度(vs x264) | CPU 占用 | 质量 |
|------|------|-------------|---------|------|
| x264 (medium) | 通用 CPU | 1× | ~400% | 优秀 |
| **NVENC** | NVIDIA GPU | 4-6× | ~50% | 很好 |
| **VAAPI** | Intel/AMD GPU | 3-4× | ~45% | 好 |
| **QSV** | Intel CPU/GPU | 3-5× | ~40% | 好 |
| **VideoToolbox** | macOS/Apple Silicon | 3-5× | ~30% | 好 |
| **nvv4l2h264enc** | Jetson | 3-4× | ~5% | 好 |

### 7.2 NVIDIA NVENC

```bash
# 检查 NVENC 支持
ffmpeg -encoders | grep nvenc
# → h264_nvenc, hevc_nvenc, av1_nvenc

# NVENC 低延迟推流
ffmpeg -hwaccel cuda -hwaccel_output_format cuda \
    -i input.mp4 \
    -c:v h264_nvenc \
    -preset p4 \              # p1(最快) ~ p7(最慢最好)
    -tune ll \                # ll=低延迟, hq=高质量
    -b:v 4000k \
    -maxrate 4500k \
    -bufsize 4000k \
    -g 60 \
    -bf 0 \
    -c:a aac -b:a 128k \
    -f flv rtmp://server:1935/live/stream

# NVENC H.265 SRT 推流
ffmpeg -hwaccel cuda -i input.mp4 \
    -c:v hevc_nvenc -preset p4 -b:v 3000k -g 60 \
    -c:a aac -b:a 128k \
    -f mpegts "srt://server:9000?mode=caller&latency=500000"
```

### 7.3 Intel VAAPI / QSV

```bash
# 检查 VAAPI 设备
ls /dev/dri/renderD*

# VAAPI 编码推流
ffmpeg -vaapi_device /dev/dri/renderD128 -i input.mp4 \
    -vf 'format=nv12,hwupload' \
    -c:v h264_vaapi -b:v 4000k \
    -c:a aac -b:a 128k \
    -f flv rtmp://server:1935/live/stream

# QSV 编码推流
ffmpeg -hwaccel qsv -i input.mp4 \
    -c:v h264_qsv -preset faster -b:v 4000k \
    -c:a aac -b:a 128k \
    -f flv rtmp://server:1935/live/stream
```

### 7.4 NVIDIA Jetson（nvv4l2h264enc）

Jetson 平台使用专用的 V4L2 编码器，CPU 占用仅 5%：

```bash
# GStreamer CSI 摄像头 → H.264 → RTP/UDP 推流
gst-launch-1.0 -e \
    nvarguscamerasrc ! \
    'video/x-raw(memory:NVMM), width=1920, height=1080, framerate=30/1' ! \
    nvv4l2h264enc \
        bitrate=4000000 \
        control-rate=1 \
        insert-sps-pps=true \
        maxperf-enable=1 \
        iframeinterval=30 ! \
    h264parse ! \
    rtph264pay config-interval=1 ! \
    udpsink host=192.168.1.10 port=5000 sync=false

# 接收端
gst-launch-1.0 \
    udpsrc port=5000 \
        caps="application/x-rtp, encoding-name=H264, payload=96" ! \
    rtph264depay ! h264parse ! avdec_h264 ! autovideosink
```

---

## 八、FFmpeg 推拉流实战

### 8.1 拉流：RTSP → 本地文件

```bash
# 从 IP 摄像头拉流并录制
ffmpeg -rtsp_transport tcp \
    -i rtsp://admin:pass@192.168.1.100/stream1 \
    -c copy \
    -f segment -segment_time 300 -strftime 1 \
    "recording_%Y%m%d_%H%M%S.mp4"
```

### 8.2 推流：本地文件 → RTMP

```bash
# 循环推流视频文件到 RTMP
ffmpeg -re -stream_loop -1 -i input.mp4 \
    -c:v libx264 -preset fast -tune zerolatency \
    -b:v 4000k -g 60 -bf 0 \
    -c:a aac -b:a 128k \
    -f flv rtmp://localhost:1935/live/test
```

### 8.3 转推：RTSP → RTMP

```bash
# IP 摄像头 RTSP 转推到直播平台
ffmpeg -rtsp_transport tcp \
    -i rtsp://admin:pass@192.168.1.100/stream1 \
    -c:v copy -c:a aac \
    -f flv rtmp://live-push.example.com/live/stream_key
```

### 8.4 转推：RTMP → SRT

```bash
# 协议转换：RTMP 推流转发到 SRT
ffmpeg -i rtmp://localhost:1935/live/stream \
    -c copy -f mpegts \
    "srt://remote:9000?mode=caller&latency=500000&passphrase=MySecret&pbkeylen=32"
```

### 8.5 SRT → HLS 切片

```bash
# SRT 接收并切成 HLS
ffmpeg -i "srt://:9000?mode=listener&latency=500000" \
    -c copy \
    -f hls \
    -hls_time 4 \
    -hls_list_size 5 \
    -hls_flags delete_segments \
    /var/www/html/live/stream.m3u8
```

### 8.6 摄像头采集推流

```bash
# Linux V4L2 摄像头 → NVENC → RTMP
ffmpeg -f v4l2 -input_format mjpeg \
    -video_size 1920x1080 -framerate 30 \
    -i /dev/video0 \
    -c:v h264_nvenc -preset p4 -tune ll \
    -b:v 4000k -g 60 -bf 0 \
    -f flv rtmp://localhost:1935/live/camera

# macOS 摄像头 → VideoToolbox → RTMP
ffmpeg -f avfoundation -framerate 30 \
    -video_size 1920x1080 -i "0" \
    -c:v h264_videotoolbox -b:v 4000k \
    -f flv rtmp://localhost:1935/live/camera
```

### 8.7 多路输出（tee muxer）

```bash
# 同时推流到 RTMP + 保存本地 + SRT
ffmpeg -re -i input.mp4 \
    -c:v h264_nvenc -preset p4 -b:v 4000k -g 60 \
    -c:a aac -b:a 128k \
    -f tee \
    "[f=flv]rtmp://server:1935/live/stream|\
     [f=mp4]local_backup.mp4|\
     [f=mpegts]srt://remote:9000?mode=caller"
```

---

## 九、GStreamer 推拉流实战

### 9.1 基本管线结构

GStreamer 用管道（pipeline）将一系列元素（element）串联：

```
source → demux → decode → process → encode → mux → sink
```

每个元素通过 pad 连接，数据以 buffer 形式在管线中流动。

### 9.2 摄像头 → RTSP 推流

```bash
# USB 摄像头 → x264 → RTSP（使用 test-launch）
# 需要安装 gst-rtsp-server
gst-launch-1.0 v4l2src device=/dev/video0 ! \
    video/x-raw, width=1920, height=1080, framerate=30/1 ! \
    videoconvert ! x264enc tune=zerolatency bitrate=4000 ! \
    rtph264pay config-interval=1 name=pay0 pt=96 ! \
    udpsink host=192.168.1.10 port=5000
```

### 9.3 Jetson 低延迟管线

```bash
# CSI 摄像头 → NVENC H.265 → UDP（Jetson 专用）
gst-launch-1.0 -e \
    nvarguscamerasrc ! \
    'video/x-raw(memory:NVMM), width=1920, height=1080, framerate=30/1' ! \
    nvvidconv ! 'video/x-raw(memory:NVMM), format=NV12' ! \
    nvv4l2h265enc \
        bitrate=8000000 \
        insert-sps-pps=true \
        maxperf-enable=1 ! \
    h265parse ! \
    rtph265pay config-interval=1 ! \
    udpsink host=192.168.1.10 port=5000 sync=false async=false
```

### 9.4 接收端管线

```bash
# PC 端接收 H.264 RTP 流并显示
gst-launch-1.0 \
    udpsrc port=5000 \
        caps="application/x-rtp, media=video, encoding-name=H264, payload=96" ! \
    rtph264depay ! h264parse ! avdec_h264 ! \
    videoconvert ! autovideosink sync=false

# PC 端接收 H.265 RTP 流并显示
gst-launch-1.0 \
    udpsrc port=5000 \
        caps="application/x-rtp, media=video, encoding-name=H265, payload=96" ! \
    rtph265depay ! h265parse ! avdec_h265 ! \
    videoconvert ! autovideosink sync=false
```

### 9.5 GStreamer RTSP Server（Python）

```python
import gi
gi.require_version('Gst', '1.0')
gi.require_version('GstRtspServer', '1.0')
from gi.repository import Gst, GstRtspServer, GLib

Gst.init(None)

class RTSPServer:
    def __init__(self):
        self.server = GstRtspServer.RTSPServer()
        self.server.set_service("8554")

        factory = GstRtspServer.RTSPMediaFactory()
        factory.set_launch(
            '( v4l2src device=/dev/video0 ! '
            'video/x-raw, width=1920, height=1080, framerate=30/1 ! '
            'videoconvert ! x264enc tune=zerolatency bitrate=4000 speed-preset=fast ! '
            'rtph264pay name=pay0 pt=96 )'
        )
        factory.set_shared(True)

        self.server.get_mount_points().add_factory("/stream", factory)
        self.server.attach(None)
        print("RTSP server ready at rtsp://localhost:8554/stream")

if __name__ == '__main__':
    server = RTSPServer()
    GLib.MainLoop().run()
```

### 9.6 GStreamer + OpenCV 联合使用

```python
import cv2

# GStreamer 管线作为 VideoCapture 的 backend
cap = cv2.VideoCapture(
    'udpsrc port=5000 caps="application/x-rtp, encoding-name=H264, payload=96" ! '
    'rtph264depay ! h264parse ! avdec_h264 ! videoconvert ! '
    'video/x-raw, format=BGR ! appsink drop=true sync=false',
    cv2.CAP_GSTREAMER
)

# GStreamer 管线作为 VideoWriter 的 backend（硬件编码推流）
writer = cv2.VideoWriter(
    'appsrc ! videoconvert ! '
    'x264enc tune=zerolatency bitrate=4000 speed-preset=fast ! '
    'rtph264pay config-interval=1 ! '
    'udpsink host=192.168.1.10 port=5000',
    cv2.CAP_GSTREAMER, 0, 30.0, (1920, 1080)
)

while cap.isOpened():
    ret, frame = cap.read()
    if not ret:
        break
    # OpenCV 处理
    processed = cv2.Canny(frame, 50, 150)
    processed_bgr = cv2.cvtColor(processed, cv2.COLOR_GRAY2BGR)
    writer.write(processed_bgr)
    cv2.imshow('Processed', processed)
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break
```

---

## 十、MediaMTX：一站式媒体服务器

### 10.1 简介

[MediaMTX](https://github.com/bluenviron/mediamtx)（前身 rtsp-simple-server）是一个零依赖、单文件的媒体服务器，支持所有主流协议之间的自动转换。

```
任意推流协议 → MediaMTX → 任意拉流协议

支持：SRT / WebRTC(WHIP) / RTSP / RTMP / HLS / RTP / MPEG-TS
→ 自动转换为 →
SRT / WebRTC(WHEP) / RTSP / RTMP / HLS
```

### 10.2 部署

```bash
# Docker（推荐）
docker run --rm -it --network=host bluenviron/mediamtx:1

# 或手动下载
wget https://github.com/bluenviron/mediamtx/releases/download/v1.17.1/mediamtx_v1.17.1_linux_amd64.tar.gz
tar xzf mediamtx_v1.17.1_linux_amd64.tar.gz
./mediamtx
```

默认端口：
- RTSP: 8554
- RTMP: 1935
- HLS: 8888
- WebRTC(WHEP): 8889
- SRT: 8890
- API: 9997

### 10.3 推流

```bash
# FFmpeg RTSP 推流
ffmpeg -re -stream_loop -1 -i input.mp4 \
    -c copy -f rtsp rtsp://localhost:8554/mystream

# FFmpeg RTMP 推流
ffmpeg -re -stream_loop -1 -i input.mp4 \
    -c copy -f flv rtmp://localhost:1935/mystream

# FFmpeg SRT 推流
ffmpeg -re -stream_loop -1 -i input.mp4 \
    -c copy -f mpegts "srt://localhost:8890?streamid=publish:mystream"

# GStreamer RTSP 推流
gst-launch-1.0 rtspclientsink name=s location=rtsp://localhost:8554/mystream \
    filesrc location=file.mp4 ! qtdemux name=d \
    d.video_0 ! queue ! s.sink_0 \
    d.audio_0 ! queue ! s.sink_1

# OBS Studio WHIP 推流
# 服务器：http://localhost:8889/mystream/whip
# 即可通过所有协议拉流
```

### 10.4 拉流

```bash
# VLC RTSP 拉流
vlc --network-caching=50 rtsp://localhost:8554/mystream

# FFmpeg RTSP 拉流录制
ffmpeg -i rtsp://localhost:8554/mystream -c copy output.mp4

# FFmpeg SRT 拉流
ffmpeg -i "srt://localhost:8890?streamid=read:mystream" -c copy output.ts

# 浏览器 HLS 拉流
# 打开 http://localhost:8888/mystream/

# 浏览器 WebRTC 拉流
# 打开 http://localhost:8889/mystream/
```

### 10.5 核心配置

```yaml
# mediamtx.yml

# API（用于监控和管理）
api: yes
apiAddress: :9997

# RTSP 配置
rtspAddress: :8554
protocols: [tcp, udp]

# RTMP 配置
rtmpAddress: :1935

# HLS 配置
hlsAddress: :8888
hlsAlwaysRemux: yes
hlsSegmentCount: 3
hlsSegmentDuration: 1s

# WebRTC 配置
webrtcAddress: :8889

# SRT 配置
srtAddress: :8890

# 路径配置
paths:
  # 代理 IP 摄像头
  cam1:
    source: rtsp://admin:pass@192.168.1.100/stream1
    sourceOnDemand: yes  # 有人观看时才连接

  # 允许推流的路径
  live:
    # 无额外配置 = 允许任何协议推流

  # 需要认证的路径
  secure:
    publishUser: admin
    publishPass: secret123
    readUser: viewer
    readPass: view123

  # 录制到磁盘
  recorded:
    record: yes
    recordPath: ./recordings/%path/%Y-%m-%d_%H-%M-%S-%f
    recordFormat: fmp4
```

### 10.6 协议自动转换矩阵

| 推流方式 | RTSP 拉 | RTMP 拉 | HLS 拉 | WebRTC 拉 | SRT 拉 |
|---------|---------|---------|--------|----------|--------|
| RTSP 推 | ✅ | ✅ | ✅ | ✅ | ✅ |
| RTMP 推 | ✅ | ✅ | ✅ | ✅ | ✅ |
| SRT 推 | ✅ | ✅ | ✅ | ✅ | ✅ |
| WHIP 推 | ✅ | ✅ | ✅ | ✅ | ✅ |
| RTP 推 | ✅ | ✅ | ✅ | ✅ | ✅ |

推一路流，MediaMTX 自动为所有协议生成对应的拉流端点。

---

## 十一、无人机 / 机器人低延迟视频方案

### 11.1 延迟预算分析

对于无人机 FPV 或机器人遥操作，端到端延迟（Glass-to-Glass）通常要求 < 200ms：

| 环节 | 典型延迟 | 优化后 |
|------|---------|--------|
| 相机采集 + ISP | 10-33ms | 10ms（降低曝光） |
| 编码 | 5-30ms | 3-5ms（NVENC/nvv4l2） |
| 网络传输 | 1-50ms | 1-10ms（局域网/5G） |
| 协议开销（缓冲） | 0-2000ms | 0ms（裸 RTP/WebRTC） |
| 解码 | 5-30ms | 3-5ms（硬解） |
| 渲染 | 1-16ms | 1ms |
| **总计** | **22-2159ms** | **18-31ms** |

### 11.2 推荐方案

**方案 A：裸 RTP/UDP（最低延迟，局域网）**

```
Jetson:
gst-launch-1.0 nvarguscamerasrc ! \
    'video/x-raw(memory:NVMM), width=1280, height=720, framerate=60/1' ! \
    nvv4l2h264enc bitrate=4000000 control-rate=1 \
        insert-sps-pps=true iframeinterval=15 maxperf-enable=1 ! \
    h264parse ! rtph264pay config-interval=-1 ! \
    udpsink host=192.168.1.10 port=5000 sync=false async=false

PC 接收:
gst-launch-1.0 udpsrc port=5000 \
    caps="application/x-rtp, encoding-name=H264, payload=96" ! \
    rtph264depay ! h264parse ! nvh264dec ! nv3dsink sync=false
```

端到端延迟：**~20ms**（局域网）

**方案 B：SRT（抗丢包，公网/4G/5G）**

```bash
# 发送端（Listener）
ffmpeg -f v4l2 -input_format mjpeg -video_size 1280x720 -framerate 30 \
    -i /dev/video0 \
    -c:v h264_nvenc -preset p2 -tune ll -b:v 3000k -g 30 -bf 0 \
    -f mpegts "srt://:9000?mode=listener&latency=200000"

# 接收端（Caller）
ffplay -fflags nobuffer -flags low_delay -framedrop \
    "srt://drone-ip:9000?mode=caller&latency=200000"
```

端到端延迟：**~200-400ms**（4G 网络）

**方案 C：WebRTC WHIP/WHEP（浏览器观看）**

```bash
# MediaMTX 作为中转
docker run --rm -it --network=host bluenviron/mediamtx:1

# 无人机端推流（RTSP 或 SRT 推到 MediaMTX）
ffmpeg -f v4l2 -video_size 1280x720 -framerate 30 -i /dev/video0 \
    -c:v libx264 -preset ultrafast -tune zerolatency -b:v 2000k -g 30 \
    -f rtsp rtsp://server:8554/drone1

# 浏览器打开 WebRTC 播放页面
# http://server:8889/drone1/
```

端到端延迟：**~300-800ms**（含浏览器渲染）

### 11.3 方案对比

| | 裸 RTP/UDP | SRT | WebRTC |
|---|-----------|-----|--------|
| 延迟 | ~20ms | ~200-400ms | ~300-800ms |
| 抗丢包 | 无 | ARQ 重传 | NACK 重传 |
| 加密 | 无 | AES-256 | DTLS-SRTP |
| 浏览器 | 不支持 | 不支持 | 原生支持 |
| 适用网络 | 可靠局域网 | 公网/4G/5G | 任意 |
| 复杂度 | 低 | 中 | 高 |

---

## 十二、性能优化最佳实践

### 12.1 降低编码延迟

```bash
# x264 低延迟配置
-preset ultrafast -tune zerolatency -profile baseline -bf 0 -g 30

# NVENC 低延迟配置
-preset p1 -tune ll -bf 0 -g 30 -rc cbr -delay 0

# GStreamer nvv4l2h264enc 低延迟
nvv4l2h264enc maxperf-enable=1 control-rate=1 \
    insert-sps-pps=true iframeinterval=15 EnableTwopassCBR=false
```

### 12.2 降低拉流延迟

```bash
# FFplay 低延迟播放
ffplay -fflags nobuffer -flags low_delay -framedrop \
    -analyzeduration 0 -probesize 32 \
    -sync ext \
    rtsp://server:8554/stream

# VLC 低延迟配置
vlc --network-caching=50 --clock-jitter=0 \
    --sout-mux-caching=0 \
    rtsp://server:8554/stream

# GStreamer 低延迟接收
gst-launch-1.0 udpsrc port=5000 \
    caps="application/x-rtp, encoding-name=H264" ! \
    rtph264depay ! h264parse ! avdec_h264 ! \
    autovideosink sync=false
```

### 12.3 网络优化

```bash
# 增大 UDP 缓冲区（Linux）
sudo sysctl -w net.core.rmem_max=26214400
sudo sysctl -w net.core.wmem_max=26214400
sudo sysctl -w net.core.rmem_default=26214400

# 在 FFmpeg 中设置 UDP 缓冲区
ffmpeg -i input -f mpegts "udp://192.168.1.10:5000?buffer_size=2621440"

# SRT 延迟缓冲调优
# latency = max(RTT × 4, 120ms)
# 局域网 RTT ~1ms → latency=120000 (120ms)
# 4G RTT ~50ms → latency=200000 (200ms)
# 公网 RTT ~100ms → latency=400000 (400ms)
```

### 12.4 诊断工具

```bash
# 检查可用硬件编码器
ffmpeg -encoders 2>/dev/null | grep -E "nvenc|vaapi|qsv|videotoolbox"

# 测量流媒体带宽
ffprobe -v quiet -print_format json -show_streams rtsp://server/stream

# GStreamer 管线延迟测量
GST_DEBUG=3 gst-launch-1.0 ... 2>&1 | grep latency

# SRT 连接统计
# srt-live-transmit 内置统计输出

# 测量端到端延迟（在画面中嵌入时间戳）
ffmpeg -f v4l2 -i /dev/video0 \
    -vf "drawtext=text='%{localtime}':fontsize=48:fontcolor=white:x=10:y=10" \
    -c:v libx264 -f flv rtmp://server/live/test
```

---

## 十三、NAT 穿越与 WebRTC 网络部署

### 13.1 问题：为什么 WebRTC 在公网连不通

WebRTC 使用 UDP 传输媒体数据，但大多数设备都在 NAT（网络地址转换）后面。NAT 会修改出站数据包的源端口和 IP，导致外部设备无法直接向内部设备发送数据。

```
设备 A（192.168.1.100:5000）                设备 B（10.0.0.50:6000）
       │                                           │
   NAT 路由器 A                                NAT 路由器 B
  （公网 1.2.3.4:xxxxx）                    （公网 5.6.7.8:yyyyy）
       │                                           │
       └──────────── 互联网 ────────────────────────┘
                  A 不知道 B 的公网地址
                  B 不知道 A 的公网地址
                  双方都无法直接发 UDP 包给对方
```

### 13.2 ICE 框架：STUN + TURN

WebRTC 使用 **ICE**（Interactive Connectivity Establishment）框架解决 NAT 穿越：

```
ICE 候选地址收集流程：

1. Host Candidate     — 本机直接 IP（192.168.1.100:5000）
                        仅局域网内有效

2. Server Reflexive   — 通过 STUN 服务器获取公网 IP + 端口
   Candidate            STUN 服务器告诉你："外面看到你是 1.2.3.4:12345"
                        大约 80% 的 NAT 场景可以直连

3. Relay Candidate    — 通过 TURN 服务器中转所有数据
                        当 STUN 打洞失败时使用（对称 NAT）
                        100% 可通，但增加延迟和服务器成本
```

**STUN** (Session Traversal Utilities for NAT)：

```
设备 ──UDP──► STUN 服务器（公网）
      ◄──── "你的公网地址是 1.2.3.4:12345"

设备收集到的 Server Reflexive 候选地址 = 1.2.3.4:12345
对端可以向这个地址发 UDP 包实现直连
```

STUN 请求很轻量（几十字节），公共 STUN 服务器免费可用：

```
stun:stun.l.google.com:19302
stun:stun1.l.google.com:19302
stun:stun.cloudflare.com:3478
```

**TURN** (Traversal Using Relays around NAT)：

```
设备 A ──UDP──► TURN 服务器 ──UDP──► 设备 B
           所有媒体数据经过 TURN 中转
           增加延迟 10-50ms，消耗服务器带宽
```

TURN 是最后的保底方案，需要自己部署服务器。推荐开源方案：**coturn**。

### 13.3 部署 coturn（TURN 服务器）

```bash
# 安装
sudo apt install coturn

# 配置 /etc/turnserver.conf
listening-port=3478
tls-listening-port=5349
external-ip=YOUR_PUBLIC_IP
realm=your-domain.com
server-name=your-domain.com
lt-cred-mech
user=webrtc:password123
total-quota=100
stale-nonce=600
no-multicast-peers

# 启动
sudo systemctl enable coturn
sudo systemctl start coturn
```

### 13.4 MediaMTX 配置 ICE 服务器

```yaml
# mediamtx.yml
webrtcAddress: :8889
webrtcAdditionalHosts:
  - YOUR_PUBLIC_IP
webrtcICEServers2:
  - url: stun:stun.l.google.com:19302
  - url: turn:your-domain.com:3478
    username: webrtc
    password: password123
```

### 13.5 NAT 类型与穿越成功率

| NAT 类型 | 穿越难度 | STUN 直连 | TURN 中转 |
|---------|---------|----------|----------|
| Full Cone（完全锥形） | 低 | ✅ | 不需要 |
| Restricted Cone（限制锥形） | 低 | ✅ | 不需要 |
| Port Restricted Cone（端口限制锥形） | 中 | ✅ | 不需要 |
| Symmetric（对称型） | 高 | ❌ | ✅ 必须 |

家用路由器多数是 Port Restricted Cone，STUN 即可。企业防火墙和 4G/5G 运营商 NAT 多数是 Symmetric，必须依赖 TURN。

---

## 十四、PTS/DTS 时间戳与音视频同步

### 14.1 两种时间戳

每一帧编码后都携带两个时间戳：

| 时间戳 | 全称 | 含义 | 单位 |
|--------|------|------|------|
| **PTS** | Presentation Time Stamp | 这一帧应该在什么时刻**显示** | 通常 1/90000 秒 |
| **DTS** | Decoding Time Stamp | 这一帧应该在什么时刻**解码** | 同上 |

**无 B 帧时**（低延迟模式），解码顺序 = 显示顺序，DTS = PTS：

```
编码/传输顺序:  I₀  P₁  P₂  P₃  P₄  P₅
显示顺序:       I₀  P₁  P₂  P₃  P₄  P₅
DTS:            0   1   2   3   4   5
PTS:            0   1   2   3   4   5
```

**有 B 帧时**，解码顺序 ≠ 显示顺序，DTS ≠ PTS：

```
显示顺序:       I₀  B₁  B₂  P₃  B₄  B₅  P₆
编码/传输顺序:  I₀  P₃  B₁  B₂  P₆  B₄  B₅
                     ↑ P₃ 必须先解码，B₁/B₂ 才能参考它

DTS:            0   1   2   3   4   5   6
PTS:            0   3   1   2   6   4   5
```

B 帧是"先解码后面的 P 帧，再解码 B 帧"——这就是为什么 B 帧增加编码延迟。

### 14.2 音视频同步

音频和视频是独立编码的两条流，靠 PTS 对齐实现同步播放：

```
视频: I(PTS=0)  P(PTS=33ms)  P(PTS=66ms)  P(PTS=100ms) ...
音频: A(PTS=0)  A(PTS=21ms)  A(PTS=42ms)  A(PTS=64ms)  ...
                              ↑
                    播放器在 66ms 时刻同时呈现：
                    视频帧 PTS≤66ms 的最新帧 + 音频帧 PTS≤66ms 的最新样本
```

**常见音画不同步原因**：

| 原因 | 表现 | 解决方法 |
|------|------|---------|
| 推流端时钟不一致 | 音频逐渐领先/落后 | 使用同一时钟源采集音视频 |
| 编码延迟不对称 | 视频延迟大于音频 | 减少 B 帧或用硬编码 |
| 网络抖动 | 间歇性不同步 | 增加 jitter buffer |
| 播放器缓冲策略 | 启动时不同步 | 配置缓冲大小和同步模式 |

```bash
# FFmpeg 查看 PTS/DTS
ffprobe -show_frames -select_streams v:0 \
    -print_format csv input.mp4 | head -20

# FFmpeg 修复时间戳问题
ffmpeg -fflags +genpts -i broken.mp4 -c copy fixed.mp4

# FFmpeg 强制音视频同步
ffmpeg -i input -af aresample=async=1 -c:v copy output.mp4
```

---

## 十五、自适应码率（ABR）与多码率分发

### 15.1 ABR 工作原理

自适应码率的核心思想：服务端准备多个分辨率/码率版本，播放器根据当前网络状况自动切换。

```
编码器输出:
├── 1080p @ 4500 kbps ─┐
├── 720p  @ 2500 kbps ─┼── 切片器 → CDN → 播放器
├── 480p  @ 1200 kbps ─┤                   │
└── 360p  @  600 kbps ─┘                   ↓
                                    带宽估计算法
                                    (BOLA / ABR-Rule)
                                           │
                                    自动选择最佳档位
```

### 15.2 HLS 多码率梯度配置

```bash
# FFmpeg 一次编码输出 4 个码率档位的 HLS
ffmpeg -i input.mp4 \
    -filter_complex \
    "[0:v]split=4[v1][v2][v3][v4]; \
     [v1]scale=1920:1080[v1out]; \
     [v2]scale=1280:720[v2out]; \
     [v3]scale=854:480[v3out]; \
     [v4]scale=640:360[v4out]" \
    \
    -map "[v1out]" -c:v:0 libx264 -b:v:0 4500k -maxrate:v:0 4800k \
        -bufsize:v:0 9000k -preset fast -g 60 -sc_threshold 0 \
    -map "[v2out]" -c:v:1 libx264 -b:v:1 2500k -maxrate:v:1 2700k \
        -bufsize:v:1 5000k -preset fast -g 60 -sc_threshold 0 \
    -map "[v3out]" -c:v:2 libx264 -b:v:2 1200k -maxrate:v:2 1400k \
        -bufsize:v:2 2400k -preset fast -g 60 -sc_threshold 0 \
    -map "[v4out]" -c:v:3 libx264 -b:v:3 600k -maxrate:v:3 700k \
        -bufsize:v:3 1200k -preset fast -g 60 -sc_threshold 0 \
    \
    -map a:0 -c:a:0 aac -b:a:0 128k \
    -map a:0 -c:a:1 aac -b:a:1 128k \
    -map a:0 -c:a:2 aac -b:a:2 96k \
    -map a:0 -c:a:3 aac -b:a:3 64k \
    \
    -f hls \
    -hls_time 4 \
    -hls_list_size 10 \
    -hls_flags independent_segments \
    -master_pl_name master.m3u8 \
    -var_stream_map "v:0,a:0 v:1,a:1 v:2,a:2 v:3,a:3" \
    stream_%v/playlist.m3u8
```

生成的目录结构：

```
output/
├── master.m3u8          # 主播放列表（指向各码率子列表）
├── stream_0/            # 1080p @ 4500k
│   ├── playlist.m3u8
│   ├── segment_000.ts
│   └── ...
├── stream_1/            # 720p @ 2500k
├── stream_2/            # 480p @ 1200k
└── stream_3/            # 360p @ 600k
```

### 15.3 master.m3u8 格式

```
#EXTM3U
#EXT-X-VERSION:3

#EXT-X-STREAM-INF:BANDWIDTH=4628000,RESOLUTION=1920x1080
stream_0/playlist.m3u8

#EXT-X-STREAM-INF:BANDWIDTH=2628000,RESOLUTION=1280x720
stream_1/playlist.m3u8

#EXT-X-STREAM-INF:BANDWIDTH=1296000,RESOLUTION=854x480
stream_2/playlist.m3u8

#EXT-X-STREAM-INF:BANDWIDTH=664000,RESOLUTION=640x360
stream_3/playlist.m3u8
```

播放器（如 hls.js、VLC、Safari）读取 `master.m3u8`，根据带宽自动选择合适的子列表。

### 15.4 码率梯度设计参考

| 档位 | 分辨率 | 视频码率 | 音频码率 | 目标带宽 |
|------|--------|---------|---------|---------|
| 超清 | 1080p | 4500 kbps | 128 kbps | ≥5 Mbps |
| 高清 | 720p | 2500 kbps | 128 kbps | ≥3 Mbps |
| 标清 | 480p | 1200 kbps | 96 kbps | ≥1.5 Mbps |
| 流畅 | 360p | 600 kbps | 64 kbps | ≥0.8 Mbps |
| 极速 | 240p | 300 kbps | 48 kbps | ≥0.4 Mbps |

关键约束：**所有码率档位必须使用相同的 GOP 大小和关键帧对齐**（`-g 60 -sc_threshold 0`），否则切换时会出现画面跳帧。

---

## 十六、常见问题排查

### 16.1 画面绿屏 / 花屏

```
原因: 像素格式不匹配或编码器/解码器不一致
常见于: 硬件编码输出 NV12 但解码端期望 YUV420P

诊断:
  ffprobe -show_streams input | grep pix_fmt

解决:
  # 强制像素格式转换
  ffmpeg -i input -pix_fmt yuv420p -c:v libx264 output.mp4

  # GStreamer 添加 videoconvert
  ... ! videoconvert ! video/x-raw, format=NV12 ! ...
```

### 16.2 RTSP 拉流频繁卡顿

```
原因: 默认 UDP 传输在丢包时无重传

诊断:
  # 检查丢包
  ffmpeg -rtsp_transport udp -i rtsp://... -f null - 2>&1 | grep "error"

解决:
  # 切换到 TCP 传输（牺牲少量延迟换取可靠性）
  ffmpeg -rtsp_transport tcp -i rtsp://camera/stream -c copy output.mp4

  # 或增大 UDP 缓冲
  ffmpeg -buffer_size 2097152 -i rtsp://camera/stream -c copy output.mp4
```

### 16.3 播放延迟越来越大（累积延迟）

```
原因: 播放器的 jitter buffer 持续增长，不丢弃过期帧

诊断:
  延迟从开始的 1 秒逐渐增长到 10+ 秒

解决:
  # FFplay: 禁用缓冲 + 丢帧
  ffplay -fflags nobuffer -flags low_delay -framedrop \
      -analyzeduration 0 -probesize 32 \
      rtsp://server/stream

  # GStreamer: 禁用同步
  ... ! autovideosink sync=false

  # VLC: 最小缓存
  vlc --network-caching=50 --clock-jitter=0 rtsp://server/stream
```

### 16.4 WebRTC 在公网连不通

```
原因: 对称型 NAT 导致 STUN 打洞失败，且未配置 TURN 服务器

诊断:
  浏览器 F12 → Console → 查看 ICE candidate 状态
  如果只有 host candidate 没有 srflx/relay → STUN/TURN 配置问题

解决:
  1. 添加 STUN 服务器配置（见第十三章）
  2. 部署 coturn TURN 服务器
  3. MediaMTX 配置 webrtcAdditionalHosts 为公网 IP
  4. 防火墙放行 UDP 3478(STUN/TURN) + 8889(WebRTC) + 8189(ICE)
```

### 16.5 NVENC 编码失败

```
原因 1: "No NVENC capable devices found"
  → NVIDIA 驱动未安装或版本太旧
  解决: nvidia-smi 确认 GPU 状态，更新驱动到 535+

原因 2: "OpenEncodeSessionEx failed: out of memory"
  → 消费级 GPU 有并发编码会话限制（GeForce 限制 5 路）
  解决: 减少同时编码的路数，或使用 Quadro/Tesla（无限制）
  解决(非官方): nvidia-patch 解除限制
       https://github.com/keylase/nvidia-patch

原因 3: "No capable devices found" (FFmpeg)
  → FFmpeg 编译时未启用 NVENC
  解决:
  ffmpeg -encoders 2>/dev/null | grep nvenc
  # 如果无输出，需要重新编译 FFmpeg 或安装预编译版本
```

### 16.6 推流后无声音

```
原因: 源文件音频编码不被目标容器支持

诊断:
  ffprobe input.mp4  # 查看音频编码
  # 如果是 PCM/FLAC 等推到 RTMP → 不支持

解决:
  # 转码音频为 AAC
  ffmpeg -i input -c:v copy -c:a aac -b:a 128k \
      -f flv rtmp://server/live/stream

  # 如果不需要音频
  ffmpeg -i input -c:v copy -an \
      -f flv rtmp://server/live/stream
```

### 16.7 FFmpeg 推流报 "muxer does not support non seekable output"

```
原因: 容器格式不支持流式输出（如 MP4 需要 moov atom 在文件尾部）

解决:
  # RTMP 必须用 FLV 容器
  ffmpeg -i input -c copy -f flv rtmp://server/live/stream

  # SRT/RTP 必须用 MPEGTS 容器
  ffmpeg -i input -c copy -f mpegts "srt://server:9000"

  # 如果必须用 MP4，使用 fragmented MP4
  ffmpeg -i input -c copy -movflags frag_keyframe+empty_moov \
      -f mp4 output.mp4
```

### 16.8 GStreamer 管线启动后无画面

```
原因: Caps 协商失败（元素之间的格式不匹配）

诊断:
  GST_DEBUG=3 gst-launch-1.0 ... 2>&1 | grep -i "not negotiated\|error"

解决:
  # 在格式不确定的位置添加 videoconvert / videoscale
  ... ! videoconvert ! videoscale ! video/x-raw,width=1920,height=1080 ! ...

  # 查看元素支持的 Caps
  gst-inspect-1.0 nvv4l2h264enc
```

---

## 十七、参考资源

1. **FFmpeg 官方文档**: [ffmpeg.org](https://ffmpeg.org/documentation.html)
2. **FFmpeg NVIDIA GPU 加速**: [docs.nvidia.com/video-codec-sdk](https://docs.nvidia.com/video-technologies/video-codec-sdk/12.2/pdf/Using_FFmpeg_with_NVIDIA_GPU_Hardware_Acceleration.pdf)
3. **GStreamer 文档**: [gstreamer.freedesktop.org](https://gstreamer.freedesktop.org/documentation/)
4. **GStreamer Jetson 管线**: [developer.ridgerun.com](https://developer.ridgerun.com/wiki/index.php/NVIDIA_Jetson_Orin_NX/GStreamer_Pipelines/H265)
5. **MediaMTX GitHub**: [github.com/bluenviron/mediamtx](https://github.com/bluenviron/mediamtx)
6. **SRT 协议规范**: [github.com/Haivision/srt](https://github.com/Haivision/srt)
7. **WHIP RFC 9725**: [datatracker.ietf.org/doc/rfc9725](https://datatracker.ietf.org/doc/rfc9725/)
8. **OBS WHIP 指南**: [obsproject.com/kb/whip-streaming-guide](https://obsproject.com/kb/whip-streaming-guide)
9. **FFmpeg SRT 完整命令参考**: [vajracast.com/blog/srt-streaming-ffmpeg-guide](https://vajracast.com/blog/srt-streaming-ffmpeg-guide/)
10. **2026 流媒体协议对比**: [antmedia.io/streaming-protocols](https://antmedia.io/streaming-protocols/)
11. **Jetson GStreamer 实时视频**: [roboticsknowledgebase.com/gstreamer-jetson](https://roboticsknowledgebase.com/wiki/networking/gstreamer-jetson-realtime-video/)
12. **Jetson RTSP→HLS 实战**: [prometeo.blog/rtsp-to-hls-gstreamer-jetson-orin](https://prometeo.blog/practical-case-rtsp-to-hls-via-gstreamer-on-jetson-orin/)
13. **WebRTC 原理详解（开源书）**: [webrtcforthecurious.com](https://webrtcforthecurious.com/)
14. **coturn TURN 服务器**: [github.com/coturn/coturn](https://github.com/coturn/coturn)
15. **FFmpeg HLS 多码率输出**: [ffmpeg.org/ffmpeg-formats/hls](https://ffmpeg.org/ffmpeg-formats.html#hls-2)
16. **Apple HLS 规范**: [developer.apple.com/streaming](https://developer.apple.com/streaming/)
