import SwiftUI
import Combine
import LifeOSCore

// MARK: - ViewModel

@MainActor
public final class TravelViewModel: ObservableObject {
    @Published public var trips: [TravelTrip] = []
    @Published public var packingList: [PackingItem] = []
    @Published public var isLoading = false
    
    private let persistenceKey = "lifeos_travel_trips"
    private let packingKey = "lifeos_travel_packing"
    
    public init() {
        loadFromDisk()
    }
    
    public func addTrip(_ trip: TravelTrip) {
        trips.append(trip)
        saveToDisk()
    }
    
    public func deleteTrip(at offsets: IndexSet) {
        trips.remove(atOffsets: offsets)
        saveToDisk()
    }
    
    public func deleteTrip(_ trip: TravelTrip) {
        trips.removeAll { $0.id == trip.id }
        saveToDisk()
    }
    
    public func togglePackingItem(_ item: PackingItem) {
        if let idx = packingList.firstIndex(where: { $0.id == item.id }) {
            packingList[idx].isPacked.toggle()
            saveToDisk()
        }
    }
    
    public func addPackingItem(_ item: PackingItem) {
        packingList.append(item)
        saveToDisk()
    }
    
    public func deletePackingItem(at offsets: IndexSet) {
        packingList.remove(atOffsets: offsets)
        saveToDisk()
    }
    
    public func deletePackingItem(_ item: PackingItem) {
        packingList.removeAll { $0.id == item.id }
        saveToDisk()
    }
    
    private func saveToDisk() {
        if let data = try? JSONEncoder().encode(trips) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
        if let data = try? JSONEncoder().encode(packingList) {
            UserDefaults.standard.set(data, forKey: packingKey)
        }
    }
    
    private func loadFromDisk() {
        if let data = UserDefaults.standard.data(forKey: persistenceKey),
           let saved = try? JSONDecoder().decode([TravelTrip].self, from: data) {
            trips = saved
        }
        if let data = UserDefaults.standard.data(forKey: packingKey),
           let saved = try? JSONDecoder().decode([PackingItem].self, from: data) {
            packingList = saved
        }
    }
}

// MARK: - View

public struct TravelPlannerView: View {
    @StateObject private var viewModel = TravelViewModel()
    @State private var selectedTab = 0
    @State private var newItemName = ""
    @State private var showCreateTrip = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            PremiumBackground()
            
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Travel Planner")
                            .font(.system(size: 28, weight: .bold, design: .default))
                            .foregroundColor(DesignSystem.textPrimary)
                        
