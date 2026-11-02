# 签名和公证：当前进度与后续步骤

用户已注册免费 Apple 开发者账号，尚未加入付费 Apple Developer Program，也没有本机可用的 Developer ID Application 签名身份。**按用户选择，本次通过 GitHub 分发未公证预览版；没有提交 Apple 公证。**

已准备内部程序与动态库逐项签名、Hardened Runtime 权限、签名审核、公证提交、状态查询、获取 Apple 日志和票据装订脚本。现有可用应用不会被覆盖；签名流程只处理指定的新副本。

## 可选：以后再进行正式签名公证

现阶段无需为发布当前预览包购买会员。如果以后决定提供正式签名和公证版，再打开 [Apple 中文会员注册页](https://developer.apple.com/cn/programs/enroll/)，根据实际情况选择以个人或组织身份注册。完成 Apple 账户登录、双重认证、身份验证、协议和付款，等待会员生效。

Apple 公布的年费是 99 美元，地区价格以注册页面显示的当地货币为准。账号信息、协议及付款由你本人处理。不要在聊天中发送密码、验证码或证书私钥。

会员生效后，在本聊天告诉我“开发者会员已生效”，后续再继续证书和正式公证。

## 会员生效后的流程

1. 按 Apple [Developer ID 证书指南](https://developer.apple.com/help/account/certificates/create-developer-id-certificates) 在本机生成 CSR，申请并安装 **Developer ID Application** 证书。此应用通过 DMG 分发，不需要 Developer ID Installer 证书。私钥保留在本机钥匙串。
2. 用 `security find-identity -v -p codesigning` 确认可以找到有效证书及其 40 位 SHA-1 标识。
3. 在你自己的终端运行 `xcrun notarytool store-credentials AgnesHarnessNotary`，按交互提示配置 Apple 公证认证。密码通过本机交互输入，保存到钥匙串。不要把密码写入脚本或聊天。
4. 我继续在副本上签名、验证、提交 Apple，审核公证结果，通过后装订票据并生成新的 DMG。

## 技术流程

在桌面源码目录中执行。下列绝对路径和证书标识是需要替换的占位符，不要原样运行：

```sh
python3 signing/release.py sign \
  --source '/absolute/path/to/Agnes Harness.app' \
  --destination '/absolute/path/to/release/Agnes Harness.app' \
  --identity YOUR_40_CHARACTER_SIGNING_IDENTITY
```

脚本只接受钥匙串中有效的 Developer ID Application 身份，按内层到外层逐项签署全部 Mach-O 文件，启用 Hardened Runtime 与安全时间戳，最后验证整个应用。不会用 `codesign --deep` 代替逐项签署。Node 单独授予 JIT 和原生插件加载需要的权限；不会保留 `get-task-allow` 调试权限。

把签名后的应用压缩为 ZIP：

```sh
ditto -c -k --sequesterRsrc --keepParent \
  '/absolute/path/to/release/Agnes Harness.app' \
  '/absolute/path/to/release/Agnes-Harness-signed.zip'

python3 signing/release.py submit \
  --file '/absolute/path/to/release/Agnes-Harness-signed.zip' \
  --profile AgnesHarnessNotary --receipt '/absolute/path/to/release/notary-app.json'
```

提交后保存 Apple 返回的 submission ID。脚本不会重复使用已有回执路径，避免意外重复提交。查询状态：

```sh
python3 signing/release.py status \
  --profile AgnesHarnessNotary --receipt '/absolute/path/to/release/notary-app.json'
```

状态为 Accepted 后装订到原来提交的签名应用：

```sh
python3 signing/release.py staple \
  --target '/absolute/path/to/release/Agnes Harness.app' \
  --profile AgnesHarnessNotary --receipt '/absolute/path/to/release/notary-app.json'
```

脚本先确认 Apple 已接受该回执，再下载 Apple 日志，装订并验证票据，最后进行 Gatekeeper 评估。如日志有警告，需要审阅后再发布。

随后用这个**已装订应用**重新制作 DMG，用同一 Developer ID Application 身份签署 DMG。再对最终 DMG 执行一轮 `submit → status → staple`，使用单独的 `notary-dmg.json` 回执。最终验证应用和 DMG 的票据以及 Gatekeeper 结果，并在签名完成后重新运行启动测试。

完成所有签署和装订后再计算最终 SHA-256；此后不要修改应用内的文件。

## 本机预演

`sign --local-test` 仅用于工作目录中的副本，使用 ad-hoc 签名测试 Hardened Runtime 和权限兼容性。它不能生成可通过 Apple 公证的正式签名，也不能代替公证结果。正式提交前必须使用 Developer ID 证书重新签署。

Apple 官方参考：[公证要求](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)、[命令行流程](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)。
