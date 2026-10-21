# FuyaoColorLock 项目规则

## 定位与边界

- 本项目是 macOS 菜单栏工具,通过 BetterDisplay 免费版 CLI 锁定外接显示器的连接色彩模式(像素格式),自动纠正 macOS 的重置;附带的 `scripts/patch-edid.py` 提供一次性 EDID 改写(去 YCbCr)。
- 依赖但不捆绑 BetterDisplay:默认 CLI 路径 `/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay`,可通过 UserDefaults 键 `cli.path` 覆盖。
- 不引入第三方依赖,只用系统框架(AppKit、SwiftUI、CoreGraphics、ServiceManagement)。

## 构建与验证

- 构建命令:`scripts/build-app.sh`,产物 `build/FuyaoColorLock.app`(arm64,macOS 13.0 起)。脚本内工具路径一律经 `xcrun` 动态解析,不得硬编码本机 Xcode 路径。
- 修改守护逻辑后的最小验证:启动 app,用 BetterDisplay CLI 把目标显示器切到错误模式,确认 15 秒内自动恢复(实测正常约 4–6 秒);恢复检查用 `get -name=<显示器> -connectionMode`。
- `get -identifiers` 输出为逗号分隔的多个 pretty JSON 对象,解析时按 `},{` 分割,过滤 `deviceType != "Display"`;`get -connectionMode` 单行输出形如 `<id> - <w>x<h> <rr>Hz Fixed <desc>`,匹配用描述子串(如 `8bit SDR RGB Full`)。
- EDID 脚本改动后用 `plutil -lint` 校验产物 plist,并核对 CEA flags 与校验和;override plist 的 `IODisplayEDID` 必须是 base64 `<data>`。

## 技术事实(逆向结论,勿重复调研)

- 连接色彩模式的选项来源:IORegistry `IOMobileFramebufferShim` 节点 `TimingElements → ColorModes`(字段 Depth/PixelEncoding/Colorimetry/DynamicRange/EOTF)。
- 切换连接色彩模式不经过 CGS display mode API(`CGSConfigureDisplayMode`),也不写任何 IORegistry 属性;BetterDisplay 闭源实现走 IOKit 私有通道,本项目不复刻,统一通过其 CLI。
- `SLSDisplay*Preset*` 系列函数实测与本功能无关(返回 0/-1),勿再尝试。

## 版本与发布

- 营销版本 `主版本.次版本`(当前 1.0),Info.plist 的 CFBundleVersion 从 1 递增;无特殊 SemVer 需求时不引入三段版本。
- 默认本地构建交付;git 提交按 Conventional Commits(英文),未获明确授权不 push、不发 Release。

## 已知限制

- 锁定目标为单台显示器、单一预设;事件驱动 + 15 秒轮询,非毫秒级。
- EDID 改写需要 sudo 安装并重新插拔显示器;个别 YCbCr 4:2:0 模式可能来自 EDID 之外的来源,由守护兜底。
