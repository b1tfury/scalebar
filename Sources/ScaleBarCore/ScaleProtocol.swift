import Foundation

/// Dr Trust 509 ("SWAN", Icomon/MGB 8-byte streaming variant). Mirrors scale/weigh.py.
public enum ScaleProtocol {
    public static let service = "FFB0"
    public static let config = "FFB1"
    public static let control = "FFB2"

    public enum Frame: Equatable {
        case live(Double)
        case locked(Double)
        /// `FD 01 HI LO`: a measured value, in ohms.
        case impedance(Int)
        /// `FD FF`: the scale finished and has no measurement.
        case impedanceUnavailable
    }

    public static func parse(_ d: [UInt8]) -> Frame? {
        guard d.count == 8, d[0] == 0xAC, d[1] == 0x02,
              d[2..<7].reduce(0, { $0 &+ $1 }) == d[7] else { return nil }
        let kg = Double(Int(d[2]) << 8 | Int(d[3])) / 100
        switch d[6] {
        case 0xCE where d[4] == 0 && d[5] == 0 && (d[2] | d[3]) != 0: return .live(kg)
        case 0xCA where d[4] == 0 && d[5] == 0: return .locked(kg)
        case 0xCB where d[2] == 0xFD:
            // `FD 00` only opens the measurement. Staying connected is what lets `FD 01` arrive.
            switch d[3] {
            case 0x01: return .impedance(Int(d[4]) << 8 | Int(d[5]))
            case 0xFF: return .impedanceUnavailable
            default: return nil
            }
        default: return nil
        }
    }

    static func packet(_ b2: Int, _ b3: Int, _ b4: Int, _ b5: Int) -> [UInt8] {
        var b: [UInt8] = [0xAC, 0x02, UInt8(b2 & 255), UInt8(b3 & 255), UInt8(b4 & 255), UInt8(b5 & 255), 0xCC]
        b.append(b[2..<7].reduce(0, { $0 &+ $1 }))
        return b
    }

    /// Packets written to the config characteristic after subscribing, in order.
    public static func configPackets(profile: Profile, now: Date = Date()) -> [[UInt8]] {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        return [
            packet(0xF7, 0, 0, 0), packet(0xFA, 0, 0, 0),
            packet(0xFB, profile.sex, profile.age, profile.heightCm),
            packet(0xFD, c.year! - 2000, c.month!, c.day!),
            packet(0xFC, c.hour!, c.minute!, c.second!),
            packet(0xFE, 6, 1, 0),
        ]
    }
}
