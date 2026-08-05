import SwiftUI
import Combine
import LookAfterCore

// MARK: - ViewModel

@MainActor
public final class CreativityViewModel: ObservableObject {
    @Published public var projects: [CreativeProject] = []
    private let persistenceKey = "lifeos_creative_projects"
    
    public init() {
        loadFromDisk()
    }
    
    public func addProject(_ project: CreativeProject) {
        projects.append(project)
        saveToDisk()
    }
    
    public func deleteProject(at offsets: IndexSet) {
        projects.remove(atOffsets: offsets)
        saveToDisk()
    }
    
    public func deleteProject(_ project: CreativeProject) {
        projects.removeAll { $0.id == project.id }
        saveToDisk()
    }
    
    public func updateProgress(for project: CreativeProject, progress: Double) {
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx].progress = progress
            projects[idx].lastOpened = Date()
            projects[idx].status = statusForProgress(progress)
            saveToDisk()
        }
    }
    
    private func statusForProgress(_ progress: Double) -> String {
        switch progress {
        case 0..<0.1: return "Ideation"
        case 0.1..<0.7: return "In Progress"
        case 0.7..<1.0: return "Review"
        default: return "Complete"
        }
    }
    
    private func saveToDisk() {
        if let data = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }
    
    private func loadFromDisk() {
        if let data = UserDefaults.standard.data(forKey: persistenceKey),
           let saved = try? JSONDecoder().decode([CreativeProject].self, from: data) {
            projects = saved
        }
    }
}

// MARK: - View

public struct CreativityWorkspaceView: View {
    @StateObject private var viewModel = CreativityViewModel()
    @State private var showAddSheet = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            PremiumBackground()
            
            VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Music & Creativity")
                            .font(.system(size: 28, weight: .bold, design: .default))
                            .foregroundColor(DesignSystem.textPrimary)
                        
                        Text("Enter creative flow states instantly.")
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
                
                if viewModel.projects.isEmpty {
                    EmptyStateView(
                        icon: "paintpalette.fill",
                        title: "No Creative Projects Yet",
                        subtitle: "Track audio productions, design kits, writing, and creative endeavors.",
                        actionTitle: "New Project",
                        onAction: { showAddSheet = true }
                    )
                } else {
                    ScrollView {
                        VStack(spacing: DesignSystem.spacingMD) {
                            ForEach(viewModel.projects) { project in
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text(project.title)
                                            .font(.system(size: 18, weight: .bold, design: .default))
                                            .foregroundColor(DesignSystem.textPrimary)
                                        Spacer()
                                        Button(action: {
                                            HapticManager.notification(.warning)
                                            viewModel.deleteProject(project)
                                        }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(DesignSystem.error)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Remove project")
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 20))
                                            .foregroundColor(DesignSystem.accentPrimary)
                                    }
                                    
                                    HStack {
                                        Text(project.medium)
                                            .font(.system(size: 14, weight: .medium, design: .default))
                                            .foregroundColor(DesignSystem.textSecondary)
                                        if let dayCount = project.dayCount {
                                            Text("· \(dayCount) days")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(DesignSystem.textMuted)
                                        }
                                        Spacer()
                                        Text(project.status)
                                            .font(.system(size: 11, weight: .bold, design: .default))
                                            .foregroundColor(DesignSystem.accentPrimary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Capsule().fill(DesignSystem.accentPrimary.opacity(0.15)))
                                    }

                                    if project.deadline != nil || project.lifeArea != nil {
                                        HStack(spacing: 8) {
                                            if let area = project.lifeArea {
                                                Text(area.rawValue)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundColor(DesignSystem.textMuted)
                                            }
                                            if let deadline = project.deadline {
                                                Text("Due \(deadline.formatted(date: .abbreviated, time: .omitted))")
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundColor(DesignSystem.textMuted)
                                            }
                                        }
                                    }
                                    
                                    HStack {
                                        Spacer()
                                        Text("\(Int(project.progress * 100))% Complete")
                                            .font(.system(size: 12, weight: .semibold, design: .default))
                                            .foregroundColor(DesignSystem.accentPrimary)
                                    }
                                    
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule()
                                                .fill(Color.white.opacity(0.1))
                                                .frame(height: 6)
                                            
                                            Capsule()
                                                .fill(DesignSystem.accentGradient)
                                                .frame(width: max(0, geo.size.width * project.progress), height: 6)
                                        }
                                    }
                                    .frame(height: 6)
                                }
                                .padding()
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(16)
                                .padding(.horizontal)
                                .contextMenu {
                                    Button(role: .destructive, action: {
                                        HapticManager.notification(.warning)
                                        viewModel.deleteProject(project)
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
            AddCreativeProjectSheet(viewModel: viewModel)
        }
    }
}

// MARK: - Add Creative Project Sheet

struct AddCreativeProjectSheet: View {
    @ObservedObject var viewModel: CreativityViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = ""
    @State private var medium = "Ableton Live"
    @State private var status = "Ideation"
    @State private var progress: Double = 0.1
    @State private var isCreating = false
    
    private let mediums = ["Ableton Live", "Figma", "Logic Pro", "Xcode / Swift", "Blender", "Writing / Prose", "Other"]
    
    var body: some View {
        NavigationStack {
            PremiumForm {
                Section("Project Title") {
                    TextField("Title (e.g. Ambient EP, Design Kit)", text: $title)
                        .font(.system(.body, design: .default))
                }
                Section("Medium / Tool") {
                    Picker("Medium", selection: $medium) {
                        ForEach(mediums, id: \.self) { tool in
                            Text(tool).tag(tool)
                        }
                    }
                }
                Section("Status") {
                    Picker("Status", selection: $status) {
                        ForEach(CreativeProject.statusOptions, id: \.self) { s in
                            Text(s).tag(s)
                        }
                    }
                }
                Section("Initial Progress: \(Int(progress * 100))%") {
                    Slider(value: $progress, in: 0.0...1.0, step: 0.05)
                        .tint(DesignSystem.accentPrimary)
                }
            }
            .navigationTitle("New Creative Project")
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
                        let proj = CreativeProject(title: title, medium: medium, status: status, lastOpened: Date(), progress: progress)
                        viewModel.addProject(proj)
                        HapticManager.notification(.success)
                        dismiss()
                    }) {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
        }
    }
}
