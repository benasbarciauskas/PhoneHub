import Foundation
import PhoneHubCore
import SwiftUI
import UniformTypeIdentifiers

struct TextSourcesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: TextSourceStore

    @State private var showingImporter = false
    @State private var importError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            HStack {
                Text("Text Sources").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Button("Import…") { showingImporter = true }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }

            Text("Static sources reuse one item. Cycle sources consume one item per successful automation run.")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
                .fixedSize(horizontal: false, vertical: true)

            if store.sources.isEmpty {
                ContentUnavailableView(
                    "No Text Sources",
                    systemImage: "text.badge.plus",
                    description: Text("Import a UTF-8 .txt, .json, or .xml file.")
                )
            } else {
                List {
                    ForEach(store.sources) { source in
                        sourceRow(source)
                    }
                }
                .listStyle(.inset)
            }

            if let importError {
                Text(importError)
                    .font(.caption)
                    .foregroundStyle(Theme.err)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.s4)
        .frame(width: 520, height: 480)
        .background(Theme.surface)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.plainText, .json, .xml],
            allowsMultipleSelection: false,
            onCompletion: importFiles
        )
    }

    private func sourceRow(_ source: TextSource) -> some View {
        HStack(spacing: Theme.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name).font(.system(size: 13, weight: .medium))
                Text("\(source.items.count) item\(source.items.count == 1 ? "" : "s") · \(position(source))")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
            }
            Spacer()
            Picker("Mode", selection: Binding(
                get: { source.mode },
                set: { mode in
                    var updated = source
                    updated.mode = mode
                    store.update(updated)
                }
            )) {
                Text("Static").tag(TextSourceMode.static)
                Text("Cycle").tag(TextSourceMode.cycle)
            }
            .labelsHidden()
            .frame(width: 90)
            Button("Reset") { store.resetCursor(source.id) }
                .disabled(source.cursor == 0)
            Button(role: .destructive) { store.delete(source.id) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Theme.s1)
    }

    private func position(_ source: TextSource) -> String {
        source.mode == .static
            ? "static"
            : "next \(source.normalizedCursor + 1) of \(source.items.count)"
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            try importFile(url)
            importError = nil
        } catch {
            importError = "Import failed: \(error.localizedDescription)"
        }
    }

    private func importFile(_ url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let format: TextSourceFormat
        switch url.pathExtension.lowercased() {
        case "txt": format = .plainText
        case "json": format = .json
        case "xml": format = .xml
        default: throw TextSourceParseError.invalidStructure
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
        if let size = values.fileSize, size > TextSourceParser.maximumBytes {
            throw TextSourceParseError.fileTooLarge
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: TextSourceParser.maximumBytes + 1) ?? Data()
        let items = try TextSourceParser.parse(data: data, format: format)
        let rawName = url.deletingPathExtension().lastPathComponent
        _ = try store.add(
            name: rawName.isEmpty ? "Imported source" : rawName,
            items: items,
            mode: items.count > 1 ? .cycle : .static
        )
    }
}
