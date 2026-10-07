import AppKit
import ScaleBarCore

enum GarminState: Equatable {
    case notPushed
    case pushing
    case pushed(String)
    case failed(String)
}

struct Weighin {
    var reading: Reading
    var composition: Composition
    var ts: String
    var since: String?
    var delta: Double?
    var saveError: String?
    var garmin: GarminState
}

/// Owns the status item. The popover, its view and the BLE session are created on click and
/// released once the popover closes with no scan running. Main thread only.
final class StatusBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store = WeighinStore.default
    private var popover: NSPopover?
    private var view: BodyView?
    private var reader: ScaleReader?
    private var ticker: Timer?
    private var current: Weighin?

    /// A reading this recent is shown instead of starting a new scan.
    private let freshFor: TimeInterval = 15 * 60

    override init() {
        super.init()
        let img = NSImage(systemSymbolName: "scalemass", accessibilityDescription: "ScaleBar")
        img?.isTemplate = true
        item.button?.image = img
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(toggle)
        current = loadLatest()
        render()
    }

    @objc private func toggle() {
        if let popover, popover.isShown { popover.performClose(nil); return }
        show()
        let fresh = current.map { Date().timeIntervalSince($0.reading.date) < freshFor } ?? false
        if reader?.state.isActive != true && !fresh { startScan() }
    }

    private func show() {
        guard let button = item.button else { return }
        if popover == nil {
            let v = BodyView()
            v.rescan.target = self
            v.rescan.action = #selector(startScan)
            v.push.target = self
            v.push.action = #selector(pushTapped)
            v.quit.target = NSApp
            v.quit.action = #selector(NSApplication.terminate(_:))
            let vc = NSViewController()
            vc.view = v
            let p = NSPopover()
            p.contentViewController = vc
            p.contentSize = BodyView.size
            p.behavior = .transient
            p.delegate = self
            popover = p
            view = v
        }
        render()
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.render() }
    }

    @objc private func startScan() {
        let r = ScaleReader(profile: .sahil)
        r.onChange = { [weak self] state in self?.handle(state) }
        reader = r
        r.start()
    }

    @objc private func pushTapped() {
        push()
    }

    private func handle(_ state: ScanState) {
        switch state {
        case .done(let reading):
            reader = nil
            current = save(reading)
            if current?.saveError == nil { push() }
            if popover?.isShown != true { show() }
        case .failed, .idle:
            reader = nil
        default:
            break
        }
        render()
    }

    private func save(_ r: Reading) -> Weighin {
        let c = Composition(weight: r.weight, impedance: r.impedance, profile: .sahil)
        let ts = WeighinStore.timestamp(r.date)
        var w = Weighin(reading: r, composition: c, ts: ts, garmin: .notPushed)
        if let prev = store.previous(before: ts) {
            w.since = WeighinStore.dayLabel(prev.ts)
            w.delta = r.weight - prev.kg
        }
        do {
            try store.save(r, c, profile: .sahil)
        } catch {
            w.saveError = error.localizedDescription
        }
        return w
    }

    private func push() {
        guard var w = current, w.garmin != .pushing else { return }
        if case .pushed = w.garmin { return }
        w.garmin = .pushing
        current = w
        render()
        let ts = w.ts
        GarminPush.run(ts: ts, dbPath: store.path) { [weak self] result in
            guard let self, self.current?.ts == ts else { return }
            switch result {
            case .success:
                self.current?.garmin = .pushed(Self.clock(Date()))
            case .failure(let e):
                self.current?.garmin = .failed(e.localizedDescription)
            }
            self.render()
        }
    }

    /// Last saved weigh-in, so the panel shows numbers before the next scan.
    private func loadLatest() -> Weighin? {
        guard let row = store.latest() else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let reading = Reading(date: f.date(from: row.ts) ?? Date(), weight: row.kg, impedance: row.ohm, frames: [])
        let c = Composition(weight: row.kg, impedance: row.ohm, profile: .sahil)
        var w = Weighin(reading: reading, composition: c, ts: row.ts, garmin: .notPushed)
        if let pushed = row.pushedAt { w.garmin = .pushed(String(pushed.suffix(8).prefix(5))) }
        if let prev = store.previous(before: row.ts) {
            w.since = WeighinStore.dayLabel(prev.ts)
            w.delta = row.kg - prev.kg
        }
        return w
    }

    private static func clock(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    /// Same value on every reading means the scale is not really measuring.
    private func impedanceNotice() -> String? {
        let all = store.impedances()
        guard all.count >= 2, let first = all.first, all.allSatisfy({ $0 == first }) else { return nil }
        let which = all.count == 2 ? "both readings" : "all \(all.count) readings"
        return "Impedance read exactly \(first) Ω on \(which), so fat, water and muscle move with weight only."
    }

    private func render() {
        let state = reader?.state ?? .idle
        var m = BodyModel()
        if let w = current {
            m.weight = w.reading.weight
            m.weightIsFinal = true
            m.composition = w.composition
            m.impedance = w.reading.impedance
            m.since = w.since
            m.delta = w.delta
            m.garmin = w.saveError == nil ? w.garmin : nil
            m.status = "Weighed " + Self.clock(w.reading.date) + (w.reading.impedance.map { "  ·  \($0) Ω" } ?? "")
            if let e = w.saveError { m.notes.append("Not saved: \(e)") }
            if w.reading.impedance == nil { m.notes.append("No impedance. Step on barefoot and stay still after the weight locks.") }
            else if let n = impedanceNotice() { m.notes.append(n) }
        } else {
            m.status = "No weigh-ins yet"
        }
        var title = current.map { String(format: "%.1f", $0.reading.weight) } ?? ""
        func left(_ until: Date) -> String {
            let s = max(0, Int(until.timeIntervalSinceNow))
            return String(format: "%d:%02d", s / 60, s % 60)
        }
        switch state {
        case .scanning(let until):
            m.status = "Searching… \(left(until)) left. Step on the scale."
            title = "…"
        case .connecting:
            m.status = "Scale found, connecting…"
            title = "…"
        case .waitingForStep(let until):
            m.status = "Connected. Step on barefoot. \(left(until)) left."
            title = "…"
        case .live(let kg), .locked(let kg):
            if case .locked = state { m.status = "Weight locked. Stay still for body composition…" } else { m.status = "Measuring…" }
            m.weight = kg
            m.weightIsFinal = false
            m.composition = nil
            m.garmin = nil
            m.notes = []
            title = String(format: "%.1f", kg)
        case .failed(let msg):
            m.status = msg
        case .idle, .done:
            break
        }
        item.button?.title = title.isEmpty ? "" : " " + title
        view?.rescan.isEnabled = !state.isActive
        view?.model = m
    }
}

extension StatusBarController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        ticker?.invalidate()
        ticker = nil
        guard reader?.state.isActive != true else { return }
        popover = nil
        view = nil
    }
}
