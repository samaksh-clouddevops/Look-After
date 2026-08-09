import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Universal Inbox — review queue for captures that need attention.
struct InboxView: View {

    @ObservedObject var inboxVM: InboxViewModel
    let userId: String

    @State private var captureText = ""
    @State private var showQuickCapture = false
    @StateObject private var speechManager = SpeechRecognitionManager()
    @FocusState private var isCaptureFieldFocused: Bool

    private var reviewItems: [InboxItem] {
        inboxVM.items.filter { $0.status == .unprocessed || $0.status == .needsReview }
    }

    private var routedItems: [InboxItem] {
        inboxVM.items.filter { $0.status != .unprocessed && $0.status != .needsReview }
    }

    var body: some View {
        ZStack {
            PremiumBackground()

            VStack(spacing: 0) {
                header
                quickCaptureBar
                itemsList
            }
        }
        .task { await inboxVM.loadItems(userId: userId) }
        .refreshable { await inboxVM.loadItems(userId: userId) }
        .keyboardDismissToolbar(label: "Done")
        .onChange(of: speechManager.transcript) { _, transcript in
            guard !transcript.isEmpty else { return }
            captureText = transcript
        }
        .accessibilityIdentifier("screen-inbox")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Inbox")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(DesignSystem.textPrimary)
                Text(reviewItems.isEmpty ? "All caught up" : "\(reviewItems.count) need review")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(reviewItems.isEmpty ? DesignSystem.textMuted : DesignSystem.accentPrimary)
            }
            Spacer()
            Button(action: { showQuickCapture.toggle() }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(DesignSystem.textMuted)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var quickCaptureBar: some View {
        if showQuickCapture {
            VStack(spacing: 8) {
                HStack(spacing: DesignSystem.spacingSM) {
                    TextField("Capture anything...", text: $captureText, axis: .vertical)
                        .font(.system(size: 15))
                        .lineLimit(1...4)
                        .focused($isCaptureFieldFocused)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.radiusMD)
                                .fill(DesignSystem.backgroundSecondary)
                                .overlay(RoundedRectangle(cornerRadius: DesignSystem.radiusMD).stroke(DesignSystem.border))
                        )
                        .accessibilityIdentifier("capture-text-field")
                        .onSubmit { capture() }

                    Button(action: capture) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(captureText.isEmpty ? AnyShapeStyle(DesignSystem.textMuted) : AnyShapeStyle(DesignSystem.accentPrimary))
                    }
                    .disabled(captureText.isEmpty || inboxVM.isProcessing)
                    .accessibilityIdentifier("capture-save")
                }

                HStack {
                    Button(action: toggleVoice) {
                        Label(speechManager.isListening ? "Stop" : "Speak", systemImage: speechManager.isListening ? "waveform.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .accessibilityIdentifier("capture-mic")
                    Spacer()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .onAppear { isCaptureFieldFocused = true }
        }
    }

    private var itemsList: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.spacingSM) {
                if reviewItems.isEmpty && routedItems.isEmpty {
                    emptyState
                } else {
                    if !reviewItems.isEmpty {
                        sectionHeader("Needs review")
                        ForEach(reviewItems) { item in
                            InboxItemCard(
                                item: item,
                                onProcess: { Task { await inboxVM.processItem(item) } },
                                onDelete: { Task { await inboxVM.deleteItem(item) } },
                                isProcessing: inboxVM.isProcessing
                            )
                        }
                    }
                    if !routedItems.isEmpty {
                        sectionHeader("Recently routed")
                        ForEach(routedItems.prefix(20)) { item in
                            InboxItemCard(
                                item: item,
                                onProcess: {},
                                onDelete: { Task { await inboxVM.deleteItem(item) } },
                                isProcessing: false
                            )
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(DesignSystem.textMuted)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: DesignSystem.spacingMD) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(DesignSystem.textMuted)
            Text("Inbox Zero!")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(DesignSystem.textSecondary)
            Text("Captures auto-route to tasks, calendar, journal, and mood.\nOnly uncertain items land here.")
                .font(.system(size: 14))
                .foregroundColor(DesignSystem.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func capture() {
        let text = captureText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        captureText = ""
        isCaptureFieldFocused = false
        KeyboardDismiss.dismiss()
        Task {
            _ = await inboxVM.quickCapture(text: text, userId: userId, source: .inbox)
        }
    }

    private func toggleVoice() {
        if speechManager.isListening {
            speechManager.stopListening()
        } else {
            Task { await speechManager.startListening() }
        }
    }
}

struct InboxItemCard: View {
    let item: InboxItem
    let onProcess: () -> Void
    let onDelete: () -> Void
    let isProcessing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            HStack {
                Image(systemName: item.type.icon)
                    .foregroundColor(DesignSystem.accentPrimary)
                Text(item.type.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DesignSystem.textMuted)
                Spacer()
                Text(item.status.rawValue)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(statusColor.opacity(0.15)))
            }

            Text(item.content)
                .font(.system(size: 14))
                .foregroundColor(DesignSystem.textPrimary)
                .lineLimit(4)

            if let summary = item.aiSummary {
                Label(summary, systemImage: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DesignSystem.accentPrimary)
            }

            if item.status == .unprocessed || item.status == .needsReview {
                HStack(spacing: DesignSystem.spacingSM) {
                    Button(action: onProcess) {
                        Label(isProcessing ? "Routing…" : "Fix routing", systemImage: "arrow.triangle.branch")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(DesignSystem.accentGradient))
                    }
                    .disabled(isProcessing)
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(DesignSystem.error)
                    }
                }
            }
        }
        .elevatedSurface()
    }

    private var statusColor: Color {
        switch item.status {
        case .unprocessed, .needsReview: return DesignSystem.warning
        case .processing: return DesignSystem.accentPrimary
        case .categorized, .actionCreated: return DesignSystem.success
        case .archived, .dismissed: return DesignSystem.textMuted
        }
    }
}
