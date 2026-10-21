<p align="center">
  <a href="README.md">English</a> | 简体中文
</p>

<h1 align="center">FuyaoColorLock</h1>

<p align="center">
  轻量 macOS 菜单栏工具:通过 BetterDisplay 免费版 CLI 锁定外接显示器的连接色彩模式(像素格式)并自动恢复
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0%2B-000000?logo=macos" alt="macOS 13.0 或更高">
  <img src="https://img.shields.io/badge/version-1.0-4F6B00" alt="版本 1.0">
  <img src="https://img.shields.io/badge/Swift-6-FA7343?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT 许可证">
</p>

macOS 经常在你选定的像素格式(例如 8-bit SDR RGB Full Range)被手动设置之后,又在睡眠唤醒、重新连接或链路重新协商时把外接显示器切回 YCbCr 或 10-bit 变体。BetterDisplay 免费版可以切换该模式,但“保持锁定”的 Configuration Protection 是 Pro 功能。

FuyaoColorLock 只补齐这一块:监听显示器重配置、唤醒和模式变化事件,一旦目标显示器偏离锁定的色彩模式,就通过 BetterDisplay 免费版自带的 CLI 自动改回。在实测机器上,强制切走锁定模式后约 4 至 6 秒内被纠正回来。

## 功能

- 锁定一台外接显示器的连接色彩模式(8/10-bit、RGB 或 YCbCr 采样、Full/Limited 范围预设)
- 响应显示器重配置回调、唤醒事件和手动切换(2.5 秒去抖),另有 15 秒兜底轮询
- 菜单栏显示当前模式,可切换目标显示器、目标模式,一键立即恢复
- 可选开机自启
- 附带 `patch-edid.py`:可选的一次性 EDID 改写脚本,从显示器 EDID 中去掉 YCbCr 能力,让 macOS 不再提供 YCbCr 模式

## 环境要求

- macOS 13.0 或更高(在 Apple Silicon 上构建与实测)
- [BetterDisplay](https://github.com/waydabber/BetterDisplay)(免费版即可)安装在 `/Applications/BetterDisplay.app` 并保持运行——CLI 依赖其本地连接

## 快速开始

```bash
git clone <本仓库>
cd FuyaoColorLock
scripts/build-app.sh
open build/FuyaoColorLock.app
```

点击菜单栏锁图标,选择目标显示器(例如 *Redmi 27 NU*)和目标模式(例如 *8-bit SDR RGB Full Range*),锁定立即生效。验证方式:在 BetterDisplay 里手动切走模式,几秒内会被拉回。

## 工作原理

- **模式枚举**:BetterDisplay 暴露的连接色彩模式列表,对应显示驱动在 IORegistry(`IOMobileFramebufferShim`)发布的 `TimingElements → ColorModes` 表。
- **读取与设置**:BetterDisplay 免费版 CLI 支持 `get -connectionMode` 与 `set -connectionMode="bpc:8+range:full+encoding:rgb"`,本项目为其加了超时与重试封装。
- **锁定**:`CGDisplayRegisterReconfigurationCallback`、`NSWorkspace` 唤醒通知与低频轮询触发检查,将实时模式描述与锁定预设比对,不一致即重新应用。

## 可选:用 EDID 改写彻底移除 YCbCr 模式

如果不满足于“纠正”,想让 YCbCr 选项彻底消失,可从显示器实时 EDID 生成改写版 override:

```bash
python3 scripts/patch-edid.py --name "Redmi 27 NU" --outdir build/edid-override
```

脚本会清除 CEA-861 的 YCbCr 4:4:4 / 4:2:2 能力位和 YCbCr 4:2:0 capability map 数据块,修正校验和,并打印安装到 `/Library/Displays/Contents/Resources/Overrides/` 的确切 `sudo` 命令。安装后重新插拔显示器(或重启)生效;回滚时删除该文件并再次插拔即可。

说明:安装与卸载需要管理员权限并重新插拔;个别 4:2:0 模式可能来自 EDID 之外的驱动侧来源——建议保持菜单栏锁定的开启状态,作为精确且常开的最终保障。

## 项目结构

```
Sources/FuyaoColorLock/   Swift 源码(CLI 封装、守护逻辑、菜单栏界面)
scripts/build-app.sh      构建 build/FuyaoColorLock.app(工具路径经 xcrun 动态解析)
scripts/patch-edid.py     可选 EDID override 生成脚本
Resources/Info.plist      Bundle 元数据(LSUIElement 菜单栏应用)
```

## 隐私

无网络访问、无沙箱、无辅助功能权限。全部操作都在本地:BetterDisplay CLI 与 IORegistry 读取。

## 许可证

MIT。FuyaoColorLock 是独立工具,与 BetterDisplay 无从属关系,仅调用你本机安装的 BetterDisplay CLI。

---

本项目在开发过程中使用生成式 AI 协助编码。

<a href="https://github.com/fenxer/llm-things/blob/main/stickers/vibe-pr.svg">
  <img src="https://github.com/fenxer/llm-things/blob/main/stickers/vibe-pr.svg" alt="Vibe PR" width="220">
</a>
