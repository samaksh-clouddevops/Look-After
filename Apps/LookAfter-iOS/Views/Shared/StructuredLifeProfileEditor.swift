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
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
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
        Button {
            Task { await action() }
        } label: {
            HStack {
                if isOrganizing {
                    ProgressView().tint(DesignSystem.textPrimary)
                }
                Text(title)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
        }
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
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
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
    /// Adds a toolbar button above the keyboard to dismiss it.
    func keyboardDismissToolbar(
        label: String = "Done",
        onDone: (() -> Void)? = nil
    ) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(label) {
                    onDone?()
                    KeyboardDismiss.dismiss()
                }
                .fontWeight(.semibold)
            }
        }
    }

    /// Dismisses the keyboard when tapping outside focused fields.
    func dismissKeyboardOnTap() -> some View {
        onTapGesture {
            KeyboardDismiss.dismiss()
        }
    }
}
