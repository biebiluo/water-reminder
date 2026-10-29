import SwiftUI
import UserNotifications

struct WaterRecord: Identifiable, Codable {
    var id = UUID()
    var amount: Int
    var time: Date
}

@main
struct WaterReminderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @AppStorage("dailyGoal") private var dailyGoal = 2000
    @AppStorage("reminderOn") private var reminderOn = false
    @AppStorage("reminderMinutes") private var reminderMinutes = 120
    @State private var records: [WaterRecord] = []
    @State private var customAmount = 200
    @State private var lastDateKey = ""
    @State private var notice = ""

    private var todayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private var total: Int { records.reduce(0) { $0 + $1.amount } }
    private var progress: Double {
        guard dailyGoal > 0 else { return 0 }
        return min(1, Double(total) / Double(dailyGoal))
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Text("💧 今日喝水")
                            .font(.title2.bold())
                        Text("\(total) / \(dailyGoal) ml")
                            .font(.title.bold())
                        ProgressView(value: progress)
                            .tint(.blue)
                        Text(total >= dailyGoal ? "今天目标完成啦 🎉" : "还差 \(max(0, dailyGoal - total)) ml")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("快速记录").font(.headline)
                        HStack(spacing: 12) {
                            ForEach([100, 200, 300, 500], id: \.self) { amount in
                                Button("+\(amount)") { add(amount) }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                        HStack {
                            Stepper("自定义：\(customAmount) ml", value: $customAmount, in: 50...1000, step: 50)
                            Button("记录") { add(customAmount) }
                                .buttonStyle(.bordered)
                        }
                        HStack {
                            Button("撤销上一条") { undo() }.disabled(records.isEmpty)
                            Button("清空今日") { records = []; save() }
                                .foregroundStyle(.red)
                                .disabled(records.isEmpty)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("每日目标").font(.headline)
                        Stepper("\(dailyGoal) ml", value: $dailyGoal, in: 500...4000, step: 100)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("喝水提醒").font(.headline)
                        Toggle("开启提醒", isOn: $reminderOn)
                            .onChange(of: reminderOn) { _ in applyReminder() }
                        Picker("间隔", selection: $reminderMinutes) {
                            Text("1小时").tag(60)
                            Text("2小时").tag(120)
                            Text("3小时").tag(180)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: reminderMinutes) { _ in applyReminder() }
                        Text("开启后会按间隔发本地通知，提醒你喝水。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if !notice.isEmpty {
                            Text(notice).font(.footnote).foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("今日记录（\(records.count) 条）").font(.headline)
                        if records.isEmpty {
                            Text("还没有记录，喝一杯记一杯。").foregroundStyle(.secondary)
                        } else {
                            ForEach(records.reversed()) { record in
                                HStack {
                                    Text(timeFormatter.string(from: record.time))
                                    Spacer()
                                    Text("+\(record.amount) ml")
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("喝水提醒")
            .onAppear { load() }
        }
    }

    private func add(_ amount: Int) {
        records.append(WaterRecord(amount: amount, time: Date()))
        save()
    }

    private func undo() {
        records.removeLast()
        save()
    }

    private func load() {
        let key = todayKey
        lastDateKey = UserDefaults.standard.string(forKey: "waterLastDate") ?? ""
        if lastDateKey != key {
            records = []
            UserDefaults.standard.set(key, forKey: "waterLastDate")
            save()
            return
        }
        guard let data = UserDefaults.standard.data(forKey: "waterRecords"),
              let decoded = try? JSONDecoder().decode([WaterRecord].self, from: data) else {
            records = []
            return
        }
        records = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: "waterRecords")
        }
        UserDefaults.standard.set(todayKey, forKey: "waterLastDate")
    }

    private func applyReminder() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard reminderOn else {
            notice = "提醒已关闭"
            return
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                if !granted {
                    notice = "没有通知权限，请在系统设置里打开通知。"
                    return
                }
                for i in 1...8 {
                    let content = UNMutableNotificationContent()
                    content.title = "喝水提醒"
                    content.body = "该喝水了，喝一杯再继续。"
                    content.sound = .default
                    let trigger = UNTimeIntervalNotificationTrigger(
                        timeInterval: TimeInterval(reminderMinutes * 60 * i),
                        repeats: false
                    )
                    let request = UNNotificationRequest(
                        identifier: "water-\(i)",
                        content: content,
                        trigger: trigger
                    )
                    center.add(request)
                }
                notice = "提醒已开启，每 \(reminderMinutes) 分钟提醒一次。"
            }
        }
    }
}
