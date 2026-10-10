# MouseGesture

macOS 原生右键鼠标手势工具。按住鼠标右键绘制直线或折线，松开后执行对应操作。

采用 Swift、SwiftUI、AppKit 和 Core Graphics，支持 macOS 13 及以上；提供 Intel `x86_64` 与 Apple Silicon `arm64` 的 Universal 打包脚本，无第三方运行时依赖。

## 第一版功能

| 默认轨迹 | 操作 |
| --- | --- |
| ← | 左侧桌面 |
| → | 右侧桌面 |
| ↓ | 显示桌面 |
| ↑ | 调度中心 |
| ↓ → | 关闭当前标签页 / 文稿（默认 ⌘ W） |
| ↓ ← | 关闭当前窗口（操作辅助功能关闭按钮） |
| ↑ →、↑ ↓ | 默认不执行，可在设置中绑定操作 |

- 菜单栏常驻，关闭设置窗口后继续工作，可随时暂停或退出。
- 八种预设轨迹可分别绑定任意内置操作；当前不支持自由录入额外轨迹形状。
- 实时轨迹和识别预览、可调最短轨迹长度、设置持久化。
- 可录制动作快捷键，适配用户修改过的系统快捷键。
- 按 Bundle ID 排除应用；按住 Option 再按右键可临时绕过手势。
- 不读取屏幕内容，不需要录屏权限，不上传鼠标轨迹，无网络请求。

## 操作说明

1. 首次打开应用后，在系统设置 → 隐私与安全性 → 辅助功能中允许 MouseGesture。
2. 授权后应用自动尝试启动监听。若仍提示无法监听，可重新授权、重启应用；若系统提示输入监控权限，也需允许。
3. 在前台应用中按住右键，画出表格中的轨迹，松开执行。
4. 普通右键点击在松开时补发，保留右键菜单。移动不足 16 点按点击处理；超过 16 点会作为手势接管，但只有达到设置的最短长度并识别成功才执行。
5. 绘制中按 Esc 或其他键、按鼠标左键可取消。斜线、未绑定和无法识别的轨迹不会执行动作，也不会弹出菜单。
6. 需要原生右键拖拽（如游戏、3D 软件、部分右键菜单拖选）时，先按住 Option 再按右键，或排除该应用。

操作作用于开始绘制时的前台应用，而不是鼠标所指的后台窗口。绘制或执行前发现前台应用改变会取消操作。关闭标签页使用应用的快捷键，无标签页的应用可能关闭文稿或窗口；未保存文稿的确认框由目标应用保留。

## 系统快捷键

默认发送：显示桌面 `F11`，左右桌面 `Control + ← / →`，调度中心 `Control + ↑`，关闭标签页 `Command + W`。

请确保系统设置 → 键盘 → 键盘快捷键 → 调度中心中的对应快捷键已开启，并与本应用一致。可以点击本应用设置中的快捷键按钮重新录制。系统会优先处理部分全局快捷键；若无法录入，可先临时关闭系统对应快捷键，录制完成后重新开启。

左右切换需要已有至少两个桌面；边缘桌面不会循环。应用仅发送快捷键，无法确认系统或目标应用是否完成操作，因此状态显示“已发送”。关闭窗口使用公开的辅助功能 API，未暴露关闭按钮的应用会提示无法关闭。

## 开发和验证

需要 macOS、Xcode 15 或更新版本及 Command Line Tools。没有 Node.js / npm 依赖。

```bash
# 仅运行纯识别逻辑测试、双架构类型检查，不构建或启动应用
bash scripts/check.sh

# 在 Xcode 中打开 Swift Package
open Package.swift
```

`scripts/check.sh` 使用 Swift 解释器执行 `Tests/GestureCoreTests.swift`，覆盖方向、折线、往返、斜线拒绝、抖动、最小长度、多显示器负坐标、普通点击、取消和采样上限，再分别以 macOS 13 为部署目标对两个架构检查类型。

项目默认不主动构建应用。需要可运行 `.app` 时，显式执行：

```bash
bash scripts/package.sh
open dist/MouseGesture.app
```

输出 `dist/MouseGesture.app` 和 `dist/MouseGesture-universal.zip`，脚本会检查二进制包含 `arm64` 和 `x86_64` 两个架构。建议把 `.app` 固定放在 `/Applications` 再授权，避免移动应用导致权限失效。

默认本地 ad-hoc 签名，未经过 Apple 公证。拥有 Developer ID 时，可设置 `SIGNING_IDENTITY` 后打包；公证需自行配置 Apple 开发者凭据。下载分发版本可能触发 Gatekeeper 检查，不能将本地签名等同于公证。

GitHub Actions 在 push / PR 时只运行检查。手动运行“检查与打包”工作流才会生成可下载的 Universal ZIP；不自动创建 Release。

## 架构

```text
Sources/GestureCore/           纯手势识别和笔画状态
Sources/MouseGesture/         菜单栏、设置、事件监听、轨迹、动作执行
Resources/Info.plist          应用元数据
Tests/                       无系统操作的识别测试
scripts/check.sh              逻辑测试与双架构类型检查
scripts/package.sh            显式 Universal 打包
```

事件处理：右键按下 → 暂存原始事件 → 采样轨迹 → 松开 → 补发普通点击或执行已识别操作。补发事件带有来源标记，避免再次进入识别流程。绘制预览限流到约 60 FPS，单次最多保留 2048 个采样点，超限取消。

## 验收范围

自动检查不代替实际鼠标、系统权限和双架构真机验证。发布前请完成 [手动验收清单](docs/manual-testing.md)。特别需要验证普通右键菜单、多个显示器与全屏空间、系统快捷键、不同应用的窗口关闭行为，以及休眠恢复。

## 技术依据

- [Apple：CGEvent 事件监听接口](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:))
- [Apple：Universal macOS 二进制](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary)
- [Apple：在多个空间中工作](https://support.apple.com/zh-cn/guide/mac-help/mh14112/mac)

## License

MIT
