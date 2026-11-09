import Foundation
import CarapaceCore

struct CLIError: Error {
    let code: String
    let message: String
    let hint: String?
    let exitCode: Int32

    static func usage(_ message: String) -> CLIError {
        CLIError(code: "USAGE", message: message, hint: "运行 carapace --help 查看命令", exitCode: 2)
    }

    static func validation(_ message: String) -> CLIError {
        CLIError(code: "VALIDATION", message: message, hint: nil, exitCode: 3)
    }

    static func notFound(_ message: String) -> CLIError {
        CLIError(code: "NOT_FOUND", message: message, hint: nil, exitCode: 4)
    }

    static func conflict(_ message: String) -> CLIError {
        CLIError(code: "CONFLICT", message: message, hint: "重新读取后再提交", exitCode: 5)
    }

    static func database(_ message: String) -> CLIError {
        CLIError(code: "DB", message: message, hint: "检查数据库权限或是否被占用", exitCode: 6)
    }

    static func quote(_ message: String) -> CLIError {
        CLIError(code: "QUOTE", message: message, hint: "检查网络或稍后重试", exitCode: 7)
    }
}

func mapStoreError(_ error: StoreError) -> CLIError {
    switch error {
    case .validation(let message):
        return .validation(message)
    case .notFound(let message):
        return .notFound(message)
    case .conflict(let message, _):
        return .conflict(message)
    case .open(let message), .sql(let message):
        return .database(message)
    }
}

enum Output {
    static func success(_ data: Any, args: CLIArgs, store: Store?) {
        var meta: [String: Any] = [
            "api_version": CarapaceBuild.apiVersion,
            "app_version": CarapaceBuild.version,
            "as_of": Dates.now()
        ]
        if let store {
            meta["db"] = store.path
            if let schema = try? store.schemaVersion() {
                meta["schema_version"] = schema
            }
        }
        if let requestId = args.requestId {
            meta["request_id"] = requestId
        }
        emit(["ok": true, "data": data, "meta": meta], text: args.text)
    }

    static func failure(_ error: CLIError) {
        var body: [String: Any] = [
            "code": error.code,
            "message": error.message
        ]
        if let hint = error.hint { body["hint"] = hint }
        emit([
            "ok": false,
            "error": body,
            "meta": [
                "api_version": CarapaceBuild.apiVersion,
                "app_version": CarapaceBuild.version
            ]
        ], text: false)
    }

    private static func emit(_ object: [String: Any], text: Bool) {
        if text, let data = object["data"] {
            print(textDescription(data))
            return
        }
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            FileHandle.standardOutput.write(Data("{\"ok\":false,\"error\":{\"code\":\"INTERNAL\",\"message\":\"JSON 编码失败\"}}\n".utf8))
            return
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func textDescription(_ value: Any) -> String {
        if let rows = value as? [[String: Any]] {
            return rows.map { row in
                row.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "  ")
            }.joined(separator: "\n")
        }
        if let dict = value as? [String: Any] {
            return dict.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n")
        }
        return "\(value)"
    }
}

/// 把任意 Codable 值转成 JSONSerialization 能接受的 Any。
func jsonable<T: Encodable>(_ value: T) -> Any {
    guard let data = try? JSONEncoder().encode(value),
          let object = try? JSONSerialization.jsonObject(with: data) else {
        return NSNull()
    }
    return object
}