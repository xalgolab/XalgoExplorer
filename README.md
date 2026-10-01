# XalgoExplorer

XalgoExplorer is a native macOS file manager designed for Windows users who are moving to macOS.

It keeps familiar desktop-file workflows close at hand while adopting macOS conventions: a clean native window, multi-pane browsing, drag-and-drop file operations, keyboard navigation, localized tooltips, and a compact sidebar for daily locations and mounted drives.

## Why It Exists

Many Windows users moving to macOS miss a file manager that feels direct, visible, and keyboard-friendly. XalgoExplorer focuses on that transition:

- Familiar multi-pane file browsing for comparing and moving files.
- Finder-style copy and move behavior across disks.
- Clear toolbar actions for back, forward, up, refresh, new folder, new file, cut, copy, and paste.
- A compact icon rail for Home, Pictures, Desktop, Downloads, Documents, Music, Videos, mounted drives, and network locations.
- Localized labels and tooltips for international users.
- Native macOS packaging as an app bundle and DMG installer.

## Candidate Build

The native-interface refactor is available as a GitHub prerelease for testing:

- Version: `v0.2.0-candidate`
- Platform: Apple Silicon macOS
- Minimum macOS: 14.0
- Liquid Glass: macOS 26 or later; native material fallback on macOS 14/15
- Package: `xAlgo_Explorer_v0.2.0-candidate_aarch64.dmg`
- Release: [v0.2.0-candidate](https://github.com/xalgolab/XalgoExplorer/releases/tag/v0.2.0-candidate)
- Release notes: [ten-language notes and validation limits](docs/releases/v0.2.0-candidate.md)
- SHA256: `865829a92ea751eab25aa6370bb984274cd5e4eeedd8d377c7bb0f13db786300`

This is a testing candidate with an ad-hoc signature, not a Developer ID-notarized stable release. Real-mouse sidebar drops, long-distance drag selection, cross-volume drops, and older-system compatibility still need manual validation. See the release notes before using it on important files.

## Version Notes

Localized version notes are available in the release notes and language documents listed below.

### v0.2.0-candidate

- Uses Apple's Liquid Glass API, standard AppKit title bar, native symbol buttons, search field, menus, and resizable split views.
- Preserves the main/two-assistant workspace model, scoped navigation and sorting, system clipboard interoperability, and established drag rules.
- Loads directories and performs copy/move/trash operations away from the main thread; ignores stale navigation results and avoids full file-area reloads on selection.
- Unifies native keyboard focus, text-editing command routing, tooltips, and ten-language command labels.
- See [the changelog](CHANGELOG.md) and [implementation and validation plan](docs/native-v0.2.0-plan.md).

### v0.1.2-candidate

This candidate moves the file area to native macOS AppKit controls while keeping the existing SwiftUI shell and product behavior:

- Replaced the list file area with `NSTableView`.
- Replaced file and preview grid areas with `NSCollectionView`.
- Kept `ExplorerModel` as the single source of truth for paths, selection, sorting, drag/drop rules, clipboard behavior, and pane focus.
- Improved column resizing, header sorting, keyboard selection, focus routing, and three-pane file-area stability.
- Fixed keyboard selection scrolling so the active selection is automatically brought into view.
- Fixed AppKit drag pasteboard handling for internal drags, multi-file drags, and Finder-style copy/move behavior.
- Added regression coverage for AppKit file-area selection, drag pasteboard behavior, keyboard scrolling, and candidate release metadata.
- Full ten-language notes: [v0.1.2-candidate](docs/releases/v0.1.2-candidate.md).

### v0.1.1-candidate

This candidate focuses on file-operation safety, packaging hygiene, and UI reliability:

- Fixed stale internal drag payload handling so a cancelled drag cannot hijack a later file drop.
- Added rename validation for path traversal and path separators, preventing names like `../file` or `a/b` from becoming cross-directory moves.
- Changed cut-and-paste back into the original directory to a no-op instead of silently creating duplicate names.
- Added Finder-compatible system pasteboard support for copying and pasting file URLs between Finder and xAlgo Explorer.
- Added a clear close path for search and released search focus so arrow-key navigation returns to the file list.
- Replaced the hardcoded network device placeholder with an empty network discovery state until real discovery is implemented.
- Updated the candidate version metadata and packaged DMG naming to `v0.1.1-candidate`.

### v0.1.0-candidate

Initial public candidate with the native macOS file manager shell, multi-pane layout, icon rail, localized tooltips, drag-and-drop file operations, keyboard navigation, and signed Apple Silicon app/DMG packaging.

## Build From Source

Requirements:

- Apple Silicon Mac
- macOS 14 or later
- Xcode 26 or later with the macOS 26 SDK (validated with Xcode 27 / Swift 6.4)
- Swift 6 toolchain

Commands:

```sh
swift test
make app
make dmg
```

The packaged app and DMG are written to `dist/`.

## Languages

Documentation is available in:

- [English](docs/en.md)
- [简体中文](docs/zh-CN.md)
- [日本語](docs/ja.md)
- [한국어](docs/ko.md)
- [Deutsch](docs/de.md)
- [Français](docs/fr.md)
- [Español](docs/es.md)

## License

XalgoExplorer is released under the MIT License. See [LICENSE](LICENSE).
