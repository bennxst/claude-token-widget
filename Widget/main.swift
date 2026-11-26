// Token-Widget: kleines Desktop-Widget, das den Gesamt-Tokenverbrauch live anzeigt.
import AppKit

let size: CGFloat = 158      // Breite
let height: CGFloat = 158    // Höhe (quadratisch)
let accent = NSColor(srgbRed: 0.35, green: 0.68, blue: 1.0, alpha: 1)

// Summiert alle Token-Zähler aus den lokalen Claude-Code-Verläufen (~/.claude/projects/**/*.jsonl).
// Jede Antwort steht dort teils mehrfach, daher wird nach Nachrichten-ID + Request-ID entdoppelt.
// Liefert die Gesamtsumme und jede Antwort mit Zeitpunkt (für die eigene Limit-Rechnung).
func countTokens() -> (Int, [(Date, Int)]) {
    let root = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/projects")
    let keys = ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
    var seen = Set<String>(), total = 0
    var entries: [(Date, Int)] = []
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
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
            var n = 0
            for k in keys { n += usage[k] as? Int ?? 0 }
            total += n
            if let t = obj["timestamp"] as? String, let d = iso.date(from: t) { entries.append((d, n)) }
        }
    }
    return (total, entries)
}

struct Limit { var percent: Double; var resetsIn: TimeInterval? }

// Plan-Limits: liest den eigenen Claude-Code-Login aus dem Schlüsselbund (nur lokal, wird nirgends gespeichert)
// und fragt damit die inoffizielle Anthropic-Schnittstelle ab. Schlägt etwas fehl, bleibt die Anzeige "nicht verbunden".
var lastLimits: (Limit?, Limit?) = (nil, nil)
var lastFetch = Date.distantPast

func fetchLimits() -> (Limit?, Limit?) {
    if Date().timeIntervalSince(lastFetch) < 120 { return lastLimits }
    lastFetch = Date()
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    guard (try? p.run()) != nil else { return lastLimits }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let oauth = obj["claudeAiOauth"] as? [String: Any],
          let token = oauth["accessToken"] as? String else { lastLimits = (nil, nil); return lastLimits }
    var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
    req.timeoutInterval = 15
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    var result: Data?
    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { d, resp, _ in
        if (resp as? HTTPURLResponse)?.statusCode == 200 { result = d }
        sem.signal()
    }.resume()
    _ = sem.wait(timeout: .now() + 20)
    guard let d = result, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { lastLimits = (nil, nil); return lastLimits }
    func limit(_ key: String) -> Limit? {
        guard let o = j[key] as? [String: Any], let u = o["utilization"] as? Double else { return nil }
        var reset: TimeInterval?
        if let r = o["resets_at"] as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let date = f.date(from: r) ?? ISO8601DateFormatter().date(from: r)
            if let date = date { reset = max(0, date.timeIntervalSinceNow) }
        }
        return Limit(percent: u, resetsIn: reset)
    }
    lastLimits = (limit("five_hour"), limit("seven_day"))
    return lastLimits
}

// Eigene Rechnung ohne Login: 5-Stunden-Fenster beginnen mit der ersten Nachricht (auf volle Stunde abgerundet)
// und laufen 5 Stunden. Woche = Verbrauch der letzten 7 Tage.
struct LocalUsage { var block: Int; var blockReset: TimeInterval?; var week: Int }

func localUsage(_ entries: [(Date, Int)]) -> LocalUsage {
    let now = Date(), five: TimeInterval = 5 * 3600
    var start: Date?, sum = 0, last = Date.distantPast
    for (d, n) in entries.sorted(by: { $0.0 < $1.0 }) {
        if let s = start, d < s.addingTimeInterval(five), d.timeIntervalSince(last) < five { sum += n }
        else { start = Date(timeIntervalSince1970: floor(d.timeIntervalSince1970 / 3600) * 3600); sum = n }
        last = d
    }
    let week = entries.filter { now.timeIntervalSince($0.0) < 7 * 86400 }.reduce(0) { $0 + $1.1 }
    if let s = start, now < s.addingTimeInterval(five) {
        return LocalUsage(block: sum, blockReset: s.addingTimeInterval(five).timeIntervalSince(now), week: week)
    }
    return LocalUsage(block: 0, blockReset: nil, week: week)
}

