import Foundation

enum NativeCommandKey: String, CaseIterable {
    case about, fileMenu, viewMenu, goMenu
    case newFolder, newFile, cut, copy, paste, selectAll, open, rename, moveToTrash
    case search, closeSearch, refresh, goBack, goForward, goUp
    case viewMode, listView, filesView, previewView
    case sortBy, sortName, sortModified, sortCreated, sortSize, sortType, sortExtension
    case ascending, descending, nextPane, previousPane
    case mainPane, assistTopPane, assistBottomPane, threePanes
    case removeShortcut, eject, fixedIcons
    case columnName, columnModified, columnCreated, columnSize, columnType, columnExtension
    case emptyFolder, noSearchResults, loading, loadFailed
    case close, hideSidebar, automaticUpdates, language, chooseApplication, copyURL, info, noNetworkDevices
}

enum NativeCommandText {
    static func localized(_ key: NativeCommandKey, language: String) -> String {
        let language = resolvedLanguage(language)
        if let existing = existingKey(for: key) {
            return AppText.localized(existing, language: language)
        }
        return translations[key]?.value(for: language) ?? key.rawValue
    }

    static func viewMode(_ mode: ExplorerViewMode, language: String) -> String {
        let key: NativeCommandKey = switch mode {
        case .list: .listView
        case .files: .filesView
        case .preview: .previewView
        }
        return localized(key, language: language)
    }

    static func sortField(_ field: SortField, language: String) -> String {
        let key: NativeCommandKey = switch field {
        case .name: .sortName
        case .modified: .sortModified
        case .created: .sortCreated
        case .size: .sortSize
        case .type: .sortType
        case .ext: .sortExtension
        }
        return localized(key, language: language)
    }

    static func column(_ column: FileColumn, language: String) -> String {
        let key: NativeCommandKey = switch column {
        case .name: .columnName
        case .modified: .columnModified
        case .type: .columnType
        case .size: .columnSize
        }
        return localized(key, language: language)
    }

    // Keep system-language resolution aligned with AppText without changing its private implementation.
    static func resolvedLanguage(_ language: String, preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        if language != "system", AppText.supportedLanguages.contains(where: { $0.id == language }) {
            return language
        }
        let preferred = (preferredLanguages.first ?? Locale.current.identifier).lowercased()
        if preferred.hasPrefix("zh-hant") || preferred.hasPrefix("zh-tw") || preferred.hasPrefix("zh-hk") {
            return "zh-Hant"
        }
        if preferred.hasPrefix("zh") { return "zh-Hans" }
        for language in ["ja", "ko", "fr", "de", "es", "pt", "ru"] where preferred.hasPrefix(language) {
            return language
        }
        return "en"
    }

    private static func existingKey(for key: NativeCommandKey) -> AppTextKey? {
        switch key {
        case .newFolder: .tooltipCreateFolder
        case .newFile: .tooltipCreateFile
        case .cut: .tooltipCut
        case .copy: .tooltipCopy
        case .paste: .tooltipPaste
        case .search: .tooltipSearch
        case .refresh: .tooltipRefresh
        case .goBack: .tooltipBack
        case .goForward: .tooltipForward
        case .goUp: .tooltipGoUp
        case .viewMenu: .tooltipView
        case .sortBy: .tooltipSort
        case .threePanes: .tooltipThreePane
        default: nil
        }
    }

    private struct Translation {
        let zhHans: String
        let zhHant: String
        let en: String
        let ja: String
        let ko: String
        let fr: String
        let de: String
        let es: String
        let pt: String
        let ru: String

        func value(for language: String) -> String {
            switch language {
            case "zh-Hans": zhHans
            case "zh-Hant": zhHant
            case "ja": ja
            case "ko": ko
            case "fr": fr
            case "de": de
            case "es": es
            case "pt": pt
            case "ru": ru
            default: en
            }
        }
    }

