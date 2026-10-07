import Foundation
import SQLite3
import ScaleBarCore

/// Writes to the same `weighin` table as scale/weigh.py. Garmin push stays in weigh.py.
struct WeighinStore {
    let path: String

    static var `default`: WeighinStore {
        let p = UserDefaults.standard.string(forKey: "dbPath") ?? NSHomeDirectory() + "/health/health.db"
        return WeighinStore(path: p)
    }

    static func dayLabel(_ ts: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        guard let d = f.date(from: ts) else { return String(ts.prefix(10)) }
        let out = DateFormatter()
        out.dateFormat = "d MMM"
        return out.string(from: d)
    }

    static func timestamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.string(from: d)
    }

    /// Newest row, including ones that never got an impedance value.
    func latest() -> (ts: String, kg: Double, ohm: Int?, pushedAt: String?)? {
        guard FileManager.default.fileExists(atPath: path), let db = open() else { return nil }
        defer { sqlite3_close(db) }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "select ts, weight_kg, impedance_ohm, garmin_pushed_at from weighin order by ts desc limit 1", -1, &st, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(st) }
        guard sqlite3_step(st) == SQLITE_ROW, let c = sqlite3_column_text(st, 0) else { return nil }
        let ohm: Int? = sqlite3_column_type(st, 2) == SQLITE_NULL ? nil : Int(sqlite3_column_int(st, 2))
        let pushed = sqlite3_column_text(st, 3).map { String(cString: $0) }
        return (String(cString: c), sqlite3_column_double(st, 1), ohm, pushed)
    }

    /// Every measured impedance, oldest first.
    func impedances() -> [Int] {
        guard FileManager.default.fileExists(atPath: path), let db = open() else { return [] }
        defer { sqlite3_close(db) }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "select impedance_ohm from weighin where impedance_ohm is not null order by ts", -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        var out: [Int] = []
        while sqlite3_step(st) == SQLITE_ROW { out.append(Int(sqlite3_column_int(st, 0))) }
        return out
    }

    /// Most recent earlier weigh-in that actually measured impedance. Retries with no
    /// impedance would otherwise show up as a +0.00 kg change a few minutes later.
    func previous(before ts: String) -> (ts: String, kg: Double)? {
        guard FileManager.default.fileExists(atPath: path), let db = open() else { return nil }
        defer { sqlite3_close(db) }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "select ts, weight_kg from weighin where ts < ? and impedance_ohm is not null order by ts desc limit 1", -1, &st, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(st) }
        bind(st, 1, ts)
        guard sqlite3_step(st) == SQLITE_ROW, let c = sqlite3_column_text(st, 0) else { return nil }
        return (String(cString: c), sqlite3_column_double(st, 1))
    }

    func save(_ r: Reading, _ c: Composition, profile p: Profile) throws {
        guard let db = open() else { throw err("cannot open \(path)") }
        defer { sqlite3_close(db) }
        let create = """
            create table if not exists weighin(ts text primary key, weight_kg real, impedance_ohm integer,
            bmi real, fat_pct real, fat_kg real, ffm_kg real, water_pct real, skeletal_muscle_kg real, bone_kg real,
            bmr_kcal integer, profile text, frames text, garmin_pushed_at text, garmin_fields text)
            """
        guard sqlite3_exec(db, create, nil, nil, nil) == SQLITE_OK else { throw err(String(cString: sqlite3_errmsg(db))) }
        let sql = "insert or replace into weighin(ts, weight_kg, impedance_ohm, bmi, fat_pct, fat_kg, ffm_kg, water_pct,"
            + " skeletal_muscle_kg, bone_kg, bmr_kcal, profile, frames) values(?,?,?,?,?,?,?,?,?,?,?,?,?)"
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { throw err(String(cString: sqlite3_errmsg(db))) }
        defer { sqlite3_finalize(st) }
        let framesJSON = String(data: try JSONSerialization.data(withJSONObject: r.frames), encoding: .utf8)
        let values: [Any?] = [
            Self.timestamp(r.date), r.weight, r.impedance, c.bmi, c.fatPct, c.fatKg, c.ffmKg, c.waterPct,
            c.skeletalMuscleKg, c.boneKg, c.bmrKcal,
            "{\"sex\": \(p.sex), \"age\": \(p.age), \"height_cm\": \(p.heightCm)}", framesJSON,
        ]
        for (i, v) in values.enumerated() {
            let idx = Int32(i + 1)
            switch v {
            case let s as String: bind(st, idx, s)
            case let d as Double: sqlite3_bind_double(st, idx, d)
            case let n as Int: sqlite3_bind_int64(st, idx, Int64(n))
            default: sqlite3_bind_null(st, idx)
            }
        }
        guard sqlite3_step(st) == SQLITE_DONE else { throw err(String(cString: sqlite3_errmsg(db))) }
    }

    private func open() -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else { sqlite3_close(db); return nil }
        sqlite3_busy_timeout(db, 30_000)
        return db
    }

    private func bind(_ st: OpaquePointer?, _ i: Int32, _ s: String) {
        sqlite3_bind_text(st, i, s, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func err(_ msg: String) -> NSError {
        NSError(domain: "ScaleBar", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