                        Text("Itineraries and smart packing.")
                            .font(.system(size: 15, weight: .medium, design: .default))
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                    Spacer()
                    Button(action: { showCreateTrip = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                
                HStack(spacing: 0) {
                    Button("Trips") { selectedTab = 0 }
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundColor(selectedTab == 0 ? .white : DesignSystem.textMuted)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(selectedTab == 0 ? Capsule().fill(DesignSystem.backgroundSecondary) : nil)
                    
                    Button("Packing") { selectedTab = 1 }
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundColor(selectedTab == 1 ? .white : DesignSystem.textMuted)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(selectedTab == 1 ? Capsule().fill(DesignSystem.backgroundSecondary) : nil)
                }
                .padding(.horizontal)
                .padding(.vertical, 20)
                
                TabView(selection: $selectedTab) {
                    // Trips Tab
                    ScrollView {
                        if viewModel.trips.isEmpty {
                            EmptyStateView(
                                icon: "airplane.departure",
                                title: "No Trips Planned",
                                subtitle: "Create your first trip to start organizing your travels.",
                                actionTitle: "Create Trip",
                                onAction: { showCreateTrip = true }
                            )
                            .padding(.top, 40)
                        } else {
                            VStack(spacing: DesignSystem.spacingMD) {
                                ForEach(viewModel.trips) { trip in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(trip.destination)
                                                .font(.system(size: 18, weight: .bold, design: .default))
                                                .foregroundColor(DesignSystem.textPrimary)
                                            Spacer()
                                            Button(action: {
                                                HapticManager.notification(.warning)
                                                viewModel.deleteTrip(trip)
                                            }) {
                                                Image(systemName: "trash")
                                                    .foregroundColor(DesignSystem.error)
                                            }
                                            .buttonStyle(.plain)
                                            Text(trip.isUpcoming ? "Upcoming" : "Past")
                                                .font(.system(size: 12, weight: .bold, design: .default))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.white.opacity(0.1))
                                                .cornerRadius(6)
                                                .foregroundColor(DesignSystem.textSecondary)
                                        }
                                        
                                        Text("\(trip.startDate.formatted(date: .abbreviated, time: .omitted)) - \(trip.endDate.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.system(size: 14, weight: .medium, design: .default))
                                            .foregroundColor(DesignSystem.textMuted)
                                    }
                                    .padding()
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(16)
                                    .padding(.horizontal)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            HapticManager.notification(.warning)
                                            viewModel.deleteTrip(trip)
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .tag(0)
                    
                    // Packing Tab
                    ScrollView {
                        VStack(spacing: DesignSystem.spacingSM) {
                            HStack {
                                TextField("Add packing item...", text: $newItemName)
                                    .font(.system(size: 15, design: .default))
                                    .foregroundColor(DesignSystem.textPrimary)
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                                
                                Button(action: {
                                    guard !newItemName.isEmpty else { return }
                                    let item = PackingItem(name: newItemName, category: "General", isPacked: false)
                                    viewModel.addPackingItem(item)
                                    newItemName = ""
                                    HapticManager.impact(.light)
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundColor(DesignSystem.accentPrimary)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                            
                            if viewModel.packingList.isEmpty {
                                EmptyStateView(
                                    icon: "bag",
                                    title: "Packing List Empty",
                                    subtitle: "Add items to your packing list above."
                                )
                                .padding(.top, 20)
                            } else {
                                ForEach(viewModel.packingList) { item in
                                    HStack(spacing: 16) {
                                        Button {
                                            viewModel.togglePackingItem(item)
                                            HapticManager.impact(.light)
                                        } label: {
                                            Image(systemName: item.isPacked ? "checkmark.square.fill" : "square")
                                                .font(.system(size: 22))
                                                .foregroundColor(item.isPacked ? DesignSystem.accentPrimary : DesignSystem.textMuted)
                                        }
                                        
                                        VStack(alignment: .leading) {
                                            Text(item.name)
                                                .font(.system(size: 16, weight: .medium, design: .default))
                                                .foregroundColor(item.isPacked ? DesignSystem.textMuted : DesignSystem.textPrimary)
                                                .strikethrough(item.isPacked)
                                            
                                            Text(item.category)
                                                .font(.system(size: 12, weight: .regular, design: .default))
                                                .foregroundColor(DesignSystem.textMuted)
                                        }
                                        Spacer()
                                        Button(action: {
                                            HapticManager.notification(.warning)
                                            viewModel.deletePackingItem(item)
                                        }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(DesignSystem.error)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Remove item")
                                    }
                                    .padding()
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(12)
                                    .padding(.horizontal)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            HapticManager.notification(.warning)
                                            viewModel.deletePackingItem(item)
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .tag(1)
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif
            }
        }
        .sheet(isPresented: $showCreateTrip) {
            CreateTripSheet(viewModel: viewModel)
        }
    }
}

// MARK: - Create Trip Sheet

struct CreateTripSheet: View {
    @ObservedObject var viewModel: TravelViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var destination = ""
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
    @State private var isCreating = false
    
    var body: some View {
        NavigationStack {
            PremiumForm {
                Section("Destination") {
                    TextField("Where are you going?", text: $destination)
                        .font(.system(.body, design: .default))
                }
                Section("Dates") {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    DatePicker("End", selection: $endDate, displayedComponents: .date)
                }
            }
            .navigationTitle("New Trip")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        guard !destination.isEmpty else { return }
                        isCreating = true
                        let trip = TravelTrip(destination: destination, startDate: startDate, endDate: endDate)
                        viewModel.addTrip(trip)
                        HapticManager.notification(.success)
                        dismiss()
                    }) {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(destination.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
        }
    }
}
