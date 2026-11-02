import AppKit
import WebKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandlerWithReply {
    var window: NSWindow!
    var web: WKWebView!
    var statusItem: NSStatusItem!
    var supervisor: Process?
    var inputPipe: Pipe?
    var currentURL: URL?
    var eventBuffer = Data()
    var terminating = false
    var restarting = false
    var lockFD: Int32 = -1
    var startupError: String?
    var folderPanel: NSOpenPanel?
    let fm = FileManager.default
    lazy var root: URL = {
        if let override = ProcessInfo.processInfo.environment["AGNES_DESKTOP_TEST_ROOT"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Agnes Harness Desktop", isDirectory: true)
    }()
    lazy var backendHome = root.appendingPathComponent("Home-v1", isDirectory: true)
    lazy var logs = root.appendingPathComponent("Logs", isDirectory: true)
    lazy var workspace = root.appendingPathComponent("Workspace", isDirectory: true)

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            for url in [root, logs, workspace] {
                try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            }
            lockFD = Darwin.open(root.appendingPathComponent("desktop.lock").path, O_CREAT | O_RDWR, 0o600)
            guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
                for app in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "") where app.processIdentifier != getpid() {
                    app.activate(options: [.activateAllWindows])
                }
                NSApp.terminate(nil)
                return
            }
            _ = fcntl(lockFD, F_SETFD, FD_CLOEXEC)
            makeMenus()
            makeWindow()
            startRuntime()
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法创建 Agnes 的运行目录"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func menuItem(_ title: String, _ action: Selector?, _ key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
    func makeMenus() {
        let main = NSMenu()
        let app = NSMenu()
        app.addItem(menuItem("关于 Agnes Harness Desktop", #selector(about)))
        app.addItem(.separator())
        app.addItem(menuItem("显示主窗口", #selector(showWindow), "0"))
        app.addItem(menuItem("重新启动本地服务…", #selector(restartRuntime)))
        app.addItem(menuItem("在浏览器中打开", #selector(openBrowser)))
        app.addItem(.separator())
        app.addItem(menuItem("打开运行日志", #selector(openLogs)))
        app.addItem(menuItem("打开数据目录", #selector(openData)))
        app.addItem(menuItem("打开默认工作目录", #selector(openWorkspace)))
        app.addItem(.separator())
        app.addItem(menuItem("隐藏 Agnes Harness", #selector(hideApp), "h"))
        app.addItem(menuItem("退出 Agnes Harness", #selector(quitApp), "q"))
        let appRoot = NSMenuItem(); appRoot.submenu = app; main.addItem(appRoot)
        let edit = NSMenu(title: "编辑")
        for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        let editRoot = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""); editRoot.submenu = edit; main.addItem(editRoot)
        let view = NSMenu(title: "显示")
        view.addItem(menuItem("重新加载工作台", #selector(reload), "r"))
        view.addItem(menuItem("放大", #selector(zoomIn), "+"))
        view.addItem(menuItem("缩小", #selector(zoomOut), "-"))
        view.addItem(menuItem("实际大小", #selector(resetZoom), "1"))
        let viewRoot = NSMenuItem(title: "显示", action: nil, keyEquivalent: ""); viewRoot.submenu = view; main.addItem(viewRoot)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(NSMenuItem(title: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        let winRoot = NSMenuItem(title: "窗口", action: nil, keyEquivalent: ""); winRoot.submenu = windowMenu; main.addItem(winRoot)
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Agnes Harness")
        let status = NSMenu()
        status.addItem(menuItem("显示 Agnes Harness", #selector(showWindow)))
        status.addItem(menuItem("打开运行日志", #selector(openLogs)))
        status.addItem(.separator())
        status.addItem(menuItem("退出", #selector(quitApp)))
        statusItem.menu = status
    }
    func makeWindow() {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.websiteDataStore = .default()
        // This bridge only returns a user-selected folder. Backend workspace admission is unchanged.
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "agnesFolderPicker")
        if let url = Bundle.main.url(forResource: "desktop-picker", withExtension: "js"), let script = try? String(contentsOf: url, encoding: .utf8) {
            config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        if #available(macOS 13.3, *) { web.isInspectable = ProcessInfo.processInfo.environment["AGNES_DESKTOP_INSPECT"] == "1" }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1320, height: 860), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Agnes Harness"
        window.minSize = NSSize(width: 900, height: 620)
        window.contentView = web
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("AgnesDesktopMain")
        window.center()
        showWindow()
    }
    func showState(_ title: String, _ detail: String, error: Bool = false) {
        let escaped = detail.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        web.loadHTMLString("""
        <!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><style>
        :root{color-scheme:light dark}*{box-sizing:border-box}body{margin:0;font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#faf9f6;color:#202422;display:grid;place-items:center;height:100vh}.wrap{width:480px;padding:48px}.mark{width:62px;height:62px;border-radius:19px;background:#254d3e;color:#faf9f6;display:grid;place-items:center;font-size:34px;font-weight:500;margin-bottom:30px}h1{font-size:27px;letter-spacing:-.6px;font-weight:600}p{font-size:14px;line-height:1.8;color:#6d746f}.line{height:3px;width:96px;background:#e2e8e2;margin-top:28px;border-radius:3px;overflow:hidden}.line:after{content:'';display:block;width:35%;height:100%;background:#52745b;animation:load 1.3s infinite ease-in-out}@keyframes load{from{transform:translateX(-100%)}to{transform:translateX(400%)}}footer{margin-top:42px;font-size:11px;letter-spacing:2px;color:#92988f}@media(prefers-color-scheme:dark){body{background:#1a1e1b;color:#e4e9e2}p{color:#a2aca2}.line{background:#303a32}}
        </style><div class="wrap"><div class="mark">a</div><h1>\(title)</h1><p>\(escaped)</p>\(error ? "" : "<div class='line'></div>")<footer>AGNES HARNESS DESKTOP</footer></div></html>
        """, baseURL: nil)
    }
    func startRuntime() {
        guard supervisor == nil, !terminating else { return }
        currentURL = nil
        startupError = nil
        eventBuffer.removeAll()
        showState("正在打开 Agnes", "正在准备本地工作台。首次启动需要稍等片刻。")
        guard let resources = Bundle.main.resourceURL else { return }
        let proc = Process()
        proc.executableURL = resources.appendingPathComponent("node/bin/node")
        proc.arguments = [resources.appendingPathComponent("supervisor.mjs").path]
        proc.currentDirectoryURL = workspace
        var env = ProcessInfo.processInfo.environment
        for key in ["NODE_OPTIONS", "NODE_PATH", "AGH_HOME", "AGNES_HOME", "AGNES_PROFILE", "AGNES_DATA_DIR", "AGNES_WEB_ORIGIN", "AGNES_DESKTOP_RUNTIME"] { env.removeValue(forKey: key) }
        env["AGNES_DESKTOP_HOME"] = backendHome.path
        env["AGNES_DESKTOP_LOGS"] = logs.path
        env["AGNES_DESKTOP_WORKSPACE"] = workspace.path
        env["AGNES_DESKTOP_PARENT_PID"] = String(getpid())
        proc.environment = env
        let output = Pipe(); let input = Pipe()
        proc.standardOutput = output; proc.standardInput = input
        let errorURL = logs.appendingPathComponent("launcher.log")
        if !fm.fileExists(atPath: errorURL.path) { fm.createFile(atPath: errorURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
        let errorHandle = try? FileHandle(forWritingTo: errorURL)
        _ = try? errorHandle?.seekToEnd()
        proc.standardError = errorHandle ?? FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async { self?.consume(data) }
        }
        proc.terminationHandler = { [weak self] ended in
            DispatchQueue.main.async {
                guard let self = self, self.supervisor === ended else { return }
                self.supervisor = nil
                self.inputPipe = nil
                try? errorHandle?.close()
                if self.terminating { NSApp.reply(toApplicationShouldTerminate: true) }
                else if self.restarting { self.restarting = false; self.startRuntime() }
                else if self.startupError == nil {
                    self.showState("本地服务已停止", "从 Agnes Harness 菜单选择「重新启动本地服务」，或打开运行日志查看原因。", error: true)
                }
            }
        }
        supervisor = proc; inputPipe = input
        do { try proc.run() } catch {
            supervisor = nil
            output.fileHandleForReading.readabilityHandler = nil
            try? errorHandle?.close()
            showState("无法打开运行环境", error.localizedDescription, error: true)
        }
    }
    func consume(_ data: Data) {
        eventBuffer.append(data)
        if eventBuffer.count > 262144 { eventBuffer.removeAll(); return }
        while let range = eventBuffer.range(of: Data([10])) {
            let line = eventBuffer.subdata(in: 0..<range.lowerBound)
            eventBuffer.removeSubrange(0..<range.upperBound)
            guard let value = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let type = value["type"] as? String else { continue }
            if type == "ready", !terminating, let raw = value["url"] as? String, let url = URL(string: raw), url.scheme == "http", url.host == "127.0.0.1", url.port != nil {
                currentURL = url
                web.load(URLRequest(url: url))
                statusItem.button?.toolTip = "Agnes Harness · 运行中"
            } else if type == "error", !terminating {
                startupError = value["message"] as? String ?? "请查看运行日志。"
                currentURL = nil
                showState("需要检查本地服务", startupError!, error: true)
                statusItem.button?.toolTip = "Agnes Harness · 服务已停止"
            }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard supervisor != nil else { return .terminateNow }
        if terminating { return .terminateLater }
        terminating = true
        folderPanel?.cancel(nil)
        showState("正在退出 Agnes", "正在停止本地服务并保存状态。")
        try? inputPipe?.fileHandleForWriting.write(contentsOf: Data("stop\n".utf8))
        try? inputPipe?.fileHandleForWriting.close()
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        if lockFD >= 0 { flock(lockFD, LOCK_UN); Darwin.close(lockFD) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); return false }
    @objc func showWindow() { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func hideApp() { NSApp.hide(nil) }
    @objc func quitApp() { NSApp.terminate(nil) }
    @objc func openBrowser() { if let url = currentURL { NSWorkspace.shared.open(url) } }
    @objc func openLogs() { NSWorkspace.shared.open(logs) }
    @objc func openData() { NSWorkspace.shared.open(root) }
    @objc func openWorkspace() { NSWorkspace.shared.open(workspace) }
    @objc func reload() { if currentURL != nil { web.reload() } }
    @objc func zoomIn() { web.pageZoom = min(web.pageZoom + 0.1, 2) }
    @objc func zoomOut() { web.pageZoom = max(web.pageZoom - 0.1, 0.6) }
    @objc func resetZoom() { web.pageZoom = 1 }
    @objc func restartRuntime() {
        guard !terminating, !restarting else { return }
        if supervisor == nil { startRuntime(); return }
        let alert = NSAlert()
        alert.messageText = "重新启动本地服务？"
        alert.informativeText = "正在执行的任务会被中断，已保存的会话和设置会保留。"
        alert.addButton(withTitle: "重新启动"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        restarting = true
        currentURL = nil
        showState("正在重新启动", "正在停止当前服务，随后重新打开工作台。")
        try? inputPipe?.fileHandleForWriting.write(contentsOf: Data("stop\n".utf8))
    }
    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Agnes Harness Desktop", .applicationVersion: "0.1.0", .credits: NSAttributedString(string: "独立桌面封装 · AgnesAI-Labs/agnes-harness\n内置 Node.js 24.20.0 · Apache-2.0\n非 Agnes AI 官方发行版。")])
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if url.absoluteString == "about:blank" { decisionHandler(.allow); return }
        if let current = currentURL, url.scheme == current.scheme, url.host == current.host, url.port == current.port {
            decisionHandler(action.shouldPerformDownload ? .download : .allow); return
        }
        if url.scheme == "blob", action.shouldPerformDownload { decisionHandler(.download); return }
        if action.navigationType == .linkActivated || action.targetFrame == nil {
            if ["https", "http", "mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
        }
        decisionHandler(.cancel)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, ["https", "http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
        return nil
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(response.canShowMIMEType ? .allow : .download)
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = (suggestedFilename as NSString).lastPathComponent
        panel.beginSheetModal(for: window) { result in completionHandler(result == .OK ? panel.url : nil) }
    }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories; panel.canChooseFiles = true
        panel.beginSheetModal(for: window) { result in completionHandler(result == .OK ? panel.urls : nil) }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, let url = currentURL,
              message.frameInfo.securityOrigin.protocol == url.scheme,
              message.frameInfo.securityOrigin.host == url.host,
              message.frameInfo.securityOrigin.port == url.port,
              let body = message.body as? [String: String] else {
            replyHandler(nil, "Origin rejected"); return
        }
        if body["action"] == "cancel" { folderPanel?.cancel(nil); replyHandler(["status": "cancelled"], nil); return }
        guard body["action"] == "pick", folderPanel == nil, !terminating else {
            replyHandler(["status": "unavailable"], nil); return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = "选择工作文件夹"; panel.directoryURL = workspace
        folderPanel = panel
        showWindow()
        panel.beginSheetModal(for: window) { [weak self] result in
            self?.folderPanel = nil
            if result == .OK, let url = panel.url { replyHandler(["status": "selected", "path": url.path], nil) }
            else { replyHandler(["status": "cancelled"], nil) }
        }
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert(); alert.messageText = message; alert.beginSheetModal(for: window) { _ in completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert(); alert.messageText = message; alert.addButton(withTitle: "确定"); alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { result in completionHandler(result == .alertFirstButtonReturn) }
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        if let url = currentURL, origin.host == url.host, origin.port == url.port { decisionHandler(.prompt) }
        else { decisionHandler(.deny) }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { if currentURL != nil { webView.reload() } }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled && !terminating {
            showState("工作台暂时无法连接", "可使用「显示 → 重新加载工作台」，或重新启动本地服务。", error: true)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
