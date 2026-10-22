# FuyaoColorLock 项目规则

## 定位与边界

- 本项目仓库/目录名 `FuyaoColorLock`,App 显示名 **Fuyao Color Lock**;macOS 菜单栏工具,管理外接显示器连接色彩模式(像素格式:位深/RGB-YCbCr/Full-Limited/EOTF)。
- **零第三方依赖**:不依赖也不调用 BetterDisplay(已从本机完全卸载);只用系统框架(AppKit、SwiftUI、CoreGraphics、IOKit、ServiceManagement)+ SkyLight/CoreDisplay 私有符号(dlsym)。
- 锁定机制 = 一次性 EDID override(去 YCbCr,`scripts/patch-edid.py` 生成)+ App 事件驱动重检测;不直接写连接模式。

## 构建与验证

- 构建:`scripts/build-app.sh`,产物 `build/FuyaoColorLock.app`(arm64,macOS 13.0 起)。工具路径一律经 `xcrun` 动态解析。
- 修改枚举逻辑后:用 `Sources/FuyaoColorLock/{DisplayCatalog,PrivateSLS}.swift` + 临时 main.swift 编译命令行版验证 `DisplayCatalog.snapshot()` 输出(每台显示器的名字、当前 timing、模式列表)。
- `lock.<displayID>.enabled` / `lock.<displayID>.targetModeID` 为持久化键;displayID 形如 `名字-<CGDirectDisplayID>`。
- EDID 脚本改动后:`plutil -lint` 校验产物,核对 CEA flags(0x30 位清除)与校验和;`IODisplayEDID` 必须是 base64 `<data>`。

## 技术事实(已逆向验证,勿重复调研)

- 连接色彩模式列表来源:IORegistry `IOMobileFramebufferShim` 节点 `TimingElements → ColorModes`;字段映射(已与 BetterDisplay 列表逐一校准):`PixelEncoding` 0=RGB、2=YCbCr 4:2:0、3=4:4:4、6=4:2:2;`DynamicRange` 1=Full、0=Limited;`EOTF` 0=SDR、1=HDR、2=HDR10;`DPTimingModeId` = 当前 timing 的 ID;刷新率用 `VerticalAttributes.PreciseSyncRate`/65536。
- "当前模式"指示:读 `~/Library/Preferences/ByHost/com.apple.windowserver.displays.*.plist` 的 `DisplaySets.Configs[*].DisplayConfig[*].LinkDescription`(Range/BitDepth/EOTF/PixelEncoding),按 `UUID` 与 CG 显示器匹配;`CGDisplayCreateUUIDFromDisplayID` 在当前系统由 **SkyLight** 导出(非 CoreGraphics/CoreDisplay),经 dlsym 调用。该记录只在显示器有持久化连接配置时存在,缺失时 UI 显示"由 macOS 自动选择"。
- CG 显示器 ↔ shim 配对:`SLSCopyDisplayInfoDictionary(d)["IODisplayLocation"]` 中的 `disp0@…`/`dispextN@…` 段;显示名取 `CoreDisplay_DisplayCreateInfoDictionary(d)["DisplayProductName"]`(本地化字典,取 zh_CN/en_US)。
- **连接模式的直接读/写通道未破解且已排除**:不属于 CGS mode API(`CGSConfigureDisplayMode`/mode 描述均不编码连接模式,实测切换无关联)、不写任何 IORegistry 属性(全树 diff + 高频轮询 + 反汇编调用点证实)、`SLSDisplay*Preset*` 家族实测返回 0/-1 与本功能无关、`IOMobileFramebufferUserClient` selector 空输入全被拒。BetterDisplay 的写通道为其闭源实现,本项目不复刻。
- `SLSDetectDisplays()`(无参)可触发显示器重新检测;显示器睡眠期间相关读取会失败,唤醒后恢复。
- CGS 私有签名(macOS 27 实测):`CGSGetNumberOfDisplayModes(display,&n)`、`CGSGetCurrentDisplayMode(display,&id)`、`CGSGetDisplayModeDescriptionOfLength(display,idx,buf,0xD4)`、`CGSConfigureDisplayMode(config,display,modeID)`(需 `SLSMainConnectionID()` 先初始化连接)。

## 版本与发布

- 营销版本 `主版本.次版本`(当前 1.0),CFBundleVersion 从 1 递增;无三段 SemVer 需求时不引入。
- 默认本地构建交付;git 提交用英文 Conventional Commits,未获明确授权不 push、不发 Release。

## 已知限制

- "当前连接模式"无法独立读取(闭源);UI 展示当前 timing + 驱动偏好排序的模式列表,默认不选中。
- EDID 改写需 sudo 安装并重新插拔显示器;个别 YCbCr 4:2:0 模式可能来自 EDID 之外的来源,装后实测确认。
- Redmi 27 NU 的 `DPTimingModeId` 在链路折腾后可能暂缺,fallback 用最高分 timing;重新插拔显示器后恢复。
