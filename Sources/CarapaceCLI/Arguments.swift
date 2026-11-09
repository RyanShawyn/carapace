import Foundation

struct CLIArgs {
    var positionals: [String] = []
    var flags: [String: String] = [:]
    var switches: Set<String> = []

    var text = false
    var dryRun = false
    var yes = false
    var noNotify = false
    var requestId: String?
    var dbPath: String?

    private static let boolFlags: Set<String> = [
        "json", "text", "dry-run", "yes", "no-notify",
        "closed", "include-closed", "refresh", "no-quotes",
        "include-done", "unread", "resolved", "complete", "default", "help",
        "include-needs-review"
    ]

    init(_ raw: [String]) throws {
        var index = 0
        while index < raw.count {
            let arg = raw[index]
            if arg.hasPrefix("--") {
                let body = String(arg.dropFirst(2))
                if body.isEmpty { index += 1; continue }
                if let equals = body.firstIndex(of: "=") {
                    let key = String(body[..<equals])
                    let value = String(body[body.index(after: equals)...])
                    flags[key] = value
                } else if Self.boolFlags.contains(body) {
                    switches.insert(body)
                } else if index + 1 < raw.count, !raw[index + 1].hasPrefix("-") {
                    flags[body] = raw[index + 1]
                    index += 1
                } else {
                    switches.insert(body)
                }
            } else {
                positionals.append(arg)
            }
            index += 1
        }

        text = switches.contains("text") || flags["format"] == "text"
        dryRun = switches.contains("dry-run")
        yes = switches.contains("yes")
        noNotify = switches.contains("no-notify")
        requestId = flags["request-id"]
        dbPath = flags["db"]
    }

    var group: String { positionals.first ?? "" }
    var verb: String? { positionals.count > 1 ? positionals[1] : nil }

    func value(_ key: String) -> String? {
        guard let value = flags[key], !value.isEmpty else { return nil }
        return value
    }

    func require(_ key: String) throws -> String {
        guard let value = value(key) else {
            throw CLIError.usage("缺少 --\(key)")
        }
        return value
    }

    func int64(_ key: String) throws -> Int64? {
        guard let raw = value(key) else { return nil }
        guard let value = Int64(raw) else {
            throw CLIError.usage("--\(key) 必须是整数")
        }
        return value
    }

    func double(_ key: String) throws -> Double? {
        guard let raw = value(key) else { return nil }
        guard let value = Double(raw), value.isFinite else {
            throw CLIError.usage("--\(key) 必须是数字")
        }
        return value
    }

    func bool(_ key: String) -> Bool {
        switches.contains(key)
    }

    func requireYes(_ action: String) throws {
        guard yes else {
            throw CLIError.usage("\(action) 需要用户确认，追加 --yes")
        }
    }
}