import SwiftUI
import LookAfterCore

/// Thin review of parked / fluid recovery candidates — ask which matter.
public struct ParkedFluidReviewView: View {
    @State private var entries: [ParkedTaskEntry] = []
    @State private var selected: Set<String> = []
    var onPullSelected: ([ParkedTaskEntry]) -> Void
    var onDismiss: () -> Void

    public init(
        onPullSelected: @escaping ([ParkedTaskEntry]) -> Void = { _ in },
        onDismiss: @escaping () -> Void = {}
    ) {
        self.onPullSelected = onPullSelected
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Pick what still matters. The rest stays parked until a gap opens.")
                        .font(.dsCaption())
                        .foregroundStyle(DesignSystem.textSecondary)
                        .listRowBackground(Color.clear)
                }
                Section("Recoverable") {
                    ForEach(entries) { entry in
                        Button {
                            toggle(entry.taskID)
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(entry.taskID)
                                      ? "checkmark.circle.fill"
                                      : "circle")
                                    .foregroundStyle(
                                        selected.contains(entry.taskID)
                                        ? DesignSystem.accentPrimary
                                        : DesignSystem.textMuted
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                        .font(.dsBody(weight: .medium))
                                        .foregroundStyle(DesignSystem.textPrimary)
                                    Text("\(entry.originalDurationMinutes)m · \(entry.lifeArea.rawValue)")
                                        .font(.dsCaption())
                                        .foregroundStyle(DesignSystem.textMuted)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Parked & fluid")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pull selected") {
                        let chosen = entries.filter { selected.contains($0.taskID) }
                        onPullSelected(chosen)
                        onDismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .onAppear {
                entries = ParkedTaskQueueStore.shared.candidatesForReintegration(limit: 20)
            }
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }
}
