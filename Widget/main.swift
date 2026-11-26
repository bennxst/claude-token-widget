// Token-Widget: kleines Desktop-Widget, das den Gesamt-Tokenverbrauch live anzeigt.
import AppKit

let size: CGFloat = 160
let accent = NSColor(srgbRed: 0.35, green: 0.68, blue: 1.0, alpha: 1)

// Summiert alle Token-Zähler aus den lokalen Claude-Code-Verläufen (~/.claude/projects/**/*.jsonl).
// Jede Antwort steht dort teils mehrfach, daher wird nach Nachrichten-ID + Request-ID entdoppelt.
func countTokens() -> Int {
    let root = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/projects")
    let keys = ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
    var seen = Set<String>(), total = 0
    let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
    while let url = files?.nextObject() as? URL {
        guard url.pathExtension == "jsonl", let data = try? Data(contentsOf: url) else { continue }
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard line.range(of: Data("\"usage\"".utf8)) != nil,
                  let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let msg = obj["message"] as? [String: Any],
                  let usage = msg["usage"] as? [String: Any] else { continue }
            let id = "\(msg["id"] ?? "")|\(obj["requestId"] ?? "")"
            if id != "|" && !seen.insert(id).inserted { continue }
            for k in keys { total += usage[k] as? Int ?? 0 }
        }
    }
    return total
}

final class WidgetView: NSVisualEffectView {
    let caption = NSTextField(labelWithString: "CLAUDE TOKENS")
    let dot = NSView()
    let big = NSTextField(labelWithString: "–")
    let unit = NSTextField(labelWithString: "")
    let exact = NSTextField(labelWithString: "lädt …")

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 24
        layer?.masksToBounds = true

        caption.font = .systemFont(ofSize: 10, weight: .semibold)
        caption.textColor = .secondaryLabelColor
        dot.wantsLayer = true
        dot.layer?.backgroundColor = accent.cgColor
        dot.layer?.cornerRadius = 3

        big.font = .systemFont(ofSize: 52, weight: .bold).rounded
        big.textColor = .labelColor
        unit.font = .systemFont(ofSize: 17, weight: .semibold).rounded
        unit.textColor = accent
        exact.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        exact.textColor = .secondaryLabelColor

        for v in [caption, dot, big, unit, exact] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        // Feste Zeilen von oben nach unten, jede mit eigener Höhe: nichts kann sich überlagern.
        big.maximumNumberOfLines = 1
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            dot.centerYAnchor.constraint(equalTo: caption.centerYAnchor),
            caption.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            caption.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            caption.heightAnchor.constraint(equalToConstant: 14),
            big.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            big.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            big.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: 10),
            big.heightAnchor.constraint(equalToConstant: 52),
            unit.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            unit.topAnchor.constraint(equalTo: big.bottomAnchor, constant: 2),
            unit.heightAnchor.constraint(equalToConstant: 20),
            exact.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            exact.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            exact.topAnchor.constraint(greaterThanOrEqualTo: unit.bottomAnchor, constant: 6),
            exact.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ total: Int) {
        let (num, word) = Self.short(total)
        big.stringValue = num
        // Schrift so groß wie möglich, aber nie breiter als das Widget
        var pt: CGFloat = 46
        while pt > 20 {
            let w = (num as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: pt, weight: .bold).rounded]).width
            if w <= size - 32 { break }
            pt -= 2
        }
        big.font = NSFont.systemFont(ofSize: pt, weight: .bold).rounded
        unit.stringValue = word
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "de_DE")
        exact.stringValue = f.string(from: NSNumber(value: total)) ?? "\(total)"
    }

    static func short(_ n: Int) -> (String, String) {
        // Nächste Einheit schon ab 999,5, damit nie "1.000 Millionen" erscheint
        let units = ["Tokens", "Tausend", "Millionen", "Milliarden", "Billionen"]
        var v = Double(n), i = 0
        while v >= 999.5 && i < units.count - 1 { v /= 1000; i += 1 }
        let w = units[i]
        let digits = (i == 0 || v >= 99.95) ? 0 : (v >= 9.995 ? 1 : 2)
        let f = NumberFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return (f.string(from: NSNumber(value: v)) ?? "\(v)", w)
    }
}

extension NSFont {
    var rounded: NSFont {
        guard let d = fontDescriptor.withDesign(.rounded) else { return self }
        return NSFont(descriptor: d, size: pointSize) ?? self
    }
}

final class App: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let view = WidgetView(frame: NSRect(x: 0, y: 0, width: size, height: size))

    func applicationDidFinishLaunching(_ n: Notification) {
        window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.contentView = view
        window.isMovableByWindowBackground = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if !window.setFrameUsingName("TokenWidget"), let s = NSScreen.main?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: s.maxX - size - 24, y: s.maxY - size - 24))
        }
        window.setFrameAutosaveName("TokenWidget")
        window.orderFront(nil)

        let menu = NSMenu()
        menu.addItem(withTitle: "Jetzt aktualisieren", action: #selector(refresh), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Widget beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        view.menu = menu

        refresh()
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
    }

    @objc func refresh() {
        DispatchQueue.global(qos: .utility).async {
            var total = countTokens()
            // Testmodus: TOKEN_TEST=<zahl> zeigt eine feste Zahl
            if let t = ProcessInfo.processInfo.environment["TOKEN_TEST"], let v = Int(t) { total = v }
            DispatchQueue.main.async {
                self.view.show(total)
                // Testmodus: Token-Widget --snapshot <pfad.png> speichert ein Bild und beendet sich
                if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
                    self.view.layoutSubtreeIfNeeded()
                    if let rep = self.view.bitmapImageRepForCachingDisplay(in: self.view.bounds) {
                        self.view.cacheDisplay(in: self.view.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
                    }
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
