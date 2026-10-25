# FuyaoColorLock 项目规则

## 定位和边界

- 仓库和目录名为 `FuyaoColorLock`，应用名称为 **Fuyao Color Lock**。这是原生 macOS 菜单栏工具，用于查看和显式设置外接显示器连接格式，不是 ICC 校色或面板色域测量工具。
- 保持零第三方运行时依赖，使用 AppKit、SwiftUI、CoreGraphics、IOKit、QuartzCore、ServiceManagement 和系统工具。不要求安装或运行 BetterDisplay。
- 显示器事件、唤醒、启动和轮询只刷新数据，不能自动重设模式。真实显示设置只响应用户明确的应用或 EDID 安装操作。
- 不支持实际应用的格式和规格继续展示，但不能提供可点击的应用动作；不得把保存偏好、驱动支持列表或历史记录称为应用成功。

## 原生模式通道

- QuartzCore 私有 `CADisplay.displays` 按 `displayId` 对应 CG 显示器；`currentMode`、`availableModes` 和 `setCurrentMode:` 是已通过官方 BetterDisplay 二进制静态分析及本机只读探测确认的通道。详细证据见 `docs/PRIVATE_DISPLAY_API.md`，不得恢复旧版“没有直接设置通道”的绝对结论。
- `CADisplayMode.internalRepresentation` 是 `UInt64`，不能截断，也不能与 IORegistry 的 timing/mode 数字 ID 混用。getter 和 setter 必须检查 Objective-C 类型编码；能力缺失或映射不唯一时只读展示。
- 设置前重新确认显示器稳定身份和当前模式，重新枚举目标对象；只允许当前分辨率、刷新率、HDR 和 VRR 状态兼容的模式。设置请求被接受不等于成功，须重复回读完整模式确认；显示器移除、模式变化或超时必须保持未确认。
- native 模式设置和 EDID 安装恢复共享 `DisplayMutationGate`，避免同时修改显示配置。不要在无人值守验证中调用真实 setter。
- `colorGamut` 等原生字符串可以原样展示；IORegistry 未独立解码的 `Colorimetry` 数字保持原值，不硬编码成 P3、sRGB 或 BT.2020。

## 数据来源

- IORegistry `IOMobileFramebufferShim` 的 `TimingElements → ColorModes` 提供驱动能力；`DPTimingModeId` 只有精确匹配时才标记当前时序，缺失时不得用最高评分时序替代。
- 已有字段映射：`PixelEncoding` 0=RGB、2=YCbCr 4:2:0、3=4:4:4、6=4:2:2；`DynamicRange` 1=Full、0=Limited；`EOTF` 0=SDR、1=HDR、2=HDR10。私有字段跨系统仍需实际读取验证。
- WindowServer `LinkDescription` 只是保存记录，不是实时链路回读。缺失字段不补造默认值；多个不同记录明确标记冲突，不采用无依据的 last-wins。
- 显示器持久身份优先系统 UUID。旧 `lock.<name>-<CGID>.targetModeID` 仅是无法可靠还原的历史数字 ID，允许清除，不按当前表猜回历史格式。
- EDID 优先取匹配 framebuffer；传输节点回退必须按厂商、产品和序号唯一匹配，不能按同名显示器猜测。真实 EDID、UUID、序号不得写入测试、文档或日志。

## EDID override

- 原生 UI 提供改写摘要、导出、管理员授权安装和恢复。Python 脚本仍可单独生成文件；应用本身不依赖 Python。
- 只限制 CTA 中的 YCbCr 声明，不能保证 HDMI Full Range、指定某个位深或物理色域，也不会改写显示器 EEPROM。安装后的成功状态仅表示文件已写入并读回，仍需重新连接及硬件验收。
- CTA 数据块为高 3 位 tag、低 5 位长度；扩展 tag 7 的 `0x0E` 和 `0x0F` 为 4:2:0 视频及能力映射块。保留所有其他扩展和 DTD，修正偏移及校验和，拒绝损坏或未支持的输入。
- override 文件路径中的厂商和产品 ID 使用十六进制，`IODisplayEDID` 使用 plist `<data>`。安装保留原 plist 其他字段及原文件备份；外部修改、符号链接或不安全所有权不得被覆盖。
- 安装恢复脚本只在临时目录、无特权模式下自动测试；实际 `/Library` 写入和管理员流程由用户验收。认证由系统完成，应用不收集密码。

## 界面

- 参考 EC25 Toolbox 的原生呈现：`NSStatusItem + NSPopover`，固定 480×660 pt 逻辑画布，每次展示前按锚点屏幕 `visibleFrame` 减去 24 pt 安全钳制。
- 关闭 hosting 的 intrinsic 尺寸回写，每次展示同步 content size、preferred size、frame 和零原点 bounds；页面内部滚动，切换显示器或模式数量不改变外框，不对整个面板应用尺寸动画。
- 保持原生控件、系统外观、纯文本分组标题、中性操作按钮；技术值等宽且可选择，长名称和状态自然换行。新增文案同步 `Resources/en.lproj` 和 `Resources/zh-Hans.lproj`。
- UI 和真实显示器切换的视觉验收由用户完成，默认不启动应用、截图或更改实际显示设置。

## 构建和验证

- `scripts/build-app.sh` 生成 `build/FuyaoColorLock.app`，arm64、macOS 13.0 起；工具路径通过 `xcrun` 动态解析。构建先完成暂存包及 ad hoc 签名校验，再替换旧产物。
- `scripts/test.sh` 聚合离线回归；改动范围小且已有有效检查时不重复完整套件。修改枚举后额外执行只读目录探测，输出仅包含匿名计数和必要技术规格。
- 修改 EDID 算法后校验完整扩展、DTD、checksum 和 plist；Swift 与 Python 对相同合成数据应输出相同字节。安装恢复测试只能指向临时目录。
- 详细验证边界和人工验收步骤维护在 `docs/VALIDATION.md` 与 `docs/VALIDATION_ZH.md`。构建通过不代表真实模式切换、管理员授权或物理 HDMI 输出已验收。

## 版本和发布

- 营销版本保持两段，当前 1.0；`CFBundleVersion` 单调递增，当前 2。
- 每个已验证阶段建立范围明确的英文 Conventional Commit；默认不 push、不发布 Release，不提交 build、反编二进制、日志或真实设备数据。
