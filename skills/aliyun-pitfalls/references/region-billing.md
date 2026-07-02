## 📍 區域與計費

### 大陸區 vs 國際區的實名差異

| 區域類型 | Region 範例 | 實名要求 |
|---------|-------------|---------|
| 大陸區 | cn-beijing / cn-hangzhou / cn-shenzhen | ✅ 必須中國實名認證（國際版帳號買不了）|
| 國際區 | ap-northeast-1 / ap-southeast-1 / us-west-1 | ❌ 不用中國實名 |

**症狀**：
```
Code: NO_REAL_REGISTER_AUTHENTICATION
Code: Order.NoRealNameAuthentication
Message: Real-name verification has not been completed for the account.
HostId: vpc.cn-beijing.aliyuncs.com   ← 注意這個 HostId
```

**99% 是 provider 漂移到大陸區了**，不是真的要實名（如果你在做國際區）。

**排查順序**：
1. 看錯誤 HostId — 是不是真的 cn-* ？
2. 看 tfvars `region` — 是不是真的設了國際區 ？
3. 看 provider config — 是不是缺 `region = var.region` ？
4. 看 lock 檔 — 是不是 `hashicorp/alicloud` 殘留（見下方）？

---
