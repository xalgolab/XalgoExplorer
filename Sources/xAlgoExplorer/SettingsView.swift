import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileInfoView: View {
    @EnvironmentObject private var model: ExplorerModel
    @Environment(\.dismiss) private var dismiss
    let info: FileInfoSheet

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: FileSystemService.appIcon(for: info.entry))
                    .resizable()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.entry.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(info.entry.url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Divider()

            LabeledContent(model.commandText(.sortType), value: info.entry.typeDescription)
            LabeledContent(model.commandText(.sortSize), value: info.sizeText)
            LabeledContent(model.commandText(.sortModified), value: info.modifiedText)
            LabeledContent(model.commandText(.sortCreated), value: info.createdText)

            HStack {
                Spacer()
                Button(model.commandText(.close)) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 440)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: ExplorerModel

    var body: some View {
        Form {
            Toggle(model.commandText(.hideSidebar), isOn: Binding(
                get: { model.hideRail },
                set: { model.setHideRail($0) }
            ))

            Toggle(model.commandText(.automaticUpdates), isOn: Binding(
                get: { model.autoCheckUpdates },
                set: { model.setAutoCheckUpdates($0) }
            ))

            Picker(model.commandText(.language), selection: Binding(
                get: { model.language },
                set: { model.setLanguage($0) }
            )) {
                ForEach(AppText.supportedLanguages) { language in
                    Text(language.title).tag(language.id)
                }
            }


        }
        .formStyle(.grouped)
        .padding(16)
    }
}

struct AboutView: View {
    @EnvironmentObject private var model: ExplorerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)

            Text(AppMetadata.name)
                .font(.system(size: 22, weight: .semibold))

            Text("Version \(AppMetadata.version)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(AppMetadata.copyright)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Button(model.commandText(.close)) {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .padding(.top, 6)
        }
        .padding(28)
        .frame(width: 360)
    }
}
