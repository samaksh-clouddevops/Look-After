import SwiftUI
import LookAfterCore
import LookAfterAI

/// Manage GLM API keys with rotation, health status, and secure storage.
struct APIKeysSettingsView: View {
    @StateObject private var viewModel = APIKeysSettingsViewModel()
    @State private var showAddSheet = false
    @State private var editingRecord: GLMKeyRecord?
    @State private var openAIKeyDraft = ""
    @State private var openAIStatusMessage: String?
    @AppStorage(SpeechVoiceSettings.openAIKeyConfiguredKey) private var openAIConfigured = false

    var body: some View {
        ZStack {
            PremiumBackground()

            List {
                Section(content: {
                    HStack {
                        Label("OpenAI (cloud voice)", systemImage: "waveform")
                        Spacer()
                        Text(openAIConfigured ? "Configured" : "Missing")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(openAIConfigured ? DesignSystem.success : DesignSystem.warning)
                    }
                    .listRowBackground(DesignSystem.contentSurface)

                    SecureField("Paste OpenAI API key", text: $openAIKeyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .listRowBackground(DesignSystem.contentSurface)

                    Button("Save OpenAI key") {
                        let trimmed = openAIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else {
                            openAIStatusMessage = "Paste a key first."
                            return
                        }
                        if GLMKeyManager.shared.storeOpenAIAPIKey(trimmed) {
                            openAIKeyDraft = ""
                            openAIConfigured = true
                            openAIStatusMessage = "Saved for cloud voice."
                        } else {
                            openAIStatusMessage = "Could not save key to Keychain."
                        }
                    }
                    .listRowBackground(DesignSystem.contentSurface)

                    Button("Sync from ~/ADHD/credentials") {
                        if GLMKeyManager.shared.syncOpenAIDeveloperCredentials() {
                            openAIConfigured = true
                            openAIStatusMessage = "Synced OpenAI key from credentials."
                        } else {
                            openAIConfigured = SpeechVoiceSettings.isOpenAIKeyConfigured
                            openAIStatusMessage = "No openai_api_key found in credentials."
                        }
                    }
                    .listRowBackground(DesignSystem.contentSurface)

                    if let openAIStatusMessage {
                        Text(openAIStatusMessage)
                            .font(.system(size: 12))
                            .foregroundColor(DesignSystem.textSecondary)
                            .listRowBackground(DesignSystem.contentSurface)
                    }
                }, header: {
                    Text("Cloud voice")
                }, footer: {
                    Text("OpenAI TTS uses this key directly. GLM keys below are only for chat/planning.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                })

                if let active = viewModel.activeKey {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "bolt.circle.fill")
                                .foregroundColor(DesignSystem.accentPrimary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Active Key")
                                    .font(.system(size: 13, weight: .semibold, design: .default))
                                Text("\(active.name) · \(active.maskedDisplay)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(DesignSystem.textSecondary)
                            }
                        }
                        .listRowBackground(DesignSystem.contentSurface)
                    }
                }

                if viewModel.allKeysExhausted {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("All keys unavailable", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(DesignSystem.warning)
                            Text(GLMServiceError.allKeysExhausted.errorDescription ?? "All keys are exhausted.")
                                .font(.system(size: 12, design: .default))
                                .foregroundColor(DesignSystem.textSecondary)
                            Button("Retry AI Connection") {
                                Task { await viewModel.retryAllKeys() }
                            }
                            .font(.system(size: 13, weight: .semibold, design: .default))
                        }
                        .listRowBackground(DesignSystem.contentSurface)
                    }
                }

                Section(content: {
                    if viewModel.keys.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No API keys yet")
                                .font(.system(size: 15, weight: .semibold, design: .default))
                            Text("Add one or more API keys. \(UserFacingCopy.productName) rotates automatically when a key hits quota.")
                                .font(.system(size: 12, design: .default))
                                .foregroundColor(DesignSystem.textSecondary)
                        }
                        .listRowBackground(DesignSystem.contentSurface)
                    } else {
                        ForEach(viewModel.keys) { record in
                            keyRow(record)
                                .listRowBackground(DesignSystem.contentSurface)
                        }
                        .onMove(perform: viewModel.moveKeys)
                        .onDelete(perform: viewModel.deleteKeys)
                    }

                    Button(action: { showAddSheet = true }) {
                        Label("Add Key", systemImage: "plus.circle.fill")
                    }
                    .listRowBackground(DesignSystem.contentSurface)
                }, header: {
                    Text("API Keys")
                }, footer: {
                    Text("\(UserFacingCopy.productName) uses GLM 5.3 (z.ai), not Gemini. Old Gemini keys were migrated here but will not work — delete them and add a GLM key.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                })

                if !viewModel.keys.isEmpty {
                    Section(content: {
                        Button("Remove All Keys", role: .destructive) {
                            viewModel.clearAllKeys()
                        }
                        .listRowBackground(DesignSystem.contentSurface)
                    }, footer: {
                        Text("Clears Keychain secrets and legacy Gemini storage. Use this before adding your z.ai GLM key.")
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.textMuted)
                    })
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("API Keys")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            if !viewModel.keys.isEmpty {
                EditButton()
            }
            #endif
        }
        .sheet(isPresented: $showAddSheet) {
            APIKeyEditorSheet(mode: .add) { name, secret in
                viewModel.addKey(name: name, secret: secret)
            }
        }
        .sheet(item: $editingRecord) { record in
            APIKeyEditorSheet(mode: .edit(record)) { name, secret in
                viewModel.updateKey(id: record.id, name: name, secret: secret)
            }
        }
        .onAppear {
            viewModel.refresh()
            openAIConfigured = SpeechVoiceSettings.isOpenAIKeyConfigured
                || GLMKeyManager.shared.syncOpenAIDeveloperCredentials()
        }
        .accessibilityIdentifier("screen-api-keys")
    }

    @ViewBuilder
    private func keyRow(_ record: GLMKeyRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: record.status.iconName)
                    .foregroundColor(statusColor(record.status))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(record.name)
                            .font(.system(size: 15, weight: .semibold, design: .default))
                        if record.isDefault {
                            Text("Default")
                                .font(.system(size: 10, weight: .bold, design: .default))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(DesignSystem.accentPrimary.opacity(0.2)))
                        }
                    }
                    Text(record.maskedDisplay)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(DesignSystem.textSecondary)
                    Text(record.status.label)
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundColor(statusColor(record.status))

                    if let reason = record.lastFailureReason, record.status == .failing || record.status == .exhausted {
                        Text(reason)
                            .font(.system(size: 11, design: .default))
                            .foregroundColor(DesignSystem.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { record.isEnabled },
                    set: { viewModel.setEnabled(record.id, enabled: $0) }
                ))
                .labelsHidden()
            }

