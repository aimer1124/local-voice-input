import Cocoa

// 用法: hud <message> [duration_seconds]
//
// 样式可通过环境变量覆盖（任意子集），未设置则用默认值：
//   HUD_Y_PERCENT      距屏幕底部百分比 (0–100, 默认 18)
//   HUD_HEIGHT         窗口高度 px (默认 96)
//   HUD_FONT_SIZE      字号 (默认 26)
//   HUD_FONT_WEIGHT    字重: ultraLight/thin/light/regular/medium/semibold/bold/heavy/black
//   HUD_CORNER_RADIUS  圆角 px (默认 20)
//   HUD_MATERIAL       毛玻璃材质: hudWindow/sidebar/popover/menu/windowBackground/
//                       headerView/sheet/titlebar/toolTip/fullScreenUI/contentBackground/
//                       underWindowBackground/underPageBackground
//   HUD_WIDTH_MIN      自适应宽度的下限 (默认 220)
//   HUD_WIDTH_MAX      自适应宽度的上限 (默认 900)
//
// 全局键盘 (#23)：
//   HUD_ON_UP_CMD      非空时注册全局 ↑ 监听；按 ↑ 时把整段 shell 通过 /bin/bash -c 启动
//                      （仅在 HUD 显示期间生效）。需要系统设置 → 隐私 → 输入监控里把
//                      hud 二进制打勾，否则首次注册会失败并打到 /tmp/vinput_debug.log。
//   HUD_ON_ESC_CMD     非空时按 ESC 先执行该命令再关闭 HUD（同样走全局监控器 + 同样的
//                      输入监控权限要求）。录音期间 vinput_bg.sh 用它实现「ESC 取消本轮」。
//   ESC 永远立即关闭 HUD（不依赖任何权限，因为 ESC 监听走的还是全局监控器，但即使
//   注册失败也不影响 HUD 本身的自动消失）。

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("Usage: hud <message> [duration]")
    exit(1)
}
let message = args[1]
let duration = args.count >= 3 ? (Double(args[2]) ?? 2.0) : 2.0

// ── 环境变量读取 ──────────────────────────────────────
let env = ProcessInfo.processInfo.environment

func envDouble(_ key: String, _ fallback: Double) -> Double {
    if let raw = env[key], !raw.isEmpty, let v = Double(raw) { return v }
    return fallback
}
func envInt(_ key: String, _ fallback: Int) -> Int {
    if let raw = env[key], !raw.isEmpty, let v = Int(raw) { return v }
    return fallback
}
func envString(_ key: String, _ fallback: String) -> String {
    if let raw = env[key], !raw.isEmpty { return raw }
    return fallback
}

let cfgYPercent      = envDouble("HUD_Y_PERCENT", 18.0)
let cfgHeight        = CGFloat(envInt("HUD_HEIGHT", 96))
let cfgFontSize      = CGFloat(envInt("HUD_FONT_SIZE", 26))
let cfgFontWeight    = envString("HUD_FONT_WEIGHT", "semibold")
let cfgCornerRadius  = CGFloat(envInt("HUD_CORNER_RADIUS", 20))
let cfgMaterial      = envString("HUD_MATERIAL", "hudWindow")
let cfgWidthMin      = CGFloat(envInt("HUD_WIDTH_MIN", 220))
let cfgWidthMax      = CGFloat(envInt("HUD_WIDTH_MAX", 900))
let cfgOnUpCmd       = envString("HUD_ON_UP_CMD", "")
let cfgOnEscCmd      = envString("HUD_ON_ESC_CMD", "")

func fontWeight(_ name: String) -> NSFont.Weight {
    switch name.lowercased() {
    case "ultralight": return .ultraLight
    case "thin":       return .thin
    case "light":      return .light
    case "regular":    return .regular
    case "medium":     return .medium
    case "semibold":   return .semibold
    case "bold":       return .bold
    case "heavy":      return .heavy
    case "black":      return .black
    default:           return .semibold
    }
}

func material(_ name: String) -> NSVisualEffectView.Material {
    switch name {
    case "hudWindow":             return .hudWindow
    case "sidebar":               return .sidebar
    case "popover":               return .popover
    case "menu":                  return .menu
    case "selection":             return .selection
    case "windowBackground":      return .windowBackground
    case "headerView":            return .headerView
    case "sheet":                 return .sheet
    case "titlebar":              return .titlebar
    case "toolTip":               return .toolTip
    case "fullScreenUI":          return .fullScreenUI
    case "contentBackground":     return .contentBackground
    case "underWindowBackground": return .underWindowBackground
    case "underPageBackground":   return .underPageBackground
    default:                      return .hudWindow
    }
}

