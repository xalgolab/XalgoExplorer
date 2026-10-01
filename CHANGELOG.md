# Changelog

## v0.2.0-candidate - 2026-10-01

Testing prerelease: [release notes and validation limits](docs/releases/v0.2.0-candidate.md). Ad-hoc signed; not Developer ID notarized.

### 简体中文

- 原生界面重构：标准 AppKit 标题栏、系统按钮与菜单、NSSearchField、可调整的三工作区分割视图。
- macOS 26 起使用 Apple Liquid Glass API；macOS 14/15 回退至系统材质，侧栏与工具条使用一致效果。
- 保留已确认的分区导航、查看、排序、焦点编辑、剪贴板和文件拖拽定义。
- 目录读取及复制、移动、废纸篓操作移出主线程；旧目录结果不覆盖新导航；选择变化不重载整个文件区。
- 原生方向键、圈选滚动、多选右键菜单、搜索取消与焦点恢复；菜单和悬停提示覆盖十种语言。
- 清理废弃 SwiftUI 文件区实现，拆分侧栏、工具条、设置和窗口管理，增加原生事件与文件安全测试。

### 繁體中文

- 重構原生視窗、分割工作區、按鈕、搜尋與選單；macOS 26 起採用系統 Liquid Glass，舊版使用系統材質。
- 保留既有功能定義，改善背景檔案操作、選取更新、鍵盤與焦點路由，補齊十語言命令及測試。

### English

- Rebuilt the native shell with the standard AppKit title bar, buttons, search, menus, and resizable split views. Uses system Liquid Glass on macOS 26+, with native material on older supported systems.
- Preserved existing feature semantics; added background file operations, incremental selection updates, native focus/keyboard routing, ten-language commands, and regression tests.

### 日本語

- 標準 AppKit タイトルバー、ボタン、検索、メニュー、サイズ変更可能な分割表示に再構成。macOS 26 以降はシステムの Liquid Glass、旧対応 OS は標準マテリアルを使用します。
- 既存の機能仕様を維持し、バックグラウンド処理、選択更新、キー操作とフォーカス、10言語のコマンド、回帰テストを改善しました。

### 한국어

- 기본 AppKit 제목 표시줄, 버튼, 검색, 메뉴와 크기 조절 분할 화면으로 재구성했습니다. macOS 26 이상은 시스템 Liquid Glass, 이전 지원 버전은 기본 소재를 사용합니다.
- 기존 기능을 유지하면서 백그라운드 파일 작업, 선택 갱신, 키보드와 포커스, 10개 언어 명령 및 회귀 테스트를 개선했습니다.

### Français

- Interface native remaniée : barre de titre AppKit standard, boutons, recherche, menus et panneaux redimensionnables. Liquid Glass système sur macOS 26+, matériau natif sur les versions antérieures prises en charge.
- Comportements conservés ; opérations en arrière-plan, sélection incrémentale, clavier et focus natifs, commandes en dix langues et tests de régression améliorés.

### Deutsch

- Native Oberfläche mit Standard-AppKit-Titelleiste, Schaltflächen, Suche, Menüs und verstellbaren Bereichen. System-Liquid-Glass ab macOS 26, natives Material auf älteren unterstützten Versionen.
- Bestehendes Verhalten bleibt erhalten; Hintergrundoperationen, inkrementelle Auswahlaktualisierung, Tastatur/Fokus, Befehle in zehn Sprachen und Regressionstests verbessert.

### Español

- Interfaz nativa renovada con barra de título AppKit, botones, búsqueda, menús y paneles ajustables. Liquid Glass del sistema en macOS 26+ y material nativo en versiones anteriores compatibles.
- Se conserva el comportamiento existente; mejoras en operaciones en segundo plano, selección incremental, teclado, foco, comandos en diez idiomas y pruebas de regresión.

### Português

- Interface nativa refeita com barra de título AppKit, botões, pesquisa, menus e painéis ajustáveis. Liquid Glass do sistema no macOS 26+ e material nativo nas versões anteriores compatíveis.
- Comportamentos preservados; melhorias nas operações em segundo plano, seleção incremental, teclado, foco, comandos em dez idiomas e testes de regressão.

### Русский

- Обновлён нативный интерфейс: стандартная строка заголовка AppKit, кнопки, поиск, меню и изменяемые панели. Системный Liquid Glass на macOS 26+, нативный материал на более ранних поддерживаемых версиях.
- Сохранено прежнее поведение; улучшены фоновые файловые операции, обновление выделения, клавиатура, фокус, команды на десяти языках и регрессионные тесты.

## v0.1.2-candidate - 2026-05-08

### 简体中文

