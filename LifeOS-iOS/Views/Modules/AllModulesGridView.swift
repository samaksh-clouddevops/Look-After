import SwiftUI
import LifeOSCore
import LifeOSAI
import LifeOSData
import LifeOSFeatures

/// Grid hub — every module uses DestinationTile + TagChipView from the premium design system.
struct AllModulesGridView: View {

    @EnvironmentObject private var shell: AppShellState
    @ObservedObject var modulesVM: LifeModulesViewModel

    var body: some View {
        NavigationStack {
            PremiumScreen {
                VStack(alignment: .leading, spacing: DesignSystem.sectionGap) {
                    VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
                        Text("Modules")
                            .font(.dsDisplay())
                            .foregroundColor(DesignSystem.textPrimary)
                        Text("Every life domain in one place.")
                            .font(.dsBody())
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                    .screenPadding()
                    .padding(.top, DesignSystem.spacingLG)

                    VStack(spacing: DesignSystem.spacingSM) {
                        moduleLink(
                            title: "Task Manager",
                            subtitle: "Plan and complete work",
                            badge: "Active",
                            destination: TaskListView(
                                tasksVM: TasksViewModel(decomposer: TaskDecomposer()),
                                adhdVM: ADHDViewModel(),
                                userId: "user"
                            )
                        )

                        moduleLink(
                            title: "Data Insights",
                            subtitle: "Patterns from your history",
                            badge: "Personalized",
                            destination: InsightsDashboardView(brain: ExecutiveBrain())
                        )

                        moduleLink(
                            title: "AI Memory",
                            subtitle: "Semantic search over your life",
                            badge: "Semantic",
                            destination: AIMemoryView(modulesVM: modulesVM)
                        )

                        moduleLink(
                            title: "Finance & Bills",
                            subtitle: "Track what is due",
                            badge: modulesVM.bills.filter { !$0.isPaid }.count > 0 ? "\(modulesVM.bills.filter { !$0.isPaid }.count) due" : nil,
                            destination: FinanceBillsView(modulesVM: modulesVM)
                        )

                        moduleLink(
                            title: "Hydration",
                            subtitle: "Daily water intake",
                            badge: "\(Int(modulesVM.totalWaterTodayMl))ml",
                            destination: HydrationNutritionView(modulesVM: modulesVM)
                        )

                        moduleLink(
                            title: "Shopping",
                            subtitle: "Lists and inventory",
                            badge: "\(modulesVM.shoppingItems.filter { !$0.isPurchased }.count) items",
                            destination: ShoppingInventoryView(modulesVM: modulesVM)
                        )

                        moduleLink(
                            title: "Relationships",
                            subtitle: "People who matter",
                            badge: modulesVM.contacts.filter { $0.needsContact }.count > 0 ? "\(modulesVM.contacts.filter { $0.needsContact }.count) reach out" : nil,
                            destination: RelationshipsView(modulesVM: modulesVM)
                        )

                        moduleLink(
                            title: "Journaling",
                            subtitle: "Daily reflection",
                            badge: "Daily",
                            destination: ReflectionJournalView(modulesVM: modulesVM)
                        )

                        moduleLink(title: "Calendar", subtitle: "Events and focus windows", badge: nil, destination: CalendarIntelligenceView())
                        moduleLink(title: "Medication", subtitle: "Adherence and schedules", badge: "Due", destination: MedicationView())
                        if CycleFeatureGate.isEligible {
                            moduleLink(title: "Cycle", subtitle: "Phase tracking and insights", badge: nil, destination: CycleDashboardView())
                        }
                        moduleLink(title: "Home", subtitle: "Routines and inventory", badge: "Routine", destination: HomeManagementView())
                        moduleLink(title: "Travel", subtitle: "Trips and packing", badge: nil, destination: TravelPlannerView())
                        moduleLink(title: "Creativity", subtitle: "Music and projects", badge: nil, destination: CreativityWorkspaceView())
                        moduleLink(title: "Learning", subtitle: "Notes and knowledge", badge: nil, destination: LearningKnowledgeView())
                    }
                    .screenPadding()
                }
                .padding(.bottom, DesignSystem.spacingXXL)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView().environmentObject(shell)) {
                        Image(systemName: "gearshape")
                            .premiumIcon()
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            await modulesVM.loadAllData(userId: "user")
        }
    }

    @ViewBuilder
    private func moduleLink<D: View>(title: String, subtitle: String, badge: String?, destination: D) -> some View {
        NavigationLink {
            destination
        } label: {
            DestinationTile(title: title, subtitle: subtitle, badge: badge)
        }
        .buttonStyle(PremiumPressStyle())
    }
}
