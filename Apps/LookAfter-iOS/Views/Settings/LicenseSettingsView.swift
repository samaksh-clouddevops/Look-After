import SwiftUI
import LookAfterCore
import LookAfterData

/// One-time product key (UUID) redeem for licensed Azure-proxied AI.
struct LicenseRedeemView: View {
    @StateObject private var license = LicenseManager.shared
    @State private var productKey: String = ""
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss

    var onFinished: (() -> Void)?

    var body: some View {
        ZStack {
            PremiumBackground()
            Form {
                Section {
                    Text("Enter the product key you received with Look After. It unlocks AI without putting API keys on your device.")
                        .font(.system(size: 13))
                        .foregroundColor(DesignSystem.textSecondary)
                        .listRowBackground(DesignSystem.contentSurface)
                }

                Section("Product key") {
                    TextField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $productKey)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .font(.system(size: 14, design: .monospaced))
                        .listRowBackground(DesignSystem.contentSurface)

                    Button {
                        Task { await redeem() }
                    } label: {
                        if license.isBusy {
                            ProgressView()
                        } else {
                            Text("Activate")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(license.isBusy || productKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .listRowBackground(DesignSystem.contentSurface)
                }

                if license.isLicensed {
                    Section {
                        Label("License active", systemImage: "checkmark.seal.fill")
                            .foregroundColor(DesignSystem.success)
                            .listRowBackground(DesignSystem.contentSurface)
                    }
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundColor(DesignSystem.warning)
                            .listRowBackground(DesignSystem.contentSurface)
                    }
                }

                Section {
                    Button("Skip for now") {
                        onFinished?()
                        dismiss()
                    }
                    .listRowBackground(DesignSystem.contentSurface)
                } footer: {
                    Text("You can activate later in Settings. Without a license, AI needs a personal GLM key or runs in deterministic mode.")
                        .font(.system(size: 11))
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Activate Look After")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityIdentifier("screen-license-redeem")
    }

    private func redeem() async {
        message = nil
        do {
            try await license.redeem(productKey: productKey)
            message = nil
            HapticManager.notification(.success)
            try? await Task.sleep(nanoseconds: 600_000_000)
            onFinished?()
            dismiss()
        } catch {
            message = error.localizedDescription
            HapticManager.notification(.error)
        }
    }
}

/// Settings surface for license status + redeem.
struct LicenseSettingsView: View {
    @StateObject private var license = LicenseManager.shared

    var body: some View {
        ZStack {
            PremiumBackground()
            List {
                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(license.isLicensed ? "Active" : "Not activated")
                            .foregroundColor(license.isLicensed ? DesignSystem.success : DesignSystem.textSecondary)
                    }
                    .listRowBackground(DesignSystem.contentSurface)

                    if let redeemedAt = license.redeemedAt {
                        HStack {
                            Text("Redeemed")
                            Spacer()
                            Text(redeemedAt)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(DesignSystem.textSecondary)
                        }
                        .listRowBackground(DesignSystem.contentSurface)
                    }
                }

                if license.proxyClient == nil {
                    Section {
                        Text("Auth proxy URL is not configured. Set AuthProxyBaseURL in Info.plist after deploying Azure.")
                            .font(.system(size: 13))
                            .foregroundColor(DesignSystem.textSecondary)
                            .listRowBackground(DesignSystem.contentSurface)
                    }
                } else {
                    Section {
                        NavigationLink("Enter product key") {
                            LicenseRedeemView()
                        }
                        .listRowBackground(DesignSystem.contentSurface)

                        Button("Refresh status") {
                            Task { await license.refreshStatus() }
                        }
                        .disabled(license.isBusy)
                        .listRowBackground(DesignSystem.contentSurface)
                    }
                }

                if let err = license.lastError {
                    Section {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundColor(DesignSystem.warning)
                            .listRowBackground(DesignSystem.contentSurface)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("License")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            Task { await license.refreshStatus() }
        }
        .accessibilityIdentifier("screen-license-settings")
    }
}
