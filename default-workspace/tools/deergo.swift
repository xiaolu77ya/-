// dsh-quickopen：全局快捷键（⌥⌘O）弹出搜索框，列出匹配的应用/文件，回车打开。
import Cocoa
import Carbon.HIToolbox

/// 优先用 App 包内置的解析器（可分发），找不到再退回开发机路径
let RESOLVER: String = {
    if let u = Bundle.main.resourceURL?.appendingPathComponent("resolve_target.py").path,
       FileManager.default.fileExists(atPath: u) { return u }
    return NSString(string: "~/Documents/deepseek-harness/default-workspace/tools/resolve_target.py").expandingTildeInPath
}()
let ROW_H: CGFloat = 44
let MAX_ROWS = 7

final class QuickPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct Hit {
    let type: String   // APP / FILE
    let path: String
    let name: String
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    var panel: QuickPanel!
    var card: NSView!
    var field: NSTextField!
    var status: NSTextField!
    var brand: NSTextField!
    var rowsBox: NSView!
    var rowViews: [NSView] = []

    var hotKeyRef: EventHotKeyRef?
    var token = 0
    var hits: [Hit] = []
    var sel = 0
    let cardW: CGFloat = 620

    @objc func onSubmitAction() { submit() }

    func installEditMenu() {
        let main = NSMenu()
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { ev in
            guard self.panel.isVisible else { return ev }
            let editor = self.field.currentEditor() as? NSTextView
            let composing = editor?.hasMarkedText() ?? false

            if ev.modifierFlags.contains(.command) {
                let key = (ev.charactersIgnoringModifiers ?? "").lowercased()
                let map: [String: Selector] = [
                    "a": #selector(NSText.selectAll(_:)),
                    "c": #selector(NSText.copy(_:)),
                    "v": #selector(NSText.paste(_:)),
                    "x": #selector(NSText.cut(_:)),
                    "z": Selector(("undo:")),
                ]
                if let sel = map[key] {
                    NSApp.sendAction(sel, to: nil, from: nil)
                    return nil
                }
            }
            if ev.keyCode == 36 || ev.keyCode == 76 {
                if composing {
                    // 拼音/组词状态：回车只上屏到输入框，不触发搜索；再按一次回车才搜索
                    return ev
                }
                self.submit()
                return nil
            }
            if ev.keyCode == 53 {
                if composing { return ev }
                self.hidePanel()
                return nil
            }
            if !composing && !self.hits.isEmpty {
                if ev.keyCode == 125 { self.moveSel(1); return nil }   // ↓
                if ev.keyCode == 126 { self.moveSel(-1); return nil }  // ↑
            }
            return ev
        }
        installEditMenu()
        buildPanel()
        registerHotKey()
        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.showPanel() }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--query"), i + 1 < CommandLine.arguments.count {
            let q = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showPanel()
                self.field.stringValue = q
                self.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
            }
        }
    }

    func buildPanel() {
        let h = headH() + 30
        panel = QuickPanel(contentRect: NSRect(x: 0, y: 0, width: cardW + 20, height: h),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let holder = NSView(frame: NSRect(x: 0, y: 0, width: cardW + 20, height: h))
        holder.wantsLayer = true
        panel.contentView = holder

        card = NSView(frame: NSRect(x: 10, y: 10, width: cardW, height: h - 20))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 0.97).cgColor
        card.layer?.cornerRadius = 16
        card.layer?.cornerCurve = .continuous
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        holder.addSubview(card)

        let deerURL = Bundle.main.resourceURL?.appendingPathComponent("deer_white.png")
        let deerImg = deerURL.flatMap { NSImage(contentsOf: $0) } ?? NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "搜索")
        if let sym = deerImg {
            let iv = NSImageView(frame: NSRect(x: 18, y: 0, width: 26, height: 26))
            iv.image = sym
            sym.isTemplate = true
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.contentTintColor = NSColor.white.withAlphaComponent(0.62)
            iv.frame.origin.y = h - 20 - 36
            card.addSubview(iv)
        }

        field = NSTextField(frame: NSRect(x: 54, y: 0, width: cardW - 54 - 64, height: 34))
        field.font = NSFont.systemFont(ofSize: 21)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = .white
        field.delegate = self
        field.target = self
        field.action = #selector(onSubmitAction)
        field.placeholderAttributedString = NSAttributedString(
            string: "搜索应用 / 文件 / 文件夹",
            attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.38),
                         .font: NSFont.systemFont(ofSize: 21)])
        card.addSubview(field)

        let keyCap = NSTextField(labelWithString: "⏎")
        keyCap.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        keyCap.textColor = NSColor.white.withAlphaComponent(0.35)
        keyCap.frame = NSRect(x: cardW - 44, y: 0, width: 20, height: 18)
        card.addSubview(keyCap)

        rowsBox = NSView(frame: NSRect(x: 0, y: 0, width: cardW, height: 0))
        card.addSubview(rowsBox)

        status = NSTextField(labelWithString: "↑↓ 选择 · 回车打开 · Esc 取消")
        status.font = NSFont.systemFont(ofSize: 11.5)
        status.textColor = NSColor.white.withAlphaComponent(0.42)
        status.frame = NSRect(x: 56, y: 0, width: cardW - 190, height: 16)
        card.addSubview(status)

        brand = NSTextField(labelWithString: "DeerGo  ⌥⌘O")
        brand.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        brand.textColor = NSColor.white.withAlphaComponent(0.28)
        brand.alignment = .right
        brand.frame = NSRect(x: cardW - 140, y: 0, width: 118, height: 16)
        card.addSubview(brand)
    }

    func headH() -> CGFloat { 62 }

    func layout(fieldHeightTotal: CGFloat, rows: Int) {
        let rowsH = CGFloat(rows) * ROW_H
        let statusH: CGFloat = 32
        let cardH = 54 + rowsH + statusH
        let totalH = cardH + 20
        let topY = panel.frame.maxY
        let f = NSRect(x: panel.frame.minX, y: topY - totalH, width: cardW + 20, height: totalH)
        panel.setFrame(f, display: true)
        panel.contentView?.frame = NSRect(x: 0, y: 0, width: cardW + 20, height: totalH)
        card.frame = NSRect(x: 10, y: 10, width: cardW, height: cardH)
        let top = cardH
        field.frame = NSRect(x: 54, y: top - 46, width: cardW - 54 - 64, height: 34)
        if let iv = card.subviews.first(where: { $0 is NSImageView }) {
            iv.frame = NSRect(x: 18, y: top - 35, width: 26, height: 26)
        }
        if let cap = card.subviews.first(where: { $0 is NSTextField && ($0 as! NSTextField).stringValue == "⏎" }) {
            cap.frame.origin.y = top - 40
        }
        rowsBox.frame = NSRect(x: 0, y: statusH - 2, width: cardW, height: rowsH)
        status.frame = NSRect(x: 56, y: 10, width: cardW - 190, height: 16)
        brand.frame = NSRect(x: cardW - 140, y: 10, width: 118, height: 16)
    }

    func showPanel() {
        let scr = NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        field.stringValue = ""
        hits = []
        sel = 0
        renderRows()
        layout(fieldHeightTotal: 0, rows: 0)
        status.stringValue = "↑↓ 选择 · 回车打开 · Esc 取消"
        status.textColor = NSColor.white.withAlphaComponent(0.42)
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: scr.midX - size.width / 2, y: scr.maxY - size.height - 160))

        NSApp.setActivationPolicy(.regular)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(field)
        for d in [0.05, 0.15, 0.30, 0.50, 0.80] {
            DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                self.panel.makeKey()
                self.panel.makeFirstResponder(self.field)
            }
        }
        log("show active=\(NSApp.isActive) key=\(panel.isKeyWindow)")
    }

    func hidePanel() {
        panel.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    func moveSel(_ d: Int) {
        guard !hits.isEmpty else { return }
        sel = max(0, min(hits.count - 1, sel + d))
        renderRows()
    }

    func renderRows() {
        for v in rowViews { v.removeFromSuperview() }
        rowViews = []
        let n = min(hits.count, MAX_ROWS)
        layout(fieldHeightTotal: 0, rows: n)
        for i in 0..<n {
            let h = hits[i]
            let y = CGFloat(n - 1 - i) * ROW_H + 4
            let row = NSView(frame: NSRect(x: 8, y: y, width: cardW - 16, height: ROW_H - 4))
            row.wantsLayer = true
            row.layer?.cornerRadius = 9
            row.layer?.backgroundColor = (i == sel ? NSColor.white.withAlphaComponent(0.13)
                                                   : NSColor.clear).cgColor
            let icon = NSImageView(frame: NSRect(x: 12, y: 7, width: 24, height: 24))
            icon.image = h.type == "APP" ? NSWorkspace.shared.icon(forFile: h.path)
                                         : NSWorkspace.shared.icon(forFile: h.path)
            icon.imageScaling = .scaleProportionallyUpOrDown
            row.addSubview(icon)

            let title = NSTextField(labelWithString: displayName(h))
            title.font = NSFont.systemFont(ofSize: 13.5, weight: i == sel ? .medium : .regular)
            title.textColor = NSColor.white.withAlphaComponent(0.95)
            title.frame = NSRect(x: 46, y: 12, width: 260, height: 18)
            title.lineBreakMode = .byTruncatingTail
            row.addSubview(title)

            let sub = NSTextField(labelWithString: subtitle(h))
            sub.font = NSFont.systemFont(ofSize: 11)
            sub.textColor = NSColor.white.withAlphaComponent(0.38)
            sub.frame = NSRect(x: 300, y: 13, width: cardW - 16 - 320, height: 16)
            sub.lineBreakMode = .byTruncatingMiddle
            row.addSubview(sub)

            let click = NSClickGestureRecognizer(target: self, action: #selector(rowClicked(_:)))
            row.addGestureRecognizer(click)
            rowsBox.addSubview(row)
            rowViews.append(row)
        }
    }

    func displayName(_ h: Hit) -> String {
        if h.type == "APP" {
            if !h.name.isEmpty { return h.name }
            return (h.path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
        }
        return h.name
    }

    func subtitle(_ h: Hit) -> String {
        if h.type == "APP" { return "应用" }
        let dir = (h.path as NSString).deletingLastPathComponent
        return (dir as NSString).abbreviatingWithTildeInPath
    }

    @objc func rowClicked(_ g: NSClickGestureRecognizer) {
        guard let v = g.view, let idx = rowViews.firstIndex(of: v) else { return }
        sel = idx
        submit()
    }

    func controlTextDidChange(_ obj: Notification) {
        let q = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        token += 1
        let t = token
        if q.isEmpty {
            hits = []
            sel = 0
            renderRows()
            status.stringValue = "↑↓ 选择 · 回车打开 · Esc 取消"
            status.textColor = NSColor.white.withAlphaComponent(0.42)
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
            let list = self.resolveList(q)
            DispatchQueue.main.async {
                guard t == self.token else { return }
                self.hits = list
                self.sel = 0
                self.renderRows()
                if list.isEmpty {
                    self.status.stringValue = "没有匹配项"
                    self.status.textColor = NSColor.systemRed.withAlphaComponent(0.85)
                } else {
                    self.status.stringValue = "↑↓ 选择 · 回车打开 · Esc 取消"
                    self.status.textColor = NSColor.white.withAlphaComponent(0.42)
                }
            }
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) {
            if textView.hasMarkedText() { return false }
            submit(); return true
        }
        if sel == #selector(NSResponder.cancelOperation(_:)) { hidePanel(); return true }
        return false
    }

    func submit() {
        let q = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { hidePanel(); return }
        if !hits.isEmpty && sel < hits.count {
            let h = hits[sel]
            log("submit q=\(q) -> \(h.type) \(h.path)")
            run(["/usr/bin/open", h.path])
            hidePanel()
            return
        }
        log("submit q=\(q) (resolve)")
        status.stringValue = "找一下…"
        DispatchQueue.global().async {
            let list = self.resolveList(q)
            DispatchQueue.main.async {
                guard let first = list.first else {
                    self.status.stringValue = "没找到「\(q)」"
                    self.status.textColor = .systemRed
                    return
                }
                self.log("open \(first.type) \(first.path)")
                self.run(["/usr/bin/open", first.path])
                self.hidePanel()
            }
        }
    }

    func resolveList(_ q: String) -> [Hit] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", RESOLVER, "--list", q]
        if !FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") {
            DispatchQueue.main.async {
                self.status.stringValue = "需要 python3：请安装「命令行开发者工具」"
                self.status.textColor = .systemOrange
            }
        }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let s = String(data: data, encoding: .utf8) ?? ""
        var out: [Hit] = []
        for line in s.split(separator: "\n") {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            if parts.count >= 3 {
                out.append(Hit(type: parts[0], path: parts[1], name: parts[2]))
            }
        }
        return out
    }

    func log(_ m: String) {
        let line = "[\(Date())] \(m)\n"
        if let d = line.data(using: .utf8) {
            let url = URL(fileURLWithPath: "/tmp/quickopen.log")
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(d); try? h.close()
            } else {
                try? d.write(to: url)
            }
        }
    }

    func run(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: args[0])
        p.arguments = Array(args.dropFirst())
        try? p.run()
    }

    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, _, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue().showPanel()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)

        let id = EventHotKeyID(signature: OSType(0x44534851), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_O), UInt32(cmdKey | optionKey), id,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