    private static let translations: [NativeCommandKey: Translation] = [
        .about: Translation(zhHans: "关于", zhHant: "關於", en: "About", ja: "このアプリについて", ko: "정보", fr: "À propos de", de: "Über", es: "Acerca de", pt: "Sobre", ru: "О программе"),
        .fileMenu: Translation(zhHans: "文件", zhHant: "檔案", en: "File", ja: "ファイル", ko: "파일", fr: "Fichier", de: "Ablage", es: "Archivo", pt: "Arquivo", ru: "Файл"),
        .goMenu: Translation(zhHans: "前往", zhHant: "前往", en: "Go", ja: "移動", ko: "이동", fr: "Aller", de: "Gehe zu", es: "Ir", pt: "Ir", ru: "Переход"),
        .selectAll: Translation(zhHans: "全选", zhHant: "全選", en: "Select All", ja: "すべてを選択", ko: "모두 선택", fr: "Tout sélectionner", de: "Alles auswählen", es: "Seleccionar todo", pt: "Selecionar tudo", ru: "Выбрать всё"),
        .open: Translation(zhHans: "打开", zhHant: "打開", en: "Open", ja: "開く", ko: "열기", fr: "Ouvrir", de: "Öffnen", es: "Abrir", pt: "Abrir", ru: "Открыть"),
        .rename: Translation(zhHans: "重命名", zhHant: "重新命名", en: "Rename", ja: "名前を変更", ko: "이름 변경", fr: "Renommer", de: "Umbenennen", es: "Renombrar", pt: "Renomear", ru: "Переименовать"),
        .moveToTrash: Translation(zhHans: "移到废纸篓", zhHant: "移到垃圾桶", en: "Move to Trash", ja: "ゴミ箱に入れる", ko: "휴지통으로 이동", fr: "Placer dans la corbeille", de: "In den Papierkorb legen", es: "Trasladar a la papelera", pt: "Mover para o Lixo", ru: "Переместить в Корзину"),
        .closeSearch: Translation(zhHans: "关闭搜索", zhHant: "關閉搜尋", en: "Close Search", ja: "検索を閉じる", ko: "검색 닫기", fr: "Fermer la recherche", de: "Suche schließen", es: "Cerrar búsqueda", pt: "Fechar pesquisa", ru: "Закрыть поиск"),
        .viewMode: Translation(zhHans: "查看方式", zhHant: "顯示方式", en: "View Mode", ja: "表示形式", ko: "보기 방식", fr: "Mode d’affichage", de: "Darstellung", es: "Modo de visualización", pt: "Modo de visualização", ru: "Режим просмотра"),
        .listView: Translation(zhHans: "列表", zhHant: "列表", en: "List", ja: "リスト", ko: "목록", fr: "Liste", de: "Liste", es: "Lista", pt: "Lista", ru: "Список"),
        .filesView: Translation(zhHans: "文件", zhHant: "檔案", en: "Icons", ja: "アイコン", ko: "아이콘", fr: "Icônes", de: "Symbole", es: "Iconos", pt: "Ícones", ru: "Значки"),
        .previewView: Translation(zhHans: "预览", zhHant: "預覽", en: "Preview", ja: "プレビュー", ko: "미리보기", fr: "Aperçu", de: "Vorschau", es: "Vista previa", pt: "Pré-visualização", ru: "Предпросмотр"),
        .sortName: Translation(zhHans: "名称", zhHant: "名稱", en: "Name", ja: "名前", ko: "이름", fr: "Nom", de: "Name", es: "Nombre", pt: "Nome", ru: "Имя"),
        .sortModified: Translation(zhHans: "修改时间", zhHant: "修改時間", en: "Date Modified", ja: "変更日", ko: "수정 날짜", fr: "Date de modification", de: "Änderungsdatum", es: "Fecha de modificación", pt: "Data de modificação", ru: "Дата изменения"),
        .sortCreated: Translation(zhHans: "创建时间", zhHant: "建立時間", en: "Date Created", ja: "作成日", ko: "생성 날짜", fr: "Date de création", de: "Erstellungsdatum", es: "Fecha de creación", pt: "Data de criação", ru: "Дата создания"),
        .sortSize: Translation(zhHans: "大小", zhHant: "大小", en: "Size", ja: "サイズ", ko: "크기", fr: "Taille", de: "Größe", es: "Tamaño", pt: "Tamanho", ru: "Размер"),
        .sortType: Translation(zhHans: "类型", zhHant: "種類", en: "Kind", ja: "種類", ko: "종류", fr: "Type", de: "Art", es: "Clase", pt: "Tipo", ru: "Тип"),
        .sortExtension: Translation(zhHans: "扩展名", zhHant: "副檔名", en: "Extension", ja: "拡張子", ko: "확장자", fr: "Extension", de: "Dateierweiterung", es: "Extensión", pt: "Extensão", ru: "Расширение"),
        .ascending: Translation(zhHans: "升序", zhHant: "遞增", en: "Ascending", ja: "昇順", ko: "오름차순", fr: "Croissant", de: "Aufsteigend", es: "Ascendente", pt: "Crescente", ru: "По возрастанию"),
        .descending: Translation(zhHans: "降序", zhHant: "遞減", en: "Descending", ja: "降順", ko: "내림차순", fr: "Décroissant", de: "Absteigend", es: "Descendente", pt: "Decrescente", ru: "По убыванию"),
        .nextPane: Translation(zhHans: "下一个窗格", zhHant: "下一個面板", en: "Next Pane", ja: "次のペイン", ko: "다음 창", fr: "Panneau suivant", de: "Nächster Bereich", es: "Panel siguiente", pt: "Próximo painel", ru: "Следующая панель"),
        .previousPane: Translation(zhHans: "上一个窗格", zhHant: "上一個面板", en: "Previous Pane", ja: "前のペイン", ko: "이전 창", fr: "Panneau précédent", de: "Vorheriger Bereich", es: "Panel anterior", pt: "Painel anterior", ru: "Предыдущая панель"),
        .mainPane: Translation(zhHans: "主窗格", zhHant: "主面板", en: "Main Pane", ja: "メインペイン", ko: "기본 창", fr: "Panneau principal", de: "Hauptbereich", es: "Panel principal", pt: "Painel principal", ru: "Основная панель"),
        .assistTopPane: Translation(zhHans: "上方辅助窗格", zhHant: "上方輔助面板", en: "Upper Pane", ja: "上のペイン", ko: "위쪽 창", fr: "Panneau supérieur", de: "Oberer Bereich", es: "Panel superior", pt: "Painel superior", ru: "Верхняя панель"),
        .assistBottomPane: Translation(zhHans: "下方辅助窗格", zhHant: "下方輔助面板", en: "Lower Pane", ja: "下のペイン", ko: "아래쪽 창", fr: "Panneau inférieur", de: "Unterer Bereich", es: "Panel inferior", pt: "Painel inferior", ru: "Нижняя панель"),
        .removeShortcut: Translation(zhHans: "移除快捷方式", zhHant: "移除捷徑", en: "Remove Shortcut", ja: "ショートカットを削除", ko: "바로가기 제거", fr: "Supprimer le raccourci", de: "Verknüpfung entfernen", es: "Eliminar acceso directo", pt: "Remover atalho", ru: "Удалить ярлык"),
        .eject: Translation(zhHans: "推出", zhHant: "退出", en: "Eject", ja: "取り出す", ko: "추출", fr: "Éjecter", de: "Auswerfen", es: "Expulsar", pt: "Ejetar", ru: "Извлечь"),
        .fixedIcons: Translation(zhHans: "固定图标", zhHant: "固定圖示", en: "Pinned Icons", ja: "固定アイコン", ko: "고정 아이콘", fr: "Icônes épinglées", de: "Angeheftete Symbole", es: "Iconos fijados", pt: "Ícones fixados", ru: "Закреплённые значки"),
        .columnName: Translation(zhHans: "文件名", zhHant: "檔案名稱", en: "Name", ja: "名前", ko: "이름", fr: "Nom", de: "Name", es: "Nombre", pt: "Nome", ru: "Имя"),
        .columnModified: Translation(zhHans: "修改日期", zhHant: "修改日期", en: "Date Modified", ja: "変更日", ko: "수정 날짜", fr: "Date de modification", de: "Änderungsdatum", es: "Fecha de modificación", pt: "Data de modificação", ru: "Дата изменения"),
        .columnCreated: Translation(zhHans: "创建日期", zhHant: "建立日期", en: "Date Created", ja: "作成日", ko: "생성 날짜", fr: "Date de création", de: "Erstellungsdatum", es: "Fecha de creación", pt: "Data de criação", ru: "Дата создания"),
        .columnSize: Translation(zhHans: "大小", zhHant: "大小", en: "Size", ja: "サイズ", ko: "크기", fr: "Taille", de: "Größe", es: "Tamaño", pt: "Tamanho", ru: "Размер"),
        .columnType: Translation(zhHans: "类型", zhHant: "種類", en: "Kind", ja: "種類", ko: "종류", fr: "Type", de: "Art", es: "Clase", pt: "Tipo", ru: "Тип"),
        .columnExtension: Translation(zhHans: "扩展名", zhHant: "副檔名", en: "Extension", ja: "拡張子", ko: "확장자", fr: "Extension", de: "Dateierweiterung", es: "Extensión", pt: "Extensão", ru: "Расширение"),
        .emptyFolder: Translation(zhHans: "此文件夹为空", zhHant: "此資料夾是空的", en: "This folder is empty", ja: "このフォルダは空です", ko: "이 폴더는 비어 있습니다", fr: "Ce dossier est vide", de: "Dieser Ordner ist leer", es: "Esta carpeta está vacía", pt: "Esta pasta está vazia", ru: "Эта папка пуста"),
        .noSearchResults: Translation(zhHans: "没有搜索结果", zhHant: "沒有搜尋結果", en: "No search results", ja: "検索結果がありません", ko: "검색 결과가 없습니다", fr: "Aucun résultat", de: "Keine Suchergebnisse", es: "Sin resultados", pt: "Nenhum resultado", ru: "Ничего не найдено"),
        .loading: Translation(zhHans: "正在载入", zhHant: "載入中", en: "Loading", ja: "読み込み中", ko: "불러오는 중", fr: "Chargement", de: "Wird geladen", es: "Cargando", pt: "Carregando", ru: "Загрузка"),
        .loadFailed: Translation(zhHans: "无法载入此文件夹", zhHant: "無法載入此資料夾", en: "Unable to load this folder", ja: "このフォルダを読み込めません", ko: "이 폴더를 불러올 수 없습니다", fr: "Impossible de charger ce dossier", de: "Dieser Ordner kann nicht geladen werden", es: "No se puede cargar esta carpeta", pt: "Não foi possível carregar esta pasta", ru: "Не удалось загрузить эту папку"),
        .close: Translation(zhHans: "关闭", zhHant: "關閉", en: "Close", ja: "閉じる", ko: "닫기", fr: "Fermer", de: "Schließen", es: "Cerrar", pt: "Fechar", ru: "Закрыть"),
        .hideSidebar: Translation(zhHans: "隐藏侧边栏", zhHant: "隱藏側邊欄", en: "Hide Sidebar", ja: "サイドバーを隠す", ko: "사이드바 가리기", fr: "Masquer la barre latérale", de: "Seitenleiste ausblenden", es: "Ocultar barra lateral", pt: "Ocultar barra lateral", ru: "Скрыть боковую панель"),
        .automaticUpdates: Translation(zhHans: "自动检查更新", zhHant: "自動檢查更新", en: "Automatically Check for Updates", ja: "アップデートを自動確認", ko: "자동으로 업데이트 확인", fr: "Rechercher automatiquement les mises à jour", de: "Automatisch nach Updates suchen", es: "Buscar actualizaciones automáticamente", pt: "Buscar atualizações automaticamente", ru: "Автоматически проверять обновления"),
        .language: Translation(zhHans: "语言", zhHant: "語言", en: "Language", ja: "言語", ko: "언어", fr: "Langue", de: "Sprache", es: "Idioma", pt: "Idioma", ru: "Язык"),
        .chooseApplication: Translation(zhHans: "选择应用程序打开", zhHant: "選擇應用程式開啟", en: "Open With Application", ja: "アプリケーションを選択して開く", ko: "응용 프로그램을 선택하여 열기", fr: "Ouvrir avec une application", de: "Mit Programm öffnen", es: "Abrir con una aplicación", pt: "Abrir com aplicativo", ru: "Открыть в приложении"),
        .copyURL: Translation(zhHans: "复制 URL", zhHant: "複製 URL", en: "Copy URL", ja: "URLをコピー", ko: "URL 복사", fr: "Copier l’URL", de: "URL kopieren", es: "Copiar URL", pt: "Copiar URL", ru: "Скопировать URL"),
        .info: Translation(zhHans: "属性", zhHant: "取得資訊", en: "Get Info", ja: "情報を見る", ko: "정보 가져오기", fr: "Lire les informations", de: "Informationen", es: "Obtener información", pt: "Obter informações", ru: "Свойства"),
        .noNetworkDevices: Translation(zhHans: "未发现网络设备", zhHant: "未找到網路裝置", en: "No network devices found", ja: "ネットワークデバイスが見つかりません", ko: "네트워크 기기를 찾을 수 없습니다", fr: "Aucun appareil réseau trouvé", de: "Keine Netzwerkgeräte gefunden", es: "No se encontraron dispositivos de red", pt: "Nenhum dispositivo de rede encontrado", ru: "Сетевые устройства не найдены")
    ]
}

extension ExplorerModel {
    func commandText(_ key: NativeCommandKey) -> String {
        NativeCommandText.localized(key, language: language)
    }
}