            HStack(spacing: 12) {
                if let lastUsed = record.lastUsedAt {
                    metadataLabel("Last used", value: lastUsed.formatted(date: .abbreviated, time: .shortened))
                }
                if let lastSuccess = record.lastSuccessfulRequest {
                    metadataLabel("Last success", value: lastSuccess.formatted(date: .omitted, time: .shortened))
                }
            }

            HStack(spacing: 10) {
                Button("Test") {
                    Task { await viewModel.testKey(record.id) }
                }
                .font(.system(size: 12, weight: .semibold, design: .default))

                Button("Make Default") {
                    viewModel.setDefault(record.id)
                }
                .font(.system(size: 12, weight: .semibold, design: .default))
                .disabled(record.isDefault)

                Button("Edit") {
                    editingRecord = record
                }
                .font(.system(size: 12, weight: .semibold, design: .default))
            }

            if let testMessage = viewModel.testResults[record.id] {
                Text(testMessage)
                    .font(.system(size: 11, design: .default))
                    .foregroundColor(DesignSystem.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func metadataLabel(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .default))
                .foregroundColor(DesignSystem.textMuted)
            Text(value)
                .font(.system(size: 11, design: .default))
                .foregroundColor(DesignSystem.textSecondary)
        }
    }

    private func statusColor(_ status: GLMKeyStatus) -> Color {
        switch status {
        case .active: return DesignSystem.success
        case .disabled: return DesignSystem.textMuted
        case .exhausted: return DesignSystem.warning
        case .failing: return DesignSystem.error
        }
    }
}

