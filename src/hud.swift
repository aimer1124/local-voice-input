import Cocoa

// 用法: hud <message> [duration_seconds]
let args = CommandLine.arguments
guard args.count >= 2 else {
    print("Usage: hud <message> [duration]")
    exit(1)
}
let message = args[1]
let duration = args.count >= 3 ? (Double(args[2]) ?? 2.0) : 2.0

// 杀掉上一个 HUD 实例（如果有），避免叠加
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

    init(message: String, duration: Double) {
        self.message = message
        self.duration = duration
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 多屏支持：选鼠标光标所在的屏幕作为"当前屏"
        let mouseLocation = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
        guard let screen = activeScreen else { exit(1) }
        let screenFrame = screen.frame

        let font = NSFont.systemFont(ofSize: 26, weight: .semibold)
        let textSize = (message as NSString).size(withAttributes: [.font: font])
        let padding: CGFloat = 60
        let windowWidth = min(max(textSize.width + padding, 220), 900)
        let windowHeight: CGFloat = 96

        // 中下方：水平居中、垂直距屏幕底部 18%
        let originX = screenFrame.minX + (screenFrame.width - windowWidth) / 2
        let originY = screenFrame.minY + screenFrame.height * 0.18

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
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 20
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

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                self.window.animator().alphaValue = 0
            }, completionHandler: {
                NSApp.terminate(nil)
            })
        }
    }
}

let delegate = HUDDelegate(message: message, duration: duration)
app.delegate = delegate
app.run()
