import SwiftUI
import LifeOSCore
import LifeOSAI
import LifeOSData
import LifeOSFeatures

/// Universal Inbox View — capture and process anything.
struct InboxView: View {
    
    @ObservedObject var inboxVM: InboxViewModel
    let userId: String
    
    @State private var captureText = ""
    @State private var showQuickCapture = false
    @FocusState private var isCaptureFieldFocused: Bool
    
    var body: some View {
        ZStack {
            PremiumBackground()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("Inbox")
                            .font(.system(size: 28, weight: .bold, design: .default))
                            .foregroundColor(DesignSystem.textPrimary)
                        
                        if inboxVM.unprocessedCount > 0 {
                            Text("\(inboxVM.unprocessedCount) unprocessed")
                                .font(.system(size: 13, weight: .semibold, design: .default))
                                .foregroundColor(DesignSystem.accentPrimary)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: { showQuickCapture.toggle() }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                }
                .padding()
                
                // Quick Capture Bar
                if showQuickCapture {
                    HStack(spacing: DesignSystem.spacingSM) {
                        TextField("Capture anything...", text: $captureText, axis: .vertical)
                            .font(.system(size: 15, design: .default))
                            .foregroundColor(DesignSystem.textPrimary)
                            .lineLimit(1...4)
                            .focused($isCaptureFieldFocused)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.radiusMD)
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignSystem.radiusMD)
                                            .stroke(DesignSystem.accentPrimary.opacity(0.3), lineWidth: 1)
                                    )
                            )
                            .onSubmit { capture() }
                        
                        Button(action: capture) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(
                                    captureText.isEmpty
                                        ? AnyShapeStyle(Color.white.opacity(0.2))
                                        : AnyShapeStyle(DesignSystem.accentGradient)
                                )
                        }
                        .disabled(captureText.isEmpty)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear { isCaptureFieldFocused = true }
                }
                
                // Items list
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: DesignSystem.spacingSM) {
                        if inboxVM.items.isEmpty {
                            emptyState
                        } else {
                            ForEach(inboxVM.items) { item in
                                InboxItemCard(
                                    item: item,
                                    onProcess: {
                                        Task { await inboxVM.processItem(item) }
                                    },
                                    onDelete: {
                                        Task { await inboxVM.deleteItem(item) }
                                    },
                                    isProcessing: inboxVM.isProcessing
                                )
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .task {
            await inboxVM.loadItems(userId: userId)
        }
        .keyboardDismissToolbar(label: "Done")
    }
    
    private var emptyState: some View {
        VStack(spacing: DesignSystem.spacingMD) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(DesignSystem.textMuted)
            
            Text("Inbox Zero!")
                .font(.system(size: 20, weight: .bold, design: .default))
                .foregroundColor(DesignSystem.textSecondary)
            
            Text("Capture thoughts, links, photos — anything.\nAI will categorize and create actions.")
                .font(.system(size: 14, weight: .medium, design: .default))
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
            await inboxVM.quickCapture(text: text)
        }
    }
}

/// An inbox item card with AI processing.
struct InboxItemCard: View {
    let item: InboxItem
    let onProcess: () -> Void
    let onDelete: () -> Void
    let isProcessing: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            // Header
            HStack {
                Image(systemName: item.type.icon)
                    .font(.system(size: 14))
                    .foregroundColor(DesignSystem.accentPrimary)
                
                Text(item.type.rawValue)
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundColor(DesignSystem.textMuted)
                
                Spacer()
                
                // Status badge
                Text(item.status.rawValue)
                    .font(.system(size: 10, weight: .bold, design: .default))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(statusColor.opacity(0.15))
                    )
                
                Text(item.createdAt.relativeTimeString)
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundColor(DesignSystem.textMuted)
            }
            
            // Content
            Text(item.content)
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundColor(DesignSystem.textPrimary)
                .lineLimit(3)
            
            // AI Summary (if processed)
            if let summary = item.aiSummary {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                    
                    Text(summary)
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundColor(DesignSystem.accentPrimary)
                }
            }
            
            if let action = item.aiSuggestedAction, action != "archive" {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 11))
                    Text("Suggested: \(action)")
                        .font(.system(size: 12, weight: .medium, design: .default))
                }
                .foregroundColor(DesignSystem.success)
            }
            
            // Life area tag
            if let area = item.lifeArea {
                Label(area.rawValue, systemImage: area.icon)
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundColor(DesignSystem.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                    )
            }
            
            // Actions
            if item.status == .unprocessed {
                HStack(spacing: DesignSystem.spacingSM) {
                    Button(action: onProcess) {
                        Label(
                            isProcessing ? "Processing..." : "Process with AI",
                            systemImage: "sparkles"
                        )
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(DesignSystem.accentGradient))
                    }
                    .disabled(isProcessing)
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(DesignSystem.error)
                    }
                }
                .padding(.top, 4)
            }
        }
        .elevatedSurface()
    }
    
    private var statusColor: Color {
        switch item.status {
        case .unprocessed: return DesignSystem.textSecondary
        case .processing: return DesignSystem.accentPrimary
        case .categorized: return DesignSystem.success
        case .actionCreated: return DesignSystem.accentPrimary
        case .archived: return DesignSystem.textMuted
        case .dismissed: return DesignSystem.textMuted
        }
    }
}
