# JSON 结构

## 成功

```json
{
  "ok": true,
  "data": {},
  "meta": {
    "api_version": 1,
    "app_version": "0.1.0",
    "schema_version": 8,
    "db": "/Users/me/Library/Application Support/Carapace/store.sqlite3",
    "as_of": "2026-11-06T15:00:00+08:00",
    "request_id": "写操作才有"
  }
}
```

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

## 退出码

| 码 | 含义 |
|---|---|
| 0 | 成功 |
| 2 | 参数错误 |
| 3 | 校验失败 |
| 4 | 未找到 |
| 5 | 版本冲突 |
| 6 | 数据库错误 |
| 7 | 行情/网络错误 |
| 9 | 内部错误 |

## 主要对象

### Position

```json
{
  "id": 12,
  "code": "600000",
  "name": "浦发银行",
  "kind": "holding | watch",
  "market": "cn | hk | us | index",
  "currency": "CNY | HKD | USD",
  "source": "eastmoney | sina | cmb | fund",
  "unit": "share | fund | gram",
  "quantity": 100,
  "avgCost": 10,
  "status": "open | closed",
  "openedAt": "2026-11-06",
  "closedAt": null,
  "note": null,
  "watchPrice": null,
  "quoteKey": null,
  "quoteCode": "600000"
}
```

### Portfolio

```json
{
  "currency": "CNY",
  "totalValue": 2005.99,
  "totalCost": 2000,
  "totalPnl": 6.0,
  "todayPnl": 32.0,
  "hasCompleteValuation": true,
  "positions": [
    {
      "id": 12,
      "code": "600000",
      "quantity": 100,
      "quote": {"code": "600000", "price": 10.03, "time": "...", "source": "eastmoney"},
      "value": 1003,
      "valueCNY": 1003,
      "todayPnl": 16,
      "totalPnl": 3,
      "weight": 0.5,
      "fxRate": 1,
      "nextLevel": {"id": "buy-1", "kind": "buy", "price": 9.5, "quantity": 1000}
    }
  ]
}
```

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
    {"id": "buy-1", "kind": "buy", "price": 9.5, "quantity": 1000, "condition": "回到 20 日线"}
  ],
  "updatedAt": "2026-11-06T15:00:00+08:00",
  "executedLevels": ["buy-1"]
}
```

### Quote

```json
{
  "code": "600000",
  "name": "浦发银行",
  "price": 10.03,
  "prevClose": 9.87,
  "changePct": 1.62,
  "time": "2026-11-06 15:00:00",
  "source": "eastmoney",
  "sellPrice": null,
  "prevSellPrice": null,
  "valuationPrice": 10.03
}
```

### Review

```json
{
  "id": 7,
  "positionId": 12,
  "kind": "plan | exit | weekly",
  "dueAt": "2026-12-01",
  "status": "due | in_progress | done",
  "facts": "[[\"持仓天数\",\"12 天\"]]",
  "notes": "我的判断",
  "profileId": "a-share-stock",
  "outcome": "[]",
  "completedAt": null,
  "createdAt": "2026-11-06T15:00:00+08:00"
}
```

### Draft

```json
{
  "id": 5,
  "kind": "plan",
  "positionId": 12,
  "skill": "carapace",
  "payload": "{\"levels\":[],\"description\":\"...\"}",
  "baseVersion": 3,
  "status": "pending | applied | discarded",
  "note": "Claude 复核",
  "createdAt": "2026-11-06T15:00:00+08:00",
  "decidedAt": null
}
```

### Memory

```json
{
  "id": 4,
  "scope": "global | profile | instrument | position",
  "scopeId": null,
  "kind": "principle | preference | pattern | lesson | fact | hypothesis",
  "title": "不追高",
  "content": "只在计划档位买入",
  "evidence": "外部 Agent 添加",
  "confidence": 0.8,
  "source": "agent",
  "status": "active | archived | superseded",
  "createdAt": "2026-11-06T15:00:00+08:00",
  "updatedAt": "2026-11-06T15:00:00+08:00"
}
```

写操作成功时 `data` 里通常还会有 `"dry_run": false`；`--dry-run` 时为 `true` 且不写入。