// ── 单例机制：杀掉前一个 HUD 实例 ────────────────────
let pidFile = "/tmp/vinput_hud.pid"
if let prevStr = try? String(contentsOfFile: pidFile, encoding: .utf8),
   let prevPid = Int32(prevStr.trimmingCharacters(in: .whitespacesAndNewlines)),
   prevPid != ProcessInfo.processInfo.processIdentifier {
    kill(prevPid, SIGTERM)
}
let myPid = ProcessInfo.processInfo.processIdentifier
try? "\(myPid)".write(toFile: pidFile, atomically: true, encoding: .utf8)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

class HUDDelegate: NSObject, NSApplicationDelegate {
    let message: String
    let duration: Double
    var window: NSWindow!
    var monitor: Any?
    var dismissed = false

    init(message: String, duration: Double) {
        self.message = message
        self.duration = duration
    }

    func dismiss() {
        if dismissed { return }
        dismissed = true
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            self.window.animator().alphaValue = 0
        }, completionHandler: {
            NSApp.terminate(nil)
        })
    }

    func spawnRerun(_ cmd: String) {
        // 用 /bin/bash -c 启动；detached + 父子无 file-descriptor 继承避免管道泄漏。
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-lc", cmd]
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            FileHandle.standardError.write(
                "hud: failed to spawn rerun: \(error)\n".data(using: .utf8) ?? Data())
        }
    }

    func setupKeyboardMonitor() {
        // cfgOnUpCmd / cfgOnEscCmd 任一非空才注册监听；两者都空时不占全局监控器。
        // NSEvent.addGlobalMonitorForEvents 在没拿到 Input Monitoring 权限时返回 nil —
        // 写到 stderr（最后会被 vinput_debug.log 兜住）然后跳过，不影响 HUD 显示。
        if cfgOnUpCmd.isEmpty && cfgOnEscCmd.isEmpty { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, !self.dismissed else { return }
            switch event.keyCode {
            case 126:  // ↑
                if !cfgOnUpCmd.isEmpty {
                    self.spawnRerun(cfgOnUpCmd)
                    self.dismiss()
                }
            case 53:   // ESC
                if !cfgOnEscCmd.isEmpty {
                    self.spawnRerun(cfgOnEscCmd)
                }
                self.dismiss()
            default:
                break
            }
        }
        if monitor == nil {
            FileHandle.standardError.write(
                "hud: NSEvent.addGlobalMonitorForEvents returned nil — grant Input Monitoring permission to the hud binary in System Settings → Privacy → Input Monitoring.\n"
                .data(using: .utf8) ?? Data())
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let mouseLocation = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
        guard let screen = activeScreen else { exit(1) }
        let screenFrame = screen.frame

        let font = NSFont.systemFont(ofSize: cfgFontSize, weight: fontWeight(cfgFontWeight))
        let textSize = (message as NSString).size(withAttributes: [.font: font])
        let padding: CGFloat = 60
        let windowWidth = min(max(textSize.width + padding, cfgWidthMin), cfgWidthMax)
        let windowHeight = cfgHeight

        let originX = screenFrame.minX + (screenFrame.width - windowWidth) / 2
        let originY = screenFrame.minY + screenFrame.height * (cfgYPercent / 100.0)

        window = NSWindow(
            contentRect: NSRect(x: originX, y: originY, width: windowWidth, height: windowHeight),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))
        blur.material = material(cfgMaterial)
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = cfgCornerRadius
        blur.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: message)
        label.font = font
        label.textColor = .labelColor
        label.alignment = .center
        label.backgroundColor = .clear
        label.isBordered = false
        label.isEditable = false
        label.frame = NSRect(
            x: 24,
            y: (windowHeight - textSize.height) / 2 - 2,
            width: windowWidth - 48,
            height: textSize.height + 4
        )
        blur.addSubview(label)

        window.contentView = blur
        window.alphaValue = 0
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            window.animator().alphaValue = 1.0
        })

        setupKeyboardMonitor()

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.dismiss()
        }
    }
}

let delegate = HUDDelegate(message: message, duration: duration)
app.delegate = delegate
app.run()
