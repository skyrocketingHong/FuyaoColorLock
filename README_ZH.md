<p align="center">
  <a href="README.md">English</a> | 简体中文
</p>

<h1 align="center">Fuyao Color Lock</h1>

<p align="center">
  原生 macOS 菜单栏工具，用于查看和设置外接显示器连接格式。
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0%2B-000000?logo=macos" alt="macOS 13.0 或更高">
  <img src="https://img.shields.io/badge/version-1.0-4F6B00" alt="版本 1.0">
  <img src="https://img.shields.io/badge/Swift-6-FA7343?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT 许可证">
</p>

Fuyao Color Lock 读取系统当前连接模式，并通过原生显示 API 请求切换支持的格式。面板将实时模式、驱动公布的能力和 macOS 历史配置记录分开展示。

**只有与当前分辨率、刷新率、HDR 和 VRR 状态兼容的原生模式可以应用。** 其他模式保持只读。操作成功必须经过重复系统回读确认，这不等同于对 HDMI 输出或面板色域的独立测量。应用不修改 ICC 描述文件，也不会在唤醒后自动重新应用模式。

## 功能

- 原生弹出面板，固定画布并在内部滚动。不同显示器的模式数量不会改变面板高度。
- 分别展示显示时序、macOS 记录和驱动能力；缺失或冲突的信息明确提示。
- 通过 `CADisplay` 显式切换连接格式，使用原生 64 位模式 ID，并回读确认；不需要安装 BetterDisplay。
- 显示器变化、唤醒和定期轮询时只读刷新。启动应用或选择显示器不会重新配置连接。
- 提供简体中文和英语资源，沿用系统外观与原生控件。
- 原生“RGB 优先”分组，提供 EDID 改写预览、导出、管理员授权安装和原文件恢复；安装后需手动重新连接并验证输出。

## 环境要求和构建

需要 Apple Silicon、macOS 13.0 或更高，以及通过 `xcode-select` 或 `DEVELOPER_DIR` 选择的 Xcode 工具链。原生应用不依赖第三方组件，也不需要 Python；只有可选命令行 EDID 工具及其测试需要 Python 3。

在当前仓库内执行：

```bash
scripts/build-app.sh
open build/FuyaoColorLock.app
```

脚本生成经过优化的 arm64 应用，包含本地化资源，并在验证 ad hoc 签名后替换旧构建。应用未公证。此次构建序号为 2，营销版本保持 1.0。

## 如何理解面板

| 信息 | 含义 |
| --- | --- |
| 实时连接 | 原生系统当前模式，包括时序、格式、范围、位深和系统报告的色域。 |
| macOS 记录 | WindowServer 保存的字段，可能缺失、过期或冲突，不是实时测量。 |
| 模式选项 | 与当前时序兼容、且设置通道可用的原生模式提供“应用”。其他时序和仅来自驱动表的条目只读展示。 |
| 历史目标 | 旧版保存、无法可靠还原的数字 ID。驱动 ID 可能改变，不能据此猜测当时的颜色格式。 |
| 刷新 | 重新读取目录和保存的记录，不切换模式。 |

点击兼容模式旁的“应用”。链路重新协商期间屏幕可能短暂变黑。面板会先显示等待，重复回读确认后才报告成功，否则明确标记未确认。无法应用的选项不可点击；清除历史偏好不会修改显示器。无法读取的当前时序和未解码色度不会被猜测成已知值。

## 可选 EDID override

在面板中选择显示器，找到“通过 EDID 优先使用 RGB”分组：

- **导出**：保存 plist，不修改系统。
- **安装**：展示改写内容，确认后调用 macOS 管理员授权；保留已有 plist 其他字段，先备份原文件，再安装修改后的 EDID。
- **恢复**：按原字节恢复备份；原先不存在 override 时移除此应用安装的文件。检测到外部改动时停止恢复，避免覆盖它们。

override 按厂商和产品 ID 生效，可能同时影响多台同型号显示器。应用将文件安装状态与实际输出分开展示。安装或恢复后需重新连接，Full RGB 仍须硬件验证。这是系统级覆盖配置，不会写入显示器 EEPROM。

可选命令行工具只生成文件：

```bash
python3 scripts/patch-edid.py --name "你的显示器名称" --outdir build/edid-override
```

命令只生成文件并打印安装说明，不执行安装。显示器不可用或 EDID 校验失败时，脚本直接报错，不生成改写结果。检查产物后再按输出执行需要管理员权限的安装命令；目标位置已有 override 时应先备份。安装后重新连接显示器。回滚时恢复原备份，或仅删除此次新安装的 override，再重新连接。

改写会清除 CTA YCbCr 4:4:4 和 4:2:2 标志，并移除 CTA YCbCr 4:2:0 视频及能力映射数据块，保留其他扩展和详细时序。它**不能指定**某个位深、Full Range、SDR、HDR、sRGB 或 P3。驱动行为及未被改写的其他声明仍可能影响链路协商，实际结果需要在连接的显示器上确认。

## 手动验证修改是否成功

### 应用格式后查看实时模式

