import AppKit
import XCTest
@testable import xAlgoExplorer

@MainActor
final class NativeCommandTests: XCTestCase {
    func testEveryCommandHasAllTenTranslations() {
        let languages = AppText.supportedLanguages.filter { $0.id != "system" }
        XCTAssertEqual(languages.count, 10)
        for language in languages {
            for key in NativeCommandKey.allCases {
                let text = NativeCommandText.localized(key, language: language.id)
                XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(language.id): \(key)")
                XCTAssertNotEqual(text, key.rawValue, "\(language.id): \(key)")
            }
        }
    }

    func testSharedCommandLabelsReuseExistingLocalization() {
        let mappings: [(NativeCommandKey, AppTextKey)] = [
            (.newFolder, .tooltipCreateFolder), (.newFile, .tooltipCreateFile),
            (.cut, .tooltipCut), (.copy, .tooltipCopy), (.paste, .tooltipPaste),
            (.search, .tooltipSearch), (.refresh, .tooltipRefresh),
            (.goBack, .tooltipBack), (.goForward, .tooltipForward), (.goUp, .tooltipGoUp),
            (.viewMenu, .tooltipView), (.sortBy, .tooltipSort), (.threePanes, .tooltipThreePane)
        ]
        for language in AppText.supportedLanguages {
            for (command, existing) in mappings {
                XCTAssertEqual(
                    NativeCommandText.localized(command, language: language.id),
                    AppText.localized(existing, language: language.id)
                )
            }
        }
    }

    func testSystemLanguageResolutionAndExplicitOverrides() {
        for language in AppText.supportedLanguages where language.id != "system" {
            XCTAssertEqual(NativeCommandText.resolvedLanguage(language.id, preferredLanguages: ["en-US"]), language.id)
        }
        let preferred: [String: String] = [
            "zh-CN": "zh-Hans", "zh-Hant-TW": "zh-Hant", "zh-HK": "zh-Hant",
            "ja-JP": "ja", "ko-KR": "ko", "fr-FR": "fr", "de-DE": "de",
            "es-ES": "es", "pt-BR": "pt", "ru-RU": "ru", "en-US": "en", "it-IT": "en"
        ]
        for (preferred, expected) in preferred {
            XCTAssertEqual(NativeCommandText.resolvedLanguage("system", preferredLanguages: [preferred]), expected)
        }
    }

    func testViewSortAndColumnLabelsAreLocalized() {
        XCTAssertEqual(NativeCommandText.viewMode(.list, language: "en"), "List")
        XCTAssertEqual(NativeCommandText.viewMode(.files, language: "ja"), "アイコン")
        XCTAssertEqual(NativeCommandText.viewMode(.preview, language: "de"), "Vorschau")
        XCTAssertEqual(NativeCommandText.sortField(.modified, language: "en"), "Date Modified")
        XCTAssertEqual(NativeCommandText.sortField(.ext, language: "zh-Hant"), "副檔名")
        XCTAssertEqual(NativeCommandText.column(.name, language: "zh-Hans"), "文件名")
        XCTAssertEqual(NativeCommandText.column(.modified, language: "fr"), "Date de modification")
        XCTAssertEqual(NativeCommandText.localized(.closeSearch, language: "en"), "Close Search")
        XCTAssertEqual(NativeCommandText.localized(.noNetworkDevices, language: "ja"), "ネットワークデバイスが見つかりません")
    }

    func testTextInputsIncludeSearchAndReadOnlyText() {
        _ = NSApplication.shared
        let text = NSTextView()
        text.isEditable = false
        XCTAssertTrue(NativeCommandRouting.isTextInput(text))
        XCTAssertTrue(NativeCommandRouting.isTextInput(NSSearchField()))
        XCTAssertTrue(NativeCommandRouting.isTextInput(NSTextField()))
        XCTAssertFalse(NativeCommandRouting.isTextInput(NSView()))
        XCTAssertFalse(NativeCommandRouting.isTextInput(nil))
    }

