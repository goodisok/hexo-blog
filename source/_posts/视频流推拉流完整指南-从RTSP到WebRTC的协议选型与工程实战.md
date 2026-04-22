---
title: 视频流推拉流完整指南：从 RTSP 到 WebRTC 的协议选型与工程实战
date: 2026-04-22 14:00:00
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

## 三、视频编码基础

### 3.1 编码格式对比

| 编码 | 标准 | 压缩效率 | 硬件支持 | 适用场景 |
|------|------|---------|---------|---------|
| **H.264/AVC** | 2003 | 基准 (1×) | 极广 | 兼容性优先、实时通信 |
| **H.265/HEVC** | 2013 | 1.5-2× | 广泛 | 4K/高清存储、广播 |
| **AV1** | 2018 | 1.5-2× | 逐步增加 | Web 视频、未来趋势 |
| **VP9** | 2013 | ~1.4× | 有限 | YouTube、Chrome |

### 3.2 关键编码参数

```bash
# H.264 编码核心参数说明
ffmpeg -i input -c:v libx264 \
    -preset fast \          # 编码速度 vs 质量权衡
                            # ultrafast > superfast > veryfast > faster > fast
                            # > medium > slow > slower > veryslow
    -tune zerolatency \     # 低延迟调优（禁用 B 帧、减少缓冲）
    -profile:v high \       # baseline(兼容)/main/high(质量)
    -b:v 4000k \            # 目标码率
    -maxrate 4500k \        # 最大码率（CBR/VBR 上限）
    -bufsize 8000k \        # VBV 缓冲大小
    -g 60 \                 # GOP 大小（关键帧间隔 = 帧率×秒数）
    -keyint_min 60 \        # 最小关键帧间隔
    -bf 0 \                 # B 帧数量（0=低延迟）
    output.mp4
```

### 3.3 码率参考

| 分辨率 | 帧率 | H.264 推荐码率 | H.265 推荐码率 |
|--------|------|---------------|---------------|
| 720p | 30fps | 2.5-4 Mbps | 1.5-2.5 Mbps |
| 1080p | 30fps | 4-6 Mbps | 2.5-4 Mbps |
| 1080p | 60fps | 6-9 Mbps | 4-6 Mbps |
| 4K | 30fps | 13-20 Mbps | 8-13 Mbps |
| 4K | 60fps | 20-30 Mbps | 13-20 Mbps |

---

## 四、硬件编码加速

### 4.1 为什么需要硬件编码

软件编码（x264）质量好但 CPU 占用极高。1080p@30fps 的 x264 medium 可以吃满 4 核 CPU。在嵌入式设备（Jetson、树莓派）上，软编根本不可行。

| 方案 | 平台 | 速度(vs x264) | CPU 占用 | 质量 |
|------|------|-------------|---------|------|
| x264 (medium) | 通用 CPU | 1× | ~400% | 优秀 |
| **NVENC** | NVIDIA GPU | 4-6× | ~50% | 很好 |
| **VAAPI** | Intel/AMD GPU | 3-4× | ~45% | 好 |
| **QSV** | Intel CPU/GPU | 3-5× | ~40% | 好 |
| **VideoToolbox** | macOS/Apple Silicon | 3-5× | ~30% | 好 |
| **nvv4l2h264enc** | Jetson | 3-4× | ~5% | 好 |

### 4.2 NVIDIA NVENC

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

### 4.3 Intel VAAPI / QSV

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

### 4.4 NVIDIA Jetson（nvv4l2h264enc）

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

## 五、FFmpeg 推拉流实战

### 5.1 拉流：RTSP → 本地文件

```bash
# 从 IP 摄像头拉流并录制
ffmpeg -rtsp_transport tcp \
    -i rtsp://admin:pass@192.168.1.100/stream1 \
    -c copy \
    -f segment -segment_time 300 -strftime 1 \
    "recording_%Y%m%d_%H%M%S.mp4"
```

### 5.2 推流：本地文件 → RTMP

```bash
# 循环推流视频文件到 RTMP
ffmpeg -re -stream_loop -1 -i input.mp4 \
    -c:v libx264 -preset fast -tune zerolatency \
    -b:v 4000k -g 60 -bf 0 \
    -c:a aac -b:a 128k \
    -f flv rtmp://localhost:1935/live/test
```

### 5.3 转推：RTSP → RTMP

