# Flask-RESTX Swagger/OpenAPI 規範

本文件定義了本專案使用 `Flask-RESTX` 撰寫 API 文檔的完整規範。
當你在 `handler/` 中新增或修改端點時，**必須**遵循以下所有規則。

---

## 基礎設施前置檢查

首次接手專案或發現 Swagger UI 無法訪問時，確認以下項目：

- `requirements.txt` 包含 `flask-restx`
- `app/interfaces/api/router.py` 中 `Api` 實例配置了 `title`、`version`、`description`、`doc`、`authorizations`
- `Api` 的 `doc` 參數設定了 Swagger UI 路徑（如 `doc="/doc/"`）
- `authorizations` 正確配置了 `BearerAuth`（apiKey, header, Authorization）

---

## 核心原則

1. **Schema 定義在 `schema/` 目錄**：按資源分檔，Handler import 使用。禁止在 Handler 內 inline 定義 api.model。
2. **不使用 `@ns.marshal_with`**：避免與 `pkg/response` 手動回應格式雙重衝突。
3. **使用 `@ns.response` 標註文檔**：僅作為 Swagger 文檔標註，不自動序列化。
4. **使用 `pkg/response` 統一回傳**：`success()` / `created()` / `error()`。

---

## Namespace 定義規範

每個資源模組**必須**建立獨立的 `Namespace`：

```python
from flask_restx import Namespace
user_ns = Namespace("users", description="用戶管理")
```

| 屬性 | 規則 | 必填 |
|------|------|------|
| `name` | 小寫 kebab-case，作為 URL 路徑片段 | 必填 |
| `description` | 中文描述 | 必填 |

---

## api.model 定義規範

使用 `ns.model()` 定義請求與回應結構，讓 Swagger UI 自動生成文檔。

### 必填規則

- **每個端點**的請求 Body 和回應 Data 都必須有對應的 `api.model`
- **每個欄位**都必須包含 `description`（中文）與 `example`
- 使用 `required=True` 標記必填欄位
- `enum` 型別欄位必須列出所有可選值

### 欄位型別對照

| Python 型別 | Flask-RESTX fields | 用法 |
|-------------|-------------------|------|
| `str` | `fields.String` | `fields.String(required=True, description="用戶名稱", example="王小明")` |
| `int` | `fields.Integer` | `fields.Integer(description="用戶 ID", example=1)` |
| `float` | `fields.Float` | `fields.Float(description="價格", example=99.9)` |
| `bool` | `fields.Boolean` | `fields.Boolean(description="是否啟用", example=True)` |
| `datetime` | `fields.DateTime` | `fields.DateTime(description="建立時間")` |
| `list` | `fields.List` | `fields.List(fields.String, description="標籤列表")` |
| `nested` | `fields.Nested` | `fields.Nested(other_model, description="巢狀物件")` |

---

## Handler 裝飾器規範

每個 Resource 方法**必須**加上以下全部適用的裝飾器：

| 裝飾器 | 說明 | 必填 |
|--------|------|------|
| `@ns.doc(description="...", security="BearerAuth")` | 端點說明 + 認證標記 | 必填 |
| `@ns.expect(model, validate=True)` | 請求 Body 的 model | 有 Body 時必填 |
| `@ns.response(code, "描述", model)` | 成功與錯誤的回應文檔 | 必填 |
| `@ns.param("name", "描述")` | 路徑/查詢參數說明 | 有參數時必填 |
| `@jwt_required()` | JWT 認證 | 需認證時必填 |

### 重要：回應方式

```python
# ✅ 正確：@ns.response 標註文檔 + pkg/response 回傳
@ns.response(200, "成功", response_model)
def get(self):
    return success(data=result)

# ❌ 錯誤：marshal_with 會與 success() 的 dict 衝突
@ns.marshal_with(response_model)
def get(self):
    return success(data=result)  # 雙重包裝！
```

---

## 查詢參數 (Query Parameters)

### 方式一：`@ns.param`（推薦，用於簡單篩選）

```python
@ns.param("role", "角色篩選 (admin/customer)", _in="query", required=False)
@ns.param("page", "頁碼，預設 1", _in="query", type=int, required=False)
@ns.param("limit", "每頁筆數，預設 20", _in="query", type=int, required=False)
```

### 方式二：`reqparse`（用於需要型別轉換與驗證的場景）

```python
from flask_restx import reqparse

user_parser = reqparse.RequestParser()
user_parser.add_argument("role", type=str, required=False, help="角色篩選", location="args")
user_parser.add_argument("page", type=int, required=False, default=1, help="頁碼", location="args")
user_parser.add_argument("limit", type=int, required=False, default=20, help="每頁筆數", location="args")

@ns.expect(user_parser)
def get(self):
    args = user_parser.parse_args()
    ...
```

---

## 檔案上傳 (File Upload)

使用 `reqparse` 搭配 `location="files"`：

```python
from werkzeug.datastructures import FileStorage

upload_parser = reqparse.RequestParser()
upload_parser.add_argument(
    "file", type=FileStorage, required=True,
    help="要上傳的圖片檔案", location="files",
)

@ns.route("/upload")
class FileUpload(Resource):
    @ns.doc(description="上傳圖片檔案", security="BearerAuth")
    @ns.expect(upload_parser)
    @ns.response(201, "上傳成功")
    @ns.response(400, "檔案格式錯誤")
    @jwt_required()
    def post(self):
        """上傳檔案"""
        args = upload_parser.parse_args()
        uploaded_file = args["file"]
        # ... 儲存至 storage/upload/
```

---

## 分頁回應 Model

當 API 支援分頁時，定義統一的分頁外層 model：

```python
pagination_model = ns.model("Pagination", {
    "page": fields.Integer(description="當前頁碼", example=1),
    "limit": fields.Integer(description="每頁筆數", example=20),
    "total": fields.Integer(description="總筆數", example=100),
    "total_pages": fields.Integer(description="總頁數", example=5),
})

paginated_response_model = ns.model("PaginatedUserResponse", {
    "code": fields.Integer(description="狀態碼", example=200),
    "message": fields.String(description="訊息", example="success"),
    "data": fields.List(fields.Nested(user_model), description="用戶列表"),
    "pagination": fields.Nested(pagination_model, description="分頁資訊"),
})
```

---

## 存取 Swagger UI

- **路徑**：由 `Api(doc="/doc/")` 決定
- **訪問**：`http://localhost:5000/doc/`（開發模式直接可用）
- **無需生成指令**：Flask-RESTX 自動根據裝飾器與 model 生成 OpenAPI spec
- **JSON Spec**：`http://localhost:5000/swagger.json`