final class Bar: NSView {
    var value: Double = 0 { didSet { needsLayout = true } }
    var color = accent { didSet { fill.layer?.backgroundColor = color.cgColor } }
    let fill = NSView()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        layer?.cornerRadius = 2
        fill.wantsLayer = true
        fill.layer?.backgroundColor = color.cgColor
        fill.layer?.cornerRadius = 2
        addSubview(fill)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        fill.frame = NSRect(x: 0, y: 0, width: bounds.width * CGFloat(min(max(value, 0), 100) / 100), height: bounds.height)
    }
}

final class LimitRow: NSView {
    let title = NSTextField(labelWithString: "")
    let pct = NSTextField(labelWithString: "–")
    let bar = Bar()
    let reset = NSTextField(labelWithString: "")
    init(title t: String) {
        super.init(frame: .zero)
        title.stringValue = t
        title.font = .systemFont(ofSize: 9, weight: .semibold)
        title.textColor = .secondaryLabelColor
        pct.font = .monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        pct.textColor = .labelColor
        pct.alignment = .right
        reset.font = .systemFont(ofSize: 9, weight: .medium)
        reset.textColor = .tertiaryLabelColor
        for v in [title, pct, bar, reset] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor), title.topAnchor.constraint(equalTo: topAnchor),
            title.heightAnchor.constraint(equalToConstant: 12),
            pct.trailingAnchor.constraint(equalTo: trailingAnchor), pct.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor), bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2), bar.heightAnchor.constraint(equalToConstant: 4),
            reset.leadingAnchor.constraint(equalTo: leadingAnchor), reset.trailingAnchor.constraint(equalTo: trailingAnchor),
            reset.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 2), reset.heightAnchor.constraint(equalToConstant: 11),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    static func resetText(_ r: TimeInterval) -> String {
        let m = Int(r / 60), d = m / 1440, h = (m % 1440) / 60, mi = m % 60
        return "Reset in " + (d > 0 ? "\(d) T \(h) Std" : (h > 0 ? "\(h) Std \(mi) Min" : "\(mi) Min"))
    }

    // Ohne Login: Token-Zahl statt Prozent, kein Balken
    func showLocal(tokens: Int, note: String) {
        let (num, word) = WidgetView.short(tokens)
        let abbr = ["Tokens": "", "Tausend": " Tsd", "Millionen": " Mio", "Milliarden": " Mrd", "Billionen": " Bio"][word] ?? ""
        pct.stringValue = num + abbr
        bar.isHidden = true
        reset.stringValue = note
    }

    func show(_ l: Limit?) {
        bar.isHidden = false
        guard let l = l else { pct.stringValue = "–"; bar.value = 0; reset.stringValue = ""; return }
        pct.stringValue = "\(Int(l.percent.rounded())) %"
        bar.value = l.percent
        // NUR_BLAU=1 (z. B. im LaunchAgent): Balken immer blau, ohne Orange/Rot
        bar.color = ProcessInfo.processInfo.environment["NUR_BLAU"] != nil ? accent
            : (l.percent >= 90 ? .systemRed : (l.percent >= 70 ? .systemOrange : accent))
        reset.stringValue = l.resetsIn.map(Self.resetText) ?? ""
    }
}

final class WidgetView: NSVisualEffectView {
    let caption = NSTextField(labelWithString: "TOKENS")
    let dot = NSView()
    let big = NSTextField(labelWithString: "–")
    let unit = NSTextField(labelWithString: "")
    let exact = NSTextField(labelWithString: "lädt …")
    let line = NSView()
    let fiveHour = LimitRow(title: "5-STUNDEN")
    let week = LimitRow(title: "WOCHE")

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 22
        layer?.masksToBounds = true

