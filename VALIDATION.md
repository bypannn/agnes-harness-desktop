# 验证记录

日期：2026-11-02（Asia/Shanghai）。

环境：macOS 26.6.2（25G83），arm64；Swift 6.4；Node v24.20.0；pnpm 10.34.5。

上游固定提交：`43085b2bc2dfa519dd39b78e67224cb1f0d36320`。

## 构建和分发

- 官方 `tools/toolchain/run.mjs install --frozen-lockfile` 和 `--filter @agnes/cli build:local` 通过。使用工作目录内的独立 Node 和固定 pnpm，工具链自检通过，未修改全局环境。上游工作区未做代码修改。
- `build.py` 通过。应用和内置 Node 均为 arm64；应用体积约 296 MiB。
- `codesign --verify --deep --strict` 对输出应用和只读安装镜像中的应用均通过。ad-hoc 签名，未公证。
- `hdiutil verify` 通过。只读挂载后直接运行镜像中的应用成功，健康检查返回 `{"status":"ok"}`，界面恢复原 Demo 会话。
- 两个 JavaScript 文件的 `node --check` 通过；Python 源码解析通过；桌面主程序编译通过。

## 界面实测

中文配置向导、本地 Demo、原生文件夹面板并返回所选路径、中文粘贴与发送、收到 Demo 回复、重命名会话、退出并重开。首次配置完成状态、会话名称和消息保留。测试未调用真实模型，也未使用 API Key。

## 生命周期测试

最终打包应用的测试结果：

```text
test_boot_health_shutdown_and_persistence ... ok
test_occupied_saved_port_and_corrupt_preferences ... ok
test_parent_crash_stops_web_and_daemon ... ok
test_quit_during_startup_cleans_backend ... ok
test_start_failure_reports_error_and_exits ... ok

Ran 5 tests in 37.757s
OK
```

覆盖启动与健康检查、正常停止、重启后的工作文件和端口保留、端口占用、损坏的端口偏好、运行入口缺失、启动后不同时间点退出，以及父进程被强制结束后的 Web 和 daemon 清理。所有测试使用隔离临时目录。

未实测：macOS 13—25、Intel Mac、Windows、Linux、真实模型、语音、全部第三方插件与长期运行。

## 签名公证准备（同日追加）

本机签名身份检查为 `0 valid identities found`，用户确认尚未加入 Apple Developer Program，因此未申请证书，未提交 Apple 公证。

在工作目录内创建独立测试副本，按内层到外层逐项 ad-hoc 签署全部 10 个 Mach-O 文件，并启用 Hardened Runtime。审核结果：10 个均有 runtime 标志；没有 get-task-allow 调试权限。Node 仅保留 JIT 和原生库加载权限。V8 计算测试及 sharp/libvips 原生 PNG 编码通过。

该 Hardened Runtime 副本再次运行全部 5 组生命周期测试：全部通过，耗时 38.294 秒。签名脚本在没有有效 Developer ID 证书时拒绝正式签署，且未创建目标应用。Python 语法检查通过。

这些是本地预演结果，不能代替 Developer ID 正式签名、Apple 公证通过回执、票据装订或最终 Gatekeeper 评估。原有应用和 DMG 未被替换。