@MainActor
final class APIKeysSettingsViewModel: ObservableObject {
    @Published private(set) var keys: [GLMKeyRecord] = []
    @Published private(set) var activeKey: GLMKeyRecord?
    @Published var testResults: [String: String] = [:]
    @Published var allKeysExhausted = false

    private let glm = GLMService.shared

    func refresh() {
        keys = glm.keyManagerAccess.allRecords()
        activeKey = glm.keyManagerAccess.activeKeyDisplay()
        allKeysExhausted = !keys.isEmpty && glm.keyManagerAccess.eligibleKeys().isEmpty
    }

    func addKey(name: String, secret: String) {
        _ = try? glm.keyManagerAccess.addKey(name: name, secret: secret)
        refresh()
    }

    func updateKey(id: String, name: String, secret: String) {
        try? glm.keyManagerAccess.updateKey(id: id, name: name, secret: secret.isEmpty ? nil : secret)
        refresh()
    }

    func deleteKeys(at offsets: IndexSet) {
        for index in offsets {
            let id = keys[index].id
            try? glm.keyManagerAccess.deleteKey(id: id)
        }
        refresh()
    }

    func moveKeys(from source: IndexSet, to destination: Int) {
        var ordered = keys
        ordered.move(fromOffsets: source, toOffset: destination)
        glm.keyManagerAccess.reorderKeys(ids: ordered.map(\.id))
        refresh()
    }

    func setEnabled(_ id: String, enabled: Bool) {
        try? glm.keyManagerAccess.updateKey(id: id, isEnabled: enabled)
        refresh()
    }

    func setDefault(_ id: String) {
        try? glm.keyManagerAccess.updateKey(id: id, isDefault: true)
        refresh()
    }

    func testKey(_ id: String) async {
        let result = await glm.testKey(id: id)
        switch result {
        case .success(let response):
            testResults[id] = "Connected · \(response)"
        case .failure(let error):
            testResults[id] = error.localizedDescription
        }
        refresh()
    }

    func retryAllKeys() async {
        for key in keys {
            glm.keyManagerAccess.resetHealth(for: key.id)
        }
        refresh()
    }

    func clearAllKeys() {
        glm.keyManagerAccess.clearAllKeys()
        testResults = [:]
        refresh()
    }
}

private struct APIKeyEditorSheet: View {
    enum Mode: Identifiable {
        case add
        case edit(GLMKeyRecord)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let record): return record.id
            }
        }

        var title: String {
            switch self {
            case .add: return "Add API Key"
            case .edit: return "Edit API Key"
            }
        }
    }

    let mode: Mode
    let onSave: (String, String) -> Void

    @State private var name = ""
    @State private var secret = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PremiumForm {
                Section(content: {
                    TextField("Label (e.g. Personal, Backup)", text: $name)
                    SecureField("GLM API key", text: $secret)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                }, footer: {
                    if case .edit = mode {
                        Text("Leave the key field blank to keep the existing secret.")
                    } else {
                        Text("Get a key at z.ai")
                    }
                })
            }
            .navigationTitle(mode.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, secret)
                        dismiss()
                    }
                    .disabled(isSaveDisabled)
                }
            }
            .onAppear {
                if case .edit(let record) = mode {
                    name = record.name
                }
            }
            .keyboardDismissToolbar(label: "Done")
        }
    }

    private var isSaveDisabled: Bool {
        switch mode {
        case .add:
            return secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .edit:
            return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
