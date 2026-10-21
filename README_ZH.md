<p align="center">
  <a href="README.md">English</a> | 简体中文
</p>

<h1 align="center">Fuyao Color Lock</h1>

<p align="center">
  零依赖的 macOS 菜单栏工具:按显示器展示真实支持的连接色彩模式,并可选 EDID override 实现锁定
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0%2B-000000?logo=macos" alt="macOS 13.0 或更高">
  <img src="https://img.shields.io/badge/version-1.0-4F6B00" alt="版本 1.0">
  <img src="https://img.shields.io/badge/Swift-6-FA7343?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT 许可证">
</p>

macOS 经常在睡眠唤醒或链路重新协商后,把外接显示器从你选定的像素格式(例如 8-bit SDR RGB Full Range)重置回 YCbCr 或 10-bit 变体。BetterDisplay 可以切换,但“保持锁定”是 Pro 功能,而且它的切换通道闭源。

Fuyao Color Lock 采用完全独立的路线:

- **读**:显示驱动在 IORegistry 公布每台显示器的时序表(`TimingElements → ColorModes`,含位深、RGB/YCbCr 采样、范围、EOTF)。App 直接读取并按显示器分标签页展示**该显示器实际支持的模式**——没有硬编码列表。
- **锁**:配套的 `patch-edid.py` 脚本生成一次性 EDID override,从显示器 EDID 中去掉 YCbCr 能力。安装后 macOS 在任何重置时都选不到 YCbCr 模式,无需后台进程。App 在锁定开启时监听显示器事件,并在重连/唤醒后自动重新检测显示器(`SLSDetectDisplays`)。

## 环境要求

- macOS 13.0 或更高(在 Apple Silicon、macOS 27 上构建与验证)
- 无任何第三方依赖。不需要 BetterDisplay(已安装的可以卸载)。

## 快速开始

```bash
git clone <本仓库>
cd FuyaoColorLock
scripts/build-app.sh
open build/FuyaoColorLock.app
```

菜单栏面板按外接显示器分标签页。每页显示当前时序和该显示器实际支持的模式列表(首行为驱动偏好,默认不选中任何项),并有独立的锁定开关。点选某个模式即固定目标并打开该显示器的锁定;显示器事件后 App 自动重新检测,把模式选择拉回边界内。

### 彻底屏蔽 YCbCr

```bash
python3 scripts/patch-edid.py --name "Redmi 27 NU" --outdir build/edid-override
```

脚本从实时 EDID 生成改写版(清除 CEA-861 的 YCbCr 4:4.4/4:2:2 能力位与 4:2:0 capability map,修正校验和),并打印安装到 `/Library/Displays/Contents/Resources/Overrides/` 的确切 `sudo` 命令。安装后重新插拔显示器生效;回滚时删除该文件再插拔。

## 工作原理

- 显示器枚举:通过 `SLSCopyDisplayInfoDictionary` 的 `IODisplayLocation`(含 `disp0@…` 控制器段)把 CG 在线显示器与对应 framebuffer shim 配对;名字来自 CoreDisplay 信息字典。
- 色彩模式字段已在 macOS 27 上与 BetterDisplay 的列表逐一校准:`PixelEncoding` 0=RGB / 2=YCbCr 4:2:0 / 3=4:4:4 / 6=4:2:2,`DynamicRange` 1=Full / 0=Limited,`EOTF` 0=SDR / 2=HDR10;`DPTimingModeId` 指示当前时序。
- App 刻意**不做**的事:直接写入连接模式。该通道位于闭源 IOKit 层(已验证:不属于 CGS display mode API、不写 IORegistry 属性、也不是 `SLSDisplay*Preset` 家族)。EDID override 加上事件驱动的重新检测,在无需该通道的情况下实现锁定。

## 项目结构

```
Sources/FuyaoColorLock/   Swift 源码(显示器目录、守护、菜单栏界面、SLS 桥接)
scripts/build-app.sh      构建 build/FuyaoColorLock.app(工具路径经 xcrun 动态解析)
scripts/patch-edid.py     EDID override 生成脚本(去 YCbCr)
Resources/Info.plist      Bundle 元数据(LSUIElement 菜单栏应用)
```

## 隐私

无网络访问、无沙箱、无辅助功能权限。全部操作为本地 IORegistry/CoreGraphics 读取,以及你自行安装的可选 EDID override。

## 许可证

MIT。

---

本项目在开发过程中使用生成式 AI 协助编码。

<a href="https://github.com/fenxer/llm-things/blob/main/stickers/vibe-pr.svg">
  <img src="https://github.com/fenxer/llm-things/blob/main/stickers/vibe-pr.svg" alt="Vibe PR" width="220">
</a>
