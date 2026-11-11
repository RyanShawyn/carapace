import Foundation
import SQLite3
import Darwin

public enum StoreError: LocalizedError {
    case open(String)
    case sql(String)
    case validation(String)
    case notFound(String)
    case conflict(String, Plan?)

    public var errorDescription: String? {
        switch self {
        case .open(let m): return "打开数据库失败：\(m)"
        case .sql(let m): return "数据库错误：\(m)"
        case .validation(let m): return m
        case .notFound(let m): return m
        case .conflict(let m, _): return m
        }
    }

    public var conflictPlan: Plan? {
        if case .conflict(_, let plan) = self { return plan }
        return nil
    }
}

public final class Store: @unchecked Sendable {
    var db: OpaquePointer?
    let lock = NSRecursiveLock()
    private var writeDepth = 0
    static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    public let path: String

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Carapace", isDirectory: true)
    }

    public static var defaultPath: String {
        if let override = ProcessInfo.processInfo.environment["CARAPACE_DB"], !override.isEmpty {
            return override
        }
        return defaultDirectory.appendingPathComponent("store.sqlite3").path
    }

    public convenience init() throws {
        try self.init(path: Store.defaultPath)
    }

    public init(path: String) throws {
        self.path = path
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)

        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        guard rc == SQLITE_OK, db != nil else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(rc)"
            throw StoreError.open(msg)
        }
        sqlite3_busy_timeout(db, 3000)
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA foreign_keys=ON;")
        try migrate()
        chmod(path, 0o600)
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Schema

    func migrate() throws {
        let version = try schemaVersion()
        if version > 0 && version < 8 { try backupBeforeMigration(version: version) }

        // v8 需要重建 reviews/drafts 并删除 AI 表；外键检查必须在事务外关闭。
        try exec("PRAGMA foreign_keys=OFF;")
        try exec("BEGIN IMMEDIATE;")
        do {
            let current = try schemaVersion()
            try exec("""
        CREATE TABLE IF NOT EXISTS positions (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          code       TEXT NOT NULL,
          name       TEXT NOT NULL,
          source     TEXT NOT NULL,
          unit       TEXT NOT NULL,
          quantity   REAL NOT NULL DEFAULT 0,
          avg_cost   REAL NOT NULL DEFAULT 0,
          status     TEXT NOT NULL DEFAULT 'open',
          opened_at  TEXT NOT NULL,
          closed_at  TEXT,
          kind       TEXT NOT NULL DEFAULT 'holding',
          note       TEXT,
          watch_price REAL,
          market     TEXT NOT NULL DEFAULT 'cn',
          quote_key  TEXT
        );
        CREATE TABLE IF NOT EXISTS plans (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          position_id INTEGER NOT NULL UNIQUE REFERENCES positions(id),
          version     INTEGER NOT NULL DEFAULT 1,
          author      TEXT NOT NULL,
          description TEXT,
          next_review TEXT,
          levels      TEXT NOT NULL,
          updated_at  TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS changes (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          position_id   INTEGER NOT NULL REFERENCES positions(id),
          type          TEXT NOT NULL,
          qty_before    REAL,
          qty_after     REAL,
          cost_before   REAL,
          cost_after    REAL,
          price         REAL,
          fee           REAL,
          level_price   REAL,
          level_id     TEXT,
          plan_version INTEGER,
          direction    TEXT,
          plan_snapshot TEXT,
          note          TEXT,
          occurred_at   TEXT NOT NULL,
          created_at    TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_changes_position ON changes(position_id, id);
        CREATE INDEX IF NOT EXISTS idx_positions_status ON positions(status);
        CREATE TABLE IF NOT EXISTS meta (
          key   TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
        """)
        if current < 3 {
            // v2: 行情源改为东方财富 / 新浪，旧数据就地迁移。
            try exec("UPDATE positions SET source = 'eastmoney' WHERE source = 'tencent';")
            try exec("UPDATE positions SET source = 'sina' WHERE source = 'sge';")
            // v3: 档位、计划执行、提醒都使用稳定标识，而不是浮点价格。
            if try hasColumn("changes", name: "level_id") == false {
                try exec("ALTER TABLE changes ADD COLUMN level_id TEXT;")
            }
            if try hasColumn("changes", name: "plan_version") == false {
                try exec("ALTER TABLE changes ADD COLUMN plan_version INTEGER;")
            }
            if try hasColumn("changes", name: "direction") == false {
                try exec("ALTER TABLE changes ADD COLUMN direction TEXT;")
            }
            try exec("""
            CREATE TABLE IF NOT EXISTS alerts (
              id TEXT PRIMARY KEY,
              position_id INTEGER REFERENCES positions(id),
              kind TEXT NOT NULL,
              title TEXT NOT NULL,
              detail TEXT NOT NULL,
              first_triggered_at TEXT NOT NULL,
              last_triggered_at TEXT NOT NULL,
              acknowledged_at TEXT,
              resolved_at TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_alerts_active ON alerts(resolved_at, kind);
            """)
            try exec("UPDATE changes SET direction = 'buy' WHERE type = 'buy' AND direction IS NULL;")
            try exec("UPDATE changes SET direction = 'sell' WHERE type = 'sell' AND direction IS NULL;")
            try migratePlanLevelIDs()
            try exec("PRAGMA user_version = 3;")
        }
        if current < 5 { try migrateV5() }
        if current < 6 { try migrateV6() }
        if current < 7 { try migrateV7() }
        if current < 8 { try migrateV8() }
        try exec("PRAGMA user_version = 8;")
        try exec("COMMIT;")
        try exec("PRAGMA foreign_keys=ON;")
        } catch {
            try? exec("ROLLBACK;")
            try? exec("PRAGMA foreign_keys=ON;")
            throw error
        }
    }

    func hasColumn(_ table: String, name: String) throws -> Bool {
        let stmt = try prepare("PRAGMA table_info(\(table));")
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if text(stmt, 1) == name { return true }
        }
        return false
    }

    func migratePlanLevelIDs() throws {
        let stmt = try prepare("SELECT position_id, levels FROM plans;")
        var rows: [(Int64, String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append((sqlite3_column_int64(stmt, 0), text(stmt, 1) ?? "[]"))
        }
        sqlite3_finalize(stmt)
        for (id, raw) in rows {
            guard let data = raw.data(using: .utf8),
                  let levels = try? JSONDecoder().decode([PlanLevel].self, from: data) else { continue }
            let update = try prepare("UPDATE plans SET levels = ? WHERE position_id = ?")
            defer { sqlite3_finalize(update) }
            bind(update, 1, encode(levels))
            sqlite3_bind_int64(update, 2, id)
            try stepDone(update)
        }
    }

    public func schemaVersion() throws -> Int {
        let stmt = try prepare("PRAGMA user_version;")
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    public func tableExists(_ name: String) throws -> Bool {
        let stmt = try prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, name)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    func backupBeforeMigration(version: Int) throws {
        let destination = path + ".\(version)-backup"
        if FileManager.default.fileExists(atPath: destination) { return }
        let escapedDestination = destination.replacingOccurrences(of: "'", with: "''")
        try exec("VACUUM INTO '\(escapedDestination)';")
        chmod(destination, 0o600)
    }

    // MARK: - SQLite helpers

    func exec(_ sql: String) throws {
        guard let db else { throw StoreError.open("连接已关闭") }
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(err)
            throw StoreError.sql(msg)
        }
    }

    func prepare(_ sql: String) throws -> OpaquePointer {
        guard let db else { throw StoreError.open("连接已关闭") }
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            throw StoreError.sql(String(cString: sqlite3_errmsg(db)))
        }
        return stmt
    }

    func stepDone(_ stmt: OpaquePointer) throws {
        guard let db else { throw StoreError.open("连接已关闭") }
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw StoreError.sql(String(cString: sqlite3_errmsg(db)))
        }
    }

    func bind(_ stmt: OpaquePointer, _ i: Int32, _ v: String?) {
        if let v { sqlite3_bind_text(stmt, i, v, -1, Store.transient) }
        else { sqlite3_bind_null(stmt, i) }
    }

    func bind(_ stmt: OpaquePointer, _ i: Int32, _ v: Double?) {
        if let v { sqlite3_bind_double(stmt, i, v) }
        else { sqlite3_bind_null(stmt, i) }
    }

    func text(_ stmt: OpaquePointer, _ i: Int32) -> String? {
        guard sqlite3_column_type(stmt, i) != SQLITE_NULL,
              let c = sqlite3_column_text(stmt, i) else { return nil }
        return String(cString: c)
    }

    func double(_ stmt: OpaquePointer, _ i: Int32) -> Double? {
        sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, i)
    }

    func lastID() -> Int64 { sqlite3_last_insert_rowid(db) }

    func write<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }

        // 嵌套写入使用 SAVEPOINT，便于幂等包装器在同一个事务里记录结果。
        if writeDepth > 0 {
            try exec("SAVEPOINT carapace_sp;")
            do {
                let value = try body()
                try exec("RELEASE carapace_sp;")
                return value
            } catch {
                try? exec("ROLLBACK TO carapace_sp;")
                try? exec("RELEASE carapace_sp;")
                throw error
            }
        }

        writeDepth += 1
        defer { writeDepth -= 1 }
        try exec("BEGIN IMMEDIATE;")
        do {
            let value = try body()
            try exec("COMMIT;")
            return value
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    func read<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    // MARK: - Reads

    static let positionColumns = "id, code, name, source, unit, quantity, avg_cost, status, opened_at, closed_at, kind, note, watch_price, market, quote_key"

    public func positions(includeClosed: Bool = false) throws -> [Position] {
        return try read {
            let sql = """
            SELECT \(Self.positionColumns)
            FROM positions
            \(includeClosed ? "WHERE kind = 'holding'" : "WHERE kind = 'holding' AND status = 'open'")
            ORDER BY id
            """
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            var out: [Position] = []
            while sqlite3_step(stmt) == SQLITE_ROW { out.append(readPosition(stmt)) }
            return out
        }
    }

    /// 观察标的：数量/成本恒为 0，不参与组合计算。
    public func watches() throws -> [Position] {
        try read {
            let stmt = try prepare("""
            SELECT \(Self.positionColumns)
            FROM positions WHERE kind = 'watch' AND status = 'open'
            ORDER BY id
            """)
            defer { sqlite3_finalize(stmt) }
            var out: [Position] = []
            while sqlite3_step(stmt) == SQLITE_ROW { out.append(readPosition(stmt)) }
            return out
        }
    }

    /// 开放持仓 + 观察标的，供行情刷新使用。
    public func trackedPositions() throws -> [Position] {
        try read {
            let stmt = try prepare("""
            SELECT \(Self.positionColumns)
            FROM positions WHERE status = 'open' AND kind IN ('holding', 'watch')
            ORDER BY id
            """)
            defer { sqlite3_finalize(stmt) }
            var out: [Position] = []
            while sqlite3_step(stmt) == SQLITE_ROW { out.append(readPosition(stmt)) }
            return out
        }
    }

    public func position(id: Int64) throws -> Position? {
        return try read {
            let stmt = try prepare("""
            SELECT \(Self.positionColumns)
            FROM positions WHERE id = ?
            """)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, id)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return readPosition(stmt)
        }
    }

    public func openPosition(code: String) throws -> Position? {
        return try read {
            let stmt = try prepare("""
            SELECT \(Self.positionColumns)
            FROM positions WHERE code = ? AND kind = 'holding' AND status = 'open' LIMIT 1
            """)
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, normalizeCode(code))
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return readPosition(stmt)
        }
    }

    public func watchPosition(code: String, market: InstrumentMarket = .cn) throws -> Position? {
        try read {
            let stmt = try prepare("""
            SELECT \(Self.positionColumns)
            FROM positions
            WHERE code = ? AND market = ? AND kind = 'watch' AND status = 'open'
            LIMIT 1
            """)
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, normalizeCode(code))
            bind(stmt, 2, market.rawValue)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return readPosition(stmt)
        }
    }

    public func plan(positionId: Int64) throws -> Plan? {
        return try read {
            let stmt = try prepare("""
            SELECT id, position_id, version, author, description, next_review, levels, updated_at
            FROM plans WHERE position_id = ?
            """)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, positionId)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return readPlan(stmt)
        }
    }

    public func changes(positionId: Int64, type: ChangeType? = nil, limit: Int = 500) throws -> [Change] {
        guard limit > 0 else { return [] }
        let limit = min(limit, 2000)
        return try read {
            let stmt = try prepare("""
            SELECT id, position_id, type, qty_before, qty_after, cost_before, cost_after,
                   price, fee, level_price, level_id, plan_version, direction,
                   plan_snapshot, note, occurred_at, created_at
            FROM changes WHERE position_id = ? \(type == nil ? "" : "AND type = ?")
            ORDER BY id DESC LIMIT ?
            """)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, positionId)
            var index: Int32 = 2
            if let type { bind(stmt, index, type.rawValue); index += 1 }
            sqlite3_bind_int(stmt, index, Int32(limit))
            var out: [Change] = []
            while sqlite3_step(stmt) == SQLITE_ROW { out.append(readChange(stmt)) }
            return out
        }
    }

    public func allChanges(type: ChangeType? = nil, limit: Int = 500) throws -> [Change] {
        let limit = min(max(limit, 1), 100_000)
        return try read {
            let sql = """
            SELECT id, position_id, type, qty_before, qty_after, cost_before, cost_after,
                   price, fee, level_price, level_id, plan_version, direction,
                   plan_snapshot, note, occurred_at, created_at
            FROM changes
            \(type == nil ? "" : "WHERE type = ?")
            ORDER BY id DESC LIMIT ?
            """
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            var idx: Int32 = 1
            if let type { bind(stmt, idx, type.rawValue); idx += 1 }
            sqlite3_bind_int(stmt, idx, Int32(limit))
            var out: [Change] = []
            while sqlite3_step(stmt) == SQLITE_ROW { out.append(readChange(stmt)) }
            return out
        }
    }

    public func executedLevelPrices(positionId: Int64) throws -> Set<String> {
        return try read {
            let current = try plan(positionId: positionId)
            let stmt = try prepare("""
            SELECT level_id, level_price, direction, plan_version FROM changes
            WHERE position_id = ? AND (level_id IS NOT NULL OR level_price IS NOT NULL)
              AND type IN ('buy', 'sell', 'clear') AND voided_at IS NULL
            ORDER BY id
            """)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, positionId)
            var out: Set<String> = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let id = text(stmt, 0) { out.insert(id); continue }
                // 旧流水只有在同方向、同价格的当前档位中唯一对应时才迁移。
                let price = sqlite3_column_double(stmt, 1)
                let side = text(stmt, 2)
                let matches = current?.levels.filter {
                    $0.price == price && (side == nil || $0.kind.rawValue == side)
                } ?? []
                if matches.count == 1, let id = matches.first?.id { out.insert(id) }
            }
            return out
        }
    }

    public func meta(_ key: String) throws -> String? {
        return try read {
            let stmt = try prepare("SELECT value FROM meta WHERE key = ?")
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, key)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return text(stmt, 0)
        }
    }

    public func setMeta(_ key: String, _ value: String) throws {
        try write {
            let stmt = try prepare("""
            INSERT INTO meta (key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """)
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, key)
            bind(stmt, 2, value)
            try stepDone(stmt)
        }
    }

    public func dataVersion() throws -> Int32 {
        return try read {
            let stmt = try prepare("PRAGMA data_version;")
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return sqlite3_column_int(stmt, 0)
        }
    }

    // MARK: - Writes

    @discardableResult
    public func addPosition(code rawCode: String, name rawName: String,
                            source: QuoteSource? = nil, unit: UnitKind? = nil,
                            quantity: Double, cost: Double,
                            openedAt: String = Dates.today(),
                            plan: [PlanLevel] = [], description: String? = nil,
                            nextReview: String? = nil,
                            market: InstrumentMarket = .cn,
                            quoteKey: String? = nil) throws -> Position {
        let code = normalizeCode(rawCode)
        guard !code.isEmpty else { throw StoreError.validation("股票代码不能为空") }
        guard quantity.isFinite, quantity > 0 else { throw StoreError.validation("建仓数量必须大于 0") }
        guard cost.isFinite, cost > 0 else { throw StoreError.validation("建仓成本必须大于 0") }
        guard market.isHoldable else {
            throw StoreError.validation("该市场目前只支持观察，暂不支持建仓")
        }
        if let nextReview, !nextReview.isEmpty, !Dates.isDay(nextReview) {
            throw StoreError.validation("复盘日期必须是 YYYY-MM-DD")
        }

        let resolvedSource = market == .cn ? (source ?? inferSource(code)) : .eastmoney
        let resolvedUnit = market == .cn
            ? (unit ?? (isGold(code) ? .gram : .share))
            : .share
        let key = market == .hk ? (quoteKey ?? "116.\(code)") : quoteKey
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        // 手工建仓也挂到默认账户，导入同代码成交时才能合并到同一持仓周期。
        let accountId = (try? defaultAccount())?.id

        return try write {
            if let existing = try openPosition(code: code) {
                throw StoreError.validation("\(existing.name) 已有持仓，请直接加仓")
            }
            // 同代码的观察项在买入时消化：继承框架、备注、计划与指标，不留重复记录。
            let existingWatch = try watchPosition(code: code, market: market)
            let watchPlan: Plan? = existingWatch.flatMap { try? self.plan(positionId: $0.id) }
            let inheritedProfile: String? = nil
            let mergedPlan = plan.isEmpty ? (watchPlan?.levels ?? []) : plan
            let mergedDescription = description ?? watchPlan?.description
            let mergedReview = nextReview ?? watchPlan?.nextReview
            let mergedNote = existingWatch?.note

            let stmt = try prepare("""
            INSERT INTO positions
              (code, name, source, unit, quantity, avg_cost, status, opened_at, closed_at,
               kind, note, profile_id, market, quote_key, account_id)
            VALUES (?, ?, ?, ?, ?, ?, 'open', ?, NULL, 'holding', ?, ?, ?, ?, ?)
            """)
            bind(stmt, 1, code)
            bind(stmt, 2, name.isEmpty ? code : name)
            bind(stmt, 3, resolvedSource.rawValue)
            bind(stmt, 4, resolvedUnit.rawValue)
            bind(stmt, 5, quantity)
            bind(stmt, 6, cost)
            bind(stmt, 7, openedAt)
            bind(stmt, 8, mergedNote)
            bind(stmt, 9, inheritedProfile)
            bind(stmt, 10, market.rawValue)
            bind(stmt, 11, key)
            if let accountId { sqlite3_bind_int64(stmt, 12, accountId) } else { sqlite3_bind_null(stmt, 12) }
            try stepDone(stmt)
            sqlite3_finalize(stmt)
            let pid = lastID()

            _ = try insertChange(positionId: pid, type: .open, qtyBefore: 0, qtyAfter: quantity,
                                 costBefore: 0, costAfter: cost, price: cost, fee: nil,
                                 levelPrice: nil, levelId: nil, planVersion: nil, direction: nil, planSnapshot: nil,
                                 note: existingWatch == nil ? nil : "由观察转入", occurredAt: openedAt)

            // 即使没有档位，只要写了说明/复盘日期也建一版计划，避免建仓时填的逻辑丢失。
            if !mergedPlan.isEmpty || mergedDescription != nil || mergedReview != nil {
                try validate(levels: mergedPlan, allowEmpty: mergedPlan.isEmpty,
                             allowMissingQuantity: plan.isEmpty)
                let snapshot = PlanSnapshot(version: 1, author: "user", description: mergedDescription,
                                            nextReview: mergedReview, levels: mergedPlan)
                _ = try insertPlanRow(positionId: pid, version: 1, author: "user",
                                      description: mergedDescription, nextReview: mergedReview,
                                      levels: mergedPlan, updatedAt: Dates.now())
                _ = try insertChange(positionId: pid, type: .plan, qtyBefore: nil, qtyAfter: nil,
                                     costBefore: nil, costAfter: nil, price: nil, fee: nil,
                                     levelPrice: nil, levelId: nil, planVersion: nil, direction: nil, planSnapshot: encode(snapshot),
                                     note: "初始计划", occurredAt: openedAt)
            }

            if let watch = existingWatch {
                try copyMetrics(from: watch.id, to: pid)
                try deleteWatchRow(id: watch.id)
            }
            return try position(id: pid)!
        }
    }

    @discardableResult
    public func recordTrade(positionId: Int64, side: TradeSide, quantity: Double, price: Double,
                            fee: Double = 0, costAfter: Double? = nil, levelId: String? = nil,
                            levelPrice: Double? = nil, note: String? = nil,
                            occurredAt: String = Dates.today()) throws -> TradeResult {
        guard quantity.isFinite, quantity > 0 else { throw StoreError.validation("数量必须大于 0") }
        guard price.isFinite, price > 0 else { throw StoreError.validation("价格必须大于 0") }
        guard fee.isFinite, fee >= 0 else { throw StoreError.validation("手续费不能为负") }
        guard Dates.isDay(occurredAt) else { throw StoreError.validation("成交日期必须是 YYYY-MM-DD") }

        return try write {
            guard let pos = try position(id: positionId) else {
                throw StoreError.notFound("持仓不存在")
            }
            guard pos.status == .open else { throw StoreError.validation("该持仓已清仓") }

            if side == .sell && quantity > pos.quantity + 1e-9 {
                throw StoreError.validation("卖出数量超过当前持仓")
            }
            if pos.unit == .share {
                guard quantity.rounded() == quantity else {
                    throw StoreError.validation("股票和基金份额必须为整数")
                }
            }
            let matchedLevel: PlanLevel?
            let matchedVersion: Int?
            if levelId != nil || levelPrice != nil {
                guard let plan = try plan(positionId: positionId) else {
                    throw StoreError.validation("该持仓还没有计划，不能关联档位")
                }
                let matches = plan.levels.filter {
                    $0.kind.rawValue == side.rawValue
                        && (levelId == nil || $0.id == levelId)
                        && (levelPrice == nil || $0.price == levelPrice)
                }
                guard matches.count == 1, let level = matches.first else {
                    throw StoreError.validation("成交方向与计划档位不匹配")
                }
                let executed = try executedLevelPrices(positionId: positionId)
                guard !executed.contains(level.id) else {
                    throw StoreError.validation("该计划档位已经执行过")
                }
                matchedLevel = level
                matchedVersion = plan.version
            } else {
                matchedLevel = nil
                matchedVersion = nil
            }
            let qtyAfter = max(0, side == .buy ? pos.quantity + quantity : pos.quantity - quantity)
            let autoCost: Double
            if side == .buy {
                autoCost = qtyAfter > 0
                    ? (pos.quantity * pos.avgCost + quantity * price + fee) / qtyAfter
                    : pos.avgCost
            } else {
                autoCost = pos.avgCost
            }
            let newCost = costAfter ?? autoCost
            guard newCost.isFinite, newCost >= 0 else {
                throw StoreError.validation("成本必须大于等于 0")
            }

            let type: ChangeType = qtyAfter <= 0 ? .clear : (side == .buy ? .buy : .sell)
            let change = try insertChange(positionId: positionId, type: type,
                                          qtyBefore: pos.quantity, qtyAfter: qtyAfter,
                                          costBefore: pos.avgCost, costAfter: newCost,
                                          price: price, fee: fee,
                                          levelPrice: matchedLevel?.price, levelId: matchedLevel?.id,
                                          planVersion: matchedVersion, direction: side.rawValue,
                                          planSnapshot: nil, note: note, occurredAt: occurredAt)

            try updatePosition(id: positionId, quantity: qtyAfter, cost: newCost,
                               status: qtyAfter <= 0 ? .closed : .open,
                               closedAt: qtyAfter <= 0 ? occurredAt : nil)
            return TradeResult(change: change, position: try position(id: positionId)!,
                               matchedLevel: matchedLevel)
        }
    }

    @discardableResult
    public func clearPosition(positionId: Int64, price: Double, costAfter: Double? = nil,
                              fee: Double = 0, note: String? = nil,
                              occurredAt: String = Dates.today()) throws -> TradeResult {
        guard price.isFinite, price > 0 else { throw StoreError.validation("价格必须大于 0") }
        guard fee.isFinite, fee >= 0 else { throw StoreError.validation("手续费不能为负") }
        guard Dates.isDay(occurredAt) else { throw StoreError.validation("成交日期必须是 YYYY-MM-DD") }

        return try write {
            guard let pos = try position(id: positionId) else {
                throw StoreError.notFound("持仓不存在")
            }
            guard pos.status == .open, pos.quantity > 0 else {
                throw StoreError.validation("该持仓已经没有数量")
            }
            let newCost = costAfter ?? pos.avgCost
            let change = try insertChange(positionId: positionId, type: .clear,
                                          qtyBefore: pos.quantity, qtyAfter: 0,
                                          costBefore: pos.avgCost, costAfter: newCost,
                                          price: price, fee: fee, levelPrice: nil, levelId: nil,
                                          planVersion: nil, direction: "sell",
                                          planSnapshot: nil, note: note, occurredAt: occurredAt)
            try updatePosition(id: positionId, quantity: 0, cost: newCost,
                               status: .closed, closedAt: occurredAt)
            return TradeResult(change: change, position: try position(id: positionId)!,
                               matchedLevel: nil)
        }
    }

    @discardableResult
    public func adjustPosition(positionId: Int64, delta: Double, costAfter: Double? = nil,
                               price: Double? = nil, note: String? = nil,
                               occurredAt: String = Dates.today()) throws -> TradeResult {
        guard delta.isFinite, delta != 0 else { throw StoreError.validation("调整数量不能为 0") }

        return try write {
            guard let pos = try position(id: positionId) else {
                throw StoreError.notFound("持仓不存在")
            }
            let qtyAfter = pos.quantity + delta
            guard qtyAfter >= 0 else { throw StoreError.validation("调整后数量不能为负") }
            let totalCost = pos.quantity * pos.avgCost
            let autoCost = qtyAfter > 0 ? totalCost / qtyAfter : 0
            let newCost = costAfter ?? autoCost
            let change = try insertChange(positionId: positionId, type: .adjust,
                                          qtyBefore: pos.quantity, qtyAfter: qtyAfter,
                                          costBefore: pos.avgCost, costAfter: newCost,
                                          price: price, fee: nil, levelPrice: nil, levelId: nil, planVersion: nil, direction: nil,
                                          planSnapshot: nil, note: note, occurredAt: occurredAt)
            try updatePosition(id: positionId, quantity: qtyAfter, cost: newCost,
                               status: qtyAfter <= 0 ? .closed : .open,
                               closedAt: qtyAfter <= 0 ? occurredAt : nil)
            return TradeResult(change: change, position: try position(id: positionId)!,
                               matchedLevel: nil)
        }
    }

    @discardableResult
    public func setCost(positionId: Int64, cost: Double,
                        note: String? = nil) throws -> TradeResult {
        guard cost.isFinite, cost >= 0 else { throw StoreError.validation("成本必须大于等于 0") }

        return try write {
            guard let pos = try position(id: positionId) else {
                throw StoreError.notFound("持仓不存在")
            }
            let change = try insertChange(positionId: positionId, type: .cost,
                                          qtyBefore: pos.quantity, qtyAfter: pos.quantity,
                                          costBefore: pos.avgCost, costAfter: cost,
                                          price: nil, fee: nil, levelPrice: nil, levelId: nil, planVersion: nil, direction: nil,
                                          planSnapshot: nil, note: note,
                                          occurredAt: Dates.today())
            try updatePosition(id: positionId, quantity: pos.quantity, cost: cost,
                               status: pos.status, closedAt: pos.closedAt)
            return TradeResult(change: change, position: try position(id: positionId)!,
                               matchedLevel: nil)
        }
    }

    @discardableResult
    public func updatePlan(positionId: Int64, levels: [PlanLevel],
                           description: String? = nil, nextReview: String? = nil,
                           note: String? = nil, author: String = "user",
                           ifVersion: Int? = nil) throws -> PlanUpdateResult {
        return try write {
            guard let pos = try position(id: positionId) else {
                throw StoreError.notFound("持仓不存在")
            }
            guard pos.status == .open else { throw StoreError.validation("已清仓的持仓不能改计划") }
            if pos.kind == .watch {
                guard levels.allSatisfy({ $0.kind == .buy }) else {
                    throw StoreError.validation("观察标的的计划只支持买入档")
                }
            }
            try validate(levels: levels, allowEmpty: true,
                         allowMissingQuantity: pos.kind == .watch)

            let current = try plan(positionId: positionId)
            if let nextReview, !nextReview.isEmpty, !Dates.isDay(nextReview) {
                throw StoreError.validation("复盘日期必须是 YYYY-MM-DD")
            }
            if let ifVersion {
                guard let current, current.version == ifVersion else {
                    throw StoreError.conflict(
                        "计划已变化，请查看最新版本后再保存", current)
                }
            }

            let version = (current?.version ?? 0) + 1
            let diff = Store.diff(old: current?.levels ?? [], new: levels)
            let snapshot = PlanSnapshot(version: version, author: author,
                                        description: description,
                                        nextReview: nextReview, levels: levels)

            if current == nil {
                _ = try insertPlanRow(positionId: positionId, version: version, author: author,
                                      description: description, nextReview: nextReview,
                                      levels: levels, updatedAt: Dates.now())
            } else {
                let stmt = try prepare("""
                UPDATE plans SET version = ?, author = ?, description = ?, next_review = ?,
                                 levels = ?, updated_at = ?
                WHERE position_id = ?
                """)
                sqlite3_bind_int64(stmt, 1, Int64(version))
                bind(stmt, 2, author)
                bind(stmt, 3, description)
                bind(stmt, 4, nextReview)
                bind(stmt, 5, encode(levels))
                bind(stmt, 6, Dates.now())
                sqlite3_bind_int64(stmt, 7, positionId)
                try stepDone(stmt)
                sqlite3_finalize(stmt)
            }

            _ = try insertChange(positionId: positionId, type: .plan, qtyBefore: nil, qtyAfter: nil,
                                 costBefore: nil, costAfter: nil, price: nil, fee: nil,
                                 levelPrice: nil, levelId: nil, planVersion: nil, direction: nil, planSnapshot: encode(snapshot),
                                 note: note, occurredAt: Dates.today())

            return PlanUpdateResult(plan: try plan(positionId: positionId)!, diff: diff)
        }
    }

    /// 移除计划：删除计划行，并在 changes 里留一条带原快照的记录。
    @discardableResult
    public func removePlan(positionId: Int64, note: String? = nil) throws -> Plan {
        return try write {
            guard let pos = try position(id: positionId) else {
                throw StoreError.notFound("持仓不存在")
            }
            guard pos.status == .open else {
                throw StoreError.validation("已清仓的持仓不能移除计划")
            }
            guard let current = try plan(positionId: positionId) else {
                throw StoreError.notFound("该标的还没有计划")
            }

            let snapshot = PlanSnapshot(version: current.version, author: current.author,
                                        description: current.description,
                                        nextReview: current.nextReview,
                                        levels: current.levels)
            let stmt = try prepare("DELETE FROM plans WHERE position_id = ?")
            sqlite3_bind_int64(stmt, 1, positionId)
            try stepDone(stmt)
            sqlite3_finalize(stmt)

            _ = try insertChange(positionId: positionId, type: .plan,
                                 qtyBefore: nil, qtyAfter: nil,
                                 costBefore: nil, costAfter: nil, price: nil, fee: nil,
                                 levelPrice: nil, levelId: nil, planVersion: current.version,
                                 direction: nil, planSnapshot: encode(snapshot),
                                 note: note ?? "移除计划 v\(current.version)",
                                 occurredAt: Dates.today())
            return current
        }
    }

    // MARK: - Alerts

    public func alerts(includeResolved: Bool = false, limit: Int = 200) throws -> [Alert] {
        return try read {
            let stmt = try prepare("""
            SELECT id, position_id, kind, title, detail, first_triggered_at,
                   last_triggered_at, acknowledged_at, resolved_at FROM alerts
            \(includeResolved ? "" : "WHERE resolved_at IS NULL")
            ORDER BY last_triggered_at DESC LIMIT ?
            """)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(min(max(limit, 1), 2000)))
            var result: [Alert] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let id = text(stmt, 0), let rawKind = text(stmt, 2),
                      let kind = AlertKind(rawValue: rawKind) else { continue }
                result.append(Alert(id: id, positionId: sqlite3_column_type(stmt, 1) == SQLITE_NULL
                                    ? nil : sqlite3_column_int64(stmt, 1), kind: kind,
                                    title: text(stmt, 3) ?? "", detail: text(stmt, 4) ?? "",
                                    firstTriggeredAt: text(stmt, 5) ?? "",
                                    lastTriggeredAt: text(stmt, 6) ?? "",
                                    acknowledgedAt: text(stmt, 7), resolvedAt: text(stmt, 8)))
            }
            return result
        }
    }

    public func syncAlerts(_ signals: [AlertSignal], at date: Date = Date()) throws {
        try write {
            let now = Dates.stamp.string(from: date)
            let active = Set(signals.map(\.id))
            let existing = Dictionary(uniqueKeysWithValues: try alerts(includeResolved: true)
                .map { ($0.id, $0) })
            for signal in signals {
                let previous = existing[signal.id]
                if let previous, previous.resolvedAt == nil,
                   previous.title == signal.title, previous.detail == signal.detail { continue }
                let stmt = try prepare("""
                INSERT INTO alerts (id, position_id, kind, title, detail,
                                    first_triggered_at, last_triggered_at, acknowledged_at, resolved_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, NULL, NULL)
                ON CONFLICT(id) DO UPDATE SET position_id=excluded.position_id,
                    title=excluded.title, detail=excluded.detail,
                    last_triggered_at=excluded.last_triggered_at, resolved_at=NULL
                """)
                defer { sqlite3_finalize(stmt) }
                bind(stmt, 1, signal.id)
                if let id = signal.positionId { sqlite3_bind_int64(stmt, 2, id) } else { bind(stmt, 2, Double?.none) }
                bind(stmt, 3, signal.kind.rawValue)
                bind(stmt, 4, signal.title)
                bind(stmt, 5, signal.detail)
                bind(stmt, 6, previous?.firstTriggeredAt ?? now)
                bind(stmt, 7, now)
                try stepDone(stmt)
            }
            for alert in existing.values where alert.resolvedAt == nil && !active.contains(alert.id) {
                let stmt = try prepare("UPDATE alerts SET resolved_at = ? WHERE id = ?")
                defer { sqlite3_finalize(stmt) }
                bind(stmt, 1, now)
                bind(stmt, 2, alert.id)
                try stepDone(stmt)
            }
        }
    }

    public func acknowledgeAlert(id: String) throws {
        try write {
            let stmt = try prepare("""
            UPDATE alerts SET acknowledged_at = COALESCE(acknowledged_at, ?) WHERE id = ?
            """)
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, Dates.now())
            bind(stmt, 2, id)
            try stepDone(stmt)
        }
    }

    public func acknowledgeAllAlerts() throws {
        try write {
            let stmt = try prepare("""
            UPDATE alerts SET acknowledged_at = COALESCE(acknowledged_at, ?)
            WHERE resolved_at IS NULL
            """)
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, Dates.now())
            try stepDone(stmt)
        }
    }

    // MARK: - Backup / export

    public func backup(to url: URL) throws {
        return try read {
            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw StoreError.validation("目标文件已存在，请选择新的文件名")
            }
            let escaped = url.path.replacingOccurrences(of: "'", with: "''")
            try exec("VACUUM INTO '\(escaped)';")
            chmod(url.path, 0o600)
        }
    }

    public func exportChangesCSV(to url: URL) throws {
        let rows = try allChanges(limit: 100_000)
        var text = "id,position_id,type,qty_before,qty_after,cost_before,cost_after,price,fee,level_id,level_price,plan_version,note,occurred_at,created_at\n"
        for c in rows {
            let fields = [String(c.id), String(c.positionId), c.type.rawValue]
                + [c.qtyBefore, c.qtyAfter, c.costBefore, c.costAfter, c.price, c.fee]
                    .map { $0.map { String($0) } ?? "" }
                + [c.levelId ?? "", c.levelPrice.map { String($0) } ?? "",
                   c.planVersion.map { String($0) } ?? "", c.note ?? "", c.occurredAt, c.createdAt]
            text += fields.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                .joined(separator: ",") + "\n"
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Rebuild / verify

    public func rebuild(positionId: Int64) throws {
        try write {
            let stmt = try prepare("""
            SELECT qty_after, cost_after, type, occurred_at FROM changes
            WHERE position_id = ? AND qty_after IS NOT NULL AND voided_at IS NULL
            ORDER BY id DESC LIMIT 1
            """)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, positionId)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return }
            let qty = sqlite3_column_double(stmt, 0)
            let cost = sqlite3_column_double(stmt, 1)
            let type = text(stmt, 2)
            let at = text(stmt, 3)
            let closed = qty <= 0 || type == ChangeType.clear.rawValue
            try updatePosition(id: positionId, quantity: qty, cost: cost,
                               status: closed ? .closed : .open,
                               closedAt: closed ? at : nil)
        }
    }

    @discardableResult
    public func verifyAll() throws -> Int {
        let all = try positions(includeClosed: true)
        var fixed = 0
        for p in all {
            let latest = try latestState(positionId: p.id)
            guard let latest else { continue }
            let closed = latest.qty <= 0 || latest.type == .clear
            if abs(p.quantity - latest.qty) > 1e-6 || abs(p.avgCost - latest.cost) > 1e-6
                || (p.status == .closed) != closed {
                try rebuild(positionId: p.id)
                fixed += 1
            }
        }
        return fixed
    }

    func latestState(positionId: Int64) throws -> (qty: Double, cost: Double, type: ChangeType?)? {
        return try read {
            let stmt = try prepare("""
            SELECT qty_after, cost_after, type FROM changes
            WHERE position_id = ? AND qty_after IS NOT NULL AND voided_at IS NULL
            ORDER BY id DESC LIMIT 1
            """)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, positionId)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let type = text(stmt, 2).flatMap(ChangeType.init(rawValue:))
            return (sqlite3_column_double(stmt, 0), sqlite3_column_double(stmt, 1), type)
        }
    }

    // MARK: - Row mapping

    func readPosition(_ stmt: OpaquePointer) -> Position {
        Position(
            id: sqlite3_column_int64(stmt, 0),
            code: text(stmt, 1) ?? "",
            name: text(stmt, 2) ?? "",
            source: QuoteSource(rawValue: text(stmt, 3) ?? "eastmoney") ?? .eastmoney,
            unit: UnitKind(rawValue: text(stmt, 4) ?? "share") ?? .share,
            quantity: sqlite3_column_double(stmt, 5),
            avgCost: sqlite3_column_double(stmt, 6),
            status: PositionStatus(rawValue: text(stmt, 7) ?? "open") ?? .open,
            openedAt: text(stmt, 8) ?? "",
            closedAt: text(stmt, 9),
            kind: PositionKind(rawValue: text(stmt, 10) ?? "holding") ?? .holding,
            note: text(stmt, 11),
            watchPrice: double(stmt, 12),
            market: InstrumentMarket(rawValue: text(stmt, 13) ?? "cn") ?? .cn,
            quoteKey: text(stmt, 14)
        )
    }

    func readPlan(_ stmt: OpaquePointer) -> Plan {
        let levelsJSON = text(stmt, 6) ?? "[]"
        let levels = (try? JSONDecoder().decode([PlanLevel].self,
                                                from: Data(levelsJSON.utf8))) ?? []
        return Plan(
            id: sqlite3_column_int64(stmt, 0),
            positionId: sqlite3_column_int64(stmt, 1),
            version: Int(sqlite3_column_int(stmt, 2)),
            author: text(stmt, 3) ?? "user",
            description: text(stmt, 4),
            nextReview: text(stmt, 5),
            levels: levels,
            updatedAt: text(stmt, 7) ?? ""
        )
    }

    func readChange(_ stmt: OpaquePointer) -> Change {
        Change(
            id: sqlite3_column_int64(stmt, 0),
            positionId: sqlite3_column_int64(stmt, 1),
            type: ChangeType(rawValue: text(stmt, 2) ?? "") ?? .adjust,
            qtyBefore: double(stmt, 3),
            qtyAfter: double(stmt, 4),
            costBefore: double(stmt, 5),
            costAfter: double(stmt, 6),
            price: double(stmt, 7),
            fee: double(stmt, 8),
            levelPrice: double(stmt, 9),
            levelId: text(stmt, 10),
            planVersion: double(stmt, 11).map(Int.init),
            direction: text(stmt, 12),
            planSnapshot: text(stmt, 13),
            note: text(stmt, 14),
            occurredAt: text(stmt, 15) ?? "",
            createdAt: text(stmt, 16) ?? ""
        )
    }

    // MARK: - Private writes

    func insertChange(positionId: Int64, type: ChangeType,
                              qtyBefore: Double?, qtyAfter: Double?,
                              costBefore: Double?, costAfter: Double?,
                              price: Double?, fee: Double?, levelPrice: Double?,
                              levelId: String?, planVersion: Int?, direction: String?,
                              planSnapshot: String?, note: String?,
                              occurredAt: String) throws -> Change {
        let createdAt = Dates.now()
        let stmt = try prepare("""
        INSERT INTO changes (position_id, type, qty_before, qty_after, cost_before, cost_after,
                             price, fee, level_price, level_id, plan_version, direction,
                             plan_snapshot, note, occurred_at, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """)
        sqlite3_bind_int64(stmt, 1, positionId)
        bind(stmt, 2, type.rawValue)
        bind(stmt, 3, qtyBefore)
        bind(stmt, 4, qtyAfter)
        bind(stmt, 5, costBefore)
        bind(stmt, 6, costAfter)
        bind(stmt, 7, price)
        bind(stmt, 8, fee)
        bind(stmt, 9, levelPrice)
        bind(stmt, 10, levelId)
        bind(stmt, 11, planVersion.map(Double.init))
        bind(stmt, 12, direction)
        bind(stmt, 13, planSnapshot)
        bind(stmt, 14, note)
        bind(stmt, 15, occurredAt)
        bind(stmt, 16, createdAt)
        try stepDone(stmt)
        sqlite3_finalize(stmt)
        return Change(id: lastID(), positionId: positionId, type: type,
                      qtyBefore: qtyBefore, qtyAfter: qtyAfter,
                      costBefore: costBefore, costAfter: costAfter,
                      price: price, fee: fee,
                      levelPrice: levelPrice, levelId: levelId, planVersion: planVersion,
            direction: direction, planSnapshot: planSnapshot, note: note,
                      occurredAt: occurredAt, createdAt: createdAt)
    }

    func insertPlanRow(positionId: Int64, version: Int, author: String,
                               description: String?, nextReview: String?,
                               levels: [PlanLevel], updatedAt: String) throws -> Int64 {
        let stmt = try prepare("""
        INSERT INTO plans (position_id, version, author, description, next_review, levels, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """)
        sqlite3_bind_int64(stmt, 1, positionId)
        sqlite3_bind_int(stmt, 2, Int32(version))
        bind(stmt, 3, author)
        bind(stmt, 4, description)
        bind(stmt, 5, nextReview)
        bind(stmt, 6, encode(levels))
        bind(stmt, 7, updatedAt)
        try stepDone(stmt)
        sqlite3_finalize(stmt)
        return lastID()
    }

    func updatePosition(id: Int64, quantity: Double, cost: Double,
                                status: PositionStatus, closedAt: String?) throws {
        let stmt = try prepare("""
        UPDATE positions SET quantity = ?, avg_cost = ?, status = ?, closed_at = ? WHERE id = ?
        """)
        bind(stmt, 1, quantity)
        bind(stmt, 2, cost)
        bind(stmt, 3, status.rawValue)
        bind(stmt, 4, closedAt)
        sqlite3_bind_int64(stmt, 5, id)
        try stepDone(stmt)
        sqlite3_finalize(stmt)
    }

    // MARK: - Utilities

    public static func diff(old: [PlanLevel], new: [PlanLevel]) -> PlanDiff {
        let before = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        let after = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
        let added = new.filter { before[$0.id] == nil }
        let removed = old.filter { after[$0.id] == nil }
        let changed: [PlanDiff.Change] = new.compactMap { level -> PlanDiff.Change? in
            guard let previous = before[level.id], previous != level else { return nil }
            return PlanDiff.Change(from: previous, to: level)
        }
        return PlanDiff(added: added, removed: removed, changed: changed)
    }

    func validate(levels: [PlanLevel], allowEmpty: Bool = false,
                  allowMissingQuantity: Bool = false) throws {
        guard allowEmpty || !levels.isEmpty else { throw StoreError.validation("计划至少需要一档") }
        guard Set(levels.map(\.id)).count == levels.count else {
            throw StoreError.validation("档位标识不能重复")
        }
        for level in levels {
            guard level.price.isFinite, level.price > 0 else {
                throw StoreError.validation("档位价格必须大于 0")
            }
            if level.kind == .stop {
                if level.quantity != nil && level.quantity != 0 {
                    throw StoreError.validation("停止档不设数量")
                }
            } else if let q = level.quantity {
                guard q.isFinite, q > 0 else {
                    throw StoreError.validation("买入/卖出档数量必须大于 0")
                }
            } else if !allowMissingQuantity {
                throw StoreError.validation("买入/卖出档数量必须大于 0")
            }
        }
        for kind in PlanLevel.Kind.allCases {
            let prices = levels.filter { $0.kind == kind }.map { $0.price }
            guard Set(prices).count == prices.count else {
                throw StoreError.validation("同类型档位价格不能重复")
            }
        }
    }

    func encode<T: Encodable>(_ value: T) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return (try? String(data: enc.encode(value), encoding: .utf8)) ?? "[]"
    }

    func decode<T: Decodable>(_ string: String) -> T? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func normalizeCode(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.range(of: #"^\d{6}$"#, options: .regularExpression) != nil { return value }
        if value.contains("AU9999") || value.contains("AU99.99") { return "AU9999" }
        return value
    }

    func inferSource(_ code: String) -> QuoteSource {
        isGold(code) ? .sina : .eastmoney
    }

    func isGold(_ code: String) -> Bool {
        code.uppercased().contains("AU")
    }
}
