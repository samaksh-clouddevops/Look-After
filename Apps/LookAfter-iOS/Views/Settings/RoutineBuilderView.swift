import SwiftUI
import LookAfterCore

/// Lets the user declare their fixed daily routine (wake, meals, work, gym, wind-down, sleep, etc.)
/// as a list of `RoutineBlock`s. These become `DayStructure.Anchor`s that the planner treats as
/// fixed points around which flexible tasks are scheduled.
struct RoutineBuilderView: View {
    @State private var blocks: [RoutineBlock] = RoutineBlockStore.load()
    @State private var editingBlock: RoutineBlock?
    @State private var showAddSheet = false
    @State private var importCandidates: [RoutineBlock] = []
    @State private var importMessage: String?

    var body: some View {
        ZStack {
            PremiumBackground()
            List {
                if !importCandidates.isEmpty {
                    Section(content: {
                        ForEach(importCandidates) { candidate in
                            HStack {
                                Text(candidate.title)
                                Spacer()
                                Text(candidate.timeRangeLabel())
                                    .font(.system(size: 12))
                                    .foregroundColor(DesignSystem.textMuted)
                            }
                        }
                        .listRowBackground(DesignSystem.contentSurface)
                        Button("Import These Into My Routine") { importSuggested() }
                            .listRowBackground(DesignSystem.contentSurface)
                        Button("Dismiss", role: .cancel) { importCandidates = [] }
                            .listRowBackground(DesignSystem.contentSurface)
                    }, header: { Text("Found in your fixed schedule notes") })
                }

                if let importMessage {
                    Section {
                        Text(importMessage)
                            .font(.system(size: 12))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                }

                if blocks.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No routine blocks yet")
                                .font(.system(size: 15, weight: .semibold, design: .default))
                            Text("Add the fixed parts of your day — wake up, meals, work, gym, wind-down, sleep. The planner will schedule everything else around these.")
                                .font(.system(size: 12, design: .default))
                                .foregroundColor(DesignSystem.textMuted)
                        }
                        .listRowBackground(DesignSystem.contentSurface)
                    }
                } else {
                    Section(content: {
                        ForEach(blocks.sorted(by: { $0.startMinutesFromMidnight < $1.startMinutesFromMidnight })) { block in
                            Button(action: { editingBlock = block }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(block.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(DesignSystem.textPrimary)
                                        Text(block.timeRangeLabel())
                                            .font(.system(size: 12))
                                            .foregroundColor(DesignSystem.textMuted)
                                    }
                                    Spacer()
                                    if block.isNonNegotiable {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(DesignSystem.accentPrimary)
                                    }
                                }
                            }
                            .listRowBackground(DesignSystem.contentSurface)
                        }
                        .onDelete(perform: deleteBlocks)
                    }, header: { Text("Fixed routine") })
                }

                Section {
                    Button(action: { showAddSheet = true }) {
                        Label("Add Routine Block", systemImage: "plus.circle.fill")
                    }
                    .listRowBackground(DesignSystem.contentSurface)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("My Daily Routine")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showAddSheet) {
            RoutineBlockEditorSheet(mode: .add) { newBlock in
                blocks.append(newBlock)
                RoutineBlockStore.save(blocks)
            }
        }
        .sheet(item: $editingBlock) { block in
            RoutineBlockEditorSheet(mode: .edit(block)) { updated in
                if let index = blocks.firstIndex(where: { $0.id == updated.id }) {
                    blocks[index] = updated
                } else {
                    blocks.append(updated)
                }
                RoutineBlockStore.save(blocks)
            } onDelete: {
                blocks.removeAll { $0.id == block.id }
                RoutineBlockStore.save(blocks)
            }
        }
        .accessibilityIdentifier("screen-routine-builder")
        .onAppear(perform: loadImportSuggestionsIfNeeded)
    }

    private func deleteBlocks(at offsets: IndexSet) {
        let sorted = blocks.sorted(by: { $0.startMinutesFromMidnight < $1.startMinutesFromMidnight })
        let idsToRemove = Set(offsets.map { sorted[$0].id })
        blocks.removeAll { idsToRemove.contains($0.id) }
        RoutineBlockStore.save(blocks)
    }

    /// Offers a one-time, non-destructive import of `fixedScheduleNotes` free text when the
    /// routine list is empty and the notes field has content. The notes text itself is untouched.
    private func loadImportSuggestionsIfNeeded() {
        guard blocks.isEmpty else { return }
        let notes = UserLifeProfileStore.load().fixedScheduleNotes
        guard !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let candidates = RoutineBlockStore.importFromFixedScheduleNotes(notes)
        guard !candidates.isEmpty else { return }
        importCandidates = candidates
    }

    private func importSuggested() {
        blocks.append(contentsOf: importCandidates)
        RoutineBlockStore.save(blocks)
        importMessage = "Imported \(importCandidates.count) block(s) from your fixed schedule notes."
        importCandidates = []
    }
}
