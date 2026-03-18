---
title: Windows 上 UE 5.7 + Colosseum 配置方法
date: 2026-03-18 12:00:00
categories:
  - 仿真
tags:
  - Colosseum
  - Unreal Engine
  - UE5
  - Windows
  - PX4
---

UE 5.7 + [goodisok/Colosseum](https://github.com/goodisok/Colosseum) 分支 **`feature/jpeg-geomag-px4`**。路径自定；下文 `D:\workspace`、`D:\Program Files\UE_5.7` 仅为示例。参考 [Build on Windows](https://codexlabsllc.github.io/Colosseum/build_windows/)。

## 前置

| 项 | 说明 |
|----|------|
| Git / CMake / 7-Zip | 均安装；CMake 勾选加入 PATH |
| UE 5.7 | Epic Launcher 安装（示例 5.7.2）；确认 `Engine\Build\BatchFiles` 存在 |
| VS 2022 | 工作负载「使用 C++ 的桌面开发」+ Windows 10 SDK + .NET SDK |
| 终端 | **Developer Command Prompt for VS 2022**（开始菜单 → Visual Studio 2022） |

## 克隆（须带子模块）

在 **Developer Command Prompt for VS 2022** 中：

```bat
cd /d D:\workspace
git clone --recurse-submodules -b feature/jpeg-geomag-px4 https://github.com/goodisok/Colosseum.git
cd Colosseum
```

若曾未拉子模块：`git submodule update --init --recursive`。切换分支后同样再执行一次。

## 编译插件

```bat
cd /d D:\workspace\Colosseum
build.cmd
```

产出在 `Unreal\Plugins`。找不到引擎时核对 UE 5.7 是否装全、是否与 `build.cmd` 期望一致。

## 打开环境工程

`build.cmd` 完成后，双击 **`Colosseum\Unreal\Environments\BlocksV2\BlocksV2.uproject`**，用 **UE 5.7** 打开（多版本时选对引擎），进编辑器后 **Play**。原点由关卡 **PlayerStart** 位置/朝向决定。  
`Edit → Editor Preferences` 搜 **CPU**，取消 **Use Less CPU when in Background**。

## 在其它 UE 场景中使用插件

要在自有 UE 工程里用 Colosseum（AirSim）插件：把 **`Colosseum\Unreal\Environments\BlocksV2\Plugins`** 整目录拷到目标工程根目录下的 **`Plugins`**（没有则新建），用 UE 5.7 打开工程。在 **世界场景设置（World Settings）** 里找到 **游戏模式重载（Game Mode Override）**，选 **AirSimGameMode**。  
AirSim 与仿真原点对应的是关卡里的 **Player Start**：在场景中调整 **PlayerStart** 的位置与朝向，即设定 AirSim 的原点。视需要再改 `settings.json` 等。

## 其它

- PX4 / 本分支细节：仓库 README、[MavLink and PX4](https://codexlabsllc.github.io/Colosseum/build_windows/)

**链接**：[官方 Windows 构建](https://codexlabsllc.github.io/Colosseum/build_windows/) · [goodisok/Colosseum](https://github.com/goodisok/Colosseum)
