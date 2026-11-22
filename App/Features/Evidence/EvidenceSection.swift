import FrameworkKit
import PhotosUI
import QuickLook
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Evidence attached to a requirement: notes, links, photos, and files stored on this device.
struct EvidenceSection: View {
    @Bindable var assessment: Assessment
    let ref: RequirementRef

    @Environment(\.modelContext) private var context
    @State private var editor: EvidenceEditorKind?
    @State private var showingPhotoPicker = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showingFileImporter = false
    @State private var showingCamera = false
    @State private var previewURL: URL?
    @State private var errorMessage: String?
    @State private var pendingDeletion: EvidenceItem?

    private var service: AssessmentService { AssessmentService(context: context) }
    private var items: [EvidenceItem] { assessment.response(for: ref)?.sortedEvidence ?? [] }

    var body: some View {
        Section {
            if items.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("No evidence yet")
                        .font(.dsBody)
                        .foregroundStyle(Color.dsTextSecondary)
                    Text("Add a note, a link, a photo, or a file that shows this requirement is in place. Evidence stays on this device.")
                        .font(.dsFootnote)
                        .foregroundStyle(Color.dsTextTertiary)
                }
                .padding(.vertical, DS.Space.xxs)
            }
            ForEach(items) { item in
                EvidenceRow(item: item, assessmentID: assessment.id) { open(item) }
                    .swipeActions {
                        Button(role: .destructive) { pendingDeletion = item } label: { Label("Delete", systemImage: "trash") }
                    }
                    .contextMenu { contextMenu(for: item) }
            }
            addMenu
        } header: {
            SectionHeader("Evidence")
        } footer: {
            if let errorMessage {
                Text(errorMessage).font(.dsFootnote).foregroundStyle(Color.dsDestructive)
            }
        }
    }

    // MARK: Add

    private var addMenu: some View {
        Menu {
            Button { editor = .note } label: { Label("Note", systemImage: "text.alignleft") }
            Button { editor = .link } label: { Label("Link", systemImage: "link") }
            Button { showingPhotoPicker = true } label: { Label("Photo Library", systemImage: "photo.on.rectangle") }
            if CameraPicker.isAvailable {
                Button { showingCamera = true } label: { Label("Take Photo", systemImage: "camera") }
            }
            Button { showingFileImporter = true } label: { Label("File", systemImage: "folder") }
        } label: {
            Label("Add Evidence", systemImage: "plus.circle")
                .font(.dsBody)
        }
        .keyboardShortcut("e", modifiers: .command)
        .accessibilityIdentifier("addEvidence")
        .sheet(item: $editor) { kind in
            EvidenceEditorSheet(kind: kind) { title, body in
                switch kind {
                case .note: service.addNote(title: title, text: body, to: ref, in: assessment)
                case .link:
                    if let url = URL(string: body) { service.addLink(title: title, url: url, to: ref, in: assessment) }
                }
            }
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoSelection, maxSelectionCount: 10,
                      matching: .images, photoLibrary: .shared())
        .onChange(of: photoSelection) { _, picked in
            guard !picked.isEmpty else { return }
            Task { await importPhotos(picked) }
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): urls.forEach(importFile(at:))
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in
                if let data = image.jpegData(compressionQuality: 0.85) { savePhoto(data, ext: "jpg", name: "Photo.jpg") }
            }
            .ignoresSafeArea()
        }
        .quickLookPreview($previewURL)
        .confirmationDialog("Delete this evidence?", isPresented: Binding(
            get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }
        ), titleVisibility: .visible, presenting: pendingDeletion) { item in
            Button("Delete", role: .destructive) { service.remove(item, from: ref, in: assessment) }
        } message: { item in
            Text(item.kind == .file ? "The stored copy of \(item.title) is removed from this device." : "\(item.title) is removed.")
        }
    }

    @ViewBuilder
    private func contextMenu(for item: EvidenceItem) -> some View {
        if item.kind == .file, let name = item.storedFileName,
           let url = EvidenceFileStore.url(forStoredFile: name, assessmentID: assessment.id) {
            Button { previewURL = url } label: { Label("Preview", systemImage: "eye") }
            ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
        }
        if item.kind == .link, let url = URL(string: item.urlString) {
            ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
        }
        Button(role: .destructive) { pendingDeletion = item } label: { Label("Delete", systemImage: "trash") }
    }

    // MARK: Actions

    private func open(_ item: EvidenceItem) {
        switch item.kind {
        case .file:
            if let name = item.storedFileName { previewURL = EvidenceFileStore.url(forStoredFile: name, assessmentID: assessment.id) }
        case .link:
            if let url = URL(string: item.urlString) { UIApplication.shared.open(url) }
        case .note:
            break
        }
    }

    func importFile(at url: URL) {
        do {
            let stored = try EvidenceFileStore.importFile(at: url, assessmentID: assessment.id)
            service.addFile(stored, to: ref, in: assessment)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func savePhoto(_ data: Data, ext: String, name: String) {
        do {
            let stored = try EvidenceFileStore.save(data, fileExtension: ext, originalFileName: name, assessmentID: assessment.id)
            service.addFile(stored, title: "Photo, \(Date.now.formatted(date: .abbreviated, time: .shortened))", to: ref, in: assessment)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importPhotos(_ picked: [PhotosPickerItem]) async {
        for item in picked {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let type = item.supportedContentTypes.first
                let ext = type?.preferredFilenameExtension ?? "jpg"
                savePhoto(data, ext: ext, name: "Photo.\(ext)")
            } else {
                errorMessage = "A photo could not be loaded. It may still be downloading from iCloud."
            }
        }
        photoSelection = []
    }
}

private struct EvidenceRow: View {
    let item: EvidenceItem
    let assessmentID: UUID
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: DS.Space.s) {
                Image(systemName: symbol)
                    .font(.dsBody)
                    .foregroundStyle(Color.dsAccent)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.dsBody).foregroundStyle(Color.dsTextPrimary).lineLimit(2)
                    Text(subtitle).font(.dsFootnote).foregroundStyle(Color.dsTextSecondary).lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.kind == .file ? "Opens a preview" : item.kind == .link ? "Opens the link" : "")
    }

    private var symbol: String {
        if item.kind == .file, let id = item.contentTypeIdentifier, let type = UTType(id) {
            if type.conforms(to: .image) { return "photo" }
            if type.conforms(to: .pdf) { return "doc.richtext" }
        }
        return item.kind.systemImage
    }

    private var subtitle: String {
        let date = item.createdAt.formatted(date: .abbreviated, time: .omitted)
        switch item.kind {
        case .note: return item.text.isEmpty ? date : item.text
        case .link: return URL(string: item.urlString)?.host() ?? item.urlString
        case .file:
            let size = ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file)
            return "\(size) · Added \(date)"
        }
    }
}

