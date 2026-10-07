import Foundation

/// Pushes a saved health.db row through `scale/weigh.py --push`, so Garmin auth (tokens in
/// ~/.garminconnect) and the "weight + BMI only" rule stay in one place.
enum GarminPush {
    static func run(ts: String, dbPath: String, completion: @escaping (Result<String, Error>) -> Void) {
        let candidates = [NSHomeDirectory() + "/.local/bin/uv", "/opt/homebrew/bin/uv", "/usr/local/bin/uv"]
        guard let uv = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return completion(.failure(err("uv not found. Install it from https://docs.astral.sh/uv/")))
        }
        guard let script = scriptURL(dbPath: dbPath) else {
            return completion(.failure(err("Garmin push script not found. See the README.")))
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: uv)
        if script.hasSuffix("weigh.py") {
            p.arguments = ["run", "--quiet", script, "--push", ts]
            p.currentDirectoryURL = URL(fileURLWithPath: dbPath).deletingLastPathComponent()
        } else {
            p.arguments = ["run", "--quiet", script, "--db", dbPath, "--push", ts]
        }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        p.environment = env
        // A login prompt must fail instead of waiting forever on a stdin nobody can see.
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), errPipe = Pipe()
        p.standardOutput = out
        p.standardError = errPipe

        let timeout = DispatchWorkItem { if p.isRunning { p.terminate() } }
        p.terminationHandler = { proc in
            timeout.cancel()
            let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let result: Result<String, Error> = proc.terminationStatus == 0
                ? .success(lastLine(stdout))
                : .failure(err(proc.terminationReason == .uncaughtSignal ? "timed out" : lastLine(stderr + stdout)))
            DispatchQueue.main.async { completion(result) }
        }
        do {
            try p.run()
            DispatchQueue.global().asyncAfter(deadline: .now() + 120, execute: timeout)
        } catch {
            completion(.failure(error))
        }
    }

    /// The app bundle ships `garmin_push.py`. A health-repo checkout can also use `scale/weigh.py`.
    private static func scriptURL(dbPath: String) -> String? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("garmin_push.py").path
        let weigh = URL(fileURLWithPath: dbPath).deletingLastPathComponent()
            .appendingPathComponent("scale/weigh.py").path
        return [bundled, weigh].compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0) }
    }

    private static func lastLine(_ s: String) -> String {
        s.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
    }

    private static func err(_ msg: String) -> NSError {
        NSError(domain: "ScaleBar", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
