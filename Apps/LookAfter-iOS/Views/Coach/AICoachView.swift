import SwiftUI
import LookAfterCore
import LookAfterAI

/// AI Coach — card-based conversation for ADHD support.
struct AICoachView: View {
    @ObservedObject var brain: ExecutiveBrain
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            PremiumBackground()

            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(DesignSystem.textMuted)

                    Text(UserFacingCopy.chatTitle)
                        .font(.dsHeadline())

                    Spacer()

                    Button(action: { brain.clearChat() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                    .accessibilityLabel("Clear conversation")
                }
                .padding()

                Divider()
                    .background(DesignSystem.divider)

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: DesignSystem.spacingMD) {
                            if brain.chatHistory.isEmpty {
                                welcomeSection
                            }

                            ForEach(brain.chatHistory) { message in
                                LAConversationCard(
                                    bodyText: message.content,
                                    footnote: message.timestamp.timeString,
                                    isUser: message.role == .user
                                )
                                .id(message.id)
                            }

                            if brain.isThinking {
                                thinkingIndicator
                            }
                        }
                        .padding(DesignSystem.screenHorizontal)
                    }
                    .onChange(of: brain.chatHistory.count) { _, _ in
                        if let lastMessage = brain.chatHistory.last {
                            withAnimation(reduceMotion ? nil : PremiumMotion.fade) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }

                inputBar
            }
        }
        .keyboardDismissToolbar(label: "Send", onDone: sendMessage)
        .accessibilityIdentifier("screen-coach")
    }

    private var welcomeSection: some View {
        VStack(spacing: DesignSystem.spacingMD) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(DesignSystem.textMuted)
                .padding(.top, DesignSystem.spacingXL)

            Text("Hey \(brain.userName)! Ask me anything about your day.")
                .font(.dsHeadline())
                .foregroundColor(DesignSystem.textPrimary)
                .multilineTextAlignment(.center)

            Text("I'm here to help you navigate your day.\nI have real-time access to your tasks and energy state.")
                .font(.dsSecondary())
                .foregroundColor(DesignSystem.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                suggestionChip("What have I accomplished today?")
                suggestionChip("How much uninterrupted time do I have?")
                suggestionChip("I'm feeling overwhelmed — help me pick 1 task")
                suggestionChip("I can't start this task")
            }
            .padding(.top, DesignSystem.spacingSM)
        }
        .onAppear {
            brain.loadChatHistory()
        }
    }

    private func suggestionChip(_ text: String) -> some View {
        Button(action: {
            inputText = text
            sendMessage()
        }) {
            Text(text)
                .font(.dsCaption())
                .foregroundColor(DesignSystem.accentPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(DesignSystem.accentPrimary.opacity(0.1))
                        .overlay(
                            Capsule()
                                .stroke(DesignSystem.border, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var thinkingIndicator: some View {
        HStack {
            LAConversationCard(
                title: "Thinking",
                bodyText: "…",
                isUser: false
            )
            Spacer(minLength: 0)
        }
        .accessibilityLabel("Assistant is thinking")
    }

    private var inputBar: some View {
        HStack(spacing: DesignSystem.spacingSM) {
            TextField("Ask me anything...", text: $inputText, axis: .vertical)
                .font(.dsSecondary())
                .foregroundColor(DesignSystem.textPrimary)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                        .fill(DesignSystem.backgroundSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                                .stroke(DesignSystem.border, lineWidth: 1)
                        )
                )
                .onSubmit { sendMessage() }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        inputText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? AnyShapeStyle(DesignSystem.textMuted)
                            : AnyShapeStyle(DesignSystem.accentPrimary)
                    )
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, DesignSystem.spacingMD)
        .padding(.vertical, DesignSystem.spacingSM)
        .background(DesignSystem.backgroundSecondary)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        isInputFocused = false
        KeyboardDismiss.dismiss()

        Task {
            _ = await brain.chat(message: text)
        }
    }
}
