# JSON 结构

示例标的、价格和时间均为合成占位值；不要把它们当作真实持仓。

## 成功

```json
{
  "ok": true,
  "data": {},
  "meta": {
    "api_version": 1,
    "app_version": "0.1.0",
    "as_of": "2026-11-09T15:00:00+08:00",
    "db": "/Users/me/Library/Application Support/Carapace/store.sqlite3",
    "schema_version": 8,
    "request_id": "写操作传入 --request-id 才有"
  }
}
```

`doctor` 等带 Store 的命令在 `meta` 里返回 `db` 和 `schema_version`；
`version`、`schema` 没有 Store，`meta` 里没有这两个字段。
`doctor` 的 `data` 自身还返回 `healthy`、`checks`、`api_version`、`app_version`、
`schema_version`、`db`、`app_running`。Agent 启动检查读的是 `data`。

## 失败

```json
{
  "ok": false,
  "error": {
    "code": "VALIDATION",
    "message": "数量必须大于 0",
    "hint": "可选"
  },
  "meta": {
    "api_version": 1,
    "app_version": "0.1.0"
  }
}
```

失败响应没有 `data`，也没有 `as_of`。

## 退出码

| 码 | 含义 | 典型 code |
|---|---|---|
| 0 | 成功 | — |
| 2 | 参数错误 | `USAGE` |
| 3 | 校验失败 | `VALIDATION` |
| 4 | 未找到 | `NOT_FOUND` |
| 5 | 版本冲突 | `CONFLICT` |
| 6 | 数据库错误 | `DB` |
| 7 | 行情/网络错误 | `QUOTE` |
| 9 | 内部错误 | `INTERNAL` |

## 主要对象

CLI 输出的是字典，不是 Swift Codable 的直接镜像；`NSNull` 在 JSON 里是 `null`。

### doctor

```json
{
  "healthy": true,
  "checks": [
    {"name": "database", "ok": true, "detail": "/tmp/carapace-test/store.sqlite3"},
    {"name": "schema", "ok": true, "detail": "v8"},
    {"name": "permissions", "ok": true, "detail": "600"},
    {"name": "ai_keys", "ok": true, "detail": "0 个遗留密钥"}
  ],
  "api_version": 1,
  "app_version": "0.1.0",
  "schema_version": 8,
  "db": "/tmp/carapace-test/store.sqlite3",
  "app_running": false
}
```

`app_running=true` 时会追加一条 `app_running` 检查；它本身不使 `healthy=false`。

### Position

```json
{
  "id": 12,
  "code": "000000",
  "name": "示例股份",
  "kind": "holding | watch",
  "market": "cn | hk | us | index",
  "currency": "CNY | HKD | USD",
  "source": "eastmoney | sina | cmb | fund",
  "unit": "share | gram | fund",
  "quantity": 100,
  "avgCost": 10,
  "status": "open | closed",
  "openedAt": "2026-11-09",
  "closedAt": null,
  "note": null,
  "watchPrice": null,
  "quoteKey": null,
  "quoteCode": "000000"
}
```

`positions list` 还会给有计划的行追加 `planVersion`、`nextReview`；
`positions get` 还会追加 `plan`、`executedLevels`、`changes`、`cachedQuote`。

### Portfolio

```json
{
  "currency": "CNY",
  "totalValue": 1000,
  "totalCost": 1000,
  "totalPnl": null,
  "todayPnl": null,
  "hasCompleteValuation": false,
  "positions": [
    {
      "id": 12,
      "code": "000000",
      "quantity": 100,
      "quote": null,
      "value": null,
      "valueCNY": null,
      "todayPnl": null,
      "totalPnl": null,
      "weight": null,
      "fxRate": 1,
      "nextLevel": null
    }
  ]
}
```

行情缺失时 `quote` 是 `null`，不要把成本当现价。

### Plan

