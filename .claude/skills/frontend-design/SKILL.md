---
name: frontend-design
description: Create high-quality, unique, production-grade frontend interfaces. Use this skill when the user asks to build web components, pages, artifacts, posters, or applications (e.g., websites, landing pages, dashboards, React/Vue components, HTML/CSS layouts, or styling any web UI). Generates creative, polished code and UI designs that avoid generic AI aesthetics.
color: purple
---

此技能指引創建獨特、生產級的前端介面，避免通用的「AI 廢料 (AI slop)」美學。實作真實運作的程式碼，並對美學細節與創意選擇給予極致的關注。

用戶提供前端需求：要建立的元件、頁面、應用程式或介面。他們可能包含關於目的、受眾或技術限制的背景資訊。

## 設計思維 (Design Thinking)

在編寫程式碼之前，先理解背景並致力於一個 **大膽的** 美學方向：
- **目的 (Purpose)**：此介面解決什麼問題？誰會使用它？
- **基調 (Tone)**：選擇一個極端風格：極度簡約 (brutally minimal)、極繁主義的混亂 (maximalist chaos)、復古未來主義 (retro-futuristic)、有機/自然 (organic/natural)、奢華/精緻 (luxury/refined)、俏皮/玩具般 (playful/toy-like)、編輯/雜誌風 (editorial/magazine)、粗獷主義/原始 (brutalist/raw)、裝飾藝術/幾何 (art deco/geometric)、柔和/粉彩 (soft/pastel)、工業/實用 (industrial/utilitarian) 等等。有非常多種風格可供選擇。以此為靈感，但設計出忠於該美學方向的作品。
- **限制 (Constraints)**：技術需求（框架、效能、無障礙性）。
- **差異化 (Differentiation)**：什麼讓這個設計 **令人難忘**？人們會記住的唯一特點是什麼？

**關鍵 (CRITICAL)**：選擇一個清晰的概念方向並精確執行。大膽的極繁主義和精緻的極簡主義都行得通——關鍵在於 **意圖性 (intentionality)**，而非強度。

接著實作可運作的程式碼 (HTML/CSS/JS, React, Vue 等)，必須是：
- 生產級且功能正常的
- 視覺上引人注目且令人難忘的
- 具有清晰美學觀點的連貫性
- 在每個細節上都經過精心修飾的

## 前端美學指南 (Frontend Aesthetics Guidelines)

專注於：
- **排版 (Typography)**：選擇美麗、獨特且有趣的字體。避免使用像 Arial 和 Inter 這樣的通用字體；改為選擇能提升前端美感的獨特選項；使用意想不到、充滿個性的字體選擇。將獨特的展示字體 (display font) 與精緻的內文字體 (body font) 搭配使用。
- **色彩與主題 (Color & Theme)**：致力於連貫的美學。使用 CSS 變數保持一致性。帶有鮮明強調色的主色調比膽怯、平均分佈的調色盤效果更好。
- **動態 (Motion)**：使用動畫來呈現效果和微互動。HTML 優先使用純 CSS 解決方案。React 可用時使用 Motion 函式庫。專注於高影響力的時刻：一個精心編排、帶有交錯揭示效果 (animation-delay) 的頁面載入，比分散的微互動更能帶來驚喜。使用滾動觸發和懸停狀態來創造驚喜。
- **空間構成 (Spatial Composition)**：意想不到的佈局。不對稱。重疊。對角線流動。打破網格的元素。大量的留白 **或** 受控的密度。
- **背景與視覺細節 (Backgrounds & Visual Details)**：創造氛圍和深度，而不是預設使用純色。加入符合整體美學的情境效果和紋理。應用創意形式，如漸層網格 (gradient meshes)、噪點紋理、幾何圖案、分層透明度、戲劇性的陰影、裝飾性邊框、自定義游標和顆粒覆蓋層。
- **組件拆分 (Component Splitting)**：將介面解構為模組化、可重用的單元。避免「巨型組件」，採用原子化設計 (Atomic Design) 思維。將佈局 (Layout)、邏輯 (Logic) 與展示 (Presentation) 分離。確保每個拆分出的組件都能獨立運作且維持設計系統的一致性，這不僅提升程式碼的可維護性，更能確保視覺語言在整個應用中的統一與協調。

**絕對不要 (NEVER)** 使用通用的 AI 生成美學，例如過度使用的字體家族 (Inter, Roboto, Arial, 系統字體)、老套的配色方案（特別是白色背景上的紫色漸層）、可預測的佈局和元件模式，以及缺乏特定情境特徵的千篇一律設計。

進行創意詮釋，做出讓人感覺是為該情境 **真正設計** 的意想不到的選擇。沒有設計應該是相同的。在明亮和黑暗主題、不同字體、不同美學之間變化。**絕對不要** 在不同生成結果中收斂於相同的選擇（例如 Space Grotesk）。

**重要 (IMPORTANT)**：讓實作的複雜度與美學願景相匹配。極繁主義設計需要精細的程式碼、大量的動畫和效果。極簡主義或精緻的設計需要克制、精確，以及對間距、排版和細微細節的仔細關注。優雅來自於對願景的良好執行。

請記住：Claude 有能力創作出非凡的創意作品。不要保留，展現當跳出框架思考並完全致力於獨特願景時，真正能創造出什麼。
