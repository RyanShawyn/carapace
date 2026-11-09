import Foundation
import SQLite3

// MARK: - v5 schema and data access

extension Store {
    /// v6: 观察标的复用 positions 表，kind 区分持仓与观察。
    func migrateV6() throws {
        try addColumnIfNeeded("positions", "kind", "TEXT NOT NULL DEFAULT 'holding'")
        try addColumnIfNeeded("positions", "note", "TEXT")
        try addColumnIfNeeded("positions", "watch_price", "REAL")
        try exec("CREATE INDEX IF NOT EXISTS idx_positions_kind_status ON positions(kind, status);")
    }

    /// v7: 支持港股、美股、指数；非 cn 市场目前只用于观察。
    func migrateV7() throws {
        try addColumnIfNeeded("positions", "market", "TEXT NOT NULL DEFAULT 'cn'")
        try addColumnIfNeeded("positions", "quote_key", "TEXT")
        try exec("CREATE INDEX IF NOT EXISTS idx_positions_market ON positions(market, status);")
    }

    /// v8: 移除应用内 AI。重建 reviews/drafts 去掉线程与摘要字段，删除 AI 表。
    /// 调用方已关闭外键检查，并在事务内执行。
    func migrateV8() throws {
        let hasAISummary = try hasColumn("reviews", name: "ai_summary")
        let hasReviewThread = try hasColumn("reviews", name: "thread_id")
        if hasAISummary || hasReviewThread {
            try exec("""
            CREATE TABLE reviews_v8 (
              id           INTEGER PRIMARY KEY AUTOINCREMENT,
              position_id  INTEGER REFERENCES positions(id),
              kind         TEXT NOT NULL,
              due_at       TEXT,
              period_start TEXT,
              period_end   TEXT,
              status       TEXT NOT NULL DEFAULT 'due',
              facts        TEXT,
              notes        TEXT,
              profile_id   TEXT,
              outcome_json TEXT,
              completed_at TEXT,
              created_at   TEXT NOT NULL
            );
            INSERT INTO reviews_v8
              (id, position_id, kind, due_at, period_start, period_end, status,
               facts, notes, profile_id, outcome_json, completed_at, created_at)
            SELECT id, position_id, kind, due_at, period_start, period_end, status,
                   facts, notes, profile_id, outcome_json, completed_at, created_at
            FROM reviews;
            DROP TABLE reviews;
            ALTER TABLE reviews_v8 RENAME TO reviews;
            CREATE INDEX IF NOT EXISTS idx_reviews_due ON reviews(status, due_at);
            """)
        }

        if try hasColumn("drafts", name: "thread_id") {
            try exec("""
            CREATE TABLE drafts_v8 (
              id            INTEGER PRIMARY KEY AUTOINCREMENT,
              kind          TEXT NOT NULL,
              position_id   INTEGER REFERENCES positions(id),
              skill         TEXT,
              payload       TEXT NOT NULL,
              base_version  INTEGER,
              base_quantity REAL,
              profile_id    TEXT,
              status        TEXT NOT NULL DEFAULT 'pending',
              note          TEXT,
              created_at    TEXT NOT NULL,
              decided_at    TEXT
            );
            INSERT INTO drafts_v8
              (id, kind, position_id, skill, payload, base_version, base_quantity,
               profile_id, status, note, created_at, decided_at)
            SELECT id, kind, position_id, skill, payload, base_version, base_quantity,
                   profile_id, status, note, created_at, decided_at
            FROM drafts;
            DROP TABLE drafts;
            ALTER TABLE drafts_v8 RENAME TO drafts;
            """)
        }

        for table in ["messages", "threads", "ai_models", "task_routes", "ai_providers"] {
            try exec("DROP TABLE IF EXISTS \(table);")
        }

        try exec("""
        CREATE TABLE IF NOT EXISTS cli_requests (
          id          TEXT PRIMARY KEY,
          command     TEXT NOT NULL,
          result_json TEXT NOT NULL,
          created_at  TEXT NOT NULL
        );
        """)
    }

