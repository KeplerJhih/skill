# Draw.io XML 進階模式

## 完整 XML 結構

```xml
<mxGraphModel dx="1422" dy="762" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1169" pageHeight="827" math="0" shadow="0">
  <root>
    <mxCell id="0"/>
    <mxCell id="1" parent="0"/>
    <!-- 所有節點和連線放在這裡，parent="1" -->
  </root>
</mxGraphModel>
```

**重要**：`id="0"` 是根節點，`id="1"` 是預設圖層，所有使用者節點的 parent 應為 `"1"` 或某個容器 id。

---

## 多頁面 .drawio 檔案

```xml
<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="draw.io">
  <diagram id="page1" name="Overview">
    <mxGraphModel>
      <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>
        <!-- Page 1 內容 -->
      </root>
    </mxGraphModel>
  </diagram>
  <diagram id="page2" name="Detail View">
    <mxGraphModel>
      <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>
        <!-- Page 2 內容 -->
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
```

操作多頁面時，使用 Python `xml.etree.ElementTree` 解析，僅修改目標 `<diagram>` 節點。

---

## 連線出入點 (Exit/Entry Points) 詳解

```
exitX/entryX: 0=左, 0.5=中, 1=右
exitY/entryY: 0=上, 0.5=中, 1=下
```

### 常用連線方向

| 方向 | exitX | exitY | entryX | entryY |
|------|-------|-------|--------|--------|
| 上→下 | 0.5 | 1 | 0.5 | 0 |
| 左→右 | 1 | 0.5 | 0 | 0.5 |
| 右→左 | 0 | 0.5 | 1 | 0.5 |
| 下→上 | 0.5 | 0 | 0.5 | 1 |

### 分散多條連線（避免重疊的關鍵技巧）

當一個節點有多條向下的連線時，分散出口點：

```xml
<!-- 3 條向下連線，分散 exitX -->
<mxCell style="...exitX=0.25;exitY=1;entryX=0.5;entryY=0;..." edge="1" source="A" target="B1"/>
<mxCell style="...exitX=0.5;exitY=1;entryX=0.5;entryY=0;..." edge="1" source="A" target="B2"/>
<mxCell style="...exitX=0.75;exitY=1;entryX=0.5;entryY=0;..." edge="1" source="A" target="B3"/>
```

當一個節點有多條水平連線時：

```xml
<!-- 分散 exitY -->
<mxCell style="...exitX=1;exitY=0.25;entryX=0;entryY=0.5;..." edge="1" source="A" target="C1"/>
<mxCell style="...exitX=1;exitY=0.5;entryX=0;entryY=0.5;..." edge="1" source="A" target="C2"/>
<mxCell style="...exitX=1;exitY=0.75;entryX=0;entryY=0.5;..." edge="1" source="A" target="C3"/>
```

---

## Waypoints 進階用法

### 避免兩條平行連線重疊

```xml
<!-- 連線 1：直接路由 -->
<mxCell style="edgeStyle=orthogonalEdgeStyle;rounded=1;" edge="1" source="A" target="C">
  <mxGeometry relative="1" as="geometry"/>
</mxCell>

<!-- 連線 2：加 waypoint 繞道，避免與連線 1 重疊 -->
<mxCell style="edgeStyle=orthogonalEdgeStyle;rounded=1;" edge="1" source="B" target="C">
  <mxGeometry relative="1" as="geometry">
    <Array as="points">
      <mxPoint x="400" y="300"/>
    </Array>
  </mxGeometry>
</mxCell>
```

### L 形路由

```xml
<mxCell style="edgeStyle=orthogonalEdgeStyle;rounded=1;exitX=1;exitY=0.5;entryX=0.5;entryY=0;" edge="1" source="A" target="B">
  <mxGeometry relative="1" as="geometry">
    <Array as="points">
      <mxPoint x="350" y="150"/>
    </Array>
  </mxGeometry>
</mxCell>
```

---

## 常用 Style 屬性速查

### 形狀樣式

| 屬性 | 值 | 說明 |
|------|------|------|
| `rounded` | `0` / `1` | 圓角 |
| `whiteSpace` | `wrap` | 文字自動換行 |
| `fillColor` | `#RRGGBB` | 填色 |
| `strokeColor` | `#RRGGBB` | 邊框色 |
| `fontColor` | `#RRGGBB` | 字色 |
| `fontSize` | `12` | 字體大小 |
| `fontStyle` | `0`/`1`/`2`/`3` | 0=正常, 1=粗, 2=斜, 3=粗斜 |
| `shadow` | `0` / `1` | 陰影 |
| `dashed` | `0` / `1` | 虛線邊框 |
| `opacity` | `0-100` | 透明度 |
| `container` | `1` | 標記為容器 |
| `collapsible` | `0` / `1` | 可折疊 |
| `pointerEvents` | `0` / `1` | 0=不攔截子元素事件 |