enum EvidenceEditorKind: String, Identifiable {
    case note, link
    var id: String { rawValue }
}

/// Adds a text note or a link.
struct EvidenceEditorSheet: View {
    let kind: EvidenceEditorKind
    let onSave: (_ title: String, _ body: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""

    private var normalizedURL: URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "https://" + s }
        guard let url = URL(string: s), url.host() != nil else { return nil }
        return url
    }

    private var canSave: Bool {
        kind == .note ? !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : normalizedURL != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title, prompt: Text(kind == .note ? "For example: Access review, March" : "For example: Password policy"))
                    if kind == .note {
                        TextField("Note", text: $text, axis: .vertical).lineLimit(5...15)
                    } else {
                        TextField("Address", text: $text, prompt: Text("https://"))
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } footer: {
                    Text(kind == .note
                         ? "Describe what you checked, when, and what you found."
                         : "Link to a document or page your organization controls, such as a policy on your intranet. The app does not open or store the page.")
                        .font(.dsFootnote)
                }
            }
            .navigationTitle(kind == .note ? "Add Note" : "Add Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(title.trimmingCharacters(in: .whitespacesAndNewlines),
                               kind == .note ? text.trimmingCharacters(in: .whitespacesAndNewlines) : normalizedURL?.absoluteString ?? text)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A file dropped onto the requirement (iPad drag and drop), copied to a temporary location.
struct EvidenceDropFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .item) { received in
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return EvidenceDropFile(url: dest)
        }
    }
}

/// Camera capture for photo evidence.
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
