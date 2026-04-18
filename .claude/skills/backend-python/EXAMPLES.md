# Python/Flask DDD 代碼範例

本文件包含 `backend-python` Skill 各層級的完整代碼範例。
按需讀取，無需一次全部載入。

---

## 目錄

- [1. 領域層 (Domain Layer)](#1-領域層-domain-layer)
- [2. 基礎設施層 (Infrastructure Layer)](#2-基礎設施層-infrastructure-layer)
- [3. 應用層 (Application Layer)](#3-應用層-application-layer)
- [4. 介面層 Schema 定義](#4-介面層-schema-定義)
- [5. 介面層 Handler 範例](#5-介面層-handler-範例)
- [6. 配置與 App Factory](#6-配置與-app-factory)
- [7. 異常處理與標準回應](#7-異常處理與標準回應)
- [8. 依賴注入 (router.py)](#8-依賴注入-routerpy)
- [9. 單元測試](#9-單元測試)
- [10. 專案入口與部署](#10-專案入口與部署)
- [11. Makefile](#11-makefile)
- [12. requirements.txt](#12-requirementstxt)

---

## 1. 領域層 (Domain Layer)

此層**零框架依賴**。只使用 Python 標準庫。

### Entity (dataclass)

```python
# app/domain/entity/user.py
from dataclasses import dataclass
from datetime import datetime

@dataclass
class User:
    id: int | None = None
    name: str = ""
    email: str = ""
    password_hash: str = ""
    role: str = "customer"
    created_at: datetime | None = None
    updated_at: datetime | None = None
```

### Repository Interface (ABC)

```python
# app/domain/repository/user_repository.py
from abc import ABC, abstractmethod
from app.domain.entity.user import User

class UserRepository(ABC):
    @abstractmethod
    def create(self, user: User) -> User: ...

    @abstractmethod
    def find_by_id(self, user_id: int) -> User | None: ...

    @abstractmethod
    def find_by_email(self, email: str) -> User | None: ...

    @abstractmethod
    def find_all(self, **filters) -> list[User]: ...

    @abstractmethod
    def update(self, user: User) -> User: ...

    @abstractmethod
    def delete(self, user_id: int) -> None: ...
```

---

## 2. 基礎設施層 (Infrastructure Layer)

### ORM Model (SQLAlchemy)

模型**必須**提供 `to_entity()` / `from_entity()` 映射。

```python
# app/infrastructure/persistence/models/user_model.py
from app.extensions import db

class UserModel(db.Model):
    __tablename__ = "users"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    name = db.Column(db.String(100), nullable=False)
    email = db.Column(db.String(255), unique=True, nullable=False)
    password_hash = db.Column(db.String(255), nullable=False)
    role = db.Column(db.String(20), default="customer")
    created_at = db.Column(db.DateTime, server_default=db.func.now())
    updated_at = db.Column(db.DateTime, server_default=db.func.now(), onupdate=db.func.now())

    def to_entity(self) -> "User":
        from app.domain.entity.user import User
        return User(
            id=self.id, name=self.name, email=self.email,
            password_hash=self.password_hash, role=self.role,
            created_at=self.created_at, updated_at=self.updated_at,
        )

    @staticmethod
    def from_entity(entity: "User") -> "UserModel":
        return UserModel(
            id=entity.id, name=entity.name, email=entity.email,
            password_hash=entity.password_hash, role=entity.role,
        )
```

### Repository Implementation

```python
# app/infrastructure/persistence/repositories/user_repository_impl.py
from app.extensions import db
from app.domain.entity.user import User
from app.domain.repository.user_repository import UserRepository
from app.infrastructure.persistence.models.user_model import UserModel

class SQLAlchemyUserRepository(UserRepository):
    def create(self, user: User) -> User:
        model = UserModel.from_entity(user)
        db.session.add(model)
        db.session.commit()
        return model.to_entity()

    def find_by_id(self, user_id: int) -> User | None:
        model = db.session.get(UserModel, user_id)
        return model.to_entity() if model else None

    def find_by_email(self, email: str) -> User | None:
        model = UserModel.query.filter_by(email=email).first()
        return model.to_entity() if model else None

    def find_all(self, **filters) -> list[User]:
        query = UserModel.query
        if "role" in filters:
            query = query.filter_by(role=filters["role"])
        return [m.to_entity() for m in query.all()]

    def update(self, user: User) -> User:
        model = db.session.get(UserModel, user.id)
        if model:
            model.name = user.name
            model.email = user.email
            model.role = user.role
            if user.password_hash:
                model.password_hash = user.password_hash
            db.session.commit()
            return model.to_entity()
        raise ValueError(f"User {user.id} not found")

    def delete(self, user_id: int) -> None:
        model = db.session.get(UserModel, user_id)
        if model:
            db.session.delete(model)
            db.session.commit()
```

---

## 3. 應用層 (Application Layer)

Service 透過建構子注入 Repository 介面，只操作領域實體。

```python
# app/application/service/user_service.py
from werkzeug.security import generate_password_hash
from app.domain.entity.user import User
from app.domain.repository.user_repository import UserRepository
from pkg.errors.exceptions import NotFoundError, BadRequestError

class UserService:
    def __init__(self, user_repo: UserRepository) -> None:
        self._user_repo = user_repo

    def create_user(self, name: str, email: str, password: str, role: str) -> User:
        if self._user_repo.find_by_email(email):
            raise BadRequestError(f"Email {email} already exists")
        user = User(
            name=name, email=email,
            password_hash=generate_password_hash(password), role=role,
        )
        return self._user_repo.create(user)

    def get_user_by_id(self, user_id: int) -> User:
        user = self._user_repo.find_by_id(user_id)
        if not user:
            raise NotFoundError(f"User {user_id} not found")
        return user

    def get_all_users(self, **filters) -> list[User]:
        return self._user_repo.find_all(**filters)

    def delete_user(self, user_id: int) -> None:
        user = self._user_repo.find_by_id(user_id)
        if not user:
            raise NotFoundError(f"User {user_id} not found")
        self._user_repo.delete(user_id)
```

---

## 4. 介面層 Schema 定義

Schema **定義在 `schema/` 目錄**，按資源分檔，由 Handler import 使用。
禁止在 Handler 內部 inline 定義 api.model。

```python
# app/interfaces/api/schema/user_schema.py
from flask_restx import Namespace, fields

def register_user_models(ns: Namespace) -> dict:
    """註冊 User 相關的所有 api.model，回傳 model dict。"""

    create_user = ns.model("CreateUserRequest", {
        "name": fields.String(required=True, description="用戶名稱", example="王小明"),
        "email": fields.String(required=True, description="電子郵件", example="user@example.com"),
        "password": fields.String(required=True, description="密碼 (最少 6 字元)", example="Pass1234"),
        "role": fields.String(required=True, description="角色", example="customer", enum=["admin", "customer"]),
    })

    user = ns.model("User", {
        "id": fields.Integer(description="用戶 ID", example=1),
        "name": fields.String(description="用戶名稱", example="王小明"),
        "email": fields.String(description="電子郵件", example="user@example.com"),
        "role": fields.String(description="角色", example="customer"),
        "created_at": fields.DateTime(description="建立時間"),
        "updated_at": fields.DateTime(description="更新時間"),
    })

    response = ns.model("UserResponse", {
        "code": fields.Integer(description="狀態碼", example=200),
        "message": fields.String(description="訊息", example="success"),
        "data": fields.Nested(user, description="用戶資料"),
    })

    response_list = ns.model("UserListResponse", {
        "code": fields.Integer(description="狀態碼", example=200),
        "message": fields.String(description="訊息", example="success"),
        "data": fields.List(fields.Nested(user), description="用戶列表"),
    })

    error = ns.model("ErrorResponse", {
        "code": fields.Integer(description="狀態碼", example=400),
        "message": fields.String(description="錯誤訊息", example="Bad request"),
        "data": fields.Raw(description="額外資訊", default=None),
    })

    return {
        "create_user": create_user,
        "user": user,
        "response": response,
        "response_list": response_list,
        "error": error,
    }
```

---

## 5. 介面層 Handler 範例

Handler 使用 `@ns.response` 標註 Swagger 文檔，回傳使用 `pkg/response` 統一格式。
**不使用 `@ns.marshal_with`**（避免與手動回應格式雙重衝突）。

```python
# app/interfaces/api/handler/user_handler.py
from flask import request
from flask_restx import Namespace, Resource
from flask_jwt_extended import jwt_required
from app.application.service.user_service import UserService
from app.interfaces.api.schema.user_schema import register_user_models
from pkg.response.api_response import success, created

def create_user_namespace(user_service: UserService) -> Namespace:
    ns = Namespace("users", description="用戶管理")
    models = register_user_models(ns)

    @ns.route("/")
    class UserList(Resource):
        @ns.doc(description="取得所有用戶，支援角色篩選", security="BearerAuth")
        @ns.param("role", "角色篩選 (admin/customer)", _in="query", required=False)
        @ns.response(200, "成功", models["response_list"])
        @ns.response(500, "伺服器錯誤", models["error"])
        @jwt_required()
        def get(self):
            """取得用戶列表"""
            role = request.args.get("role")
            filters = {"role": role} if role else {}
            users = user_service.get_all_users(**filters)
            return success(data=[_serialize(u) for u in users])

        @ns.doc(description="建立新的系統用戶（管理員操作）", security="BearerAuth")
        @ns.expect(models["create_user"], validate=True)
        @ns.response(201, "建立成功", models["response"])
        @ns.response(400, "請求錯誤", models["error"])
        @jwt_required()
        def post(self):
            """建立用戶"""
            data = request.json
            user = user_service.create_user(
                name=data["name"], email=data["email"],
                password=data["password"], role=data["role"],
            )
            return created(data=_serialize(user))

    @ns.route("/<int:user_id>")
    @ns.param("user_id", "用戶 ID")
    class UserDetail(Resource):
        @ns.doc(description="依 ID 取得用戶詳細資訊", security="BearerAuth")
        @ns.response(200, "成功", models["response"])
        @ns.response(404, "用戶不存在", models["error"])
        @jwt_required()
        def get(self, user_id: int):
            """取得單一用戶"""
            user = user_service.get_user_by_id(user_id)
            return success(data=_serialize(user))

        @ns.doc(description="刪除用戶", security="BearerAuth")
        @ns.response(200, "刪除成功")
        @ns.response(404, "用戶不存在", models["error"])
        @jwt_required()
        def delete(self, user_id: int):
            """刪除用戶"""
            user_service.delete_user(user_id)
            return success(message="deleted")

    def _serialize(user) -> dict:
        return {
            "id": user.id,
            "name": user.name,
            "email": user.email,
            "role": user.role,
            "created_at": user.created_at.isoformat() if user.created_at else None,
            "updated_at": user.updated_at.isoformat() if user.updated_at else None,
        }

    return ns
```

---

## 6. 配置與 App Factory

### 多環境配置 (settings.py)

```python
# app/infrastructure/config/settings.py
import os
from datetime import timedelta

class BaseConfig:
    SECRET_KEY = os.environ.get("SECRET_KEY", "dev-secret-key")
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    JWT_SECRET_KEY = os.environ.get("JWT_SECRET_KEY", "jwt-dev-secret")
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(hours=1)

class DevConfig(BaseConfig):
    DEBUG = True
    SQLALCHEMY_DATABASE_URI = os.environ.get("DATABASE_URL", "sqlite:///dev.db")

class UATConfig(BaseConfig):
    DEBUG = False
    SQLALCHEMY_DATABASE_URI = os.environ.get("DATABASE_URL")

class ProdConfig(BaseConfig):
    DEBUG = False
    SQLALCHEMY_DATABASE_URI = os.environ.get("DATABASE_URL")

config_map = {
    "dev": DevConfig,
    "uat": UATConfig,
    "prod": ProdConfig,
}
```

### 擴展初始化 (extensions.py)

```python
# app/extensions.py
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from flask_jwt_extended import JWTManager
from flask_cors import CORS

db = SQLAlchemy()
migrate = Migrate()
jwt = JWTManager()
cors = CORS()
```

### App Factory (\_\_init\_\_.py)

```python
# app/__init__.py
import os
from flask import Flask
from app.extensions import db, migrate, jwt, cors
from app.infrastructure.config.settings import config_map

def create_app(config_name: str | None = None) -> Flask:
    if config_name is None:
        config_name = os.environ.get("APP_ENV", "dev")

    app = Flask(__name__)
    app.config.from_object(config_map[config_name])

    # 初始化擴展
    db.init_app(app)
    migrate.init_app(app, db)
    jwt.init_app(app)
    cors.init_app(app)

    # 註冊路由與 Namespace
    from app.interfaces.api.router import register_routes
    register_routes(app)

    # 全局異常處理
    from pkg.errors.exceptions import AppError
    from pkg.response.api_response import error

    @app.errorhandler(AppError)
    def handle_app_error(e):
        return error(message=e.message, code=e.code)

    return app
```

---

## 7. 異常處理與標準回應

### 自定義異常 (exceptions.py)

```python
# pkg/errors/exceptions.py
class AppError(Exception):
    """應用程式異常基類"""
    def __init__(self, message: str, code: int = 500):
        self.message = message
        self.code = code
        super().__init__(self.message)

class BadRequestError(AppError):
    def __init__(self, message: str = "Bad request"):
        super().__init__(message, code=400)

class UnauthorizedError(AppError):
    def __init__(self, message: str = "Unauthorized"):
        super().__init__(message, code=401)

class ForbiddenError(AppError):
    def __init__(self, message: str = "Forbidden"):
        super().__init__(message, code=403)

class NotFoundError(AppError):
    def __init__(self, message: str = "Resource not found"):
        super().__init__(message, code=404)
```

### 標準回應 (api_response.py)

```python
# pkg/response/api_response.py
from flask import jsonify

def success(data=None, message: str = "success", code: int = 200):
    return jsonify({"code": code, "message": message, "data": data}), code

def error(message: str = "error", code: int = 500, data=None):
    return jsonify({"code": code, "message": message, "data": data}), code

def created(data=None, message: str = "created"):
    return success(data=data, message=message, code=201)
```

---

## 8. 依賴注入 (router.py)

在此處手動組裝 Repository → Service → Handler 依賴鏈。

```python
# app/interfaces/api/router.py
from flask import Flask
from flask_restx import Api
from app.infrastructure.persistence.repositories.user_repository_impl import SQLAlchemyUserRepository
from app.application.service.user_service import UserService
from app.interfaces.api.handler.user_handler import create_user_namespace

def register_routes(app: Flask) -> None:
    api = Api(
        app,
        title="My API",
        version="1.0",
        description="DDD Flask Backend API",
        doc="/doc/",
        authorizations={
            "BearerAuth": {
                "type": "apiKey",
                "in": "header",
                "name": "Authorization",
                "description": "輸入格式: Bearer <JWT token>",
            }
        },
    )

    # ── 依賴注入組裝 ──
    user_repo = SQLAlchemyUserRepository()
    user_service = UserService(user_repo=user_repo)

    # ── 註冊 Namespace ──
    api.add_namespace(create_user_namespace(user_service), path="/admin/users")
```

---

## 9. 單元測試

測試檔與 Service 同目錄，使用 pytest + MagicMock。

```python
# app/application/service/test_user_service.py
import pytest
from unittest.mock import MagicMock
from app.application.service.user_service import UserService
from app.domain.entity.user import User
from pkg.errors.exceptions import NotFoundError, BadRequestError

@pytest.fixture
def mock_user_repo():
    return MagicMock()

@pytest.fixture
def user_service(mock_user_repo):
    return UserService(user_repo=mock_user_repo)

class TestCreateUser:
    def test_success(self, user_service, mock_user_repo):
        mock_user_repo.find_by_email.return_value = None
        mock_user_repo.create.return_value = User(id=1, name="王小明", email="test@example.com")

        result = user_service.create_user("王小明", "test@example.com", "Pass1234", "customer")

        assert result.id == 1
        assert result.name == "王小明"
        mock_user_repo.create.assert_called_once()

    def test_duplicate_email_raises_bad_request(self, user_service, mock_user_repo):
        mock_user_repo.find_by_email.return_value = User(id=1, email="test@example.com")

        with pytest.raises(BadRequestError):
            user_service.create_user("王小明", "test@example.com", "Pass1234", "customer")

class TestGetUserById:
    def test_success(self, user_service, mock_user_repo):
        mock_user_repo.find_by_id.return_value = User(id=1, name="王小明")

        result = user_service.get_user_by_id(1)

        assert result.name == "王小明"

    def test_not_found_raises_error(self, user_service, mock_user_repo):
        mock_user_repo.find_by_id.return_value = None

        with pytest.raises(NotFoundError):
            user_service.get_user_by_id(999)

class TestDeleteUser:
    def test_success(self, user_service, mock_user_repo):
        mock_user_repo.find_by_id.return_value = User(id=1, name="王小明")

        user_service.delete_user(1)

        mock_user_repo.delete.assert_called_once_with(1)

    def test_not_found_raises_error(self, user_service, mock_user_repo):
        mock_user_repo.find_by_id.return_value = None

        with pytest.raises(NotFoundError):
            user_service.delete_user(999)
```

### 整合測試 Fixtures (conftest.py)

```python
# tests/conftest.py
import pytest
from app import create_app
from app.extensions import db as _db

@pytest.fixture(scope="session")
def app():
    app = create_app(config_name="dev")
    app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///:memory:"
    app.config["TESTING"] = True
    with app.app_context():
        _db.create_all()
        yield app
        _db.drop_all()

@pytest.fixture
def client(app):
    return app.test_client()

@pytest.fixture
def db_session(app):
    with app.app_context():
        yield _db.session
        _db.session.rollback()
```

---

## 10. 專案入口與部署

### WSGI 入口 (wsgi.py)

```python
# wsgi.py
from app import create_app

app = create_app()
```

### 環境變數 (.env)

統一使用單一 `.env` 檔案，包含 Flask CLI 設定與應用程式變數。

```bash
# .env (git ignored)
FLASK_APP=wsgi.py
APP_ENV=dev
SECRET_KEY=your-secret-key
JWT_SECRET_KEY=your-jwt-secret
DATABASE_URL=sqlite:///dev.db
```

---

## 11. Makefile

```makefile
.PHONY: run dev test migrate migrate-create seed create-admin lint format clean

PYTHON = python3
FLASK  = flask
PYTEST = pytest

# 生產模式 (gunicorn)
run:
	gunicorn -w 4 -b 0.0.0.0:5000 wsgi:app

# 開發模式 (debug + 熱加載)
dev:
	$(FLASK) run --debug --port 5000

# 單元測試
test:
	$(PYTEST) -v --tb=short

# 資料庫遷移 (執行)
migrate:
	$(FLASK) db upgrade

# 資料庫遷移 (建立腳本)
migrate-create:
	$(FLASK) db migrate -m "$(msg)"

# 初始資料填充
seed:
	$(FLASK) seed

# 建立管理員
create-admin:
	$(FLASK) create-admin

# 代碼檢查
lint:
	flake8 app/ pkg/
	mypy app/ pkg/

# 代碼格式化
format:
	black app/ pkg/ tests/
	isort app/ pkg/ tests/

# 清理
clean:
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true
	rm -rf .pytest_cache/ .mypy_cache/ htmlcov/ .coverage
```

---

## 12. requirements.txt

```txt
# requirements.txt
flask>=3.0
flask-restx>=1.3
flask-sqlalchemy>=3.1
flask-migrate>=4.0
flask-jwt-extended>=4.6
flask-cors>=4.0
python-dotenv>=1.0
structlog>=24.0
gunicorn>=22.0
pytest>=8.0
black>=24.0
isort>=5.13
flake8>=7.0
mypy>=1.8
```