        caption.font = .systemFont(ofSize: 9, weight: .semibold)
        caption.textColor = .secondaryLabelColor
        dot.wantsLayer = true
        dot.layer?.backgroundColor = accent.cgColor
        dot.layer?.cornerRadius = 3

        big.font = .systemFont(ofSize: 52, weight: .bold).rounded
        big.textColor = .labelColor
        unit.font = .systemFont(ofSize: 12, weight: .semibold).rounded
        unit.textColor = accent
        exact.font = .monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        exact.textColor = .tertiaryLabelColor

        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
        exact.alignment = .right
        for v in [caption, dot, big, unit, exact, line, fiveHour, week] {
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
            caption.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            caption.heightAnchor.constraint(equalToConstant: 12),
            big.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            big.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            big.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: 2),
            big.heightAnchor.constraint(equalToConstant: 38),
            unit.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            unit.topAnchor.constraint(equalTo: big.bottomAnchor, constant: 0),
            unit.heightAnchor.constraint(equalToConstant: 14),
            exact.leadingAnchor.constraint(greaterThanOrEqualTo: caption.trailingAnchor, constant: 6),
            exact.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            exact.firstBaselineAnchor.constraint(equalTo: caption.firstBaselineAnchor),
                        line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            line.topAnchor.constraint(equalTo: unit.bottomAnchor, constant: 6),
            line.heightAnchor.constraint(equalToConstant: 1),
            fiveHour.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            fiveHour.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            fiveHour.topAnchor.constraint(equalTo: line.bottomAnchor, constant: 6),
            fiveHour.heightAnchor.constraint(equalToConstant: 31),
            week.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            week.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            week.topAnchor.constraint(equalTo: fiveHour.bottomAnchor, constant: 4),
            week.heightAnchor.constraint(equalToConstant: 31),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ total: Int) {
        let (num, word) = Self.short(total)
        big.stringValue = num
        // Schrift so groß wie möglich, aber nie breiter als das Widget
        var pt: CGFloat = 34
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
        toolTip = exact.stringValue + " Tokens"
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
    let view = WidgetView(frame: NSRect(x: 0, y: 0, width: size, height: height))

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
            window.setFrameOrigin(NSPoint(x: s.maxX - size - 24, y: s.maxY - height - 24))
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
            var (total, entries) = countTokens()
            let local = localUsage(entries)
            // Testmodus: TOKEN_TEST=<zahl> zeigt eine feste Zahl
            if let t = ProcessInfo.processInfo.environment["TOKEN_TEST"], let v = Int(t) { total = v }
            _ = entries
            // Testmodus für die Limits: LIMITS_TEST=1 (Benni: 5 Std 78 %, Woche 5 %)
            // LIMITS_OFF=1: Login-Abruf überspringen (zum Testen der eigenen Rechnung)
            var limits: (Limit?, Limit?) = ProcessInfo.processInfo.environment["LIMITS_OFF"] != nil ? (nil, nil) : fetchLimits()
            if ProcessInfo.processInfo.environment["LIMITS_TEST"] != nil {
                limits = (Limit(percent: 78, resetsIn: 80 * 60), Limit(percent: 5, resetsIn: (5 * 24 + 3) * 3600))
            }
            DispatchQueue.main.async {
                self.view.show(total)
                // Echte Prozente, wenn der Login gültig ist; sonst die eigene Rechnung
                if let l = limits.0 { self.view.fiveHour.show(l) }
                else { self.view.fiveHour.showLocal(tokens: local.block, note: local.blockReset.map(LimitRow.resetText) ?? "kein aktives Fenster") }
                if let l = limits.1 { self.view.week.show(l) }
                else { self.view.week.showLocal(tokens: local.week, note: "letzte 7 Tage") }
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
