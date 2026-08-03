import SwiftUI
import Combine
import EventKit
import LifeOSCore

// MARK: - ViewModel

@MainActor
public final class CalendarViewModel: ObservableObject {
    @Published public var events: [CalendarEventItem] = []
    @Published public var isSyncingWithAppleCalendar = false
    @Published public var syncMessage: String? = nil
    
    private let persistenceKey = "lifeos_calendar_events"
    private let eventStore = EKEventStore()
    
    public init() {
        loadFromDisk()
    }
    
    public func addEvent(_ event: CalendarEventItem) {
        events.append(event)
        events.sort { $0.startDate < $1.startDate }
        saveToDisk()
    }
    
    public func deleteEvent(at offsets: IndexSet) {
        events.remove(atOffsets: offsets)
        saveToDisk()
    }
    
    public func deleteEvent(_ event: CalendarEventItem) {
        events.removeAll { $0.id == event.id }
        saveToDisk()
    }
    
    public func syncWithAppleCalendar() async {
        isSyncingWithAppleCalendar = true
        syncMessage = nil
        
        do {
            let granted: Bool
            if #available(iOS 17.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await withCheckedThrowingContinuation { continuation in
                    eventStore.requestAccess(to: .event) { accessGranted, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: accessGranted)
                        }
                    }
                }
            }
            
            if granted {
                let startDate = Calendar.current.startOfDay(for: Date())
                let endDate = Calendar.current.date(byAdding: .day, value: 7, to: startDate)!
                let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
                let ekEvents = eventStore.events(matching: predicate)
                
                var imported: [CalendarEventItem] = []
                for ek in ekEvents {
                    let item = CalendarEventItem(
                        title: ek.title ?? "Calendar Event",
                        startDate: ek.startDate,
                        endDate: ek.endDate,
                        location: ek.location,
                        energyCost: .moderate,
                        isDeepWorkTime: false
                    )
                    imported.append(item)
                }
                
                // Merge with manual events (avoid duplicate title+startDate)
                for item in imported {
                    if !events.contains(where: { $0.title == item.title && abs($0.startDate.timeIntervalSince(item.startDate)) < 60 }) {
                        events.append(item)
                    }
                }
                events.sort { $0.startDate < $1.startDate }
                saveToDisk()
                syncMessage = "Synced \(imported.count) events from Apple Calendar"
            } else {
                syncMessage = "Calendar permission was denied."
            }
        } catch {
            syncMessage = "Calendar sync failed: \(error.localizedDescription)"
        }
        
        isSyncingWithAppleCalendar = false
    }
    
    private func saveToDisk() {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }
    
    private func loadFromDisk() {
        if let data = UserDefaults.standard.data(forKey: persistenceKey),
           let saved = try? JSONDecoder().decode([CalendarEventItem].self, from: data) {
            events = saved
        }
    }
}

// MARK: - View

public struct CalendarIntelligenceView: View {
    @StateObject private var viewModel = CalendarViewModel()
    @State private var showAddSheet = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            PremiumBackground()
            
            VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Calendar Intelligence")
                            .font(.system(size: 28, weight: .bold, design: .default))
                            .foregroundColor(DesignSystem.textPrimary)
                        
                        Text("Your time, optimized for your energy.")
                            .font(.system(size: 15, weight: .medium, design: .default))
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                    Spacer()
                    
                    // Apple Calendar Sync Button
                    Button(action: {
                        Task { await viewModel.syncWithAppleCalendar() }
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(DesignSystem.textMuted)
                            .padding(10)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .disabled(viewModel.isSyncingWithAppleCalendar)
                    
                    // Add Manual Event
                    Button(action: { showAddSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                
                if let syncMsg = viewModel.syncMessage {
                    Text(syncMsg)
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundColor(DesignSystem.textMuted)
                        .padding(.horizontal)
                }
                
                if viewModel.events.isEmpty {
                    EmptyStateView(
                        icon: "calendar.badge.clock",
                        title: "No Events Scheduled",
                        subtitle: "Add manual events or sync with your Apple Calendar.",
                        actionTitle: "Add Event",
                        onAction: { showAddSheet = true }
                    )
                } else {
                    ScrollView {
                        VStack(spacing: DesignSystem.spacingMD) {
                            ForEach(viewModel.events) { event in
                                HStack(alignment: .top, spacing: 16) {
                                    VStack {
                                        Text(event.startDate.formatted(date: .omitted, time: .shortened))
                                            .font(.system(size: 14, weight: .semibold, design: .default))
                                            .foregroundColor(DesignSystem.textSecondary)
                                        Text(event.endDate.formatted(date: .omitted, time: .shortened))
                                            .font(.system(size: 12, weight: .regular, design: .default))
                                            .foregroundColor(DesignSystem.textMuted)
                                    }
                                    .frame(width: 70, alignment: .trailing)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(event.title)
                                            .font(.system(size: 16, weight: .bold, design: .default))
                                            .foregroundColor(DesignSystem.textPrimary)
                                        if let loc = event.location, !loc.isEmpty {
                                            Text(loc)
                                                .font(.system(size: 13, weight: .medium, design: .default))
                                                .foregroundColor(DesignSystem.textSecondary)
                                        }
                                    }
                                    Spacer()
                                    Button(action: {
                                        HapticManager.notification(.warning)
                                        viewModel.deleteEvent(event)
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(DesignSystem.error)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove event")
                                }
                                .padding()
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(16)
                                .padding(.horizontal)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        HapticManager.notification(.warning)
                                        viewModel.deleteEvent(event)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddCalendarEventSheet(viewModel: viewModel)
        }
    }
}

// MARK: - Add Event Sheet

struct AddCalendarEventSheet: View {
    @ObservedObject var viewModel: CalendarViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = ""
    @State private var location = ""
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(3600)
    @State private var isCreating = false
    
    var body: some View {
        NavigationStack {
            PremiumForm {
                Section("Event Details") {
                    TextField("Event Title (e.g. Team Sync, Doctor)", text: $title)
                        .font(.system(.body, design: .default))
                    TextField("Location / Link (optional)", text: $location)
                        .font(.system(.body, design: .default))
                }
                Section("Time") {
                    DatePicker("Starts", selection: $startDate)
                    DatePicker("Ends", selection: $endDate)
                }
            }
            .navigationTitle("New Event")
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
                        guard !title.isEmpty else { return }
                        isCreating = true
                        let event = CalendarEventItem(
                            title: title,
                            startDate: startDate,
                            endDate: endDate,
                            location: location.isEmpty ? nil : location,
                            energyCost: .moderate
                        )
                        viewModel.addEvent(event)
                        HapticManager.notification(.success)
                        dismiss()
                    }) {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
        }
    }
}
