import CoreBluetooth
import Foundation
import ScaleBarCore

struct Reading {
    var date: Date
    var weight: Double
    var impedance: Int?
    var frames: [String]
}

enum ScanState {
    case idle
    case scanning(until: Date)
    case connecting
    case waitingForStep(until: Date)
    case live(Double)
    case locked(Double)
    case done(Reading)
    case failed(String)

    var isActive: Bool {
        switch self {
        case .idle, .done, .failed: return false
        default: return true
        }
    }
}

/// One-shot BLE session with the scale. The CBCentralManager only exists while a session runs,
/// so Bluetooth is untouched while idle. Main thread only.
final class ScaleReader: NSObject {
    var onChange: ((ScanState) -> Void)?
    private(set) var state: ScanState = .idle { didSet { onChange?(state) } }

    private let profile: Profile
    private let timeout: TimeInterval
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var deadline = Date()
    private var deadlineTimer: Timer?
    private var impedanceTimer: Timer?
    private var weight: Double?
    private var frames: [String] = []

    init(profile: Profile, timeout: TimeInterval = 300) {
        self.profile = profile
        self.timeout = timeout
    }

    func start() {
        guard !state.isActive else { return }
        weight = nil
        frames = []
        deadline = Date().addingTimeInterval(timeout)
        state = .scanning(until: deadline)
        deadlineTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.finish(.failed("No reading in \(Int(self?.timeout ?? 0) / 60) min. Step on the scale and scan again."))
        }
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func cancel() {
        guard state.isActive else { return }
        finish(.idle)
    }

    private func finish(_ end: ScanState) {
        deadlineTimer?.invalidate()
        impedanceTimer?.invalidate()
        deadlineTimer = nil
        impedanceTimer = nil
        if let central {
            if central.isScanning { central.stopScan() }
            if let peripheral { central.cancelPeripheralConnection(peripheral) }
        }
        peripheral = nil
        central = nil
        state = end
    }

    private func complete(impedance: Int?) {
        guard let weight else { return }
        finish(.done(Reading(date: Date(), weight: weight, impedance: impedance, frames: frames)))
    }

    private func scan() {
        state = .scanning(until: deadline)
        central?.scanForPeripherals(withServices: nil)
    }
}

extension ScaleReader: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn: scan()
        case .poweredOff: finish(.failed("Bluetooth is off."))
        case .unauthorized: finish(.failed("Bluetooth access denied. Allow ScaleBar in System Settings > Privacy > Bluetooth."))
        case .unsupported: finish(.failed("Bluetooth LE not supported."))
        default: break
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData ad: [String: Any], rssi: NSNumber) {
        let name = (ad[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""
        let services = ad[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard name.uppercased().hasPrefix("SWAN") || services.contains(CBUUID(string: ScaleProtocol.service)) else { return }
        c.stopScan()
        peripheral = p
        p.delegate = self
        state = .connecting
        c.connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([CBUUID(string: ScaleProtocol.service)])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        peripheral = nil
        scan()
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        guard state.isActive else { return }
        peripheral = nil
        // Scale went to sleep: keep the locked weight if we have one, otherwise look for it again.
        if weight != nil { complete(impedance: nil) } else { scan() }
    }
}

extension ScaleReader: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = p.services?.first(where: { $0.uuid == CBUUID(string: ScaleProtocol.service) }) else {
            return finish(.failed("Scale found but its service is missing."))
        }
        p.discoverCharacteristics([CBUUID(string: ScaleProtocol.config), CBUUID(string: ScaleProtocol.control)], for: svc)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor svc: CBService, error: Error?) {
        let chars = svc.characteristics ?? []
        guard let cfg = chars.first(where: { $0.uuid == CBUUID(string: ScaleProtocol.config) }),
              let ctrl = chars.first(where: { $0.uuid == CBUUID(string: ScaleProtocol.control) }) else {
            return finish(.failed("Scale characteristics missing."))
        }
        p.setNotifyValue(true, for: ctrl)
        let type: CBCharacteristicWriteType = cfg.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        for (i, packet) in ScaleProtocol.configPackets(profile: profile).enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 * Double(i + 1)) { [weak self, weak p] in
                guard let self, let p, self.peripheral === p else { return }
                p.writeValue(Data(packet), for: cfg, type: type)
            }
        }
        state = .waitingForStep(until: deadline)
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let data = ch.value else { return }
        let bytes = [UInt8](data)
        frames.append(bytes.map { String(format: "%02x", $0) }.joined())
        switch ScaleProtocol.parse(bytes) {
        case .live(let kg)?:
            if weight == nil { state = .live(kg) }
        case .locked(let kg)?:
            weight = kg
            state = .locked(kg)
            impedanceTimer?.invalidate()
            impedanceTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
                self?.complete(impedance: nil)
            }
        case .impedance(let ohm)?:
            // A value sent before the weight locks is the previous reading, replayed on connect.
            if weight != nil { complete(impedance: ohm) }
        case .impedanceUnavailable?:
            if weight != nil { complete(impedance: nil) }
        case nil:
            break
        }
    }
}
