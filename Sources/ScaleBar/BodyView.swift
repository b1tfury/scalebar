import AppKit
import ScaleBarCore

struct BodyModel {
    var status = ""
    var weight: Double?
    var weightIsFinal = false
    var composition: Composition?
    var impedance: Int?
    /// Day label of the previous real measurement, e.g. "4 Oct".
    var since: String?
    var delta: Double?
    var garmin: GarminState?
    var notes: [String] = []
}

/// Popover content, laid out like an InBody result sheet: each metric is a bar with its
/// reference band shaded and a marker for today. The scale is foot-to-foot only, so nothing
/// is painted onto body parts.
final class BodyView: NSView {
    static let size = NSSize(width: 420, height: 600)
    static let targetKg = 85.0

    var model = BodyModel() { didSet { needsDisplay = true; layoutButtons() } }
    let rescan = NSButton(title: "Scan again", target: nil, action: nil)
    let push = NSButton(title: "Push to Garmin", target: nil, action: nil)
    let quit = NSButton(title: "Quit", target: nil, action: nil)

    private let pad: CGFloat = 20

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        for b in [rescan, push, quit] {
            b.bezelStyle = .rounded
            b.controlSize = .small
            addSubview(b)
        }
        layoutButtons()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func layoutButtons() {
        let y = bounds.height - 38
        rescan.frame = NSRect(x: pad - 4, y: y, width: 96, height: 24)
        quit.frame = NSRect(x: bounds.width - pad - 52, y: y, width: 56, height: 24)
        push.frame = NSRect(x: bounds.midX - 62, y: y, width: 124, height: 24)
        switch model.garmin {
        case .notPushed?:
            push.isHidden = false
            push.isEnabled = true
            push.title = "Push to Garmin"
        case .failed?:
            push.isHidden = false
            push.isEnabled = true
            push.title = "Retry Garmin"
        default:
            push.isHidden = true
        }
    }

    override func draw(_ dirty: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let m = model
        let final = m.weightIsFinal

        text(m.status, at: NSPoint(x: bounds.midX, y: 14), size: 12, color: .secondaryLabelColor, align: .center)
        drawWeight(m)

        let figure = NSRect(x: pad, y: 118, width: 104, height: 318)
        drawSilhouette(in: figure, active: final)

        let colX = figure.maxX + 24
        let colW = bounds.width - pad - colX
        let c = final ? m.composition : nil
        let w = final ? m.weight : nil
        let h = Double(Profile.sahil.heightCm) / 100
        var y: CGFloat = 122
        let rowH: CGFloat = 78

        rangeRow("Weight", value: w, format: "%.2f kg", track: 55...110, band: 18.5 * h * h...25 * h * h,
                 bandLabels: ("%.0f", "%.0f"), tick: Self.targetKg, status: rangeStatus,
                 rect: NSRect(x: colX, y: y, width: colW, height: rowH))
        y += rowH
        rangeRow("BMI", value: c?.bmi, format: "%.1f", track: 16...36, band: 18.5...25,
                 bandLabels: ("%.1f", "%.0f"), tick: nil, status: bmiStatus,
                 rect: NSRect(x: colX, y: y, width: colW, height: rowH))
        y += rowH
        rangeRow("Body fat", value: c?.fatPct, format: "%.1f%%", track: 0...40, band: 8...20,
                 bandLabels: ("%.0f%%", "%.0f%%"), tick: nil, status: rangeStatus,
                 rect: NSRect(x: colX, y: y, width: colW, height: rowH))
        y += rowH
        rangeRow("Body water", value: c?.waterPct, format: "%.1f%%", track: 40...70, band: 50...65,
                 bandLabels: ("%.0f%%", "%.0f%%"), tick: nil, status: rangeStatus,
                 rect: NSRect(x: colX, y: y, width: colW, height: rowH))

        drawStats(c, y: 452)
        drawFooter(m)
    }

    // MARK: - Header

    private func drawWeight(_ m: BodyModel) {
        let kg = m.weight.map { String(format: "%.2f", $0) } ?? "—"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 44, weight: .semibold)
        let numW = (kg as NSString).size(withAttributes: [.font: font]).width
        let unitW: CGFloat = 26
        let x = bounds.midX - (numW + unitW + 4) / 2
        text(kg, at: NSPoint(x: x, y: 30), size: 44, weight: .semibold,
             color: m.weightIsFinal ? .labelColor : .secondaryLabelColor, width: numW + 2, mono: true)
        text("kg", at: NSPoint(x: x + numW + 4, y: 54), size: 15, weight: .medium, color: .secondaryLabelColor, width: unitW)

