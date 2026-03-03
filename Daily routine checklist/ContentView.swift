import SwiftUI

// MARK: - DATA MODELS

enum CategoryColor: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, purple, pink, gray
    var id: String { self.rawValue }
    
    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .gray: return .secondary
        }
    }
}

enum Weekday: Int, CaseIterable, Codable, Identifiable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
    var id: Int { self.rawValue }
    var shortName: String {
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][self.rawValue - 1]
    }
}

struct ChecklistItem: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var time: TimeOfDay
    var intervalDays: Int
    var startDate: Date
    var categoryColor: CategoryColor
    var datesTaken: [Date] = []
    var deletedDates: [Date] = []
    var selectedWeekdays: Set<Int> = []
    
    func isCompleted(on date: Date) -> Bool {
        datesTaken.contains { Calendar.current.isDate($0, inSameDayAs: date) }
    }
}

enum TimeOfDay: String, Codable, CaseIterable, Identifiable {
    case morning, withMeal = "With Meal", evening
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    
    var sortOrder: Int {
        switch self {
        case .morning: return 0
        case .withMeal: return 1
        case .evening: return 2
        }
    }
}

// MARK: - MAIN CONTENT VIEW

struct ContentView: View {
    @State private var items: [ChecklistItem] = []
    @State private var calendarGrouped: [Date: [ChecklistItem]] = [:]
    
    // UI State
    @State private var showingAddItem = false
    @State private var itemToEdit: ChecklistItem?
    @State private var scrollToDate: Date?
    
    // Delete Confirmation State
    @State private var itemToPendingDelete: ChecklistItem?
    @State private var dateOfPendingDelete: Date?
    @State private var showingDeleteOptions = false
    
    private let storageKey = "recurringChecklistItems_v4"
    private let pastDays = 30
    private let futureDays = 60
    
    var visibleDates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -pastDays, to: today),
              let end = calendar.date(byAdding: .day, value: futureDays, to: today) else { return [] }
        
        var dates: [Date] = []
        var current = start
        while current <= end {
            dates.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return dates
    }
    
    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                CalendarListView(
                    sortedDates: visibleDates,
                    calendarGrouped: calendarGrouped,
                    bindingForItem: binding(for:),
                    onEdit: { itemToEdit = $0 },
                    onDelete: prepareDelete,
                    onMove: moveItem
                )
                .onChange(of: scrollToDate) { _, newValue in
                    if let date = newValue {
                        withAnimation(.spring()) { proxy.scrollTo(date, anchor: .top) }
                    }
                }
            }
            .confirmationDialog("Delete Item", isPresented: $showingDeleteOptions, titleVisibility: .visible) {
                Button("Delete for this day only") { deleteSingleInstance() }
                Button("Delete for all days", role: .destructive) { deleteAllInstances() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Would you like to remove '\(itemToPendingDelete?.name ?? "")' just for today or delete the entire recurring item?")
            }
            .navigationTitle("Checklist")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack {
                        Button("Today") { jumpToToday() }
                        EditButton()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingAddItem = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .onAppear {
            loadItems()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { jumpToToday() }
        }
        .onChange(of: items) { _ in
            saveItems()
            calculateSchedule()
        }
        .sheet(isPresented: $showingAddItem) {
            ItemFormView(title: "New Item", onSave: { newItem in
                items.append(newItem)
            })
        }
        .sheet(item: $itemToEdit) { item in
            ItemFormView(title: "Edit Item", existingItem: item, onSave: { updatedItem in
                if let index = items.firstIndex(where: { $0.id == updatedItem.id }) {
                    items[index] = updatedItem
                }
            })
        }
    }
    
    // MARK: - LOGIC METHODS
    
    func calculateSchedule() {
        let calendar = Calendar.current
        var dict: [Date: [ChecklistItem]] = [:]
        
        for date in visibleDates {
            let startOfDate = calendar.startOfDay(for: date)
            
            let itemsForDate = items.filter { item in
                let wasTaken = item.isCompleted(on: date)
                let isDeleted = item.deletedDates.contains { calendar.isDate($0, inSameDayAs: date) }
                
                var isScheduled = false
                if !item.selectedWeekdays.isEmpty {
                    isScheduled = item.selectedWeekdays.contains(calendar.component(.weekday, from: date))
                } else {
                    let daysBetween = calendar.dateComponents([.day], from: calendar.startOfDay(for: item.startDate), to: startOfDate).day ?? 0
                    isScheduled = daysBetween % item.intervalDays == 0
                }
                
                return (wasTaken || isScheduled) && !isDeleted
            }
            dict[date] = itemsForDate
        }
        self.calendarGrouped = dict
    }
    
    func binding(for item: ChecklistItem) -> Binding<ChecklistItem> {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return .constant(item) }
        return $items[index]
    }
    
    func prepareDelete(_ item: ChecklistItem, on date: Date) {
        itemToPendingDelete = item
        dateOfPendingDelete = date
        showingDeleteOptions = true
    }
    
    func deleteSingleInstance() {
        if let item = itemToPendingDelete, let date = dateOfPendingDelete,
           let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].deletedDates.append(Calendar.current.startOfDay(for: date))
        }
    }
    
    func deleteAllInstances() {
        items.removeAll { $0.id == itemToPendingDelete?.id }
    }

    func jumpToToday() {
        scrollToDate = nil
        DispatchQueue.main.async { scrollToDate = Calendar.current.startOfDay(for: Date()) }
    }
    
    // Persistence
    func loadItems() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ChecklistItem].self, from: data) {
            items = decoded
        } else {
            let today = Calendar.current.startOfDay(for: Date())
            items = [
                ChecklistItem(id: UUID(), name: "Vitamin D", time: .morning, intervalDays: 1, startDate: today, categoryColor: .orange),
                ChecklistItem(id: UUID(), name: "Hair Care", time: .morning, intervalDays: 3, startDate: today, categoryColor: .pink)
            ]
        }
        calculateSchedule()
    }
    
    func saveItems() {
        if let encoded = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    func moveItem(from source: IndexSet, to destination: Int, for date: Date) {
        var itemsOnDay = calendarGrouped[date] ?? []
        guard let sourceIndex = source.first else { return }
        let movedItem = itemsOnDay[sourceIndex]
        
        itemsOnDay.move(fromOffsets: source, toOffset: destination)
        guard let _ = itemsOnDay.firstIndex(where: { $0.id == movedItem.id }) else { return }
        
        var workingItems = items
        guard let oldMasterIndex = workingItems.firstIndex(where: { $0.id == movedItem.id }) else { return }
        let itemToMove = workingItems.remove(at: oldMasterIndex)
        
        // Re-insertion logic remains the same to maintain your specific sorting requirement
        if let newDailyIndex = itemsOnDay.firstIndex(where: { $0.id == movedItem.id }) {
            if newDailyIndex + 1 < itemsOnDay.count {
                let nextItem = itemsOnDay[newDailyIndex + 1]
                if let target = workingItems.firstIndex(where: { $0.id == nextItem.id }) {
                    workingItems.insert(itemToMove, at: target)
                }
            } else if newDailyIndex - 1 >= 0 {
                let prevItem = itemsOnDay[newDailyIndex - 1]
                if let target = workingItems.firstIndex(where: { $0.id == prevItem.id }) {
                    workingItems.insert(itemToMove, at: target + 1)
                }
            } else {
                workingItems.insert(itemToMove, at: oldMasterIndex)
            }
        }
        items = workingItems
    }
}

