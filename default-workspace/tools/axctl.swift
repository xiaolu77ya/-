// axctl — tiny macOS accessibility CLI (AX tree + click + type + key)
// build: swiftc -O axctl.swift -o axctl
import ApplicationServices
import AppKit

func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}

func str(_ el: AXUIElement, _ name: String) -> String {
    if let s = attr(el, name) as? String { return s }
    return ""
}

func point(_ el: AXUIElement, _ name: String) -> CGPoint? {
    guard let v = attr(el, name) else { return nil }
    var p = CGPoint.zero
    if AXValueGetValue(v as! AXValue, .cgPoint, &p) { return p }
    return nil
}

func size(_ el: AXUIElement, _ name: String) -> CGSize? {
    guard let v = attr(el, name) else { return nil }
    var s = CGSize.zero
    if AXValueGetValue(v as! AXValue, .cgSize, &s) { return s }
    return nil
}

func children(_ el: AXUIElement) -> [AXUIElement] {
    return (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

func label(_ el: AXUIElement) -> String {
    let parts = [
        str(el, kAXRoleAttribute),
        str(el, kAXSubroleAttribute),
        str(el, kAXTitleAttribute),
        str(el, kAXDescriptionAttribute),
        str(el, kAXValueAttribute).prefix(60).description
    ].filter { !$0.isEmpty }
    return parts.joined(separator: " | ")
}

func appElement(_ name: String) -> AXUIElement? {
    let apps = NSWorkspace.shared.runningApplications
    let match = apps.first { ($0.localizedName ?? "") == name }
        ?? apps.first { ($0.localizedName ?? "").lowercased().contains(name.lowercased()) }
    guard let app = match else { return nil }
    return AXUIElementCreateApplication(app.processIdentifier)
}

func walk(_ el: AXUIElement, depth: Int, maxDepth: Int, path: String, visit: (AXUIElement, Int, String) -> Bool) {
    if !visit(el, depth, path) { return }
    if depth >= maxDepth { return }
    for (i, c) in children(el).enumerated() {
        walk(c, depth: depth + 1, maxDepth: maxDepth, path: "\(path).\(i)", visit: visit)
    }
}

func find(_ root: AXUIElement, _ needle: String) -> AXUIElement? {
    var found: AXUIElement?
    walk(root, depth: 0, maxDepth: 40, path: "0") { el, _, _ in
        if found != nil { return false }
        let hay = [str(el, kAXTitleAttribute), str(el, kAXDescriptionAttribute), str(el, kAXValueAttribute)].joined(separator: " ")
        if hay.lowercased().contains(needle.lowercased()) { found = el; return false }
        return true
    }
    return found
}

func postClick(_ p: CGPoint) {
    let src = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(60_000)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(40_000)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}

func typeText(_ s: String) {
    for ch in s.utf16 {
        let src = CGEventSource(stateID: .hidSystemState)
        var c = ch
        if let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) {
            down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
            up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
            up.post(tap: .cghidEventTap)
        }
        usleep(8_000)
    }
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: axctl tree <app> [depth] | windows <app> | press <app> <title> | click <x> <y> | type <text> | key <code>")
    exit(2)
}
let cmd = args[1]
let appName = args.count > 2 ? args[2] : ""
let appOpt: AXUIElement? = (cmd == "click" || cmd == "rclick" || cmd == "type" || cmd == "key" || cmd == "drag" || cmd == "hotkey" || cmd == "scroll") ? nil : appElement(appName)
if appOpt == nil && cmd != "click" && cmd != "rclick" && cmd != "type" && cmd != "key" && cmd != "drag" && cmd != "hotkey" && cmd != "scroll" && cmd != "setpos" && cmd != "geom" && cmd != "pressat" {
    print("app not found: \(appName)"); exit(1)
}
let app: AXUIElement = appOpt ?? AXUIElementCreateSystemWide()

switch cmd {
case "windows":
    for w in (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
        let p = point(w, kAXPositionAttribute) ?? .zero
        let s = size(w, kAXSizeAttribute) ?? .zero
        print("\(str(w, kAXTitleAttribute))  [x=\(Int(p.x)) y=\(Int(p.y)) w=\(Int(s.width)) h=\(Int(s.height))]")
    }
case "tree":
    let maxDepth = args.count > 3 ? (Int(args[3]) ?? 6) : 6
    walk(app, depth: 0, maxDepth: maxDepth, path: "0") { el, d, path in
        let indent = String(repeating: "  ", count: d)
        print("\(indent)\(path) \(label(el))")
        return d < maxDepth
    }
case "press":
    guard args.count > 3, let el = find(app, args[3]) else { print("not found"); exit(1) }
    let err = AXUIElementPerformAction(el, kAXPressAction as CFString)
    print("press \(label(el)) -> \(err.rawValue)")
case "click", "rclick":
    guard args.count > 3, let x = Double(args[2]), let y = Double(args[3]) else { print("bad coords"); exit(2) }
    let right = (cmd == "rclick")
    let src = CGEventSource(stateID: .hidSystemState)
    let p = CGPoint(x: x, y: y)
    CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: right ? .right : .left)?.post(tap: .cghidEventTap)
    usleep(60_000)
    CGEvent(mouseEventSource: src, mouseType: right ? .rightMouseDown : .leftMouseDown, mouseCursorPosition: p, mouseButton: right ? .right : .left)?.post(tap: .cghidEventTap)
    usleep(40_000)
    CGEvent(mouseEventSource: src, mouseType: right ? .rightMouseUp : .leftMouseUp, mouseCursorPosition: p, mouseButton: right ? .right : .left)?.post(tap: .cghidEventTap)
    print("clicked \(x),\(y) right=\(right)")
case "scroll":
    guard args.count > 4, let x = Double(args[2]), let y = Double(args[3]), let dy = Int32(args[4]) else { print("bad args"); exit(2) }
    let src = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(60_000)
    for _ in 0..<3 {
        CGEvent(scrollWheelEvent2Source: src, units: .pixel, wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
        usleep(60_000)
    }
    print("scrolled \(dy) at \(x),\(y)")
case "drag":
    guard args.count > 4, let x1 = Double(args[2]), let y1 = Double(args[3]), let x2 = Double(args[4]), let y2 = Double(args[5]) else { print("bad coords"); exit(2) }
    let src = CGEventSource(stateID: .hidSystemState)
    let a = CGPoint(x: x1, y: y1), b = CGPoint(x: x2, y: y2)
    CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: a, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(120_000)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: a, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(120_000)
    let steps = 24
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        let pt = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged, mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(18_000)
    }
    usleep(150_000)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: b, mouseButton: .left)?.post(tap: .cghidEventTap)
    print("dragged \(a) -> \(b)")
