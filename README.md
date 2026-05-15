# FinderActions Finder Extension

在 Finder 目录空白处右键显示可扩展菜单（当前包含 `Open in Codex`、`Open in ClaudeCode`），点击后在该目录执行对应 CLI。

## 行为

- 仅在目录空白处显示菜单。
- 在文件/文件夹项本身右键时不显示。
- 点击后由主 App 启动 Terminal 并执行对应命令（当前支持 `codex`、`claude`）。

## 首次安装

1. 用 Xcode 打开工程：`FinderActions.xcodeproj`
2. 给两个 target 配置签名团队（Signing & Capabilities）：
   - `FinderActions`
   - `FinderActionsFinderSyncExt`
3. 在 Xcode 中 Run 一次 `FinderActions`
4. 执行：

```bash
bash /Users/leen/Desktop/OpenInCodexFinderSync/hard_reset_extension.sh
killall Finder
```

5. 在 `System Settings -> Privacy & Security -> Extensions -> Finder Extensions` 中开启扩展。

## 升级后重装

每次改代码后，Run 一次 Xcode，然后执行：

```bash
bash /Users/leen/Desktop/OpenInCodexFinderSync/hard_reset_extension.sh
killall Finder
```

## 说明

- 工程使用 Finder Sync + 主 App 协作。
- 扩展只负责把目标目录写入请求文件并拉起主 App。
- 主 App 负责向 Terminal 发送 AppleScript，并按 action 分发执行命令。
