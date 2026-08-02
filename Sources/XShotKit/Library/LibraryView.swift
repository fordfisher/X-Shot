import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public final class LibraryViewModel: ObservableObject {
    @Published public var shots: [Shot] = []
    @Published public var searchText: String = ""
    @Published public var annotatedOnly: Bool = false
    @Published public var selection: Set<UUID> = []

    public let store: LibraryStore
    private var thumbnailCache: [UUID: NSImage] = [:]
    /// Bumped whenever cached previews change so SwiftUI redraws cards.
    @Published public private(set) var previewRevision: Int = 0

    public init(store: LibraryStore) {
        self.store = store
        reload()
    }

    public var filteredShots: [Shot] {
        shots.filter { shot in
            if annotatedOnly && !shot.hasAnnotations { return false }
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty { return true }
            let hay = "\(shot.title) \(shot.createdAt.formatted()) \(shot.width)x\(shot.height)".lowercased()
            return hay.contains(q.lowercased())
        }
    }

    public func reload() {
        shots = (try? store.fetchAll()) ?? []
        selection = selection.intersection(Set(shots.map(\.id)))
        let living = Set(shots.map(\.id))
        thumbnailCache = thumbnailCache.filter { living.contains($0.key) }
    }

    /// Call after a shot's image/annotations change on disk (e.g. editor Save).
    public func refreshShot(id: UUID) {
        thumbnailCache.removeValue(forKey: id)
        reload()
        previewRevision += 1
    }

    /// Downsampled preview so grid layout never sees full-resolution intrinsic sizes.
    public func thumbnail(for shot: Shot) -> NSImage? {
        if let cached = thumbnailCache[shot.id] { return cached }
        guard let data = try? store.loadImageData(id: shot.id),
              let image = NSImage(data: data),
              let thumb = Self.downsampled(image, maxPixel: 480) else { return nil }
        thumbnailCache[shot.id] = thumb
        return thumb
    }

    private static func downsampled(_ image: NSImage, maxPixel: CGFloat) -> NSImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let longest = max(size.width, size.height)
        let scale = min(1, maxPixel / longest)
        let target = NSSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let out = NSImage(size: target)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .medium
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1
        )
        out.unlockFocus()
        return out
    }

    public func delete(_ shot: Shot) {
        try? store.delete(id: shot.id)
        selection.remove(shot.id)
        reload()
    }

    public func deleteSelected() {
        for id in selection {
            try? store.delete(id: id)
        }
        selection.removeAll()
        reload()
    }

    public func copyToClipboard(_ shot: Shot) {
        guard let data = try? store.loadImageData(id: shot.id),
              let image = NSImage(data: data) else { return }
        ScreenCaptureService.copyToClipboard(image)
    }

    public func export(_ shot: Shot) {
        guard let data = try? store.loadImageData(id: shot.id) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "XShot-\(Int(shot.createdAt.timeIntervalSince1970)).png"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url, options: .atomic)
        }
    }

    public func exportSelected() {
        let ids = selection
        guard !ids.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for \(ids.count) PNG file(s)"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        for id in ids {
            guard let shot = shots.first(where: { $0.id == id }),
                  let data = try? store.loadImageData(id: id) else { continue }
            let name = "XShot-\(shot.createdAt.timeIntervalSince1970).png"
            try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
        }
    }

    public func reveal(_ shot: Shot) {
        NSWorkspace.shared.activateFileViewerSelecting([store.imageURL(for: shot.id)])
    }

    public func revealLibraryFolder() {
        NSWorkspace.shared.open(store.rootURL)
    }

    public func selectAllFiltered() {
        selection = Set(filteredShots.map(\.id))
    }

    public func clearSelection() {
        selection.removeAll()
    }

    public func toggleSelection(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }
}

public struct LibraryView: View {
    @ObservedObject var model: LibraryViewModel
    var onOpen: (Shot) -> Void
    var onCapture: () -> Void