### 連線樣式

| 屬性 | 值 | 說明 |
|------|------|------|
| `edgeStyle` | `orthogonalEdgeStyle` | 正交路由（推薦） |
| `edgeStyle` | `entityRelationEdgeStyle` | ER 圖連線 |
| `curved` | `1` | 曲線 |
| `rounded` | `1` | 圓角轉折 |
| `strokeWidth` | `2` | 線寬 |
| `endArrow` | `classic`/`block`/`open`/`none` | 箭頭樣式 |
| `startArrow` | 同上 | 起始箭頭 |
| `endFill` | `0` / `1` | 箭頭填色 |
| `startSize` | `6` | 起始箭頭大小 |
| `endSize` | `6` | 結束箭頭大小 |

---

## 常用形狀

### 圓角矩形（一般服務節點）

```
rounded=1;whiteSpace=wrap;
```

### 圓柱體（資料庫）

```
shape=cylinder3;whiteSpace=wrap;boundedLbl=1;backgroundOutline=1;size=15;
```

### 雲形（外部服務/Internet）

```
ellipse;shape=cloud;whiteSpace=wrap;
```

### 六角形（微服務/API）

```
shape=hexagon;perimeter=hexagonPerimeter2;whiteSpace=wrap;size=0.25;
```

### 菱形（決策點）

```
rhombus;whiteSpace=wrap;
```

### 平行四邊形（輸入/輸出）

```
shape=parallelogram;perimeter=parallelogramPerimeter;whiteSpace=wrap;size=0.1;
```

### 人形（使用者）

```
shape=mxgraph.basic.person;whiteSpace=wrap;
```

### 文件形狀

```
shape=document;whiteSpace=wrap;boundedLbl=1;backgroundOutline=1;size=0.27;
```

---

## 圖標與 Icon 套疊

在節點 value 中嵌入 icon（使用 label 形式）：

```xml
<mxCell value="&lt;b&gt;API Gateway&lt;/b&gt;" style="shape=image;verticalLabelPosition=bottom;labelBackgroundColor=default;verticalAlign=top;aspect=fixed;imageAspect=0;image=data:image/svg+xml,..." vertex="1" parent="1">
  <mxGeometry x="100" y="100" width="48" height="48" as="geometry"/>
</mxCell>
```

**建議**：優先使用純幾何形狀 + 文字標籤，比 icon 更清晰、更容易維護。

---

## 虛線連線（可選/非同步通訊）

```xml
<mxCell style="edgeStyle=orthogonalEdgeStyle;rounded=1;dashed=1;dashPattern=8 4;strokeColor=#999999;" edge="1" source="A" target="B" parent="1">
  <mxGeometry relative="1" as="geometry"/>
</mxCell>
```

---

## 連線標籤

```xml
<mxCell id="edge1" value="HTTP/REST" style="edgeStyle=orthogonalEdgeStyle;rounded=1;" edge="1" source="A" target="B" parent="1">
  <mxGeometry relative="1" as="geometry"/>
</mxCell>
```

帶偏移的標籤：

```xml
<mxCell id="edge1" value="gRPC" style="edgeStyle=orthogonalEdgeStyle;rounded=1;" edge="1" source="A" target="B" parent="1">
  <mxGeometry x="-0.3" relative="1" as="geometry">
    <mxPoint as="offset" x="0" y="-10"/>
  </mxGeometry>
</mxCell>
```

---

## 佈局計算公式

### 水平居中排列 N 個節點

```
nodeWidth = 160
gap = 200 (含節點寬度的間距) 或 40 (純間距)
totalWidth = N * nodeWidth + (N-1) * 40
startX = (canvasWidth - totalWidth) / 2
node[i].x = startX + i * (nodeWidth + 40)
```

### 垂直分層

```
layerHeight = 120 (層間距)
layer[i].y = startY + i * layerHeight
```

### Swimlane 尺寸計算

```
containerPadding = 20
titleHeight = 30 (startSize)
containerWidth = max(childrenTotalWidth + 2 * containerPadding, 300)
containerHeight = titleHeight + childrenMaxHeight + 2 * containerPadding
```
