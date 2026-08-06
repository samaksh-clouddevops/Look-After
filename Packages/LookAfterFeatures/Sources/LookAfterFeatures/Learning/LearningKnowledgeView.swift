import SwiftUI
import Combine
import LookAfterCore

// MARK: - ViewModel

@MainActor
public final class LearningViewModel: ObservableObject {
    @Published public var nodes: [KnowledgeNote] = []
    private let persistenceKey = "lifeos_learning_notes"
    
    public init() {
        loadFromDisk()
    }
    
    public func addNote(_ note: KnowledgeNote) {
        nodes.append(note)
        saveToDisk()
    }
    
    public func deleteNote(at offsets: IndexSet) {
        nodes.remove(atOffsets: offsets)
        saveToDisk()
    }
    
    public func deleteNote(_ note: KnowledgeNote) {
        nodes.removeAll { $0.id == note.id }
        saveToDisk()
    }
    
    private func saveToDisk() {
        if let data = try? JSONEncoder().encode(nodes) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }
    
    private func loadFromDisk() {
        if let data = UserDefaults.standard.data(forKey: persistenceKey),
           let saved = try? JSONDecoder().decode([KnowledgeNote].self, from: data) {
            nodes = saved
        }
    }
}

// MARK: - View

public struct LearningKnowledgeView: View {
    @StateObject private var viewModel = LearningViewModel()
    @State private var showAddSheet = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            PremiumBackground()
            
            VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Learning & Knowledge")
                            .font(.system(size: 28, weight: .bold, design: .default))
                            .foregroundColor(DesignSystem.textPrimary)
                        
                        Text("Your personalized neural library.")
                            .font(.system(size: 15, weight: .medium, design: .default))
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                    Spacer()
                    Button(action: { showAddSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                
                if viewModel.nodes.isEmpty {
                    EmptyStateView(
                        icon: "books.vertical.fill",
                        title: "No Knowledge Notes Yet",
                        subtitle: "Capture concepts, articles, book highlights, and learning milestones.",
                        actionTitle: "Add Knowledge Note",
                        onAction: { showAddSheet = true }
                    )
                } else {
                    ScrollView {
                        VStack(spacing: DesignSystem.spacingMD) {
                            ForEach(viewModel.nodes) { node in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(node.title)
                                            .font(.system(size: 18, weight: .bold, design: .default))
                                            .foregroundColor(DesignSystem.textPrimary)
                                        Spacer()
                                        Button(action: {
                                            HapticManager.notification(.warning)
                                            viewModel.deleteNote(node)
                                        }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(DesignSystem.error)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Remove note")
                                    }
                                    
                                    Text(node.content)
                                        .font(.system(size: 14, weight: .regular, design: .default))
                                        .foregroundColor(DesignSystem.textSecondary)
                                        .lineLimit(3)
                                    
                                    if !node.tags.isEmpty {
                                        HStack {
                                            ForEach(node.tags, id: \.self) { tag in
                                                Text(tag)
                                                    .font(.system(size: 11, weight: .semibold, design: .default))
                                                    .foregroundColor(DesignSystem.accentPrimary)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(DesignSystem.accentPrimary.opacity(0.15))
                                                    .cornerRadius(6)
                                            }
                                        }
                                        .padding(.top, 4)
                                    }
                                    
                                    if !node.source.isEmpty {
                                        Label(node.source, systemImage: mediaIcon(for: node.source))
                                            .font(.system(size: 11, weight: .medium, design: .default))
                                            .foregroundColor(DesignSystem.textMuted)
                                            .padding(.top, 2)
                                    }
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(16)
                                .padding(.horizontal)
                                .contextMenu {
                                    Button(role: .destructive, action: {
                                        HapticManager.notification(.warning)
                                        viewModel.deleteNote(node)
                                    }, label: {
                                        Label("Remove", systemImage: "trash")
                                    })
                                }
                            }
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddKnowledgeNoteSheet(viewModel: viewModel)
        }
    }
    
    private func mediaIcon(for format: String) -> String {
        switch format {
        case "Book": return "book.fill"
        case "Podcast": return "mic.fill"
        case "Video": return "play.rectangle.fill"
        case "Course": return "graduationcap.fill"
        default: return "doc.text.fill"
        }
    }
}

// MARK: - Add Knowledge Note Sheet

struct AddKnowledgeNoteSheet: View {
    @ObservedObject var viewModel: LearningViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = ""
    @State private var content = ""
    @State private var tagInput = ""
    @State private var mediaFormat = "Article"
    @State private var isCreating = false
    
    private let mediaFormats = ["Book", "Article", "Podcast", "Video", "Course", "Notes"]
    
    var body: some View {
        NavigationStack {
            PremiumForm {
                Section("Note Title") {
                    TextField("Title (e.g. System Design Principles)", text: $title)
                        .font(.system(.body, design: .default))
                }
                Section("Content / Summary") {
                    TextField("Write your notes or insights...", text: $content, axis: .vertical)
                        .font(.system(.body, design: .default))
                        .lineLimit(4...8)
                }
                Section("Media Format") {
                    Picker("Format", selection: $mediaFormat) {
                        ForEach(mediaFormats, id: \.self) { format in
                            Text(format).tag(format)
                        }
                    }
                }
                Section("Tags (comma separated)") {
                    TextField("e.g. Architecture, SwiftUI, AI", text: $tagInput)
                        .font(.system(.body, design: .default))
                }
            }
            .navigationTitle("New Knowledge Note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        guard !title.isEmpty else { return }
                        isCreating = true
                        let tags = tagInput.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        let note = KnowledgeNote(title: title, content: content, source: mediaFormat, tags: tags)
                        viewModel.addNote(note)
                        HapticManager.notification(.success)
                        dismiss()
                    }) {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
        }
    }
}