    public init(model: LibraryViewModel, onOpen: @escaping (Shot) -> Void, onCapture: @escaping () -> Void = {}) {
        self.model = model
        self.onOpen = onOpen
        self.onCapture = onCapture
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            toolbar
            Divider()
            if model.shots.isEmpty {
                emptyState
            } else if model.filteredShots.isEmpty {
                filteredEmpty
            } else {
                GeometryReader { geo in
                    let columnWidth: CGFloat = 200
                    let spacing: CGFloat = 18
                    let count = max(2, Int((geo.size.width - 48 + spacing) / (columnWidth + spacing)))
                    let columns = Array(repeating: GridItem(.flexible(minimum: 160), spacing: spacing), count: count)
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: spacing) {
                            ForEach(model.filteredShots) { shot in
                                shotCard(shot)
                                    .id("\(shot.id.uuidString)-\(shot.hasAnnotations)-\(model.previewRevision)")
                            }
                        }
                        .padding(24)
                    }
                }
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: NSColor(xshotHex: "#F7F8FA")),
                    Color(nsColor: NSColor(xshotHex: XShotTheme.workspaceHex))
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onAppear { model.reload() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("X-Shot")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(Color(nsColor: NSColor(xshotHex: XShotTheme.textHex)))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color(nsColor: NSColor(xshotHex: XShotTheme.mutedHex)))
            }
            Spacer()
            Button {
                onCapture()
            } label: {
                Label("Capture", systemImage: "camera.viewfinder")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(nsColor: NSColor(xshotHex: XShotTheme.accentHex)))
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private var subtitle: String {
        let shown = model.filteredShots.count
        let total = model.shots.count
        if shown == total {
            return "Local library — \(total) capture\(total == 1 ? "" : "s")"
        }
        return "Showing \(shown) of \(total)"
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField("Search…", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)

            Toggle("Annotated", isOn: $model.annotatedOnly)
                .toggleStyle(.checkbox)

            Spacer()

            if !model.selection.isEmpty {
                Text("\(model.selection.count) selected")
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: NSColor(xshotHex: XShotTheme.mutedHex)))

                Button("Copy") { copyFirstSelected() }
                    .disabled(model.selection.count != 1)
                Button("Export…") { model.exportSelected() }
                Button("Delete", role: .destructive) { confirmDeleteSelected() }
                Button("Clear") { model.clearSelection() }
            }

            Menu {
                Button("Select All") { model.selectAllFiltered() }
                Button("Clear Selection") { model.clearSelection() }
                Divider()
                Button("Reveal Library Folder") { model.revealLibraryFolder() }
                Button("Refresh") { model.reload() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("X-Shot")
                .font(.system(size: 42, weight: .bold, design: .serif))
                .foregroundStyle(Color(nsColor: NSColor(xshotHex: XShotTheme.textHex)))
            Text("Press ⇧⌘4 to capture a region.\nIt lands here, on your clipboard, and in the editor.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(nsColor: NSColor(xshotHex: XShotTheme.mutedHex)))
                .frame(maxWidth: 380)
            Button("Capture Region") { onCapture() }
                .buttonStyle(.borderedProminent)
                .tint(Color(nsColor: NSColor(xshotHex: XShotTheme.accentHex)))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredEmpty: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("No matches")
                .font(.title3.weight(.semibold))
            Text("Try another search or clear filters.")
                .foregroundStyle(Color(nsColor: NSColor(xshotHex: XShotTheme.mutedHex)))
            Button("Clear filters") {
                model.searchText = ""
                model.annotatedOnly = false
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func shotCard(_ shot: Shot) -> some View {
        let selected = model.selection.contains(shot.id)
        return VStack(alignment: .leading, spacing: 8) {
            thumbnailBlock(shot: shot, selected: selected)

            Text(shot.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(Color(nsColor: NSColor(xshotHex: XShotTheme.textHex)))
                .lineLimit(1)
            Text("\(shot.width)×\(shot.height)" + (shot.hasAnnotations ? " · annotated" : ""))
                .font(.caption2)
                .foregroundStyle(Color(nsColor: NSColor(xshotHex: XShotTheme.mutedHex)))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen(shot) }
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) {
                model.toggleSelection(shot.id)
            } else {
                model.selection = [shot.id]
            }
        }
        .contextMenu {
            Button("Open in Editor") { onOpen(shot) }
            Button("Copy Image") { model.copyToClipboard(shot) }
            Button("Export…") { model.export(shot) }
            Button("Reveal in Finder") { model.reveal(shot) }
            Divider()
            Button(selected ? "Deselect" : "Select") { model.toggleSelection(shot.id) }
            Divider()
            Button("Delete", role: .destructive) { model.delete(shot) }
        }
    }

    /// Thumbnail container that never contributes image intrinsic size to the grid.
    private func thumbnailBlock(shot: Shot, selected: Bool) -> some View {
        Color.white
            .frame(height: 140)
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { geo in
                    if let image = model.thumbnail(for: shot) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.medium)
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(nsColor: NSColor(xshotHex: XShotTheme.accentHex)))
                        .padding(8)
                        .shadow(radius: 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .clipped()
            .compositingGroup()
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        selected
                            ? Color(nsColor: NSColor(xshotHex: XShotTheme.accentHex))
                            : Color(nsColor: NSColor(xshotHex: XShotTheme.borderHex)),
                        lineWidth: selected ? 2 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    private func copyFirstSelected() {
        guard let id = model.selection.first,
              let shot = model.shots.first(where: { $0.id == id }) else { return }
        model.copyToClipboard(shot)
    }

    private func confirmDeleteSelected() {
        let alert = NSAlert()
        alert.messageText = "Delete \(model.selection.count) capture(s)?"
        alert.informativeText = "This removes images from your local X-Shot library. It cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            model.deleteSelected()
        }
    }
}
