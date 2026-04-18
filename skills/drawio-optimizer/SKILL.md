---
name: drawio-optimizer
description: >-
  Draw.io 圖表最佳化技能。當使用者提到「draw.io」、「drawio」、「架構圖」、「流程圖」、
  「系統圖」、「繪製圖表」、「畫圖」、「圖表優化」、「排版優化」、「連線重疊」、
  「diagram」、「.drawio」、「mxGraph」、「XML 圖表」、「Mermaid 圖表」、
  「畫一張」、「生成圖表」、「更新圖表」、「優化圖表」或任何與 draw.io 圖表
  建立、優化、預覽相關的需求時觸發此技能。
version: 0.1.0
---

# Draw.io Optimizer Skill

透過 Draw.io MCP 工具建立、優化與管理高品質的 draw.io 圖表。核心目標：**佈局清晰、連線不重疊、風格統一、語義化配色**。

---

## 可用工具

| 工具 | 用途 | 適用場景 |
|------|------|---------|
| `mcp__drawio__open_drawio_xml` | 以 XML 建立/編輯圖表 | 精細控制佈局、複雜架構圖、需要避免連線重疊 |
| `mcp__drawio__open_drawio_mermaid` | 以 Mermaid 語法建立圖表 | 快速原型、簡單流程圖、序列圖 |
| `mcp__drawio__open_drawio_csv` | 以 CSV 建立圖表 | 組織架構圖、大量同質節點 |

**選擇策略**：需要精確控制佈局與連線時，使用 XML；快速草圖用 Mermaid；表格式資料用 CSV。

---

## 核心原則：連線不重疊 (Edge Non-Overlap)

這是本 skill 最重要的原則。所有圖表必須確保連線清晰、不交叉、不重疊。

### 佈局策略

1. **充足間距**：節點對齊 10px 網格，水平間距 ≥200px，垂直間距 ≥120px
2. **分層排列**：同層級節點水平排列，不同層級垂直排列，形成清晰的拓撲結構
3. **連線出入點分散**：使用 `exitX/exitY/entryX/entryY`（值 0-1）控制連線接點，將多條連線分散到節點不同邊
4. **正交路由**：所有連線使用 `edgeStyle=orthogonalEdgeStyle;rounded=1;` 做圓角直角連線
5. **明確 waypoints**：當自動路由仍會重疊時，加入明確的 `<mxPoint>` waypoints 引導路徑
6. **箭頭間距**：連線末段直線至少 20px，避免箭頭與轉角重疊
7. **外部元件與容器間距**：外部節點（如 Internet、Admin）與大容器（如 VPC）之間至少留 **100px** 垂直間距，確保穿越容器邊界的邊線標籤有足夠空間，不會與容器標題重疊
8. **外部元件水平對齊目標**：外部元件應水平對齊其主要連線目標的正上方。例如 Admin 放在 Hotfix VM 正上方、Internet 放在 GKE Ingress 正上方，使垂直連線自然分散，無需額外 waypoints

### 邊線標籤防重疊

邊線穿越 swimlane 容器邊界時，標籤預設會落在容器標題上。**必須**使用 `mxGeometry` 的 `x`（相對位置 -1~1）和 `offset`（像素偏移）主動定位標籤：

```xml
<mxGeometry x="-0.6" relative="1" as="geometry">
  <mxPoint as="offset" x="45" y="0"/>
</mxGeometry>
```

- `x="-0.6"`：標籤放在邊線起點端 60% 處（負值靠近 source，正值靠近 target）
- `offset x="45"`：再向右偏移 45px，避開邊線本身

**經驗法則**：
- 穿越容器頂部進入的邊線：`x="-0.5"` 至 `x="-0.7"` + `offset x=40~50`，將標籤推到容器外的空白區
- 兩條平行邊線的標籤：分別用正負 offset x 值左右推開（如 `-35` 和 `+35`）

### 長距離回程邊線

**禁止**將長距離回程邊線（如出站流量 NAT → Internet）路由回同一個節點。長距離繞線會：
- 橫跨整個圖表，覆蓋其他元件
- 在 cloud 等不規則形狀上產生歪斜箭頭
- 邊線標籤難以定位

**正確做法**：使用**獨立的同名節點**分離入站與出站。例如左側放 Internet (Ingress)，右側放 Internet (Egress)，各自短距連線，清晰區分流向。可在節點下方加 `text` 標籤（如 "Ingress" / "Egress"）輔助辨識。

### 連線粒度選擇

同一存取模式的多個元件，**從容器層級（如 subnet）拉線**而非從每個子元件個別拉線：

```
Bad:  web-pods → DB, api-pods → DB, hotfix-vm → DB, script-vm → DB  (4 條線)
Good: subnet-gke → DB, subnet-vm → DB  (2 條線)
```

**判斷標準**：若容器內所有元件共享同一存取權限，用 1 條容器級連線取代 N 條元件級連線。只有當不同元件有不同存取方式時，才使用元件級連線。

### 節點排列規則

```
節點數 ≤ 3：單行水平排列
節點數 4-6：兩行，上 3 下 3 或依邏輯分組
節點數 > 6：使用 swimlane 容器分組
```

---

## 容器與分組

