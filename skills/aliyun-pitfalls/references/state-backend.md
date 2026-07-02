## 🪣 State / OSS Backend

### 20. OSS 操作要 region endpoint

**現象**：
```
ErrorCode=AccessDenied
ErrorMessage="The bucket you are attempting to access must be addressed using the specified endpoint."
Endpoint=oss-ap-northeast-1.aliyuncs.com
```

**修復**：所有 OSS CLI 指令加 `--endpoint`：
```bash
aliyun oss ls oss://bucket-name --endpoint oss-ap-northeast-1.aliyuncs.com
aliyun oss bucket-versioning --method put oss://b Enabled --endpoint oss-...
```

`aliyun oss mb`（建 bucket）不用，因為它走 OSS global endpoint。

---
