import CoreGraphics

/// Minimal SVG path parser for the commands Inkscape writes into a single filled shape:
/// M/m, L/l, C/c and Z/z with space-separated "x,y" pairs.
public enum SVGPath {
    public static func parse(_ d: String) -> CGPath? {
        let tokens = d.replacingOccurrences(of: ",", with: " ").split(whereSeparator: \.isWhitespace)
        let path = CGMutablePath()
        var cmd: Character = "M"
        var cur = CGPoint.zero
        var start = CGPoint.zero
        var i = 0

        func num() -> CGFloat? {
            guard i < tokens.count, let v = Double(tokens[i]) else { return nil }
            i += 1
            return CGFloat(v)
        }
        func point(relative: Bool) -> CGPoint? {
            guard let x = num(), let y = num() else { return nil }
            return relative ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
        }

        while i < tokens.count {
            let t = tokens[i]
            if t.count == 1, let c = t.first, c.isLetter {
                i += 1
                cmd = c
                if c == "z" || c == "Z" {
                    path.closeSubpath()
                    cur = start
                }
                continue
            }
            let rel = cmd.isLowercase
            switch cmd {
            case "m", "M":
                guard let p = point(relative: rel) else { return nil }
                path.move(to: p)
                cur = p
                start = p
                // Further pairs after a moveto are linetos.
                cmd = rel ? "l" : "L"
            case "l", "L":
                guard let p = point(relative: rel) else { return nil }
                path.addLine(to: p)
                cur = p
            case "c", "C":
                let origin = cur
                guard let x1 = num(), let y1 = num(), let x2 = num(), let y2 = num(), let x = num(), let y = num() else { return nil }
                let o = rel ? origin : .zero
                let end = CGPoint(x: o.x + x, y: o.y + y)
                path.addCurve(to: end, control1: CGPoint(x: o.x + x1, y: o.y + y1), control2: CGPoint(x: o.x + x2, y: o.y + y2))
                cur = end
            default:
                return nil
            }
        }
        return path
    }
}