| 容器類型 | 樣式 | 適用場景 |
|---------|------|---------|
| Swimlane | `swimlane;startSize=30;` | 有標題的分層容器（如「Gateway 層」）、容器本身需要連線 |
| Group | `group;` + `pointerEvents=0` | 無邊框邏輯分組、不需要連線到容器本身 |
| Container | 任意形狀 + `container=1` | 自訂容器，加 `pointerEvents=0` 除非容器本身需要連線 |

**父子關係**：子節點設定 `parent="containerId"`，座標為容器內的相對座標。

---

## 配色規範

配色方案按需從 reference 載入。繪圖前請先讀取 `references/color-schemes.md` 取得完整配色表。

**核心原則**：同層級同色系，不同層級不同色系，一眼辨識架構分層。

**可用配色方案**：
- **通用架構配色** — 預設，適用於非特定雲端平台的圖表
- **GCP 架構圖配色** — 繪製 GCP 架構時使用，覆蓋通用配色
- **AWS 架構圖配色** — 繪製 AWS 架構時使用，覆蓋通用配色

---

## 工作流程

### 情境 A：新建圖表

1. **需求確認**：釐清圖表類型（架構圖、流程圖、序列圖、ER 圖等）
2. **元件規劃**：列出所有節點、分組、連線關係
3. **佈局設計**：規劃分層結構與間距，確保連線不重疊
4. **XML 建構**：組裝 `mxGraphModel` XML，套用配色與樣式
5. **預覽驗證**：使用 `mcp__drawio__open_drawio_xml` 開啟預覽
6. **迭代修正**：根據用戶回饋調整佈局、配色或連線

### 情境 B：優化現有圖表

1. **讀取分析**：讀取 `.drawio` 檔案，解析節點、連線、樣式
2. **問題診斷**：檢查以下問題清單
3. **產出改善方案**：向用戶展示發現的問題與修正計畫
4. **重新生成**：建構優化後的 XML 並預覽
5. **寫入檔案**：確認後寫入原檔或新檔

### 優化檢查清單

- [ ] 節點間距是否充足（水平 ≥200px，垂直 ≥120px）
- [ ] 節點是否對齊 10px 網格
- [ ] 連線是否使用 orthogonal 路由
- [ ] 是否有連線重疊或交叉
- [ ] 同層級節點是否使用統一配色
- [ ] 容器是否正確使用 swimlane / group
- [ ] 文字是否清晰（純文字 + fontSize/fontStyle，不用 HTML）
- [ ] 箭頭末段直線是否 ≥ 20px
- [ ] 連線出入點是否合理分散

---

## XML 模板速查

### 基礎節點

```xml
<mxCell id="node1" value="Service Name" style="rounded=1;whiteSpace=wrap;fillColor=#FFF3E0;strokeColor=#FB8C00;fontColor=#E65100;fontSize=13;fontStyle=1;" vertex="1" parent="1">
  <mxGeometry x="100" y="100" width="160" height="60" as="geometry"/>
</mxCell>
```

### 正交連線（不重疊關鍵）

```xml
<mxCell id="edge1" style="edgeStyle=orthogonalEdgeStyle;rounded=1;strokeColor=#666666;exitX=0.5;exitY=1;exitDx=0;exitDy=0;entryX=0.5;entryY=0;entryDx=0;entryDy=0;" edge="1" source="node1" target="node2" parent="1">
  <mxGeometry relative="1" as="geometry"/>
</mxCell>
```

### 帶 Waypoints 的連線（避免重疊）

```xml
<mxCell id="edge2" style="edgeStyle=orthogonalEdgeStyle;rounded=1;strokeColor=#666666;" edge="1" source="node1" target="node3" parent="1">
  <mxGeometry relative="1" as="geometry">
    <Array as="points">
      <mxPoint x="300" y="250"/>
    </Array>
  </mxGeometry>
</mxCell>
```

### Swimlane 容器

```xml
<mxCell id="layer1" value="Service Layer" style="swimlane;startSize=30;fillColor=#FFF3E0;strokeColor=#FB8C00;fontColor=#E65100;fontSize=14;fontStyle=1;rounded=1;" vertex="1" parent="1">
  <mxGeometry x="50" y="50" width="500" height="200" as="geometry"/>
</mxCell>
```

---

## 圖表存放位置

所有 `.drawio` 檔案存放在：

```
<project-root>/devops/draw.io/
```

---

## 重要規則

1. **連線不重疊**：這是最高優先級，寧可增大間距也不允許連線交叉
2. **XML 合法性**：禁止在 XML 註解中使用雙連字號 (`--`)，會導致解析錯誤
3. **配色語義化**：不同層級必須使用不同色系
4. **先分析後動手**：對佈局有疑問時展示選項讓用戶選擇
5. **預覽確認制**：生成圖表後必須先預覽，用戶確認後才寫入檔案
6. **不破壞現有內容**：更新圖表時僅修改目標頁面，不影響其他頁面
7. **ID 唯一性**：所有 mxCell 的 id 必須唯一，建議使用語義化命名（如 `svc-api`、`db-main`）

---

## 參考資源

### Reference Files

詳細 XML 模式與進階技巧：
- **`references/xml-advanced.md`** — 進階 XML 模式：多頁面、自訂形狀、圖標、複雜路由
- **`references/diagram-types.md`** — 各類圖表（架構圖、流程圖、序列圖、ER 圖）的最佳實踐與範本
- **`references/color-schemes.md`** — 配色規範：通用、GCP、AWS 架構圖配色方案（繪圖前按需載入）