    func testEditingActionsUseStandardAppKitSelectors() {
        XCTAssertEqual(NativeEditingAction.cut.selector, #selector(NSText.cut(_:)))
        XCTAssertEqual(NativeEditingAction.copy.selector, #selector(NSText.copy(_:)))
        XCTAssertEqual(NativeEditingAction.paste.selector, #selector(NSText.paste(_:)))
        XCTAssertEqual(NativeEditingAction.selectAll.selector, #selector(NSText.selectAll(_:)))
    }

    func testAllTextCommandsRouteExclusivelyToNativeResponder() {
        _ = NSApplication.shared
        let text = NSTextView()
        for action in NativeEditingAction.allCases {
            var nativeCalls = 0
            let handled = NativeCommandRouting.routeEditing(
                action, firstResponder: text, isWorkspace: true,
                sendToResponder: { selector in
                    nativeCalls += 1
                    XCTAssertEqual(selector, action.selector)
                    return true
                },
                fileAction: { XCTFail("Text editing must not operate on files"); return true }
            )
            XCTAssertTrue(handled)
            XCTAssertEqual(nativeCalls, 1)
        }
    }

    func testRejectedTextCommandsNeverFallBackToFiles() {
        _ = NSApplication.shared
        let text = NSTextView()
        text.isEditable = false
        for action in NativeEditingAction.allCases {
            XCTAssertFalse(NativeCommandRouting.routeEditing(
                action, firstResponder: text, isWorkspace: true,
                sendToResponder: { _ in false },
                fileAction: { XCTFail("An unhandled text command must not fall back to files"); return true }
            ))
        }
    }

    func testSettingsAndDialogCommandsNeverFallBackToFiles() {
        for action in NativeEditingAction.allCases {
            XCTAssertFalse(NativeCommandRouting.routeEditing(
                action, firstResponder: nil, isWorkspace: false,
                sendToResponder: { _ in false },
                fileAction: { XCTFail("Non-workspace windows must not operate on files"); return true }
            ))
        }
    }

    func testFileAreaEditingRoutesToFileActions() {
        for action in NativeEditingAction.allCases {
            var fileCalls = 0
            XCTAssertTrue(NativeCommandRouting.routeEditing(
                action, firstResponder: NSView(), isWorkspace: true,
                sendToResponder: { _ in XCTFail("File command should use the file model"); return false },
                fileAction: { fileCalls += 1; return true }
            ))
            XCTAssertEqual(fileCalls, 1)
        }
    }

    func testFileCommandAvailabilityFollowsCurrentPaneSelection() async {
        let model = ExplorerModel()
        await model.waitForPendingReloads()
        model.focusedPaneID = .main
        model.mainPane.virtualPage = nil
        model.mainPane.selectedIDs = ["/tmp/main-selection"]
        model.assistTopPane.selectedIDs = []
        XCTAssertTrue(NativeCommandRouting.canPerformFileEditing(.copy, model: model))

        model.focusedPaneID = .assistTop
        XCTAssertFalse(NativeCommandRouting.canPerformFileEditing(.copy, model: model))
        model.assistTopPane.selectedIDs = ["/tmp/assist-selection"]
        XCTAssertTrue(NativeCommandRouting.canPerformFileEditing(.copy, model: model))
        model.assistTopPane.selectedIDs.removeAll()
        XCTAssertFalse(NativeCommandRouting.canPerformFileEditing(.copy, model: model))

        model.focusedPaneID = .main
        model.mainPane.virtualPage = .network
        XCTAssertFalse(NativeCommandRouting.canPerformFileEditing(.cut, model: model))
    }

    func testPaneCyclingWrapsInBothDirections() {
        XCTAssertEqual(NativeCommandRouting.nextPane(after: .main, backwards: false), .assistTop)
        XCTAssertEqual(NativeCommandRouting.nextPane(after: .assistTop, backwards: false), .assistBottom)
        XCTAssertEqual(NativeCommandRouting.nextPane(after: .assistBottom, backwards: false), .main)
        XCTAssertEqual(NativeCommandRouting.nextPane(after: .main, backwards: true), .assistBottom)
        XCTAssertEqual(NativeCommandRouting.nextPane(after: .assistBottom, backwards: true), .assistTop)
        XCTAssertEqual(NativeCommandRouting.nextPane(after: .assistTop, backwards: true), .main)
    }

    func testPaneCycleMovesNativeFirstResponderAndModelTogether() async {
        let model = ExplorerModel()
        await model.waitForPendingReloads()
        model.assistOpen = true
        model.focusedPaneID = .main
        let (window, views) = makeWorkspaceWindow()
        defer { window.close() }
        XCTAssertTrue(window.makeFirstResponder(views[.main]))

        for expected: PaneID in [.assistTop, .assistBottom, .main] {
            XCTAssertTrue(NativeCommandRouting.movePaneFocus(model: model, in: window, backwards: false))
            XCTAssertEqual(model.focusedPaneID, expected)
            XCTAssertTrue(window.firstResponder === views[expected])
        }
        XCTAssertTrue(NativeCommandRouting.movePaneFocus(model: model, in: window, backwards: true))
        XCTAssertEqual(model.focusedPaneID, .assistBottom)
        XCTAssertTrue(window.firstResponder === views[.assistBottom])
    }

    func testPaneCycleUsesActualResponderWhenModelFocusIsStale() async {
        let model = ExplorerModel()
        await model.waitForPendingReloads()
        model.assistOpen = true
        model.focusedPaneID = .main
        let (window, views) = makeWorkspaceWindow()
        defer { window.close() }
        XCTAssertTrue(window.makeFirstResponder(views[.assistBottom]))
        XCTAssertTrue(NativeCommandRouting.movePaneFocus(model: model, in: window, backwards: false))
        XCTAssertEqual(model.focusedPaneID, .main)
        XCTAssertTrue(window.firstResponder === views[.main])
    }

    func testAbsentPaneDoesNotChangeLogicalFocus() async {
        let model = ExplorerModel()
        await model.waitForPendingReloads()
        model.assistOpen = true
        model.focusedPaneID = .main
        let (window, views) = makeWorkspaceWindow()
        defer { window.close() }
        views[.assistTop]?.removeFromSuperview()
        XCTAssertTrue(window.makeFirstResponder(views[.main]))
        XCTAssertFalse(NativeCommandRouting.movePaneFocus(model: model, in: window, backwards: false))
        XCTAssertEqual(model.focusedPaneID, .main)
        XCTAssertTrue(window.firstResponder === views[.main])
    }

    func testRefusedResignationDoesNotChangeLogicalFocus() async {
        let model = ExplorerModel()
        await model.waitForPendingReloads()
        model.assistOpen = true
        model.focusedPaneID = .main
        let (window, views) = makeWorkspaceWindow()
        defer { views[.main]?.canResign = true; window.close() }
        XCTAssertTrue(window.makeFirstResponder(views[.main]))
        views[.main]?.canResign = false
        XCTAssertFalse(NativeCommandRouting.movePaneFocus(model: model, in: window, backwards: false))
        XCTAssertEqual(model.focusedPaneID, .main)
        XCTAssertTrue(window.firstResponder === views[.main])
    }

    func testClosedAssistantPanesCannotReceiveCycleFocus() async {
        let model = ExplorerModel()
        await model.waitForPendingReloads()
        model.assistOpen = false
        model.focusedPaneID = .main
        let (window, views) = makeWorkspaceWindow()
        defer { window.close() }
        XCTAssertTrue(window.makeFirstResponder(views[.main]))
        XCTAssertFalse(NativeCommandRouting.movePaneFocus(model: model, in: window, backwards: false))
        XCTAssertEqual(model.focusedPaneID, .main)
    }

    private func makeWorkspaceWindow() -> (NSWindow, [PaneID: CommandFocusView]) {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let root = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = root
        var views: [PaneID: CommandFocusView] = [:]
        for (index, pane) in PaneID.allCases.enumerated() {
            let view = CommandFocusView(frame: NSRect(x: CGFloat(index) * 180, y: 0, width: 180, height: 300))
            view.identifier = NativePaneFocus.identifier(for: pane)
            root.addSubview(view)
            views[pane] = view
        }
        return (window, views)
    }
}

@MainActor
private final class CommandFocusView: NSView {
    var canResign = true
    override var acceptsFirstResponder: Bool { true }
    override func resignFirstResponder() -> Bool { canResign }
}
