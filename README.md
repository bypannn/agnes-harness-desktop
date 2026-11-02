# Agnes Harness Desktop

独立的 macOS 桌面封装，基于 AgnesAI-Labs/agnes-harness 的完整源码构建。保留官方 Web 工作台、会话、插件、模型设置、审批与轨迹功能，用 AppKit + WKWebView 提供桌面窗口和后台生命周期管理。

**当前采用未公证预览版分发。** 下载 DMG 后拖入“应用程序”即可安装；首次打开可能被 macOS 拦截。详细步骤见 [小白安装指南](INSTALL.md)。

[下载 macOS Apple Silicon 预览版](https://github.com/bypannn/agnes-harness-desktop/releases/download/v0.1.0-preview/Agnes-Harness-Desktop-0.1.0-macOS-arm64.dmg) · [发布说明](RELEASE_NOTES.md)

当前版本：0.1.0，本地预览版。适用于 Apple Silicon Mac。构建目标为 macOS 13 及以上，实际验证环境为这台 Mac 的 macOS 26；未实测其他系统版本和 Intel Mac。不是 Agnes AI 官方发行版。

正式签名与 Apple 公证的准备进度和可选后续操作见 [签名与公证说明](signing/README.md)。本次发布不依赖 Apple 付费开发者会员。

## 使用

1. 打开 `Agnes-Harness-Desktop-0.1.0-macOS-arm64.dmg`，将 `Agnes Harness.app` 拖到“应用程序”。也可以直接打开同目录提供的 `.app`。
2. 双击应用。Node.js 24.20.0、完整 Agnes 运行包、原生辅助程序和 Web 资源已内置，无需安装 Node 或 pnpm，也无需打开终端。
3. 首次打开可选择本地 Demo，或在“设置 → 模型”中连接自己的模型账户。Demo 只提供确定性的本地演示，不进行真实推理。
4. 选择工作文件夹后开始任务。真实模型请求需要你自己的账户，费用按相应模型服务的规则结算。

点击窗口关闭按钮会隐藏主窗口，后台继续运行。可通过菜单栏的星形图标或 Dock 重新打开。`⌘Q` 或菜单里的“退出 Agnes Harness”会停止本应用自己的 Web 服务和 daemon。重新启动本地服务会中断当前任务，应用会先提示确认。

本地构建使用 ad-hoc 签名，未经过 Apple 开发者签名和公证。跨机器下载后，macOS 可能要求通过系统的“隐私与安全性”设置确认打开；本包不修改系统安全设置。

## 桌面能力

- 独立窗口、Dock 图标、菜单栏入口，窗口大小与位置保存。
- 自动启动本地服务，支持停止、重启、启动错误页和运行日志。
- 同一数据目录的单实例锁；异常关闭桌面进程后，监督进程会清理自己的后台服务。
- 优先复用上次 Web 端口，保留浏览器偏好；端口被占用时自动改选。
- 原生工作文件夹面板，原生文件上传和下载保存面板。
- 复制、剪切、粘贴、全选、重新加载和页面缩放快捷键。
- 外部网页交给系统浏览器；原生桥仅提供用户选取文件夹这一项能力，仍由 Agnes 后端验证和接纳工作区。

## 数据与日志

数据位于 `~/Library/Application Support/Agnes Harness Desktop/`：

- `Home-v1/`：Agnes 的会话、账户、配置和插件。
- `Workspace/`：初始默认工作文件夹，可以在界面中改选其他目录。
- `Logs/runtime.log`：本地服务日志，超过 2 MiB 后在下次启动轮换，保留一个上一版文件。
- `Logs/launcher.log`：桌面监督进程的错误输出。
- `web-port.json`：上次使用的端口。

应用菜单提供打开数据目录、默认工作目录和日志目录的入口。日志是本机私有诊断资料，分享前请自行检查其中的路径和内容。

这个封装使用全新数据目录，不读取或迁移之前 `AgnesHarness`、`~/.agh` 等环境。应用移动到“应用程序”后，数据仍保留在上述目录。

## 验证与限制

已在这台 Mac 上实测：中文首次配置、选择 Demo、原生文件夹选择、发送中文消息并收到本地 Demo 回复、正常退出、重开后恢复原会话。运行包的 doctor 检查中，Node、原生助手、数据目录、文件权限、凭据存储、命令沙箱、daemon 连接、插件完整性和 MCP 隔离通过；新环境没有真实模型账户属于预期提示。

自动化生命周期测试覆盖：启动与健康检查、正常退出、工作文件保留与端口复用、端口冲突、损坏的端口偏好文件、运行入口缺失、启动过程中退出、父进程被强制结束后的 Web 与 daemon 清理。

未验证真实付费模型、语音与设备权限、全部第三方插件、所有下载文件类型和长期无人值守运行。没有自动更新；Windows 和 Linux 桌面安装包未制作。Agnes 上游仍是开发者预览版，其功能边界和安全策略保持上游实现。

## 来源与构建

- 上游：<https://github.com/AgnesAI-Labs/agnes-harness>
- 固定提交：`43085b2bc2dfa519dd39b78e67224cb1f0d36320`
- 构建 Node：`24.20.0`；pnpm：`10.34.5`。
- 应用资源内的 `BUILD.json` 记录版本信息，`AGNES-LICENSE.txt`、`AGNES-NOTICE.txt`、`NODE-LICENSE.txt` 和运行包中的 `THIRD-PARTY-NOTICES/` 保留许可信息。

先按上游安装指南构建固定提交的 `packages/cli/dist/local/`，准备官方 Node.js 24.20.0 的 macOS arm64 完整解压目录，然后运行：

```sh
python3 build.py \
  --upstream /absolute/path/to/agnes-harness \
  --node /absolute/path/to/node-v24.20.0-darwin-arm64 \
  --output '/absolute/path/to/Agnes Harness.app'
```

构建脚本需要 Xcode Command Line Tools，且不会覆盖已存在的目标应用。它不会修改全局 Node、pnpm 或 shell 设置。桌面源码在 `Sources/`，生命周期测试在 `tests/lifecycle.py`：

```sh
AGNES_TEST_APP='/absolute/path/to/Agnes Harness.app' python3 tests/lifecycle.py
codesign --verify --deep --strict '/absolute/path/to/Agnes Harness.app'
```

测试使用隔离临时目录及本地服务，不需要 API Key，不调用外部模型。