// MARK: - REUSABLE UI COMPONENTS

struct CalendarListView: View {
    @Environment(\.editMode) private var editMode
    let sortedDates: [Date]
    let calendarGrouped: [Date: [ChecklistItem]]
    let bindingForItem: (ChecklistItem) -> Binding<ChecklistItem>
    let onEdit: (ChecklistItem) -> Void
    let onDelete: (ChecklistItem, Date) -> Void
    let onMove: (IndexSet, Int, Date) -> Void
    
    var body: some View {
        List {
            ForEach(sortedDates, id: \.self) { date in
                Section(header: sectionHeader(for: date)) {
                    ForEach(calendarGrouped[date] ?? []) { item in
                        ChecklistRowCalendar(item: bindingForItem(item), date: date)
                            .swipeActions(edge: .leading) {
                                Button { onEdit(item) } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { onDelete(item, date) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                    .onMove(perform: editMode?.wrappedValue.isEditing == true ? { onMove($0, $1, date) } : nil)
                }
            }
        }
    }
    
    private func sectionHeader(for date: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        return Text(dateFormatter.string(from: date))
            .foregroundColor(isToday ? .blue : .secondary)
            .fontWeight(isToday ? .bold : .regular)
            .id(date)
    }
}

struct ChecklistRowCalendar: View {
    @Binding var item: ChecklistItem
    var date: Date
    @Environment(\.editMode) private var editMode
    
    private let impactMed = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    
    var isFuture: Bool { date > Calendar.current.startOfDay(for: Date()) }
    var isPast: Bool { date < Calendar.current.startOfDay(for: Date()) }
    
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(item.categoryColor.color)
                .frame(width: 4)
                .padding(.vertical, 8)
                .opacity(isPast && !item.isCompleted(on: date) ? 0.3 : (isFuture && !item.isCompleted(on: date) ? 0.5 : 1.0))
            
            statusIcon
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body).fontWeight(.medium)
                    .foregroundColor(isPast && !item.isCompleted(on: date) ? .secondary : .primary)
                Text(item.time.displayName).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if isFuture && !item.isCompleted(on: date) {
                Image(systemName: "lock.fill").font(.caption2).foregroundColor(.secondary.opacity(0.4))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .allowsHitTesting(editMode?.wrappedValue.isEditing == false)
        .onTapGesture {
            if !isFuture || item.isCompleted(on: date) {
                impactMed.impactOccurred()
                toggleStatus()
            }
        }
        .onLongPressGesture(minimumDuration: 0.8) {
            if isFuture && !item.isCompleted(on: date) {
                impactHeavy.impactOccurred()
                toggleStatus()
            }
        }
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        if item.isCompleted(on: date) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(item.categoryColor.color)
        } else if isPast {
            Image(systemName: "xmark.circle").foregroundColor(.secondary.opacity(0.5))
        } else {
            Image(systemName: "circle").foregroundColor(Color(.systemGray4).opacity(isFuture ? 0.4 : 1.0))
        }
    }
    
    func toggleStatus() {
        let dayOfAction = Calendar.current.startOfDay(for: date)
        if item.isCompleted(on: dayOfAction) {
            item.datesTaken.removeAll { Calendar.current.isDate($0, inSameDayAs: dayOfAction) }
        } else {
            item.datesTaken.append(dayOfAction)
        }
    }
}

// MARK: - UNIFIED ITEM FORM

struct ItemFormView: View {
    @Environment(\.dismiss) var dismiss
    let title: String
    var existingItem: ChecklistItem?
    var onSave: (ChecklistItem) -> Void
    
