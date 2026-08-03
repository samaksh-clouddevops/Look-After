import SwiftUI
import LookAfterCore
import LookAfterAI

/// Developer settings for GLM API configuration and usage.
struct GLMConfigurationSettingsView: View {
    @StateObject private var viewModel = GLMConfigurationSettingsViewModel()

    var body: some View {
        ZStack {
            PremiumBackground()

            List {
                Section {
                    TextField("Base URL", text: $viewModel.baseURL)
                        .font(.system(size: 13, design: .monospaced))
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .onSubmit { viewModel.save() }
                        .listRowBackground(Color.white.opacity(0.05))

                    TextField("Model", text: $viewModel.defaultModel)
                        .font(.system(size: 13, design: .monospaced))
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .onSubmit { viewModel.save() }
                        .listRowBackground(Color.white.opacity(0.05))

                    Stepper(
                        "Timeout: \(Int(viewModel.timeoutSeconds))s",
                        value: $viewModel.timeoutSeconds,
                        in: 30...180,
                        step: 15
                    )
                    .onChange(of: viewModel.timeoutSeconds) { _, _ in viewModel.save() }
                    .listRowBackground(Color.white.opacity(0.05))

                    Toggle("Streaming", isOn: $viewModel.streamingEnabled)
                        .onChange(of: viewModel.streamingEnabled) { _, _ in viewModel.save() }
                        .listRowBackground(Color.white.opacity(0.05))
                } header: {
                    Text("GLM 5.2")
                } footer: {
                    Text("Official API: \(GLMConfiguration.defaultBaseURL). Set \(GLMConfiguration.apiKeyEnvVar) in the environment or add a key in Settings.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                }

                Section {
                    NavigationLink {
                        GLMUsageSettingsView()
                    } label: {
                        Label("Usage & Cost", systemImage: "chart.bar.doc.horizontal")
                    }
                    .listRowBackground(Color.white.opacity(0.05))

                    Button("Reset to defaults") {
                        viewModel.resetToDefaults()
                    }
                    .foregroundColor(DesignSystem.warning)
                    .listRowBackground(Color.white.opacity(0.05))
                } header: {
                    Text("Developer")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("GLM Configuration")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { viewModel.refresh() }
        .keyboardDismissToolbar(label: "Save", onDone: { viewModel.save() })
    }
}

@MainActor
final class GLMConfigurationSettingsViewModel: ObservableObject {
    @Published var baseURL: String = GLMConfiguration.defaultBaseURL
    @Published var defaultModel: String = GLMConfiguration.defaultModel
    @Published var timeoutSeconds: Double = 90
    @Published var streamingEnabled: Bool = true

    private let glm = GLMService.shared

    func refresh() {
        let config = glm.configuration
        baseURL = config.baseURL
        defaultModel = config.defaultModel
        timeoutSeconds = config.requestTimeoutSeconds
        streamingEnabled = config.streamingEnabled
    }

    func save() {
        var config = glm.configuration
        config.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        config.defaultModel = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        config.requestTimeoutSeconds = timeoutSeconds
        config.streamingEnabled = streamingEnabled
        glm.updateConfiguration(config)
    }

    func resetToDefaults() {
        glm.updateConfiguration(.default)
        refresh()
    }
}

struct GLMUsageSettingsView: View {
    @State private var summary = GLMUsageSummary()

    var body: some View {
        ZStack {
            PremiumBackground()

            List {
                Section {
                    statRow("Today", value: "\(summary.dailyRequestCount) requests", detail: String(format: "$%.4f", summary.dailyTotalUSD))
                    statRow("This month", value: "\(summary.monthlyRequestCount) requests", detail: String(format: "$%.4f", summary.monthlyTotalUSD))
                } header: {
                    Text("Usage")
                }

                Section {
                    if summary.recentRecords.isEmpty {
                        Text("No GLM requests logged yet.")
                            .foregroundColor(DesignSystem.textMuted)
                            .listRowBackground(Color.white.opacity(0.05))
                    } else {
                        ForEach(summary.recentRecords) { record in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(record.model)
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    Spacer()
                                    Image(systemName: record.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(record.success ? DesignSystem.success : DesignSystem.warning)
                                }
                                HStack(spacing: 12) {
                                    Text("\(record.promptTokens + record.completionTokens) tok")
                                    Text("\(record.latencyMs)ms")
                                }
                                .font(.system(size: 11))
                                .foregroundColor(DesignSystem.textMuted)
                            }
                            .listRowBackground(Color.white.opacity(0.05))
                        }
                    }

                    Button("Clear log", role: .destructive) {
                        GLMUsageLogger.shared.clear()
                        refresh()
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                } header: {
                    Text("Recent Requests")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("GLM Usage")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { refresh() }
    }

    private func statRow(_ title: String, value: String, detail: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(DesignSystem.textMuted)
            }
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(DesignSystem.textSecondary)
        }
        .listRowBackground(Color.white.opacity(0.05))
    }

    private func refresh() {
        summary = GLMService.shared.usageSummary()
    }
}
