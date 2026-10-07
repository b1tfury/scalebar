import AppKit
import ScaleBarCore

/// `ScaleBar --preview /tmp` writes the result screen in light and dark, then exits.
private func writePreviews(to dir: String) {
    let c = Composition(weight: 94.75, impedance: 600, profile: .sahil)
    for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", NSAppearance.Name.aqua)] {
        let view = BodyView()
        view.appearance = NSAppearance(named: appearance)
        view.model = BodyModel(
            status: "Weighed 07:07  ·  600 Ω",
            weight: 94.75, weightIsFinal: true, composition: c, impedance: 600,
            since: "4 Oct", delta: 0.55, garmin: .notPushed,
            notes: ["Impedance read exactly 600 Ω on all 3 readings, so fat, water and muscle move with weight only."]
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: BodyView.size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = view.appearance
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        window.display()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
        view.cacheDisplay(in: view.bounds, to: rep)
        let url = URL(fileURLWithPath: dir).appendingPathComponent("scalebar-\(name).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        FileHandle.standardError.write(Data("wrote \(url.path)\n".utf8))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()
    }
}

let app = NSApplication.shared
if CommandLine.arguments.dropFirst().first == "--preview" {
    writePreviews(to: CommandLine.arguments.dropFirst(2).first ?? "/tmp")
    exit(0)
}
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