```json
{
  "id": 1,
  "positionId": 12,
  "version": 3,
  "author": "agent",
  "description": "复核后的计划",
  "nextReview": "2026-12-01",
  "levels": [
    {"id": "buy-1", "kind": "buy", "price": 9, "quantity": 100, "condition": "回到均线"}
  ],
  "updatedAt": "2026-11-09T15:00:00+08:00",
  "executedLevels": []
}
```

`executedLevels` 由 `plans get` 在顶层追加；`planDict` 本身没有这个字段。
`plans update` 返回 `{"plan": ..., "diff": ...}`，版本在 `data.plan.version`。

### Quote

```json
{
  "code": "000000",
  "name": "示例股份",
  "price": 10,
  "prevClose": 10,
  "changePct": 0,
  "time": "2026-11-09 15:00:00",
  "source": "eastmoney",
  "sellPrice": null,
  "prevSellPrice": null,
  "valuationPrice": 10
}
```

### Review

```json
{
  "id": 7,
  "positionId": 12,
  "kind": "plan",
  "dueAt": "2026-12-01",
  "periodStart": null,
  "periodEnd": null,
  "status": "due",
  "facts": "[]",
  "notes": "",
  "outcome": "[]",
  "completedAt": null,
  "createdAt": "2026-11-09T15:00:00+08:00"
}
```

`facts` 和 `outcome` 是 JSON 字符串；`profileId` 不在 CLI 返回里。

### Draft

```json
{
  "id": 5,
  "kind": "plan",
  "positionId": 12,
  "skill": "carapace",
  "payload": "{\"levels\":[],\"description\":\"...\"}",
  "baseVersion": 3,
  "baseQuantity": null,
  "status": "pending",
  "note": "Claude 复核",
  "createdAt": "2026-11-09T15:00:00+08:00",
  "decidedAt": null
}
```

`payload` 是 JSON 字符串；应用草稿时 `baseVersion` 与当前计划版本不一致会返回 `CONFLICT`。

### Memory

```json
{
  "id": 4,
  "scope": "global",
  "scopeId": null,
  "kind": "principle",
  "title": "不追高",
  "content": "只在计划档位买入",
  "evidence": "外部 Agent 添加",
  "confidence": 0.8,
  "source": "agent",
  "status": "active",
  "supersededBy": null,
  "createdAt": "2026-11-09T15:00:00+08:00",
  "updatedAt": "2026-11-09T15:00:00+08:00",
  "lastUsedAt": null
}
```

`scope` 可取 `global|profile|instrument|position`，但 CLI 的 `memories add` 不接受 `profile`；
`status` 可取 `active|archived|superseded`。`memories context` 返回
`{"memories": [...], "text": "..."}`，`text` 里用 `[M1]` 等编号标注可引用记忆。

### Import preview

```json
{
  "summary": {"total": 1, "ready": 1, "duplicate": 0, "needsReview": 0, "errors": 0},
  "mapping": {"trade_time": "成交日期", "code": "证券代码"},
  "headers": ["成交日期", "证券代码"],
  "rows": [
    {
      "row": 2,
      "tradeTime": "2026-01-02",
      "code": "000000",
      "name": "示例股份",
      "side": "buy",
      "quantity": 100,
      "price": 10,
      "feeTotal": 1,
      "status": "ready",
      "message": ""
    }
  ]
}
```

`rows` 最多返回预览中的前 50 行；`needsReview` 是金额与数量×价格不一致的行，
默认提交会跳过。`import commit` 返回 `batch`、`imported`、`skipped`、
`needsReview`、`errors`。

## 写操作返回

经 `performWrite` 的写命令在 `data` 里追加 `dry_run`：`--dry-run` 为 `true` 且不写入，
正式执行为 `false`。预览返回的是命令自定义的字段，不等于正式执行返回。
带 `--request-id` 重试同一命令时，CLI 返回首次执行缓存的结果，不会重复记账。