```bash
# IP 摄像头 RTSP 转推到直播平台
ffmpeg -rtsp_transport tcp \
    -i rtsp://admin:pass@192.168.1.100/stream1 \
    -c:v copy -c:a aac \
    -f flv rtmp://live-push.example.com/live/stream_key
```

### 5.4 转推：RTMP → SRT

```bash
# 协议转换：RTMP 推流转发到 SRT
ffmpeg -i rtmp://localhost:1935/live/stream \
    -c copy -f mpegts \
    "srt://remote:9000?mode=caller&latency=500000&passphrase=MySecret&pbkeylen=32"
```

### 5.5 SRT → HLS 切片

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

### 5.6 摄像头采集推流

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

### 5.7 多路输出（tee muxer）

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

## 六、GStreamer 推拉流实战

### 6.1 基本管线结构

GStreamer 用管道（pipeline）将一系列元素（element）串联：

```
source → demux → decode → process → encode → mux → sink
```

每个元素通过 pad 连接，数据以 buffer 形式在管线中流动。

### 6.2 摄像头 → RTSP 推流

```bash
# USB 摄像头 → x264 → RTSP（使用 test-launch）
# 需要安装 gst-rtsp-server
gst-launch-1.0 v4l2src device=/dev/video0 ! \
    video/x-raw, width=1920, height=1080, framerate=30/1 ! \
    videoconvert ! x264enc tune=zerolatency bitrate=4000 ! \
    rtph264pay config-interval=1 name=pay0 pt=96 ! \
    udpsink host=192.168.1.10 port=5000
```

### 6.3 Jetson 低延迟管线

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

### 6.4 接收端管线

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

### 6.5 GStreamer RTSP Server（Python）

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

### 6.6 GStreamer + OpenCV 联合使用

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

## 七、MediaMTX：一站式媒体服务器

### 7.1 简介

[MediaMTX](https://github.com/bluenviron/mediamtx)（前身 rtsp-simple-server）是一个零依赖、单文件的媒体服务器，支持所有主流协议之间的自动转换。

```
任意推流协议 → MediaMTX → 任意拉流协议

支持：SRT / WebRTC(WHIP) / RTSP / RTMP / HLS / RTP / MPEG-TS
→ 自动转换为 →
SRT / WebRTC(WHEP) / RTSP / RTMP / HLS
```

### 7.2 部署

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

### 7.3 推流

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

### 7.4 拉流

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

### 7.5 核心配置

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

### 7.6 协议自动转换矩阵

| 推流方式 | RTSP 拉 | RTMP 拉 | HLS 拉 | WebRTC 拉 | SRT 拉 |
|---------|---------|---------|--------|----------|--------|
| RTSP 推 | ✅ | ✅ | ✅ | ✅ | ✅ |
| RTMP 推 | ✅ | ✅ | ✅ | ✅ | ✅ |
| SRT 推 | ✅ | ✅ | ✅ | ✅ | ✅ |
| WHIP 推 | ✅ | ✅ | ✅ | ✅ | ✅ |
| RTP 推 | ✅ | ✅ | ✅ | ✅ | ✅ |

推一路流，MediaMTX 自动为所有协议生成对应的拉流端点。

---

## 八、无人机 / 机器人低延迟视频方案

### 8.1 延迟预算分析

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

### 8.2 推荐方案

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

### 8.3 方案对比

| | 裸 RTP/UDP | SRT | WebRTC |
|---|-----------|-----|--------|
| 延迟 | ~20ms | ~200-400ms | ~300-800ms |
| 抗丢包 | 无 | ARQ 重传 | NACK 重传 |
| 加密 | 无 | AES-256 | DTLS-SRTP |
| 浏览器 | 不支持 | 不支持 | 原生支持 |
| 适用网络 | 可靠局域网 | 公网/4G/5G | 任意 |
| 复杂度 | 低 | 中 | 高 |

---

## 九、性能优化最佳实践

### 9.1 降低编码延迟

```bash
# x264 低延迟配置
-preset ultrafast -tune zerolatency -profile baseline -bf 0 -g 30

# NVENC 低延迟配置
-preset p1 -tune ll -bf 0 -g 30 -rc cbr -delay 0

# GStreamer nvv4l2h264enc 低延迟
nvv4l2h264enc maxperf-enable=1 control-rate=1 \
    insert-sps-pps=true iframeinterval=15 EnableTwopassCBR=false
```

### 9.2 降低拉流延迟

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

### 9.3 网络优化

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

### 9.4 诊断工具

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

## 十、参考资源

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
