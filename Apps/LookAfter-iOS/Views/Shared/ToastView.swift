import SwiftUI
import LookAfterCore

// MARK: - Toast Notification System

/// A global toast notification view for success, error, and info feedback.
struct ToastView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let message: String
    let type: ToastType
    
    enum ToastType {
        case success, error, info
        
        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .success: return DesignSystem.accentPrimary
            case .error: return DesignSystem.error
            case .info: return DesignSystem.textSecondary
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: type.icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(type.color)
            
            Text(message)
                .font(.system(size: 14, weight: .semibold, design: .default))
                .foregroundColor(.white)
                .lineLimit(2)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .modifier(ToastChrome(
            reduceTransparency: reduceTransparency,
            accentStroke: type.color.opacity(0.4)
        ))
        .padding(.horizontal, 20)
    }
}

private struct ToastChrome: ViewModifier {
    let reduceTransparency: Bool
    let accentStroke: Color

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(shape.fill(DesignSystem.contentSurfaceElevated))
                .overlay(shape.stroke(DesignSystem.border, lineWidth: 1))
        } else {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                .overlay(shape.stroke(accentStroke, lineWidth: 1))
        }
    }
}

// MARK: - Toast Modifier

struct ToastModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isShowing: Bool
    let message: String
    let type: ToastView.ToastType
    var duration: TimeInterval = 2.5
    
    @State private var dismissToken = UUID()

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            
            if isShowing {
                ToastView(message: message, type: type)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(999)
                    .padding(.top, 8)
                    .task(id: dismissToken) {
                        try? await Task.sleep(for: .seconds(duration))
                        guard !Task.isCancelled else { return }
                        withAnimation(PremiumMotion.spring(reduceMotion: reduceMotion)) {
                            isShowing = false
                        }
                    }
            }
        }
        .animation(PremiumMotion.spring(reduceMotion: reduceMotion), value: isShowing)
        .onChange(of: isShowing) { _, showing in
            if showing { dismissToken = UUID() }
        }
        .onChange(of: message) { _, _ in
            if isShowing { dismissToken = UUID() }
        }
    }
}

extension View {
    func toast(isShowing: Binding<Bool>, message: String, type: ToastView.ToastType = .success, duration: TimeInterval = 2.5) -> some View {
        modifier(ToastModifier(isShowing: isShowing, message: message, type: type, duration: duration))
    }

    func undoToast(
        isShowing: Binding<Bool>,
        message: String,
        duration: TimeInterval = 4,
        showsUndo: Bool = true,
        onUndo: @escaping () -> Void,
        onView: (() -> Void)? = nil,
        viewLabel: String = "View",
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        modifier(UndoToastModifier(
            isShowing: isShowing,
            message: message,
            duration: duration,
            showsUndo: showsUndo,
            onUndo: onUndo,
            onView: onView,
            viewLabel: viewLabel,
            onDismiss: onDismiss
        ))
    }
}

// MARK: - Undo Toast

struct UndoToastModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isShowing: Bool
    let message: String
    var duration: TimeInterval = 4
    var showsUndo: Bool = true
    let onUndo: () -> Void
    var onView: (() -> Void)?
    var viewLabel: String = "View"
    var onDismiss: (() -> Void)?

    @State private var dismissToken = UUID()

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content

            if isShowing {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(red: 0.06, green: 0.73, blue: 0.51))

                    Text(message)
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    if let onView {
                        Button(viewLabel) {
                            dismissToken = UUID()
                            withAnimation(PremiumMotion.spring(reduceMotion: reduceMotion)) {
                                isShowing = false
                            }
                            onView()
                        }
                        .font(.dsCaption(weight: .semibold))
                        .foregroundColor(DesignSystem.textSecondary)
                        .frame(minHeight: 44)
                    }

                    if showsUndo {
                        Button("Undo") {
                            dismissToken = UUID()
                            withAnimation(PremiumMotion.spring(reduceMotion: reduceMotion)) {
                                isShowing = false
                            }
                            onUndo()
                        }
                        .font(.dsCaption(weight: .semibold))
                        .foregroundColor(DesignSystem.accentPrimary)
                        .frame(minWidth: 44, minHeight: 44)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .modifier(ToastChrome(
                    reduceTransparency: reduceTransparency,
                    accentStroke: Color.white.opacity(0.15)
                ))
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(999)
                .accessibilityIdentifier("capture-outcome-toast")
                .task(id: dismissToken) {
                    try? await Task.sleep(for: .seconds(duration))
                    guard !Task.isCancelled else { return }
                    withAnimation(PremiumMotion.spring(reduceMotion: reduceMotion)) {
                        isShowing = false
                    }
                    onDismiss?()
                }
            }
        }
        .animation(PremiumMotion.spring(reduceMotion: reduceMotion), value: isShowing)
        .onChange(of: isShowing) { _, showing in
            if showing {
                dismissToken = UUID()
            }
        }
        .onChange(of: message) { _, _ in
            if isShowing {
                dismissToken = UUID()
            }
        }
    }
}