1. 选择正确的显示器，修改前记下“**实时连接模式**”，便于需要时重新选择原来的兼容模式。
2. 在“**连接模式选项**”中应用列表提供的 RGB Full 模式。例如，`8-bit · SDR · RGB Full · sRGB` 表示系统报告 8 位 SDR、全范围 RGB；仅看到 `sRGB` 不能证明编码和范围。分辨率、刷新率、HDR 和 VRR 状态应保持不变。
3. 等待数秒，查看“**最近一次模式切换**”是否显示“**切换后，系统回读与请求模式一致。**”应用要求两次间隔 0.5 秒的完整回读一致，验证窗口为六秒。“尚未确认所选模式”不能视为成功。
4. 点击“**刷新**”或按 **⌘R**，确认“**读取时间**”更新，“实时连接模式”仍与目标一致。如果显示 `YCbCr` 或 `RGB Limited`，则当前系统模式没有达到 RGB Full 目标；实时模式不可用时，结果仍属未验证。
5. 如需检查重新协商后是否保留，睡眠唤醒或重新插拔 HDMI 线后再读一次。重连前成功不代表重连后仍保持，应用不会自动重新应用模式。

驱动模式列表和“macOS 记录”仅供参考，不能代替当前模式判断。“当前模式”标签表示系统报告的状态，不是物理信号测量。

### 在应用之外交叉查看

- **macOS 系统信息**：按住 Option 键打开苹果菜单，选择“**系统信息**”，进入“**图形卡/显示器**”。核对目标显示器及其报告的分辨率；提供刷新率等字段时，再与目标比较。也可在终端运行下面的命令读取报告。该报告适合核对显示器和时序，但其中的 `RGB` 帧缓冲格式或颜色深度不能证明 HDMI 编码及 Full Range。[Apple 系统信息指南](https://support.apple.com/guide/system-information/system-information-syspr35536/mac)

  ```bash
  system_profiler SPDisplaysDataType
  ```

  预期得到显示器报告；缺少显示器或相关字段时，不能用此报告验证该项。命令只读，无需清理。

- **显示器自身菜单（OSD）**：打开当前 HDMI 输入对应的“信息”或“输入信号”页面。如果显示器会报告收到的信号编码和量化范围，核对是否为 `RGB` 和 `Full`。名为 RGB、Full 或 sRGB 的输入设置、画面预设不等于实际接收信号的测量结果。各型号菜单和字段不同，没有范围信息时，硬件结果仍标为未验证。
- **画面辅助检查**：在目标屏幕查看灰阶渐变及近黑、近白细节，例如使用 [EIZO 显示器测试](https://www.eizo.com/library/basics/eizo-monitor-test/)。保持画面设置一致，观察暗部、亮部细节是否丢失，以及色调是否出现异常变化。目视检查可发现问题，但画面正常不能单独证明 RGB Full；Gamma、HDR 和显示器处理也会影响结果。

### 单独检查 EDID 安装

1. 在“**通过 EDID 优先使用 RGB**”中确认出现“**override 文件已安装**”，展开“**文件位置**”并复制实际路径，不手填厂商和产品 ID。
2. 可在访达中通过“**前往 > 前往文件夹…**”（**⇧⌘G**）查看该文件，也可在终端校验。将引号内的占位路径替换为刚复制的路径：

   ```bash
   plutil -lint "/paste/the/path/from/File location"
   ```

   输出 `OK` 仅表示安装文件是合法 plist，不能证明 macOS 已加载其中的 EDID，更不能证明正在输出 RGB Full。文件不存在、权限错误或解析失败时，应先处理该问题，不能将文件检查记为通过。此命令只读，无需清理。
3. 重新插拔 HDMI 线，打开应用并点击“刷新”，再按前述步骤查看实时模式和 OSD。如果文件已安装，但实时模式仍是 YCbCr 或 Limited，就不能认为 RGB Full 目标已经达成；仅安装 override 不足以确认生效。
4. 要撤销由应用管理的 override，点击“**恢复…**”，然后重新连接并刷新。它会恢复原文件，或在原先无 override 时删除本应用安装的文件，不会自动恢复此前选择的原生连接模式。若外部修改导致恢复被阻止，应先检查差异，不要直接删除文件。

## 架构和验证

SwiftUI 面板由 AppKit `NSPopover` 承载。CoreGraphics 枚举显示器，IORegistry 提供时序表和 EDID；SkyLight 和 CoreDisplay 用于关联显示器、framebuffer 和保存记录。QuartzCore 私有 `CADisplay` 和 `CADisplayMode` 提供实时模式及设置通道。每次请求前检查运行时 ABI 并重新枚举模式；不支持的 API 保持只读。实现依据见[复核记录](docs/PRIVATE_DISPLAY_API_ZH.md)。

```text
Sources/FuyaoColorLock/   目录、状态、设置和原生面板
Resources/               Bundle 元数据和本地化文本
scripts/build-app.sh      本地优化构建和打包
scripts/test-models.sh    显示器模型离线回归测试
scripts/test.sh           全部离线回归检查
scripts/patch-edid.py     可选 EDID override 生成工具
Tests/                   离线回归数据和断言
```

验证结果和剩余人工验收步骤见 [VALIDATION_ZH.md](docs/VALIDATION_ZH.md)。

## 隐私

显示器信息和偏好只保留在本机。应用读取 IORegistry、CoreGraphics 和保存的 WindowServer 记录，不发送显示器标识。EDID 导出和安装仅响应明确操作，管理员凭据由 macOS 处理。原文件备份保存在 override 目录下的 `.FuyaoColorLock` 中，用于恢复。

## 许可证

MIT。

---

本项目在开发过程中使用生成式 AI 协助编码。

<a href="https://github.com/fenxer/llm-things/blob/main/stickers/vibe-pr.svg">
  <img src="https://github.com/fenxer/llm-things/blob/main/stickers/vibe-pr.svg" alt="Vibe PR" width="220">
</a>
