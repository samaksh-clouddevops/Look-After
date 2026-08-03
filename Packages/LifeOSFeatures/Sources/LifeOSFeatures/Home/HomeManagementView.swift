import SwiftUI
import LifeOSCore

/// The main view for the Home Management Module.
public struct HomeManagementView: View {
    
    @StateObject private var viewModel = HomeManagementViewModel()
    @State private var selectedTab = 0
    
    public init() {}
    
    public var body: some View {
        ZStack {
            PremiumBackground()
            
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Home & Environment")
                        .font(.system(size: 28, weight: .bold, design: .default))
                        .foregroundColor(DesignSystem.textPrimary)
                    
                    Text("Digital twin, chores, and maintenance.")
                        .font(.system(size: 15, weight: .medium, design: .default))
                        .foregroundColor(DesignSystem.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 20)
                
                // Custom segmented picker
                HStack(spacing: 0) {
                    TabButton(title: "Maintenance", isSelected: selectedTab == 0) { selectedTab = 0 }
                    TabButton(title: "Digital Twin", isSelected: selectedTab == 1) { selectedTab = 1 }
                }
                .padding(.horizontal)
                .padding(.vertical, 20)
                
                // Content
                TabView(selection: $selectedTab) {
                    MaintenanceTabView(viewModel: viewModel)
                        .tag(0)
                    
                    DigitalTwinTabView(viewModel: viewModel)
                        .tag(1)
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif
            }
        }
    }
}

// MARK: - Subviews

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .default))
                .foregroundColor(isSelected ? .white : DesignSystem.textMuted)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    ZStack {
                        if isSelected {
                            Capsule().fill(DesignSystem.backgroundSecondary)
                        }
                    }
                )
        }
    }
}

struct MaintenanceTabView: View {
    @ObservedObject var viewModel: HomeManagementViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
                
                if !viewModel.urgentMaintenanceTasks.isEmpty {
                    Text("Needs Attention")
                        .font(.system(size: 18, weight: .semibold, design: .default))
                        .foregroundColor(DesignSystem.textPrimary)
                        .padding(.horizontal)
                    
                    ForEach(viewModel.urgentMaintenanceTasks) { task in
                        MaintenanceTaskCard(task: task) {
                            viewModel.toggleTaskCompletion(task)
                        }
                        .padding(.horizontal)
                    }
                }
                
                Text("Upcoming")
                    .font(.system(size: 18, weight: .semibold, design: .default))
                    .foregroundColor(DesignSystem.textPrimary)
                    .padding(.horizontal)
                    .padding(.top, DesignSystem.spacingSM)
                
                ForEach(viewModel.upcomingMaintenanceTasks) { task in
                    MaintenanceTaskCard(task: task) {
                        viewModel.toggleTaskCompletion(task)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 40)
        }
    }
}

struct DigitalTwinTabView: View {
    @ObservedObject var viewModel: HomeManagementViewModel
    
    var body: some View {
        VStack(spacing: DesignSystem.spacingMD) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(DesignSystem.textMuted)
                TextField("Search where things are stored...", text: $viewModel.inventorySearchQuery)
                    .foregroundColor(DesignSystem.textPrimary)
                    .textFieldStyle(.plain)
            }
            .padding(12)
            .background(DesignSystem.backgroundSecondary)
            .cornerRadius(12)
            .padding(.horizontal)
            
            ScrollView {
                VStack(spacing: DesignSystem.spacingSM) {
                    ForEach(viewModel.filteredInventory) { item in
                        InventoryItemCard(item: item)
                            .padding(.horizontal)
                    }
                    
                    if viewModel.filteredInventory.isEmpty {
                        Text("No items found.")
                            .foregroundColor(DesignSystem.textMuted)
                            .padding(.top, 40)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
}

struct MaintenanceTaskCard: View {
    let task: HomeMaintenanceTask
    let onComplete: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .font(.system(size: 22))
                    .foregroundColor(DesignSystem.textMuted)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundColor(DesignSystem.textPrimary)
                
                HStack {
                    if task.isOverdue {
                        Text("Overdue")
                            .foregroundColor(DesignSystem.textMuted)
                    } else if Calendar.current.isDateInToday(task.nextDue) {
                        Text("Due Today")
                            .foregroundColor(DesignSystem.textSecondary)
                    } else {
                        Text("Due in \(Calendar.current.dateComponents([.day], from: Date(), to: task.nextDue).day ?? 0) days")
                            .foregroundColor(DesignSystem.textMuted)
                    }
                    
                    if let assignee = task.assignedTo {
                        Text("•")
                            .foregroundColor(DesignSystem.textMuted)
                        Image(systemName: task.isShared ? "person.2.fill" : "person.fill")
                            .foregroundColor(DesignSystem.textMuted)
                        Text(assignee)
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                }
                .font(.system(size: 13, weight: .medium, design: .default))
            }
            Spacer()
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct InventoryItemCard: View {
    let item: HomeInventoryItem
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundColor(DesignSystem.textPrimary)
                
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(DesignSystem.accentPrimary)
                    Text(item.location)
                        .font(.system(size: 13, weight: .medium, design: .default))
                        .foregroundColor(DesignSystem.textSecondary)
                }
            }
            Spacer()
            
            Text("Qty: \(item.quantity)")
                .font(.system(size: 14, weight: .bold, design: .default))
                .foregroundColor(DesignSystem.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
}
