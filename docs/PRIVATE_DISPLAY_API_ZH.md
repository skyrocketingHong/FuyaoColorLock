# 原生显示模式实现依据

[English](PRIVATE_DISPLAY_API.md)

复核日期：2026-10-25。本记录区分二进制静态证据、只读运行时检查和未执行的真实硬件写入。

## 证据

公开的 [BetterDisplay CLI](https://raw.githubusercontent.com/waydabber/betterdisplaycli/main/betterdisplaycli.swift) 通过 DistributedNotificationCenter 发送 JSON 请求。[官方命令文档](https://github.com/waydabber/BetterDisplay/wiki/Integration-features%2C-CLI) 提供 `connectionMode`，底层实现位于主应用。FuyaoColorLock 的初始提交 `cff69aa` 同样只是调用该主应用；后来移除依赖时，没有补上独立写入通道。

静态分析采用官方 [BetterDisplay 5.1.1](https://github.com/waydabber/BetterDisplay/releases/tag/v5.1.1)，发布于 2026-10-06。DMG SHA-256 为 `533ce08c91a02e0fdca2bc0e461404968ab18d32bbd9fd3314218e1a8d51c1de`，提取的主程序为 `682befb88bb5f199cb2568a4aa91ffc683c7e4141216eba72418a52512e0204e`。没有安装或启动该应用。

| ARM64 调用点 | 操作 |
| --- | --- |
| `0x100a89db8` | `+[CADisplay displays]` |
| `0x100a89ed8` | `displayId`，匹配 CG 显示器 ID |
| `0x100a8953c` | `availableModes` |
| `0x100a8b2c0` | `CADisplayMode.internalRepresentation`，64 位模式 ID |
| `0x100a8b304` | `setCurrentMode:`，传入原生模式对象 |

QuartzCore 通道推翻了此前“没有直接模式设置通道”的结论。仅排除 CGS、SLS 和 IOConnect 路径不足以得出该判断。

## 运行时交叉检查

只读探针检查了方法编码，并在三台外接显示器上调用 getter。`setCurrentMode:` 编码为 `v24@0:8@16`，不返回成功状态。模式 ID、宽高和位深返回无符号 64 位整数；刷新率返回 Double；颜色字段返回对象；VRR 和虚拟标志返回 Bool。

原生列表分别包含 197、295、438 个模式。限制为相同分辨率、精确相同刷新率、相同 HDR 和 VRR 状态后，兼容候选分别为 6、5、6 个。已读取 getter 并确认 setter ABI 可用，没有调用 setter。本记录不包含显示器标识、序号或原始 EDID。

## 独立实现

`CoreDisplayModes.swift` 动态解析系统类，检查 ABI 并读取原生模式对象。不分发 BetterDisplay 代码，也不依赖该应用运行。

每次写入前检查稳定显示器身份、预期当前模式和重新枚举的可用列表；只将唯一匹配且兼容的原生对象传给 setter。能力缺失、标识复用或过期选择均拒绝操作。原生模式设置与 EDID 安装共用修改互斥门。

请求后必须在六秒窗口内取得两次间隔 0.5 秒、完整字段一致的回读，才记录系统确认；后续模式变化或断开会撤销确认。这是系统回读，不是对 HDMI 信号或面板色域的测量。

私有 API 行为可能随 macOS 版本改变，不支持的签名保持只读。实际硬件切换、视觉表现和 HDMI RGB Full Range 验收仍由用户完成。被忽略的 `build/research/` 保留本地分析输出；研究二进制和解包工具不进入应用或 Git 历史。