- 将文件区切换为 macOS 原生 AppKit 控件：列表模式使用 `NSTableView`，文件/预览模式使用 `NSCollectionView`，外层 SwiftUI 结构保持不变。
- 保持 `ExplorerModel` 作为唯一业务状态源，AppKit 只负责文件显示、选择、拖拽、右键菜单和事件桥接。
- 改进列表列宽、表头排序、键盘选择、焦点切换和三窗口文件区交互稳定性。
- 修复键盘向下选择文件时选中项不会自动滚入可见区域的问题。
- 修复 AppKit 拖拽 pasteboard 写入，支持内部拖拽、多文件拖拽和 Finder 风格复制/移动规则。
- 增加 AppKit 文件区、拖拽 pasteboard、键盘滚动和选择行为的回归测试。

### 繁體中文

- 將檔案區切換為 macOS 原生 AppKit 控件：列表模式使用 `NSTableView`，檔案/預覽模式使用 `NSCollectionView`，外層 SwiftUI 結構保持不變。
- 保持 `ExplorerModel` 作為唯一業務狀態來源，AppKit 只負責檔案顯示、選取、拖放、右鍵選單和事件橋接。
- 改進列表欄寬、表頭排序、鍵盤選取、焦點切換和三視窗檔案區互動穩定性。
- 修復鍵盤向下選取檔案時選中項不會自動捲入可視區域的問題。
- 修復 AppKit 拖放 pasteboard 寫入，支援內部拖放、多檔案拖放和 Finder 風格複製/移動規則。
- 增加 AppKit 檔案區、拖放 pasteboard、鍵盤捲動和選取行為的回歸測試。

### English

- Migrated the file area to native macOS AppKit controls: `NSTableView` for list mode and `NSCollectionView` for file/preview modes, while keeping the outer SwiftUI shell unchanged.
- Kept `ExplorerModel` as the single source of business state; AppKit only handles file rendering, selection, drag and drop, context menus, and event bridging.
- Improved list column resizing, header sorting, keyboard selection, focus routing, and three-pane file-area stability.
- Fixed keyboard selection not scrolling the newly selected item into view.
- Fixed AppKit drag pasteboard writing for internal drags, multi-file drags, and Finder-style copy/move rules.
- Added regression coverage for the AppKit file area, drag pasteboard behavior, keyboard scrolling, and selection behavior.

### 日本語

- ファイル領域を macOS ネイティブの AppKit コントロールへ移行しました。リスト表示は `NSTableView`、ファイル/プレビュー表示は `NSCollectionView` を使用し、外側の SwiftUI 構造は維持しています。
- `ExplorerModel` を業務状態の唯一の情報源として維持し、AppKit はファイル表示、選択、ドラッグ&ドロップ、コンテキストメニュー、イベント橋渡しのみを担当します。
- リストの列幅調整、ヘッダー並び替え、キーボード選択、フォーカス切り替え、3 ペインのファイル領域の安定性を改善しました。
- キーボードで下方向に選択しても新しい選択項目が表示領域へ自動スクロールしない問題を修正しました。
- 内部ドラッグ、複数ファイルドラッグ、Finder 風のコピー/移動ルールに対応する AppKit drag pasteboard 書き込みを修正しました。
- AppKit ファイル領域、drag pasteboard、キーボードスクロール、選択動作の回帰テストを追加しました。

### 한국어

- 파일 영역을 macOS 네이티브 AppKit 컨트롤로 전환했습니다. 목록 모드는 `NSTableView`, 파일/미리보기 모드는 `NSCollectionView`를 사용하며 외부 SwiftUI 구조는 유지했습니다.
- `ExplorerModel`을 비즈니스 상태의 단일 소스로 유지하고, AppKit은 파일 표시, 선택, 드래그 앤 드롭, 컨텍스트 메뉴, 이벤트 브리지만 담당합니다.
- 목록 열 너비 조절, 헤더 정렬, 키보드 선택, 포커스 전환, 3개 창 파일 영역의 안정성을 개선했습니다.
- 키보드로 아래쪽 파일을 선택할 때 선택 항목이 자동으로 보이는 영역으로 스크롤되지 않던 문제를 수정했습니다.
- 내부 드래그, 다중 파일 드래그, Finder 스타일 복사/이동 규칙을 위한 AppKit drag pasteboard 쓰기를 수정했습니다.
- AppKit 파일 영역, drag pasteboard, 키보드 스크롤, 선택 동작에 대한 회귀 테스트를 추가했습니다.

### Français

