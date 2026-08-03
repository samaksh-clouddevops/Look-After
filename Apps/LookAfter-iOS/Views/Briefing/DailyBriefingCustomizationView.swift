import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Customize which Daily Briefing cards appear and how they are ordered.
struct DailyBriefingCustomizationView: View {
    @ObservedObject var briefingVM: DailyBriefingViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumBackground()

                List {
                    Section {
                        Picker("Layout", selection: Binding(
                            get: { briefingVM.layoutMode },
                            set: { briefingVM.setLayoutMode($0) }
                        )) {
                            ForEach(BriefingLayoutMode.allCases, id: \.self) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.05))
                    } header: {
                        Text("Display")
                    }

                    Section {
                        ForEach(briefingVM.cardOrder) { kind in
                            HStack {
                                Image(systemName: kind.icon)
                                    .foregroundColor(DesignSystem.accentPrimary)
                                    .frame(width: 24)
                                Text(kind.title)
                                    .foregroundColor(DesignSystem.textPrimary)
                                Spacer()
                                if briefingVM.pinnedCards.contains(kind) {
                                    Image(systemName: "pin.fill")
                                        .foregroundColor(DesignSystem.warning)
                                        .font(.system(size: 12))
                                }
                                Toggle("", isOn: Binding(
                                    get: { !briefingVM.hiddenCards.contains(kind) },
                                    set: { briefingVM.setCardHidden(kind, hidden: !$0) }
                                ))
                                .labelsHidden()
                                .tint(DesignSystem.accentPrimary)
                            }
                            .listRowBackground(Color.white.opacity(0.05))
                            .swipeActions(edge: .leading) {
                                Button {
                                    briefingVM.togglePin(kind)
                                } label: {
                                    Label(
                                        briefingVM.pinnedCards.contains(kind) ? "Unpin" : "Pin",
                                        systemImage: "pin.fill"
                                    )
                                }
                                .tint(DesignSystem.warning)
                            }
                        }
                        .onMove(perform: briefingVM.moveCard)
                    } header: {
                        Text("Cards")
                    } footer: {
                        Text("Drag to reorder. Pin cards to keep them at the top.")
                            .foregroundColor(DesignSystem.textMuted)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Customize Briefing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .foregroundColor(DesignSystem.accentPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(DesignSystem.accentPrimary)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Reset to Default") {
                        briefingVM.resetCardLayout()
                    }
                    .foregroundColor(DesignSystem.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("screen-daily-briefing-customization")
    }
}
