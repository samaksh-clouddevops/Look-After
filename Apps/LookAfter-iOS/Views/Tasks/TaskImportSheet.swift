import SwiftUI
import UniformTypeIdentifiers
import LookAfterCore
import LookAfterFeatures

/// Import tasks from CSV, text, or Excel using GLM.
struct TaskImportSheet: View {
    
    @ObservedObject var tasksVM: TasksViewModel
    let userId: String
    @Environment(\.dismiss) private var dismiss
    
    @State private var showFilePicker = false
    @State private var showFormatHelp = false
    @State private var importedFileName = ""
    
    private let allowedTypes: [UTType] = [
        .commaSeparatedText,
        .plainText,
        .text,
        UTType(filenameExtension: "csv")!,
        UTType(filenameExtension: "tsv")!,
        UTType(filenameExtension: "xlsx")!,
        UTType(filenameExtension: "xls")!,
        UTType(filenameExtension: "md")!,
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                PremiumBackground()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
                        introCard
                        formatHelpCard
                        
                        if tasksVM.isImporting {
                            importingCard
                        } else if let preview = tasksVM.importPreview {
                            previewCard(preview)
                        } else {
                            pickFileCard
                        }
                        
                        if let error = tasksVM.importError {
                            Text(error)
                                .font(.system(size: 13, design: .default))
                                .foregroundColor(DesignSystem.error)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .elevatedSurface()
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Import Tasks")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        tasksVM.clearImportPreview()
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: allowedTypes,
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
        }
    }
    
    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI reads your file", systemImage: "sparkles")
                .font(.system(size: 15, weight: .bold, design: .default))
                .foregroundColor(DesignSystem.accentPrimary)
            Text("Upload a spreadsheet or text file. The AI will figure out columns, infer priorities, and create tasks for you.")
                .font(.system(size: 13, design: .default))
                .foregroundColor(DesignSystem.textSecondary)
        }
        .padding()
        .elevatedSurface()
    }
    
    private var formatHelpCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: { withAnimation { showFormatHelp.toggle() } }) {
                HStack {
                    Text("Supported formats")
                        .font(.system(size: 14, weight: .semibold, design: .default))
                    Spacer()
                    Image(systemName: showFormatHelp ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(DesignSystem.textPrimary)
            }
            .buttonStyle(.plain)
            
            if showFormatHelp {
                VStack(alignment: .leading, spacing: 8) {
                    formatRow("CSV / Excel (.xlsx)", "Columns like title, priority, due date — headers optional")
                    formatRow("Plain text (.txt)", "One task per line, or bullet/numbered lists")
                    formatRow("Example CSV", "title,priority,minutes\nPay rent,High,15\nCall dentist,Medium,10")
                }
                .font(.system(size: 12, design: .default))
                .foregroundColor(DesignSystem.textSecondary)
            }
        }
        .padding()
        .elevatedSurface()
    }
    
    private func formatRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).fontWeight(.semibold).foregroundColor(DesignSystem.textPrimary)
            Text(detail)
        }
    }
    
    private var pickFileCard: some View {
        Button(action: { showFilePicker = true }) {
            VStack(spacing: 12) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 36))
                    .foregroundColor(DesignSystem.textMuted)
                Text("Choose File")
                    .font(.system(size: 17, weight: .bold, design: .default))
                Text(".csv, .txt, .xlsx supported")
                    .font(.system(size: 12, design: .default))
                    .foregroundColor(DesignSystem.textMuted)
            }
            .foregroundColor(DesignSystem.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .elevatedSurface()
        }
        .buttonStyle(.plain)
    }
    
    private var importingCard: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(DesignSystem.accentPrimary)
            Text("AI is reading your file…")
                .font(.system(size: 15, weight: .semibold, design: .default))
            if !importedFileName.isEmpty {
                Text(importedFileName)
                    .font(.system(size: 12, design: .default))
                    .foregroundColor(DesignSystem.textMuted)
            }
            Text("Finding tasks, inferring priorities & time estimates")
                .font(.system(size: 12, design: .default))
                .foregroundColor(DesignSystem.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .elevatedSurface()
    }
    
    private func previewCard(_ preview: TaskImportResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(preview.tasks.count) tasks found")
                        .font(.system(size: 17, weight: .bold, design: .default))
                    Text(preview.notes)
                        .font(.system(size: 12, design: .default))
                        .foregroundColor(DesignSystem.textSecondary)
                }
                Spacer()
                Button("Pick another") {
                    tasksVM.clearImportPreview()
                    showFilePicker = true
                }
                .font(.system(size: 12, weight: .semibold, design: .default))
            }
            
            ForEach(preview.tasks) { task in
                ImportTaskRowView(task: task) { selected in
                    guard var updated = tasksVM.importPreview,
                          let index = updated.tasks.firstIndex(where: { $0.id == task.id }) else { return }
                    updated.tasks[index].selected = selected
                    tasksVM.importPreview = updated
                }
            }
            
            let selectedCount = preview.tasks.filter(\.selected).count
            Button(action: {
                HapticManager.notification(.success)
                tasksVM.confirmImport(userId: userId)
                dismiss()
            }) {
                HStack {
                    Spacer()
                    Image(systemName: "square.and.arrow.down.fill")
                    Text("Import \(selectedCount) Task\(selectedCount == 1 ? "" : "s")")
                        .font(.system(size: 15, weight: .bold, design: .default))
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.vertical, 14)
                .background(Capsule().fill(DesignSystem.accentGradient))
            }
            .disabled(selectedCount == 0)
            .buttonStyle(.plain)
        }
        .padding()
        .elevatedSurface()
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importedFileName = url.lastPathComponent
            
            guard url.startAccessingSecurityScopedResource() else {
                tasksVM.importError = "Could not access the selected file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let data = try Data(contentsOf: url)
                Task {
                    await tasksVM.previewImport(from: data, fileName: url.lastPathComponent)
                }
            } catch {
                tasksVM.importError = error.localizedDescription
            }
            
        case .failure(let error):
            tasksVM.importError = error.localizedDescription
        }
    }
}

private struct ImportTaskRowView: View {
    let task: ImportedTaskDraft
    let onToggle: (Bool) -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.spacingSM) {
            Toggle("", isOn: Binding(
                get: { task.selected },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            .tint(DesignSystem.accentPrimary)
            .layoutPriority(1)
            
            VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                Text(task.title)
                    .font(.dsBody(weight: .semibold))
                    .foregroundColor(DesignSystem.textPrimary)
                    .dsPrimaryText(lineLimit: 2)
                
                MetadataTagRow(tags: [
                    TagChipView(task.priority.label, icon: task.priority.icon),
                    TagChipView(task.lifeArea.rawValue, icon: task.lifeArea.icon),
                    TagChipView("~\(task.estimatedMinutes)m")
                ])
                
                if !task.description.isEmpty {
                    Text(task.description)
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textSecondary)
                        .dsPrimaryText(lineLimit: 2)
                }
            }
            .layoutPriority(0)
        }
        .padding(.vertical, DesignSystem.spacingXS)
        .accessibilityIdentifier("screen-task-import")
    }
}
