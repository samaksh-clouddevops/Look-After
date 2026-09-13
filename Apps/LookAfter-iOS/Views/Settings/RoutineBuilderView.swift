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
    @State private var editingCandidate: RoutineBlock?

    var body: some View {
        ZStack {
            PremiumBackground()
            List {
                if !importCandidates.isEmpty {
                    Section(content: {
                        ForEach(importCandidates) { candidate in
                            Button(action: { editingCandidate = candidate }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(candidate.title)
                                            .foregroundColor(DesignSystem.textPrimary)
                                        Text(candidate.timeRangeLabel())
                                            .font(.system(size: 12))
                                            .foregroundColor(DesignSystem.textMuted)
                                    }
                                    Spacer()
                                    Image(systemName: "pencil")
                                        .font(.system(size: 12))
                                        .foregroundColor(DesignSystem.textMuted)
                                }
                            }
                            .listRowBackground(DesignSystem.contentSurface)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    importCandidates.removeAll { $0.id == candidate.id }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                        Button("Import These Into My Routine") { importSuggested() }
                            .listRowBackground(DesignSystem.contentSurface)
                        Button("Dismiss", role: .cancel) { importCandidates = [] }
                            .listRowBackground(DesignSystem.contentSurface)
                    }, header: { Text("Found in your fixed schedule notes") }, footer: {
                        Text("Tap a suggestion to edit its title or time before importing, or swipe to remove one you don't want.")
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.textMuted)
                    })
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
        .navigationTitle("Plan my daily routine")
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
        .sheet(item: $editingCandidate) { candidate in
            RoutineBlockEditorSheet(mode: .edit(candidate)) { updated in
                if let index = importCandidates.firstIndex(where: { $0.id == updated.id }) {
                    importCandidates[index] = updated
                }
            } onDelete: {
                importCandidates.removeAll { $0.id == candidate.id }
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
        var merged = blocks
        var addedCount = 0
        for candidate in importCandidates where RoutineBlockStore.conflicts(with: candidate, in: merged).isEmpty {
            merged.append(candidate)
            addedCount += 1
        }
        blocks = merged
        RoutineBlockStore.save(blocks)
        importMessage = addedCount == 0
            ? "Nothing new to import — those times already overlap your routine."
            : "Imported \(addedCount) block(s) from your fixed schedule notes."
        importCandidates = []
    }
}