case "hotkey":
    guard args.count > 2, let code = UInt16(args[2]) else { exit(2) }
    var flags: CGEventFlags = []
    if args.count > 3 {
        for f in args[3].split(separator: ",") {
            switch f {
            case "cmd": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "alt": flags.insert(.maskAlternate)
            case "ctrl": flags.insert(.maskControl)
            default: break
            }
        }
    }
    let src = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
    down?.flags = flags
    down?.post(tap: .cghidEventTap)
    usleep(40_000)
    let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
    up?.flags = flags
    up?.post(tap: .cghidEventTap)
    print("hotkey \(code) flags=\(args.count > 3 ? args[3] : "-")")
case "findtext":
    guard args.count > 3 else { exit(2) }
    let needle = args[3]
    walk(app, depth: 0, maxDepth: 40, path: "0") { el, _, path in
        let v = str(el, kAXValueAttribute)
        let t = str(el, kAXTitleAttribute)
        if v == needle || t == needle {
            let p = point(el, kAXPositionAttribute) ?? .zero
            let sz = size(el, kAXSizeAttribute) ?? .zero
            print("\(path) \(label(el)) x=\(Int(p.x)) y=\(Int(p.y)) w=\(Int(sz.width)) h=\(Int(sz.height))")
        }
        return true
    }
case "clicktext":
    guard args.count > 3 else { exit(2) }
    let needle = args[3]
    var hits: [(CGPoint, CGSize)] = []
    walk(app, depth: 0, maxDepth: 40, path: "0") { el, _, _ in
        let v = str(el, kAXValueAttribute)
        let t = str(el, kAXTitleAttribute)
        if v == needle || t == needle {
            let p = point(el, kAXPositionAttribute) ?? .zero
            let sz = size(el, kAXSizeAttribute) ?? .zero
            hits.append((p, sz))
        }
        return true
    }
    guard let h = hits.first else { print("no match for \(needle)"); exit(1) }
    let c = CGPoint(x: h.0.x + h.1.width / 2, y: h.0.y + h.1.height / 2)
    postClick(c)
    print("clicked \(needle) at \(c) (hits \(hits.count))")
case "setvalue":
    guard args.count > 4, let val = Double(args[4]) else { exit(2) }
    var target: AXUIElement?
    walk(app, depth: 0, maxDepth: 40, path: "0") { el, _, path in
        if target == nil && path == args[3] { target = el; return false }
        return true
    }
    guard let t = target else { print("path not found"); exit(1) }
    let err = AXUIElementSetAttributeValue(t, kAXValueAttribute as CFString, val as CFNumber)
    print("setvalue -> \(err.rawValue)")
case "setpos":
    guard args.count > 4, let nx = Double(args[3]), let ny = Double(args[4]) else { exit(2) }
    let wins = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    guard let w = wins.first else { print("no window"); exit(1) }
    var pt = CGPoint(x: nx, y: ny)
    let v = AXValueCreate(.cgPoint, &pt)!
    let err = AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, v)
    print("setpos -> \(err.rawValue)")
case "geom", "pressat":
    guard args.count > 3 else { exit(2) }
    let want = args[3]
    var target: AXUIElement?
    walk(app, depth: 0, maxDepth: 40, path: "0") { el, _, path in
        if target == nil && path == want { target = el; return false }
        return true
    }
    guard let t = target else { print("path not found"); exit(1) }
    if cmd == "pressat" {
        let err = AXUIElementPerformAction(t, kAXPressAction as CFString)
        print("press \(label(t)) -> \(err.rawValue)")
    } else {
        let p = point(t, kAXPositionAttribute) ?? .zero
        let s = size(t, kAXSizeAttribute) ?? .zero
        print("\(want) \(label(t)) x=\(Int(p.x)) y=\(Int(p.y)) w=\(Int(s.width)) h=\(Int(s.height))")
    }
case "type":
    typeText(appName)
    print("typed \(appName.count) chars")
case "key":
    guard let code = UInt16(appName) else { exit(2) }
    let src = CGEventSource(stateID: .hidSystemState)
    CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
    usleep(30_000)
    CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
    print("key \(code)")
default:
    print("unknown cmd"); exit(2)
}