    @State private var name: String = ""
    @State private var time: TimeOfDay = .morning
    @State private var interval: Int = 1
    @State private var color: CategoryColor = .blue
    @State private var scheduleMode = 0
    @State private var selectedWeekdays: Set<Int> = []
    
    var body: some View {
        NavigationView {
            Form {
                Section("Item Details") {
                    TextField("Name", text: $name)
                    Picker("Category Color", selection: $color) {
                        ForEach(CategoryColor.allCases) { cat in
                            Label(cat.rawValue.capitalized, systemImage: "circle.fill")
                                .foregroundColor(cat.color).tag(cat)
                        }
                    }.pickerStyle(.navigationLink)
                }
                
                Section("Schedule") {
                    Picker("Time", selection: $time) {
                        ForEach(TimeOfDay.allCases) { t in Text(t.displayName).tag(t) }
                    }.pickerStyle(.segmented)
                    
                    Picker("Schedule Type", selection: $scheduleMode) {
                        Text("Interval").tag(0)
                        Text("Weekdays").tag(1)
                    }.pickerStyle(.segmented).padding(.vertical, 4)
                    
                    if scheduleMode == 0 {
                        Stepper("Every \(interval) day(s)", value: $interval, in: 1...30)
                    } else {
                        weekdayPicker
                    }
                }
            }
            .navigationTitle(title)
            .onAppear {
                if let item = existingItem {
                    name = item.name
                    time = item.time
                    interval = item.intervalDays
                    color = item.categoryColor
                    selectedWeekdays = item.selectedWeekdays
                    scheduleMode = item.selectedWeekdays.isEmpty ? 0 : 1
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let newItem = ChecklistItem(
                            id: existingItem?.id ?? UUID(),
                            name: name,
                            time: time,
                            intervalDays: interval,
                            startDate: existingItem?.startDate ?? Calendar.current.startOfDay(for: Date()),
                            categoryColor: color,
                            datesTaken: existingItem?.datesTaken ?? [],
                            deletedDates: existingItem?.deletedDates ?? [],
                            selectedWeekdays: scheduleMode == 1 ? selectedWeekdays : []
                        )
                        onSave(newItem)
                        dismiss()
                    }.disabled(name.isEmpty || (scheduleMode == 1 && selectedWeekdays.isEmpty))
                }
            }
        }
    }
    
    private var weekdayPicker: some View {
        HStack(spacing: 4) {
            ForEach(Weekday.allCases) { day in
                let isSelected = selectedWeekdays.contains(day.rawValue)
                Text(day.shortName)
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 35)
                    .background(isSelected ? color.color : Color(.systemGray6))
                    .foregroundColor(isSelected ? .white : .primary)
                    .cornerRadius(8)
                    .onTapGesture {
                        if isSelected { selectedWeekdays.remove(day.rawValue) }
                        else { selectedWeekdays.insert(day.rawValue) }
                    }
            }
        }.padding(.vertical, 8)
    }
}

// MARK: - HELPERS

let dateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "EEEE, MMM d"
    return df
}()