        guard let w = m.weight, m.weightIsFinal else { return }
        var parts = [String(format: "%.1f kg to %.0f kg", w - Self.targetKg, Self.targetKg)]
        if let d = m.delta, let since = m.since {
            parts.append(abs(d) < 0.05 ? "same as \(since)" : String(format: "%+.2f kg since %@", d, since))
        }
        text(parts.joined(separator: "   ·   "), at: NSPoint(x: bounds.midX, y: 88), size: 12,
             color: .secondaryLabelColor, align: .center)
    }

    // MARK: - Silhouette

    private func drawSilhouette(in rect: NSRect, active: Bool) {
        guard let shape = ManSilhouette.path, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = shape.boundingBoxOfPath
        let labelH: CGFloat = 18
        let area = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - labelH)
        let s = min(area.width / b.width, area.height / b.height)
        let w = b.width * s, h = b.height * s
        let origin = CGPoint(x: area.midX - w / 2, y: area.minY + (area.height - h) / 2)
        var t = CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: s, y: s).translatedBy(x: -b.minX, y: -b.minY)
        guard let placed = shape.copy(using: &t) else { return }

        // Contact shadow under the feet.
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(ovalIn: NSRect(x: area.midX - w * 0.42, y: origin.y + h - 5, width: w * 0.84, height: 9)).fill()

        ctx.saveGState()
        ctx.addPath(placed)
        ctx.clip()
        let top = NSColor.labelColor.withAlphaComponent(active ? 0.62 : 0.22)
        let bottom = NSColor.labelColor.withAlphaComponent(active ? 0.38 : 0.12)
        NSGradient(starting: top, ending: bottom)?.draw(in: NSRect(x: origin.x, y: origin.y, width: w, height: h), angle: 90)
        ctx.restoreGState()

        let p = Profile.sahil
        text("\(p.heightCm) cm  ·  \(p.age) y", at: NSPoint(x: rect.midX, y: rect.maxY - labelH + 4), size: 10,
             color: .tertiaryLabelColor, align: .center, width: rect.width + 20)
    }

    // MARK: - Range rows

    private typealias Status = (word: String, color: NSColor)

    private func rangeStatus(_ v: Double, _ band: ClosedRange<Double>) -> Status {
        v < band.lowerBound ? ("low", .systemBlue) : v > band.upperBound ? ("high", .systemOrange) : ("normal", .systemGreen)
    }

    private func bmiStatus(_ v: Double, _ band: ClosedRange<Double>) -> Status {
        v < 18.5 ? ("underweight", .systemBlue) : v < 25 ? ("normal", .systemGreen) : v < 30 ? ("overweight", .systemOrange) : ("obese", .systemRed)
    }

    private func rangeRow(_ title: String, value: Double?, format: String, track: ClosedRange<Double>,
                          band: ClosedRange<Double>, bandLabels: (String, String), tick: Double?,
                          status: (Double, ClosedRange<Double>) -> Status, rect: NSRect) {
        let st = value.map { status($0, band) }
        let titleFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        let titleW = (title as NSString).size(withAttributes: [.font: titleFont]).width
        text(title, at: NSPoint(x: rect.minX, y: rect.minY + 2), size: 12, weight: .medium, color: .secondaryLabelColor, width: titleW + 2)
        if let st { pill(st.word, color: st.color, at: NSPoint(x: rect.minX + titleW + 8, y: rect.minY + 2)) }
        let valueText = value.map { String(format: format, $0) } ?? "—"
        text(valueText, at: NSPoint(x: rect.minX + rect.width / 2, y: rect.minY - 1), size: 16, weight: .semibold,
             color: value == nil ? .tertiaryLabelColor : .labelColor, align: .right, width: rect.width / 2, mono: true)

        let barY = rect.minY + 28
        let barH: CGFloat = 8
        let span = track.upperBound - track.lowerBound
        func x(_ v: Double) -> CGFloat {
            rect.minX + CGFloat((min(max(v, track.lowerBound), track.upperBound) - track.lowerBound) / span) * rect.width
        }
        let trackRect = NSRect(x: rect.minX, y: barY, width: rect.width, height: barH)
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: barH / 2, yRadius: barH / 2).fill()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: trackRect, xRadius: barH / 2, yRadius: barH / 2).addClip()
        NSColor.systemGreen.withAlphaComponent(0.45).setFill()
        NSRect(x: x(band.lowerBound), y: barY, width: x(band.upperBound) - x(band.lowerBound), height: barH).fill()
        NSGraphicsContext.restoreGraphicsState()

        if let tick {
            NSColor.labelColor.withAlphaComponent(0.55).setFill()
            NSRect(x: x(tick) - 0.75, y: barY - 3, width: 1.5, height: barH + 6).fill()
        }

        let labelY = barY + barH + 5
        // The target tick replaces the band's upper label when they would collide.
        let edges = tick == nil ? [(band.lowerBound, bandLabels.0), (band.upperBound, bandLabels.1)] : [(band.lowerBound, bandLabels.0)]
        for (v, fmt) in edges {
            text(String(format: fmt, v), at: NSPoint(x: x(v), y: labelY), size: 10, color: .tertiaryLabelColor,
                 align: .center, width: 40)
        }
        if let tick {
            text(String(format: "target %.0f", tick), at: NSPoint(x: x(tick), y: labelY), size: 10, weight: .medium,
                 color: .secondaryLabelColor, align: .center, width: 70)
        }

        guard let value, let st else { return }
        let d: CGFloat = 14
        let marker = NSRect(x: x(value) - d / 2, y: barY + barH / 2 - d / 2, width: d, height: d)
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(ovalIn: marker.insetBy(dx: -2, dy: -2)).fill()
        st.color.setFill()
        NSBezierPath(ovalIn: marker).fill()
    }

    private func pill(_ word: String, color: NSColor, at p: NSPoint) {
        let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let w = (word as NSString).size(withAttributes: [.font: font]).width + 12
        let r = NSRect(x: p.x, y: p.y, width: w, height: 16)
        color.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
        text(word, at: NSPoint(x: r.midX, y: p.y + 1.5), size: 10, weight: .semibold, color: color, align: .center, width: w)
    }

    // MARK: - Stats

    private func drawStats(_ c: Composition?, y: CGFloat) {
        NSColor.separatorColor.setFill()
        NSRect(x: pad, y: y - 10, width: bounds.width - pad * 2, height: 1).fill()
        let cells: [(String, String)] = [
            ("Muscle", c?.skeletalMuscleKg.map { String(format: "%.1f kg", $0) } ?? "—"),
            ("Lean mass", c?.ffmKg.map { String(format: "%.1f kg", $0) } ?? "—"),
            ("Bone", c?.boneKg.map { String(format: "%.1f kg", $0) } ?? "—"),
            ("BMR", c?.bmrKcal.map { "\($0) kcal" } ?? "—"),
        ]
        let colW = (bounds.width - pad * 2) / CGFloat(cells.count)
        for (i, cell) in cells.enumerated() {
            let x = pad + colW * CGFloat(i)
            text(cell.0, at: NSPoint(x: x, y: y), size: 11, color: .secondaryLabelColor, width: colW - 6)
            text(cell.1, at: NSPoint(x: x, y: y + 15), size: 14, weight: .semibold,
                 color: c == nil ? .tertiaryLabelColor : .labelColor, width: colW - 6, mono: true)
        }
    }

    // MARK: - Footer

    private func drawFooter(_ m: BodyModel) {
        var y: CGFloat = 506
        for note in m.notes {
            let h = paragraph(note, at: NSPoint(x: pad, y: y), width: bounds.width - pad * 2, size: 11, color: .secondaryLabelColor)
            y += h + 4
        }
        let buttonY = bounds.height - 38
        switch m.garmin {
        case .pushing?:
            text("Pushing to Garmin…", at: NSPoint(x: bounds.midX, y: buttonY + 5), size: 11, color: .secondaryLabelColor, align: .center, width: 180)
        case .pushed(let at)?:
            text("✓ On Garmin since \(at)", at: NSPoint(x: bounds.midX, y: buttonY + 5), size: 11, color: .systemGreen, align: .center, width: 180)
        case .failed(let e)?:
            text("Garmin: \(e)", at: NSPoint(x: pad, y: buttonY - 16), size: 10, color: .systemRed, width: bounds.width - pad * 2)
        default:
            break
        }
    }

    // MARK: - Text

    /// Centered alignment uses `at.x` as the midpoint; left/right use it as the box origin.
    private func text(_ s: String, at p: NSPoint, size: CGFloat, weight: NSFont.Weight = .regular,
                      color: NSColor, align: NSTextAlignment = .left, width: CGFloat = 0, mono: Bool = false) {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineBreakMode = .byTruncatingTail
        let font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let w = width > 0 ? width : (align == .center ? bounds.width - 32 : bounds.width - p.x - 16)
        let x = align == .center ? p.x - w / 2 : p.x
        (s as NSString).draw(in: NSRect(x: x, y: p.y, width: w, height: size * 1.5), withAttributes: attrs)
    }

    /// Wrapping text; returns the height used.
    private func paragraph(_ s: String, at p: NSPoint, width: CGFloat, size: CGFloat, color: NSColor) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color]
        let r = (s as NSString).boundingRect(with: NSSize(width: width, height: 200), options: [.usesLineFragmentOrigin], attributes: attrs)
        (s as NSString).draw(with: NSRect(x: p.x, y: p.y, width: width, height: ceil(r.height)), options: [.usesLineFragmentOrigin], attributes: attrs)
        return ceil(r.height)
    }
}
