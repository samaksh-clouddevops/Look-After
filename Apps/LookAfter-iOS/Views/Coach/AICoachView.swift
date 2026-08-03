import SwiftUI
import LookAfterCore
import LookAfterAI

/// AI Coach — conversational interface for ADHD support.
struct AICoachView: View {
    
    @ObservedObject var brain: ExecutiveBrain
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        ZStack {
            PremiumBackground()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(DesignSystem.textMuted)
                    
                    Text(UserFacingCopy.chatTitle)
                        .font(.system(size: 20, weight: .bold, design: .default))
                        .foregroundColor(DesignSystem.textPrimary)
                    
                    Spacer()
                    
                    Button(action: { brain.clearChat() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                }
                .padding()
                
                Divider()
                    .background(DesignSystem.borderGlass)
                
                // Chat messages
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: DesignSystem.spacingMD) {
                            // Welcome message
                            if brain.chatHistory.isEmpty {
                                welcomeSection
                            }
                            
                            ForEach(brain.chatHistory) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }
                            
                            if brain.isThinking {
                                thinkingIndicator
                            }
                        }
                        .padding()
                    }
                    .onChange(of: brain.chatHistory.count) { _, _ in
                        if let lastMessage = brain.chatHistory.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Input bar
                inputBar
            }
        }
        .keyboardDismissToolbar(label: "Send", onDone: sendMessage)
        .accessibilityIdentifier("screen-coach")
    }
    
    // MARK: - Welcome Section
    
    private var welcomeSection: some View {
        VStack(spacing: DesignSystem.spacingMD) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(DesignSystem.textMuted)
                .padding(.top, DesignSystem.spacingXL)
            
            Text("Hey \(brain.userName)! Ask me anything about your day.")
                .font(.system(size: 22, weight: .bold, design: .default))
                .foregroundColor(DesignSystem.textPrimary)
            
            Text("I'm here to help you navigate your day.\nI have real-time access to your tasks and energy state.")
                .font(.system(size: 15, weight: .medium, design: .default))
                .foregroundColor(DesignSystem.textSecondary)
                .multilineTextAlignment(.center)
            
            // Suggestion chips
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
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundColor(DesignSystem.accentPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(DesignSystem.accentPrimary.opacity(0.1))
                        .overlay(
                            Capsule()
                                .stroke(DesignSystem.accentPrimary.opacity(0.3), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Thinking Indicator
    
    private var thinkingIndicator: some View {
        HStack(alignment: .bottom) {
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(DesignSystem.accentPrimary)
                        .frame(width: 8, height: 8)
                        .opacity(0.5)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(i) * 0.2),
                            value: brain.isThinking
                        )
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(DesignSystem.surfaceGlass)
            )
            
            Spacer()
        }
    }
    
    // MARK: - Input Bar
    
    private var inputBar: some View {
        HStack(spacing: DesignSystem.spacingSM) {
            TextField("Ask me anything...", text: $inputText, axis: .vertical)
                .font(.system(size: 15, design: .default))
                .foregroundColor(DesignSystem.textPrimary)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(DesignSystem.borderGlass, lineWidth: 1)
                        )
                )
                .onSubmit { sendMessage() }
            
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        inputText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? AnyShapeStyle(Color.white.opacity(0.2))
                            : AnyShapeStyle(DesignSystem.accentGradient)
                    )
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, DesignSystem.spacingMD)
        .padding(.vertical, DesignSystem.spacingSM)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(DesignSystem.backgroundSecondary.opacity(0.8))
                )
        )
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

/// A single chat bubble.
struct ChatBubble: View {
    let message: ChatMessage
    
    var isUser: Bool { message.role == .user }
    
    var body: some View {
        HStack(alignment: .bottom) {
            if isUser { Spacer(minLength: 60) }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .foregroundColor(isUser ? .white : DesignSystem.textPrimary)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                isUser
                                    ? AnyShapeStyle(DesignSystem.accentGradient)
                                    : AnyShapeStyle(DesignSystem.surfaceGlass)
                            )
                    )
                
                Text(message.timestamp.timeString)
                    .font(.system(size: 10, weight: .medium, design: .default))
                    .foregroundColor(DesignSystem.textMuted)
            }
            
            if !isUser { Spacer(minLength: 60) }
        }
    }
}