    func migrateV5() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS accounts (
          id           INTEGER PRIMARY KEY AUTOINCREMENT,
          broker       TEXT NOT NULL,
          name         TEXT NOT NULL,
          account_no   TEXT,
          currency     TEXT NOT NULL DEFAULT 'CNY',
          timezone     TEXT NOT NULL DEFAULT 'Asia/Shanghai',
          is_default   INTEGER NOT NULL DEFAULT 0,
          created_at   TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS import_mappings (
          id           INTEGER PRIMARY KEY AUTOINCREMENT,
          broker       TEXT NOT NULL,
          name         TEXT NOT NULL,
          version      INTEGER NOT NULL DEFAULT 1,
          mapping_json TEXT NOT NULL,
          created_at   TEXT NOT NULL,
          updated_at   TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS import_batches (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          account_id    INTEGER NOT NULL REFERENCES accounts(id),
          broker        TEXT NOT NULL,
          file_name     TEXT NOT NULL,
          file_hash     TEXT NOT NULL,
          mapping_id    INTEGER REFERENCES import_mappings(id),
          status        TEXT NOT NULL,
          rows_total    INTEGER NOT NULL DEFAULT 0,
          rows_imported INTEGER NOT NULL DEFAULT 0,
          rows_skipped  INTEGER NOT NULL DEFAULT 0,
          rows_error    INTEGER NOT NULL DEFAULT 0,
          error         TEXT,
          started_at    TEXT NOT NULL,
          finished_at   TEXT
        );
        CREATE TABLE IF NOT EXISTS executions (
          id                   INTEGER PRIMARY KEY AUTOINCREMENT,
          account_id           INTEGER NOT NULL REFERENCES accounts(id),
          batch_id             INTEGER REFERENCES import_batches(id),
          broker_trade_id      TEXT,
          order_id             TEXT,
          code                 TEXT NOT NULL,
          name                 TEXT,
          side                 TEXT NOT NULL,
          quantity_scaled      INTEGER NOT NULL,
          quantity_scale       INTEGER NOT NULL DEFAULT 10000,
          price_scaled         INTEGER NOT NULL,
          price_scale          INTEGER NOT NULL DEFAULT 10000,
          amount_minor         INTEGER NOT NULL,
          fee_commission_minor INTEGER NOT NULL DEFAULT 0,
          fee_stamp_minor      INTEGER NOT NULL DEFAULT 0,
          fee_transfer_minor   INTEGER NOT NULL DEFAULT 0,
          fee_other_minor      INTEGER NOT NULL DEFAULT 0,
          fee_total_minor      INTEGER NOT NULL DEFAULT 0,
          currency             TEXT NOT NULL DEFAULT 'CNY',
          trade_time           TEXT NOT NULL,
          settle_date          TEXT,
          source               TEXT NOT NULL DEFAULT 'import',
          raw_json             TEXT,
          dedupe_key           TEXT NOT NULL,
          change_id            INTEGER REFERENCES changes(id),
          status               TEXT NOT NULL DEFAULT 'active',
          voided_at            TEXT,
          created_at           TEXT NOT NULL,
          UNIQUE (dedupe_key)
        );
        CREATE INDEX IF NOT EXISTS idx_executions_code_time ON executions(code, trade_time);
        CREATE INDEX IF NOT EXISTS idx_executions_batch ON executions(batch_id);
        CREATE TABLE IF NOT EXISTS corporate_actions (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          account_id      INTEGER NOT NULL REFERENCES accounts(id),
          batch_id        INTEGER REFERENCES import_batches(id),
          code            TEXT NOT NULL,
          action_type     TEXT NOT NULL,
          ex_date         TEXT NOT NULL,
          pay_date        TEXT,
          quantity_scaled INTEGER,
          quantity_scale  INTEGER DEFAULT 10000,
          amount_minor    INTEGER,
          note            TEXT,
          status          TEXT NOT NULL DEFAULT 'active',
          created_at      TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS instrument_profiles (
          id                 TEXT PRIMARY KEY,
          name               TEXT NOT NULL,
          asset_class        TEXT NOT NULL,
          description        TEXT,
          questions_json     TEXT NOT NULL,
          metrics_json       TEXT NOT NULL,
          plan_template_json TEXT NOT NULL,
          review_json        TEXT NOT NULL,
          risk_rules_json    TEXT NOT NULL,
          prompt_md          TEXT,
          built_in           INTEGER NOT NULL DEFAULT 1,
          enabled            INTEGER NOT NULL DEFAULT 1,
          version            INTEGER NOT NULL DEFAULT 1,
          updated_at         TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS position_metrics (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          position_id INTEGER NOT NULL REFERENCES positions(id),
          key         TEXT NOT NULL,
          label       TEXT NOT NULL,
          value_text  TEXT,
          value_num   REAL,
          unit        TEXT,
          source      TEXT NOT NULL DEFAULT 'manual',
          as_of       TEXT NOT NULL,
          note        TEXT,
          created_at  TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_metrics_position ON position_metrics(position_id, key, as_of);
        CREATE TABLE IF NOT EXISTS memories (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          scope         TEXT NOT NULL,
          scope_id      TEXT,
          kind          TEXT NOT NULL,
          title         TEXT NOT NULL,
          content       TEXT NOT NULL,
          evidence_json TEXT,
          confidence    REAL NOT NULL DEFAULT 0.5,
          source        TEXT NOT NULL,
          status        TEXT NOT NULL DEFAULT 'active',
          superseded_by INTEGER REFERENCES memories(id),
          created_at    TEXT NOT NULL,
          updated_at    TEXT NOT NULL,
          last_used_at  TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_memories_scope ON memories(scope, scope_id, status);
        CREATE TABLE IF NOT EXISTS memory_events (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          memory_id  INTEGER REFERENCES memories(id),
          action     TEXT NOT NULL,
          review_id  INTEGER,
          detail     TEXT,
          created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS style_snapshots (
          id           INTEGER PRIMARY KEY AUTOINCREMENT,
          as_of        TEXT NOT NULL,
          metrics_json TEXT NOT NULL,
          narrative    TEXT,
          created_at   TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS reviews (
          id           INTEGER PRIMARY KEY AUTOINCREMENT,
          position_id  INTEGER REFERENCES positions(id),
          kind         TEXT NOT NULL,
          due_at       TEXT,
          period_start TEXT,
          period_end   TEXT,
          status       TEXT NOT NULL DEFAULT 'due',
          facts        TEXT,
          notes        TEXT,
          profile_id   TEXT,
          outcome_json TEXT,
          completed_at TEXT,
          created_at   TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_reviews_due ON reviews(status, due_at);
        CREATE TABLE IF NOT EXISTS drafts (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          kind          TEXT NOT NULL,
          position_id   INTEGER REFERENCES positions(id),
          skill         TEXT,
          payload       TEXT NOT NULL,
          base_version  INTEGER,
          base_quantity REAL,
          profile_id    TEXT,
          status        TEXT NOT NULL DEFAULT 'pending',
          note          TEXT,
          created_at    TEXT NOT NULL,
          decided_at    TEXT
        );
        CREATE TABLE IF NOT EXISTS notifications (
          id           INTEGER PRIMARY KEY AUTOINCREMENT,
          alert_id     TEXT,
          kind         TEXT NOT NULL,
          title        TEXT NOT NULL,
          body         TEXT,
          route        TEXT,
          created_at   TEXT NOT NULL,
          read_at      TEXT,
          delivered_at TEXT,
          delivery     TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_notifications_unread ON notifications(read_at, created_at DESC);
        CREATE TABLE IF NOT EXISTS quote_samples (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          code       TEXT NOT NULL,
          price      REAL NOT NULL,
          prev_close REAL,
          source     TEXT NOT NULL,
          at         TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_quote_samples_code ON quote_samples(code, at);
        """)

        try addColumnIfNeeded("positions", "account_id", "INTEGER")
        try addColumnIfNeeded("positions", "profile_id", "TEXT")
        try addColumnIfNeeded("positions", "profile_snapshot", "TEXT")
        try addColumnIfNeeded("plans", "thesis", "TEXT")
        try addColumnIfNeeded("plans", "invalidation", "TEXT")
        try addColumnIfNeeded("plans", "risk_budget", "REAL")
        try addColumnIfNeeded("plans", "tags", "TEXT")
        try addColumnIfNeeded("plans", "profile_snapshot", "TEXT")
        try addColumnIfNeeded("changes", "execution_id", "INTEGER")
        try addColumnIfNeeded("changes", "batch_id", "INTEGER")
        try addColumnIfNeeded("changes", "account_id", "INTEGER")
        try addColumnIfNeeded("changes", "source", "TEXT")
        try addColumnIfNeeded("changes", "voided_at", "TEXT")
        try addColumnIfNeeded("alerts", "severity", "TEXT")
        try addColumnIfNeeded("drafts", "base_version", "INTEGER")
        try addColumnIfNeeded("drafts", "base_quantity", "REAL")
        try addColumnIfNeeded("drafts", "profile_id", "TEXT")

        // 默认账户
        if try scalarInt("SELECT COUNT(*) FROM accounts") == 0 {
            let stmt = try prepare("""
            INSERT INTO accounts (broker, name, currency, timezone, is_default, created_at)
            VALUES ('手工', '默认账户', 'CNY', 'Asia/Shanghai', 1, ?)
            """)
            bind(stmt, 1, Dates.now())
            try stepDone(stmt)
            sqlite3_finalize(stmt)
        }
        try exec("""
        UPDATE positions SET account_id = (SELECT id FROM accounts ORDER BY is_default DESC, id LIMIT 1)
        WHERE account_id IS NULL;
        UPDATE alerts SET severity = 'info' WHERE severity IS NULL;
        """)
    }

    func addColumnIfNeeded(_ table: String, _ column: String, _ type: String) throws {
        if try hasColumn(table, name: column) == false {
            try exec("ALTER TABLE \(table) ADD COLUMN \(column) \(type);")
        }
    }

    func scalarInt(_ sql: String) throws -> Int {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
    }

    // MARK: - Accounts

    public func accounts() throws -> [Account] {
        try read {
            let stmt = try prepare("""
            SELECT id, broker, name, account_no, currency, timezone, is_default
            FROM accounts ORDER BY is_default DESC, id
            """)
            defer { sqlite3_finalize(stmt) }
            var out: [Account] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(Account(id: sqlite3_column_int64(stmt, 0),
                                   broker: text(stmt, 1) ?? "",
                                   name: text(stmt, 2) ?? "",
                                   accountNo: text(stmt, 3),
                                   currency: text(stmt, 4) ?? "CNY",
                                   timezone: text(stmt, 5) ?? "Asia/Shanghai",
                                   isDefault: sqlite3_column_int(stmt, 6) != 0))
            }
            return out
        }
    }

    public func defaultAccount() throws -> Account? {
        try accounts().first { $0.isDefault } ?? accounts().first
    }

    @discardableResult
    public func addAccount(broker: String, name: String, accountNo: String? = nil,
                           currency: String = "CNY", isDefault: Bool = false) throws -> Account {
        try write {
            if isDefault { try exec("UPDATE accounts SET is_default = 0;") }
            let stmt = try prepare("""
            INSERT INTO accounts (broker, name, account_no, currency, timezone, is_default, created_at)
            VALUES (?, ?, ?, ?, 'Asia/Shanghai', ?, ?)
            """)
            bind(stmt, 1, broker)
            bind(stmt, 2, name)
            bind(stmt, 3, accountNo)
            bind(stmt, 4, currency)
            sqlite3_bind_int(stmt, 5, isDefault ? 1 : 0)
            bind(stmt, 6, Dates.now())
            try stepDone(stmt)
            sqlite3_finalize(stmt)
            let id = lastID()
            return try accounts().first { $0.id == id }!
        }
    }

    // MARK: - Position metrics

    public func metrics(positionId: Int64) throws -> [PositionMetric] {
        try read {
            let stmt = try prepare("""
            SELECT id, position_id, key, label, value_text, source, as_of, note
            FROM position_metrics WHERE position_id = ? ORDER BY as_of DESC, id DESC
            """)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, positionId)
            var out: [PositionMetric] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(PositionMetric(id: sqlite3_column_int64(stmt, 0),
                                          positionId: sqlite3_column_int64(stmt, 1),
                                          key: text(stmt, 2) ?? "",
                                          label: text(stmt, 3) ?? "",
                                          value: text(stmt, 4) ?? "",
                                          source: text(stmt, 5) ?? "manual",
                                          asOf: text(stmt, 6) ?? "",
                                          note: text(stmt, 7)))
            }
            return out
        }
    }

    public func setMetric(positionId: Int64, key: String, label: String,
                          value: String, source: String = "manual",
                          asOf: String = Dates.today(), note: String? = nil) throws {
        try write {
            let stmt = try prepare("""
            INSERT INTO position_metrics
              (position_id, key, label, value_text, value_num, unit, source, as_of, note, created_at)
            VALUES (?, ?, ?, ?, NULL, NULL, ?, ?, ?, ?)
            """)
            sqlite3_bind_int64(stmt, 1, positionId)
            bind(stmt, 2, key)
            bind(stmt, 3, label)
            bind(stmt, 4, value)
            bind(stmt, 5, source)
            bind(stmt, 6, asOf)
            bind(stmt, 7, note)
            bind(stmt, 8, Dates.now())
            try stepDone(stmt)
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Memories

    public func memories(scope: MemoryScope? = nil, scopeId: String? = nil,
                         status: String = "active", limit: Int = 200) throws -> [MemoryItem] {
        try read {
            var conditions = ["status = ?"]
            if scope != nil { conditions.append("scope = ?") }
            if scopeId != nil { conditions.append("scope_id = ?") }
            let stmt = try prepare("""
            SELECT id, scope, scope_id, kind, title, content, evidence_json,
                   confidence, source, status, superseded_by, created_at, updated_at, last_used_at
            FROM memories WHERE \(conditions.joined(separator: " AND "))
            ORDER BY updated_at DESC LIMIT ?
            """)
            defer { sqlite3_finalize(stmt) }
            var index: Int32 = 1
            bind(stmt, index, status); index += 1
            if let scope { bind(stmt, index, scope.rawValue); index += 1 }
            if let scopeId { bind(stmt, index, scopeId); index += 1 }
            sqlite3_bind_int(stmt, index, Int32(min(max(limit, 1), 1000)))
            var out: [MemoryItem] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let scopeRaw = text(stmt, 1), let scope = MemoryScope(rawValue: scopeRaw),
                      let kindRaw = text(stmt, 3), let kind = MemoryKind(rawValue: kindRaw) else { continue }
                out.append(MemoryItem(id: sqlite3_column_int64(stmt, 0), scope: scope,
                                      scopeId: text(stmt, 2), kind: kind,
                                      title: text(stmt, 4) ?? "",
                                      content: text(stmt, 5) ?? "",
                                      evidence: text(stmt, 6) ?? "",
                                      confidence: sqlite3_column_double(stmt, 7),
                                      source: text(stmt, 8) ?? "user",
                                      status: text(stmt, 9) ?? "active",
                                      supersededBy: sqlite3_column_type(stmt, 10) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 10),
                                      createdAt: text(stmt, 11) ?? "",
                                      updatedAt: text(stmt, 12) ?? "",
                                      lastUsedAt: text(stmt, 13)))
            }
            return out
        }
    }

    @discardableResult
    public func addMemory(scope: MemoryScope, scopeId: String?, kind: MemoryKind,
                          title: String, content: String, evidence: String,
                          confidence: Double, source: String = "user",
                          supersedes: Int64? = nil) throws -> MemoryItem {
        try write {
            if let supersedes {
                let stmt = try prepare("""
                UPDATE memories SET status = 'superseded', superseded_by = NULL, updated_at = ?
                WHERE id = ?
                """)
                bind(stmt, 1, Dates.now())
                sqlite3_bind_int64(stmt, 2, supersedes)
                try stepDone(stmt)
                sqlite3_finalize(stmt)
            }
            let stmt = try prepare("""
            INSERT INTO memories
              (scope, scope_id, kind, title, content, evidence_json, confidence,
               source, status, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?)
            """)
            bind(stmt, 1, scope.rawValue)
            bind(stmt, 2, scopeId)
            bind(stmt, 3, kind.rawValue)
            bind(stmt, 4, title)
            bind(stmt, 5, content)
            bind(stmt, 6, evidence)
            sqlite3_bind_double(stmt, 7, confidence)
            bind(stmt, 8, source)
            bind(stmt, 9, Dates.now())
            bind(stmt, 10, Dates.now())
            try stepDone(stmt)
            sqlite3_finalize(stmt)
            let id = lastID()
            if let supersedes {
                let link = try prepare("UPDATE memories SET superseded_by = ? WHERE id = ?")
                sqlite3_bind_int64(link, 1, id)
                sqlite3_bind_int64(link, 2, supersedes)
                try stepDone(link)
                sqlite3_finalize(link)
            }
            try recordMemoryEvent(memoryId: id, action: "created", detail: source)
            return try memories().first { $0.id == id }!
        }
    }

    public func updateMemory(_ m: MemoryItem) throws {
        try write {
            let stmt = try prepare("""
            UPDATE memories SET title = ?, content = ?, evidence_json = ?, confidence = ?,
                                status = ?, updated_at = ? WHERE id = ?
            """)
            bind(stmt, 1, m.title)
            bind(stmt, 2, m.content)
            bind(stmt, 3, m.evidence)
            sqlite3_bind_double(stmt, 4, m.confidence)
            bind(stmt, 5, m.status)
            bind(stmt, 6, Dates.now())
            sqlite3_bind_int64(stmt, 7, m.id)
            try stepDone(stmt)
            sqlite3_finalize(stmt)
            try recordMemoryEvent(memoryId: m.id, action: "updated")
        }
    }

    public func archiveMemory(id: Int64) throws {
        try write {
            let stmt = try prepare("UPDATE memories SET status = 'archived', updated_at = ? WHERE id = ?")
            bind(stmt, 1, Dates.now())
            sqlite3_bind_int64(stmt, 2, id)
            try stepDone(stmt)
            sqlite3_finalize(stmt)
            try recordMemoryEvent(memoryId: id, action: "archived")
        }
    }

    /// 记录记忆被检索/引用，供下次排序使用。
    public func touchMemories(ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        try write {
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
            let stmt = try prepare("UPDATE memories SET last_used_at = ? WHERE id IN (\(placeholders))")
            bind(stmt, 1, Dates.now())
            for (offset, id) in ids.enumerated() {
                sqlite3_bind_int64(stmt, Int32(offset + 2), id)
            }
            try stepDone(stmt)
            sqlite3_finalize(stmt)
        }
    }

    public func recordMemoryEvent(memoryId: Int64?, action: String,
                                  reviewId: Int64? = nil,
                                  detail: String? = nil) throws {
        try write {
            let stmt = try prepare("""
            INSERT INTO memory_events (memory_id, action, review_id, detail, created_at)
            VALUES (?, ?, ?, ?, ?)
            """)
            if let memoryId { sqlite3_bind_int64(stmt, 1, memoryId) } else { sqlite3_bind_null(stmt, 1) }
            bind(stmt, 2, action)
            if let reviewId { sqlite3_bind_int64(stmt, 3, reviewId) } else { sqlite3_bind_null(stmt, 3) }
            bind(stmt, 4, detail)
            bind(stmt, 5, Dates.now())
            try stepDone(stmt)
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Style

    public func saveStyleSnapshot(_ metrics: StyleMetrics, narrative: String) throws -> StyleSnapshot {
        try write {
            let stmt = try prepare("""
            INSERT INTO style_snapshots (as_of, metrics_json, narrative, created_at)
            VALUES (?, ?, ?, ?)
            """)
            bind(stmt, 1, Dates.today())
            bind(stmt, 2, encode(metrics))
            bind(stmt, 3, narrative)
            bind(stmt, 4, Dates.now())
            try stepDone(stmt)
            sqlite3_finalize(stmt)
            return StyleSnapshot(id: lastID(), asOf: Dates.today(),
                                 metrics: metrics, narrative: narrative)
        }
    }

    public func styleSnapshots(limit: Int = 50) throws -> [StyleSnapshot] {
        try read {
            let stmt = try prepare("SELECT id, as_of, metrics_json, narrative FROM style_snapshots ORDER BY id DESC LIMIT ?")
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(min(max(limit, 1), 200)))
            var out: [StyleSnapshot] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let metrics: StyleMetrics = decode(text(stmt, 2) ?? "{}") ?? StyleMetrics(
                    holdingDays: 0, concentration: 0, planRate: 0, offPlanRate: 0,
                    reviewRate: 0, pattern: "", best: "", worst: "")
                out.append(StyleSnapshot(id: sqlite3_column_int64(stmt, 0),
                                         asOf: text(stmt, 1) ?? "",
                                         metrics: metrics,
                                         narrative: text(stmt, 3) ?? ""))
            }
            return out
        }
    }

    // MARK: - Reviews

    public func reviews(includeDone: Bool = true, limit: Int = 200) throws -> [ReviewRecord] {
        try read {
            let stmt = try prepare("""
            SELECT id, position_id, kind, due_at, period_start, period_end, status,
                   facts, notes, profile_id, outcome_json,
                   completed_at, created_at
            FROM reviews \(includeDone ? "" : "WHERE status != 'done'")
            ORDER BY COALESCE(due_at, created_at) ASC LIMIT ?
            """)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(min(max(limit, 1), 1000)))
            var out: [ReviewRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW { out.append(readReview(stmt)) }
            return out
        }
    }

    public func review(id: Int64) throws -> ReviewRecord? {
        try reviews(includeDone: true, limit: 1000).first { $0.id == id }
    }

    func readReview(_ stmt: OpaquePointer) -> ReviewRecord {
        ReviewRecord(id: sqlite3_column_int64(stmt, 0),
                     positionId: sqlite3_column_type(stmt, 1) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 1),
                     kind: text(stmt, 2) ?? "plan",
                     dueAt: text(stmt, 3),
                     periodStart: text(stmt, 4),
                     periodEnd: text(stmt, 5),
                     status: text(stmt, 6) ?? "due",
                     factsJSON: text(stmt, 7) ?? "[]",
                     notes: text(stmt, 8) ?? "",
                     profileId: text(stmt, 9),
                     outcomeJSON: text(stmt, 10) ?? "[]",
                     completedAt: text(stmt, 11),
                     createdAt: text(stmt, 12) ?? "")
    }

    @discardableResult
    public func createReview(positionId: Int64?, kind: String, dueAt: String?,
                             profileId: String?, factsJSON: String = "[]",
                             periodStart: String? = nil, periodEnd: String? = nil) throws -> ReviewRecord {
        try write {
            let stmt = try prepare("""
            INSERT INTO reviews
              (position_id, kind, due_at, period_start, period_end, status,
               facts, notes, profile_id, outcome_json, created_at)
            VALUES (?, ?, ?, ?, ?, 'due', ?, '', ?, '[]', ?)
            """)
            if let positionId { sqlite3_bind_int64(stmt, 1, positionId) } else { sqlite3_bind_null(stmt, 1) }
            bind(stmt, 2, kind)
            bind(stmt, 3, dueAt)
            bind(stmt, 4, periodStart)
            bind(stmt, 5, periodEnd)
            bind(stmt, 6, factsJSON)
            bind(stmt, 7, profileId)
            bind(stmt, 8, Dates.now())
            try stepDone(stmt)
            sqlite3_finalize(stmt)
            return try review(id: lastID())!
        }
    }

    public func saveReview(id: Int64, notes: String,
                           outcomeJSON: String? = nil, complete: Bool = false) throws {
        try write {
            let stmt = try prepare("""
            UPDATE reviews SET notes = ?,
                               outcome_json = COALESCE(?, outcome_json),
                               status = ?, completed_at = ?
            WHERE id = ?
            """)
            bind(stmt, 1, notes)
            bind(stmt, 2, outcomeJSON)
            bind(stmt, 3, complete ? "done" : "in_progress")
            bind(stmt, 4, complete ? Dates.now() : nil)
            sqlite3_bind_int64(stmt, 5, id)
            try stepDone(stmt)
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Drafts

    public func drafts(status: String? = nil, limit: Int = 100) throws -> [DraftRecord] {
        try read {
            let stmt = try prepare("""
            SELECT id, kind, position_id, skill, payload, base_version,
                   base_quantity, profile_id, status, note, created_at, decided_at
            FROM drafts \(status == nil ? "" : "WHERE status = ?")
            ORDER BY id DESC LIMIT ?
            """)
            defer { sqlite3_finalize(stmt) }
            var idx: Int32 = 1
            if let status { bind(stmt, idx, status); idx += 1 }
            sqlite3_bind_int(stmt, idx, Int32(min(max(limit, 1), 500)))
            var out: [DraftRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(DraftRecord(
                    id: sqlite3_column_int64(stmt, 0),
                    kind: text(stmt, 1) ?? "plan",
                    positionId: sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 2),
                    skill: text(stmt, 3),
                    payload: text(stmt, 4) ?? "{}",
                    baseVersion: sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 5)),
                    baseQuantity: sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 6),
                    profileId: text(stmt, 7),
                    status: text(stmt, 8) ?? "pending",
                    note: text(stmt, 9),
                    createdAt: text(stmt, 10) ?? "",
                    decidedAt: text(stmt, 11)))
            }
            return out
        }
    }

    @discardableResult
    public func addDraft(kind: String, positionId: Int64?,
                         skill: String?, payload: String, baseVersion: Int?,
                         baseQuantity: Double?, profileId: String?,
                         note: String? = nil) throws -> DraftRecord {
        try write {
            let stmt = try prepare("""
            INSERT INTO drafts
              (kind, position_id, skill, payload, base_version,
               base_quantity, profile_id, status, note, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)
            """)
            bind(stmt, 1, kind)
            if let positionId { sqlite3_bind_int64(stmt, 2, positionId) } else { sqlite3_bind_null(stmt, 2) }
            bind(stmt, 3, skill)
            bind(stmt, 4, payload)
            if let baseVersion { sqlite3_bind_int(stmt, 5, Int32(baseVersion)) } else { sqlite3_bind_null(stmt, 5) }
            if let baseQuantity { sqlite3_bind_double(stmt, 6, baseQuantity) } else { sqlite3_bind_null(stmt, 6) }
            bind(stmt, 7, profileId)
            bind(stmt, 8, note)
            bind(stmt, 9, Dates.now())
            try stepDone(stmt)
            sqlite3_finalize(stmt)
            return try drafts(status: nil, limit: 1).first!
        }
    }

    public func decideDraft(id: Int64, status: String) throws {
        try write {
            let stmt = try prepare("UPDATE drafts SET status = ?, decided_at = ? WHERE id = ?")
            bind(stmt, 1, status)
            bind(stmt, 2, Dates.now())
            sqlite3_bind_int64(stmt, 3, id)
            try stepDone(stmt)
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Notifications

    public func notifications(unreadOnly: Bool = false, limit: Int = 200) throws -> [NotificationRecord] {
        try read {
            let stmt = try prepare("""
            SELECT id, alert_id, kind, title, body, route, created_at, read_at, delivered_at, delivery
            FROM notifications \(unreadOnly ? "WHERE read_at IS NULL" : "")
            ORDER BY id DESC LIMIT ?
            """)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(min(max(limit, 1), 500)))
            var out: [NotificationRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(NotificationRecord(
                    id: sqlite3_column_int64(stmt, 0),
                    alertId: text(stmt, 1),
                    kind: text(stmt, 2) ?? "info",
                    title: text(stmt, 3) ?? "",
                    body: text(stmt, 4) ?? "",
                    route: text(stmt, 5),
                    createdAt: text(stmt, 6) ?? "",
                    readAt: text(stmt, 7),
                    deliveredAt: text(stmt, 8),
                    delivery: text(stmt, 9) ?? "inapp"))
            }
            return out
        }
    }

    public func addNotification(kind: String, title: String, body: String = "",
                                route: String? = nil, alertId: String? = nil,
                                delivery: String = "inapp") throws {
        try write {
            let stmt = try prepare("""
            INSERT INTO notifications (alert_id, kind, title, body, route, created_at, delivery)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """)
            bind(stmt, 1, alertId)
            bind(stmt, 2, kind)
            bind(stmt, 3, title)
            bind(stmt, 4, body)
            bind(stmt, 5, route)
            bind(stmt, 6, Dates.now())
            bind(stmt, 7, delivery)
            try stepDone(stmt)
            sqlite3_finalize(stmt)
        }
    }

    /// 同一个提醒/草稿只保留一条未读通知，避免每次行情刷新都新增。
    public func addNotificationIfNeeded(alertId: String, kind: String, title: String,
                                        body: String = "", route: String? = nil,
                                        delivery: String = "inapp") throws {
        let exists = try read {
            let stmt = try prepare("""
            SELECT 1 FROM notifications WHERE alert_id = ? AND read_at IS NULL LIMIT 1
            """)
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, alertId)
            return sqlite3_step(stmt) == SQLITE_ROW
        }
        guard !exists else { return }
        try addNotification(kind: kind, title: title, body: body, route: route,
                            alertId: alertId, delivery: delivery)
    }

    public func markNotificationRead(id: Int64) throws {
        try write {
            let stmt = try prepare("UPDATE notifications SET read_at = ? WHERE id = ? AND read_at IS NULL")
            bind(stmt, 1, Dates.now())
            sqlite3_bind_int64(stmt, 2, id)
            try stepDone(stmt)
            sqlite3_finalize(stmt)
        }
    }

    public func markAllNotificationsRead() throws {
        try write {
            try exec("UPDATE notifications SET read_at = '\(Dates.now())' WHERE read_at IS NULL;")
        }
    }

    // MARK: - Import

    public func importMappings() throws -> [ImportMapping] {
        try read {
            let stmt = try prepare("SELECT id, broker, name, version, mapping_json, created_at, updated_at FROM import_mappings ORDER BY id DESC")
            defer { sqlite3_finalize(stmt) }
            var out: [ImportMapping] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(ImportMapping(
                    id: sqlite3_column_int64(stmt, 0),
                    broker: text(stmt, 1) ?? "",
                    name: text(stmt, 2) ?? "",
                    version: Int(sqlite3_column_int(stmt, 3)),
                    fields: decode(text(stmt, 4) ?? "{}") ?? [:],
                    createdAt: text(stmt, 5) ?? "",
                    updatedAt: text(stmt, 6) ?? ""))
            }
            return out
        }
    }

    @discardableResult
    public func saveImportMapping(broker: String, name: String,
                                  fields: [String: String]) throws -> ImportMapping {
        try write {
            let stmt = try prepare("""
            INSERT INTO import_mappings (broker, name, version, mapping_json, created_at, updated_at)
            VALUES (?, ?, 1, ?, ?, ?)
            """)
            bind(stmt, 1, broker)
            bind(stmt, 2, name)
            bind(stmt, 3, encode(fields))
            bind(stmt, 4, Dates.now())
            bind(stmt, 5, Dates.now())
            try stepDone(stmt)
            sqlite3_finalize(stmt)
            return try importMappings().first!
        }
    }

    @discardableResult
    public func createImportBatch(accountId: Int64, broker: String, fileName: String,
                                  fileHash: String, mappingId: Int64?,
                                  rowsTotal: Int) throws -> ImportBatch {
        try write {
            let stmt = try prepare("""
            INSERT INTO import_batches
              (account_id, broker, file_name, file_hash, mapping_id, status,
               rows_total, rows_imported, rows_skipped, rows_error, started_at)
            VALUES (?, ?, ?, ?, ?, 'preview', ?, 0, 0, 0, ?)
            """)
            sqlite3_bind_int64(stmt, 1, accountId)
            bind(stmt, 2, broker)
            bind(stmt, 3, fileName)
            bind(stmt, 4, fileHash)
            if let mappingId { sqlite3_bind_int64(stmt, 5, mappingId) } else { sqlite3_bind_null(stmt, 5) }
            sqlite3_bind_int(stmt, 6, Int32(rowsTotal))
            bind(stmt, 7, Dates.now())
            try stepDone(stmt)
            sqlite3_finalize(stmt)
            return try importBatches().first { $0.id == lastID() }!
        }
    }

    public func importBatches(limit: Int = 100) throws -> [ImportBatch] {
        try read {
            let stmt = try prepare("""
            SELECT id, account_id, broker, file_name, file_hash, mapping_id, status,
                   rows_total, rows_imported, rows_skipped, rows_error, error,
                   started_at, finished_at
            FROM import_batches ORDER BY id DESC LIMIT ?
            """)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(min(max(limit, 1), 500)))
            var out: [ImportBatch] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(ImportBatch(
                    id: sqlite3_column_int64(stmt, 0),
                    accountId: sqlite3_column_int64(stmt, 1),
                    broker: text(stmt, 2) ?? "",
                    fileName: text(stmt, 3) ?? "",
                    fileHash: text(stmt, 4) ?? "",
                    mappingId: sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 5),
                    status: ImportBatchStatus(rawValue: text(stmt, 6) ?? "") ?? .preview,
                    rowsTotal: Int(sqlite3_column_int(stmt, 7)),
                    rowsImported: Int(sqlite3_column_int(stmt, 8)),
                    rowsSkipped: Int(sqlite3_column_int(stmt, 9)),
                    rowsError: Int(sqlite3_column_int(stmt, 10)),
                    error: text(stmt, 11),
                    startedAt: text(stmt, 12) ?? "",
                    finishedAt: text(stmt, 13)))
            }
            return out
        }
    }

    public func executions(batchId: Int64? = nil, limit: Int = 1000) throws -> [Execution] {
        try read {
            let stmt = try prepare("""
            SELECT id, account_id, batch_id, broker_trade_id, order_id, code, name, side,
                   quantity_scaled, quantity_scale, price_scaled, price_scale, amount_minor,
                   fee_commission_minor, fee_stamp_minor, fee_transfer_minor, fee_other_minor,
                   fee_total_minor, currency, trade_time, settle_date, source, dedupe_key,
                   change_id, status, voided_at, created_at
            FROM executions \(batchId == nil ? "" : "WHERE batch_id = ?")
            ORDER BY trade_time, id LIMIT ?
            """)
            defer { sqlite3_finalize(stmt) }
            var idx: Int32 = 1
            if let batchId { sqlite3_bind_int64(stmt, idx, batchId); idx += 1 }
            sqlite3_bind_int(stmt, idx, Int32(min(max(limit, 1), 5000)))
            var out: [Execution] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let qScale = sqlite3_column_double(stmt, 9)
                let pScale = sqlite3_column_double(stmt, 11)
                out.append(Execution(
                    id: sqlite3_column_int64(stmt, 0),
                    accountId: sqlite3_column_int64(stmt, 1),
                    batchId: sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 2),
                    brokerTradeId: text(stmt, 3),
                    orderId: text(stmt, 4),
                    code: text(stmt, 5) ?? "",
                    name: text(stmt, 6) ?? "",
                    side: TradeSide(rawValue: text(stmt, 7) ?? "") ?? .buy,
                    quantity: sqlite3_column_double(stmt, 8) / max(qScale, 1),
                    price: sqlite3_column_double(stmt, 10) / max(pScale, 1),
                    amount: sqlite3_column_double(stmt, 12) / 100,
                    feeCommission: sqlite3_column_double(stmt, 13) / 100,
                    feeStamp: sqlite3_column_double(stmt, 14) / 100,
                    feeTransfer: sqlite3_column_double(stmt, 15) / 100,
                    feeOther: sqlite3_column_double(stmt, 16) / 100,
                    feeTotal: sqlite3_column_double(stmt, 17) / 100,
                    currency: text(stmt, 18) ?? "CNY",
                    tradeTime: text(stmt, 19) ?? "",
                    settleDate: text(stmt, 20),
                    source: text(stmt, 21) ?? "import",
                    dedupeKey: text(stmt, 22) ?? "",
                    changeId: sqlite3_column_type(stmt, 23) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 23),
                    status: text(stmt, 24) ?? "active",
                    voidedAt: text(stmt, 25),
                    createdAt: text(stmt, 26) ?? ""))
            }
            return out
        }
    }

    public func executionExists(dedupeKey: String) throws -> Bool {
        try read {
            let stmt = try prepare("SELECT 1 FROM executions WHERE dedupe_key = ? AND status != 'void' LIMIT 1")
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, dedupeKey)
            return sqlite3_step(stmt) == SQLITE_ROW
        }
    }

    @discardableResult
    public func insertExecution(_ e: Execution, batchId: Int64?) throws -> Int64 {
        try write {
            let stmt = try prepare("""
            INSERT INTO executions
              (account_id, batch_id, broker_trade_id, order_id, code, name, side,
               quantity_scaled, quantity_scale, price_scaled, price_scale, amount_minor,
               fee_commission_minor, fee_stamp_minor, fee_transfer_minor, fee_other_minor,
               fee_total_minor, currency, trade_time, settle_date, source, raw_json,
               dedupe_key, change_id, status, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 10000, ?, 10000, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, NULL, 'active', ?)
            """)
            sqlite3_bind_int64(stmt, 1, e.accountId)
            if let batchId { sqlite3_bind_int64(stmt, 2, batchId) } else { sqlite3_bind_null(stmt, 2) }
            bind(stmt, 3, e.brokerTradeId)
            bind(stmt, 4, e.orderId)
            bind(stmt, 5, e.code)
            bind(stmt, 6, e.name)
            bind(stmt, 7, e.side.rawValue)
            sqlite3_bind_int64(stmt, 8, Int64((e.quantity * 10000).rounded()))
            sqlite3_bind_int64(stmt, 9, Int64((e.price * 10000).rounded()))
            sqlite3_bind_int64(stmt, 10, Int64((e.amount * 100).rounded()))
            sqlite3_bind_int64(stmt, 11, Int64((e.feeCommission * 100).rounded()))
            sqlite3_bind_int64(stmt, 12, Int64((e.feeStamp * 100).rounded()))
            sqlite3_bind_int64(stmt, 13, Int64((e.feeTransfer * 100).rounded()))
            sqlite3_bind_int64(stmt, 14, Int64((e.feeOther * 100).rounded()))
            sqlite3_bind_int64(stmt, 15, Int64((e.feeTotal * 100).rounded()))
            bind(stmt, 16, e.currency)
            bind(stmt, 17, e.tradeTime)
            bind(stmt, 18, e.settleDate)
            bind(stmt, 19, e.source)
            bind(stmt, 20, e.dedupeKey)
            bind(stmt, 21, Dates.now())
            try stepDone(stmt)
            sqlite3_finalize(stmt)
            return lastID()
        }
    }

    @discardableResult
    public func applyImportedTrades(_ list: [Execution], batchId: Int64) throws -> [Int64: Int64?] {
        let sorted = list.sorted { $0.tradeTime < $1.tradeTime }
        return try write {
            var result: [Int64: Int64?] = [:]
            for e in sorted {
                guard e.id != 0 else { continue }
                let executionId = e.id
                let code = normalizeCode(e.code)
                let day = String(e.tradeTime.prefix(10))
                let occurred = Dates.isDay(day) ? day : Dates.today()
                let accountId = e.accountId
                let existing = try openPositionRow(accountId: accountId, code: code)
                if existing == nil {
                    guard e.side == .buy else {
                        result[executionId] = nil
                        continue
                    }
                    let cost = (e.amount + e.feeTotal) / max(e.quantity, 1e-9)
                    let profileId: String? = nil
                    let positionStmt = try prepare("""
                    INSERT INTO positions
                      (code, name, source, unit, quantity, avg_cost, status, opened_at, closed_at,
                       account_id, profile_id, profile_snapshot)
                    VALUES (?, ?, ?, ?, ?, ?, 'open', ?, NULL, ?, ?, NULL)
                    """)
                    bind(positionStmt, 1, code)
                    bind(positionStmt, 2, e.name.isEmpty ? code : e.name)
                    bind(positionStmt, 3, inferSource(code).rawValue)
                    bind(positionStmt, 4, isGold(code) ? UnitKind.gram.rawValue : UnitKind.share.rawValue)
                    sqlite3_bind_double(positionStmt, 5, e.quantity)
                    sqlite3_bind_double(positionStmt, 6, cost)
                    bind(positionStmt, 7, occurred)
                    sqlite3_bind_int64(positionStmt, 8, accountId)
                    bind(positionStmt, 9, profileId)
                    try stepDone(positionStmt)
                    sqlite3_finalize(positionStmt)
                    let pid = lastID()
                    let change = try insertChange(positionId: pid, type: .open,
                                                  qtyBefore: 0, qtyAfter: e.quantity,
                                                  costBefore: 0, costAfter: cost,
                                                  price: e.price, fee: e.feeTotal,
                                                  levelPrice: nil, levelId: nil,
                                                  planVersion: nil, direction: nil,
                                                  planSnapshot: nil,
                                                  note: "导入交割单", occurredAt: occurred)
                    try markChangeImported(change.id, executionId: executionId,
                                           batchId: batchId, accountId: accountId)
                    try linkExecution(executionId, changeId: change.id)
                    try consumeWatchOnImport(code: code, into: pid)
                    result[executionId] = change.id
                    continue
                }
                let row = existing!
                guard row.quantity + 1e-9 >= e.quantity || e.side == .buy else {
                    result[executionId] = nil
                    continue
                }
                let qtyAfter = e.side == .buy ? row.quantity + e.quantity : row.quantity - e.quantity
                let costAfter: Double
                if e.side == .buy {
                    costAfter = (row.quantity * row.cost + e.amount + e.feeTotal) / max(qtyAfter, 1e-9)
                } else {
                    costAfter = row.cost
                }
                let type: ChangeType = qtyAfter <= 1e-9 ? .clear : (e.side == .buy ? .buy : .sell)
                let change = try insertChange(positionId: row.id, type: type,
                                              qtyBefore: row.quantity, qtyAfter: qtyAfter,
                                              costBefore: row.cost, costAfter: costAfter,
                                              price: e.price, fee: e.feeTotal,
                                              levelPrice: nil, levelId: nil,
                                              planVersion: nil, direction: e.side.rawValue,
                                              planSnapshot: nil,
                                              note: "导入交割单", occurredAt: occurred)
                try markChangeImported(change.id, executionId: executionId,
                                       batchId: batchId, accountId: accountId)
                try linkExecution(executionId, changeId: change.id)
                try updatePosition(id: row.id, quantity: qtyAfter, cost: costAfter,
                                   status: qtyAfter <= 1e-9 ? .closed : .open,
                                   closedAt: qtyAfter <= 1e-9 ? occurred : nil)
                result[executionId] = change.id
            }
            return result
        }
    }

    struct PositionRow {
        var id: Int64
        var quantity: Double
        var cost: Double
        var name: String
        var unit: UnitKind
    }

    func openPositionRow(accountId: Int64, code: String) throws -> PositionRow? {
        let stmt = try prepare("""
        SELECT id, quantity, avg_cost, name, unit FROM positions
        WHERE (account_id = ? OR account_id IS NULL) AND code = ? AND kind = 'holding' AND status = 'open'
        ORDER BY id DESC LIMIT 1
        """)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, accountId)
        bind(stmt, 2, code)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return PositionRow(id: sqlite3_column_int64(stmt, 0),
                           quantity: sqlite3_column_double(stmt, 1),
                           cost: sqlite3_column_double(stmt, 2),
                           name: text(stmt, 3) ?? code,
                           unit: UnitKind(rawValue: text(stmt, 4) ?? "share") ?? .share)
    }

    func markChangeImported(_ changeId: Int64, executionId: Int64,
                            batchId: Int64, accountId: Int64) throws {
        let stmt = try prepare("""
        UPDATE changes SET execution_id = ?, batch_id = ?, account_id = ?, source = 'import'
        WHERE id = ?
        """)
        sqlite3_bind_int64(stmt, 1, executionId)
        sqlite3_bind_int64(stmt, 2, batchId)
        sqlite3_bind_int64(stmt, 3, accountId)
        sqlite3_bind_int64(stmt, 4, changeId)
        try stepDone(stmt)
        sqlite3_finalize(stmt)
    }

    func linkExecution(_ executionId: Int64, changeId: Int64) throws {
        let stmt = try prepare("UPDATE executions SET change_id = ? WHERE id = ?")
        sqlite3_bind_int64(stmt, 1, changeId)
        sqlite3_bind_int64(stmt, 2, executionId)
        try stepDone(stmt)
        sqlite3_finalize(stmt)
    }

    public func updateImportBatch(id: Int64, status: ImportBatchStatus,
                                  imported: Int, skipped: Int,
                                  errors: Int, error: String? = nil) throws {
        try write {
            let stmt = try prepare("""
            UPDATE import_batches SET status = ?, rows_imported = ?, rows_skipped = ?,
                                      rows_error = ?, error = ?, finished_at = ?
            WHERE id = ?
            """)
            bind(stmt, 1, status.rawValue)
            sqlite3_bind_int(stmt, 2, Int32(imported))
            sqlite3_bind_int(stmt, 3, Int32(skipped))
            sqlite3_bind_int(stmt, 4, Int32(errors))
            bind(stmt, 5, error)
            bind(stmt, 6, Dates.now())
            sqlite3_bind_int64(stmt, 7, id)
            try stepDone(stmt)
            sqlite3_finalize(stmt)
        }
    }

    public func voidImportBatch(id: Int64) throws -> Int {
        try write {
            let affected = try read {
                let stmt = try prepare("""
                SELECT DISTINCT position_id FROM changes WHERE batch_id = ? AND voided_at IS NULL
                """)
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_int64(stmt, 1, id)
                var out: [Int64] = []
                while sqlite3_step(stmt) == SQLITE_ROW { out.append(sqlite3_column_int64(stmt, 0)) }
                return out
            }
            let now = Dates.now()
            // 回滚后允许重新导入同一文件：把 void 行的去重键挪开，保留审计记录。
            let execStmt = try prepare("""
            UPDATE executions SET status = 'void', voided_at = ?,
                   dedupe_key = dedupe_key || '#void#' || id
            WHERE batch_id = ? AND status != 'void'
            """)
            bind(execStmt, 1, now)
            sqlite3_bind_int64(execStmt, 2, id)
            try stepDone(execStmt)
            sqlite3_finalize(execStmt)
            let changeStmt = try prepare("UPDATE changes SET voided_at = ? WHERE batch_id = ? AND voided_at IS NULL")
            bind(changeStmt, 1, now)
            sqlite3_bind_int64(changeStmt, 2, id)
            try stepDone(changeStmt)
            sqlite3_finalize(changeStmt)
            for pid in affected {
                let active = try scalarInt("SELECT COUNT(*) FROM changes WHERE position_id = \(pid) AND voided_at IS NULL")
                if active == 0 {
                    try exec("UPDATE positions SET quantity = 0, status = 'closed', closed_at = '\(now.prefix(10))' WHERE id = \(pid);")
                } else {
                    try rebuildLocked(positionId: pid)
                }
            }
            let batchStmt = try prepare("UPDATE import_batches SET status = 'voided', finished_at = ? WHERE id = ?")
            bind(batchStmt, 1, Dates.now())
            sqlite3_bind_int64(batchStmt, 2, id)
            try stepDone(batchStmt)
            sqlite3_finalize(batchStmt)
            return affected.count
        }
    }

    func rebuildLocked(positionId: Int64) throws {
        let stmt = try prepare("""
        SELECT qty_after, cost_after, type, occurred_at FROM changes
        WHERE position_id = ? AND qty_after IS NOT NULL AND voided_at IS NULL
        ORDER BY id DESC LIMIT 1
        """)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, positionId)
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            try exec("UPDATE positions SET quantity = 0, status = 'closed' WHERE id = \(positionId);")
            return
        }
        let qty = sqlite3_column_double(stmt, 0)
        let cost = sqlite3_column_double(stmt, 1)
        let type = text(stmt, 2)
        let at = text(stmt, 3)
        let closed = qty <= 0 || type == ChangeType.clear.rawValue
        try updatePosition(id: positionId, quantity: qty, cost: cost,
                           status: closed ? .closed : .open,
                           closedAt: closed ? at : nil)
    }

    // MARK: - Samples

    public func recordQuoteSample(_ q: Quote, at: String = Dates.now()) throws {
        try write {
            let stmt = try prepare("""
            INSERT INTO quote_samples (code, price, prev_close, source, at) VALUES (?, ?, ?, ?, ?)
            """)
            bind(stmt, 1, q.code)
            sqlite3_bind_double(stmt, 2, q.price)
            sqlite3_bind_double(stmt, 3, q.prevClose)
            bind(stmt, 4, q.source.rawValue)
            bind(stmt, 5, at)
            try stepDone(stmt)
            sqlite3_finalize(stmt)
        }
    }
}
