import SwiftUI
import LookAfterCore

/// Guided multi-section editor for the user's life profile.
struct StructuredLifeProfileEditor: View {
    @Binding var sections: StructuredLifeProfileSections
    var visibleSections: [LifeProfileSection] = LifeProfileSection.brainContextSections
    var minSectionHeight: CGFloat = 100
    var showsOrganizeButton: Bool = true
    var aiOrganizeAvailable: Bool = true
    var onOrganize: (() async -> Void)?
    var onOrganizeLocally: (() -> Void)?

    @State private var isOrganizing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your brain uses these notes plus your day-end reflection on Timeline to plan tomorrow — not a checklist.")
                .font(.system(size: 13))
                .foregroundColor(DesignSystem.textSecondary)

            ForEach(visibleSections) { section in
                sectionEditor(section)
            }

            if showsOrganizeButton {
                if aiOrganizeAvailable, let onOrganize {
                    organizeButton(
                        title: isOrganizing ? "Organizing with AI…" : "Organize with AI",
                        action: {
                            isOrganizing = true
                            await onOrganize()
                            isOrganizing = false
                        }
                    )
                } else if let onOrganizeLocally {
                    organizeButton(
                        title: "Format sections",
                        action: {
                            onOrganizeLocally()
                        }
                    )
                }
            }
        }
        .keyboardDismissToolbar()
    }

    @ViewBuilder
    private func sectionEditor(_ section: LifeProfileSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(DesignSystem.textPrimary)

            TextEditor(text: binding(for: section))
                .frame(minHeight: minSectionHeight)
                .padding(12)
                .scrollContentBackground(.hidden)
                .background(RoundedRectangle(cornerRadius: 12).fill(DesignSystem.contentSurfaceSubtle))
                .foregroundColor(DesignSystem.textPrimary)
                .overlay(alignment: .topLeading) {
                    if LifeProfileComposer.value(in: sections, for: section).isEmpty {
                        Text(section.placeholder)
                            .font(.system(size: 13))
                            .foregroundColor(DesignSystem.textMuted)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private func binding(for section: LifeProfileSection) -> Binding<String> {
        Binding(
            get: { LifeProfileComposer.value(in: sections, for: section) },
            set: { newValue in
                sections = LifeProfileComposer.updating(sections, section: section, value: newValue)
            }
        )
    }

    @ViewBuilder
    private func organizeButton(title: String, action: @escaping () async -> Void) -> some View {
        Button(action: {
            Task { await action() }
        }, label: {
            HStack {
                if isOrganizing {
                    ProgressView().tint(DesignSystem.textPrimary)
                }
                Text(title)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(DesignSystem.contentSurfaceElevated))
        })
        .buttonStyle(.plain)
        .disabled(isOrganizing || !sections.hasContent)
    }

    @ViewBuilder
    private func organizeButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(DesignSystem.contentSurfaceElevated))
        }
        .buttonStyle(.plain)
        .disabled(!sections.hasContent)
    }
}

#if canImport(UIKit)
import UIKit
#endif

enum KeyboardDismiss {
    static func dismiss() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }
}

extension View {
    /// Adds a Done/Send bar above the keyboard without UIKit toolbar nesting (avoids UIHostingController faults).
    func keyboardDismissToolbar(
        label: String = "Done",
        onDone: (() -> Void)? = nil
    ) -> some View {
        modifier(KeyboardDismissToolbarModifier(label: label, onDone: onDone))
    }

    /// Dismisses the keyboard when tapping outside focused fields.
    func dismissKeyboardOnTap() -> some View {
        onTapGesture {
            KeyboardDismiss.dismiss()
        }
    }
}

#if canImport(UIKit)
private struct ViewBottomPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct KeyboardDismissToolbarModifier: ViewModifier {
    let label: String
    let onDone: (() -> Void)?

    @State private var viewMaxY: CGFloat = 0
    @State private var keyboardFrame: CGRect = .zero
    @State private var keyboardVisible = false

    /// How far the keyboard covers this view. A sheet is shorter than the screen, so using the full keyboard height lifts Done onto the amount field.
    private var overlap: CGFloat {
        guard keyboardVisible else { return 0 }
        return max(0, viewMaxY - keyboardFrame.minY)
    }

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ViewBottomPreferenceKey.self,
                        value: proxy.frame(in: .global).maxY
                    )
                }
            }
            .onPreferenceChange(ViewBottomPreferenceKey.self) { viewMaxY = $0 }
            .overlay(alignment: .bottom) {
                if overlap > 1 {
                    HStack {
                        Spacer()
                        Button(label) {
                            onDone?()
                            KeyboardDismiss.dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 16)
                    .background(.bar)
                    .padding(.bottom, overlap)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.25), value: overlap)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                updateKeyboardFrame(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                updateKeyboardFrame(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardVisible = false
                keyboardFrame = .zero
            }
    }

    private func updateKeyboardFrame(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        keyboardFrame = frame
        keyboardVisible = frame.height > 0 && frame.minY < UIScreen.main.bounds.height
    }
}
#else
private struct KeyboardDismissToolbarModifier: ViewModifier {
    let label: String
    let onDone: (() -> Void)?

    func body(content: Content) -> some View {
        content
    }
}
#endif