- La zone de fichiers utilise désormais des contrôles AppKit natifs de macOS : `NSTableView` pour le mode liste et `NSCollectionView` pour les modes fichiers/aperçu, sans modifier l'enveloppe SwiftUI.
- `ExplorerModel` reste l'unique source d'état métier ; AppKit gère seulement l'affichage, la sélection, le glisser-déposer, les menus contextuels et le pont d'événements.
- Amélioration du redimensionnement des colonnes, du tri par en-tête, de la sélection au clavier, du routage du focus et de la stabilité de la zone de fichiers en trois panneaux.
- Correction du défilement automatique lors de la sélection de fichiers au clavier.
- Correction de l'écriture du pasteboard AppKit pour les glissements internes, les glissements multi-fichiers et les règles copier/déplacer de type Finder.
- Ajout de tests de régression pour la zone de fichiers AppKit, le pasteboard de glisser-déposer, le défilement clavier et la sélection.

### Deutsch

- Der Dateibereich verwendet jetzt native macOS-AppKit-Steuerelemente: `NSTableView` im Listenmodus und `NSCollectionView` im Datei-/Vorschaumodus, während die äußere SwiftUI-Struktur unverändert bleibt.
- `ExplorerModel` bleibt die einzige Quelle für Geschäftsstatus; AppKit übernimmt nur Darstellung, Auswahl, Drag-and-drop, Kontextmenüs und Event-Bridging.
- Verbesserte Stabilität für Spaltenbreiten, Kopfzeilensortierung, Tastaturauswahl, Fokuswechsel und den Dateibereich im Drei-Fenster-Modus.
- Behoben: Bei Tastaturauswahl nach unten wurde das neu ausgewählte Element nicht automatisch sichtbar gescrollt.
- Behoben: AppKit-drag-pasteboard-Schreiben für interne Drags, Mehrfachdatei-Drags und Finder-artige Kopieren-/Verschieben-Regeln.
- Regressionstests für AppKit-Dateibereich, Drag-pasteboard, Tastatur-Scrolling und Auswahlverhalten ergänzt.

### Español

- El área de archivos ahora usa controles AppKit nativos de macOS: `NSTableView` para el modo lista y `NSCollectionView` para los modos de archivos/vista previa, manteniendo intacta la estructura SwiftUI externa.
- `ExplorerModel` sigue siendo la única fuente de estado de negocio; AppKit solo gestiona renderizado, selección, arrastrar y soltar, menús contextuales y puente de eventos.
- Mejora de estabilidad para el ancho de columnas, ordenación por encabezado, selección con teclado, foco y el área de archivos de tres paneles.
- Corregido el problema por el que la selección con teclado hacia abajo no desplazaba el elemento seleccionado al área visible.
- Corregida la escritura del pasteboard de AppKit para arrastres internos, arrastres de varios archivos y reglas de copiar/mover estilo Finder.
- Añadidas pruebas de regresión para el área de archivos AppKit, drag pasteboard, desplazamiento con teclado y selección.

### Português

- A área de arquivos agora usa controles AppKit nativos do macOS: `NSTableView` no modo lista e `NSCollectionView` nos modos arquivos/pré-visualização, mantendo a estrutura SwiftUI externa.
- `ExplorerModel` continua sendo a única fonte de estado de negócio; AppKit cuida apenas de renderização, seleção, arrastar e soltar, menus de contexto e ponte de eventos.
- Melhorias em redimensionamento de colunas, ordenação por cabeçalho, seleção pelo teclado, foco e estabilidade da área de arquivos em três painéis.
- Corrigido o problema em que a seleção pelo teclado para baixo não rolava automaticamente o item selecionado para a área visível.
- Corrigida a gravação do pasteboard de drag do AppKit para drags internos, drags de vários arquivos e regras de copiar/mover no estilo Finder.
- Adicionados testes de regressão para a área de arquivos AppKit, drag pasteboard, rolagem pelo teclado e seleção.

### Русский

- Область файлов переведена на нативные элементы AppKit для macOS: `NSTableView` для режима списка и `NSCollectionView` для режимов файлов/предпросмотра, при этом внешняя структура SwiftUI сохранена.
- `ExplorerModel` остается единственным источником бизнес-состояния; AppKit отвечает только за отображение файлов, выбор, drag-and-drop, контекстные меню и мост событий.
- Улучшена стабильность изменения ширины колонок, сортировки по заголовкам, выбора с клавиатуры, переключения фокуса и файловой области в трехпанельном режиме.
- Исправлено: при выборе файлов клавиатурой вниз новый выбранный элемент не прокручивался в видимую область.
- Исправлена запись AppKit drag pasteboard для внутренних перетаскиваний, перетаскивания нескольких файлов и правил копирования/перемещения в стиле Finder.
- Добавлены регрессионные тесты для AppKit-файловой области, drag pasteboard, прокрутки с клавиатуры и поведения выбора.
