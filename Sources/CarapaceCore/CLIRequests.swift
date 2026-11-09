import Foundation
import SQLite3

extension Store {
    /// 在同一个事务里执行写操作并记录 request_id，重试时直接返回上次结果。
    /// body 返回 JSON 字符串，由 CLI 直接嵌入成功 envelope。
    public func writeIdempotentJSON(
        requestId: String?,
        command: String,
        body: () throws -> String
    ) throws -> String {
        try write {
            if let requestId, let cached = try cachedCLIResult(requestId) {
                return cached
            }
            let json = try body()
            if let requestId {
                try saveCLIResult(requestId: requestId, command: command, json: json)
            }
            return json
        }
    }

    func cachedCLIResult(_ requestId: String) throws -> String? {
        let stmt = try prepare("SELECT result_json FROM cli_requests WHERE id = ?")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, requestId)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return text(stmt, 0)
    }

    func saveCLIResult(requestId: String, command: String, json: String) throws {
        let stmt = try prepare("""
        INSERT OR REPLACE INTO cli_requests (id, command, result_json, created_at)
        VALUES (?, ?, ?, ?)
        """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, requestId)
        bind(stmt, 2, command)
        bind(stmt, 3, json)
        bind(stmt, 4, Dates.now())
        try stepDone(stmt)
    }
}