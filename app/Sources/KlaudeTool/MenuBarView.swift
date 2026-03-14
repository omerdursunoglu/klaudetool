import SwiftUI
import Charts
import ServiceManagement

struct MenuBarView: View {
    @Bindable var monitor: ClaudeSessionMonitor
    @Bindable var usageManager: UsageDataManager
    @AppStorage("selectedSound") private var selectedSound = "Glass"
    @AppStorage("volume") private var volume: Double = 0.5
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @State private var showSoundSettings = false
    @State private var selectedTimeRange: TimeRange = .sixHours

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Compact usage rows
            compactUsageRow(
                label: "5h",
                value: usageManager.fiveHourUtil,
                percent: usageManager.fiveHourPercent,
                resetText: usageManager.fiveHourResetText,
                color: fiveHourColor
            )
            compactUsageRow(
                label: "7d",
                value: usageManager.sevenDayUtil,
                percent: usageManager.sevenDayPercent,
                resetText: usageManager.sevenDayResetText,
                color: sevenDayColor
            )

            // Cost & Subscription
            HStack {
                Text(usageManager.totalCostText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                if let daysText = usageManager.subscriptionDaysText {
                    Text("renews \(daysText)")
                        .font(.system(size: 10))
                        .foregroundStyle(subscriptionColor)
                }
            }

            Divider()

            // Time range picker
            Picker("", selection: $selectedTimeRange) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            // Chart
            chartSection
                .frame(height: 100)

            // Status + Updated + Refresh
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 5, height: 5)
                Text(monitor.state.rawValue)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("\u{2022}")
                    .font(.system(size: 8))
                    .foregroundStyle(.quaternary)
                Text(usageManager.lastUpdateText)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(action: { usageManager.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }

            // Launch at Login + Quit
            HStack {
                Toggle(isOn: $launchAtLogin) {
                    Text("Launch at Login")
                        .font(.system(size: 11))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .onChange(of: launchAtLogin) { _, newValue in
                    setLaunchAtLogin(newValue)
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .buttonStyle(.borderless)
            }

            // Sound Settings (collapsible)
            DisclosureGroup(isExpanded: $showSoundSettings) {
                soundSection
            } label: {
                Label("Sound", systemImage: "speaker.wave.2")
                    .font(.system(size: 11))
            }
        }
        .padding(10)
        .frame(width: 300)
        .onAppear {
            monitor.soundManager.selectedSound = selectedSound
            monitor.soundManager.volume = Float(volume)
        }
    }

    // MARK: - Compact Usage Row

    private func compactUsageRow(label: String, value: Double, percent: Int, resetText: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * min(CGFloat(value), 1.0))
                }
            }
            .frame(height: 6)

            Text("\(percent)%")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 34, alignment: .trailing)

            Text(resetText)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 52, alignment: .trailing)
        }
    }

    // MARK: - Chart

    private var chartSection: some View {
        let now = Date()
        let cutoff = now.timeIntervalSince1970 - selectedTimeRange.seconds
        let filtered = usageManager.historyPoints.filter { $0.timestamp >= cutoff }
        let data = downsample(filtered)

        let dataSpan: TimeInterval = {
            guard let first = filtered.first, let last = filtered.last else { return 0 }
            return last.timestamp - first.timestamp
        }()
        let hasEnoughData = dataSpan > selectedTimeRange.seconds * 0.1

        return ZStack {
            Chart {
                ForEach(data) { point in
                    fiveHourMark(for: point)
                }
                ForEach(data) { point in
                    sevenDayMark(for: point)
                }
            }
            .chartXScale(domain: Date(timeIntervalSince1970: cutoff)...now)
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)%").font(.system(size: 8))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: xAxisStrideComponent, count: xAxisStrideCount)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(xAxisLabel(for: date))
                                .font(.system(size: 8))
                        }
                    }
                }
            }
            .chartForegroundStyleScale([
                "5h": Color.blue,
                "7d": Color.purple
            ])
            .chartLegend(.hidden)

            if !hasEnoughData {
                Text("Collecting data\u{2026}")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private func downsample(_ points: [UsageDataPoint]) -> [UsageDataPoint] {
        let maxPoints: Int
        switch selectedTimeRange {
        case .oneHour: maxPoints = 120
        case .sixHours: maxPoints = 360
        case .oneDay: maxPoints = 288
        case .sevenDays: maxPoints = 336
        case .thirtyDays: maxPoints = 360
        }

        guard points.count > maxPoints else { return points }

        let step = Double(points.count) / Double(maxPoints)
        var result: [UsageDataPoint] = []
        var index: Double = 0
        while Int(index) < points.count {
            result.append(points[Int(index)])
            index += step
        }
        if let last = points.last, result.last?.timestamp != last.timestamp {
            result.append(last)
        }
        return result
    }

    private func fiveHourMark(for point: UsageDataPoint) -> some ChartContent {
        LineMark(
            x: .value("Time", Date(timeIntervalSince1970: point.timestamp)),
            y: .value("Usage", point.fiveHourUtil * 100)
        )
        .foregroundStyle(by: .value("Series", "5h"))
        .interpolationMethod(.monotone)
    }

    private func sevenDayMark(for point: UsageDataPoint) -> some ChartContent {
        LineMark(
            x: .value("Time", Date(timeIntervalSince1970: point.timestamp)),
            y: .value("Usage", point.sevenDayUtil * 100)
        )
        .foregroundStyle(by: .value("Series", "7d"))
        .interpolationMethod(.monotone)
    }

    // MARK: - Sound Section

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Sound", selection: $selectedSound) {
                ForEach(SoundManager.availableSounds, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .font(.system(size: 11))
            .onChange(of: selectedSound) { _, newValue in
                monitor.soundManager.selectedSound = newValue
            }

            HStack(spacing: 6) {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 9))
                Slider(value: $volume, in: 0...1)
                    .onChange(of: volume) { _, newValue in
                        monitor.soundManager.volume = Float(newValue)
                    }
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 9))
            }

            Button("Test") {
                monitor.soundManager.play()
            }
            .font(.system(size: 11))
            .buttonStyle(.borderless)
        }
        .padding(.top, 4)
    }

    // MARK: - Colors

    private var fiveHourColor: Color {
        let v = usageManager.fiveHourUtil
        if v >= 0.80 { return .red }
        if v >= 0.50 { return .orange }
        return .green
    }

    private var sevenDayColor: Color {
        let v = usageManager.sevenDayUtil
        if v >= 0.80 { return .red }
        if v >= 0.50 { return .orange }
        return .purple
    }

    private var subscriptionColor: Color {
        guard let days = usageManager.subscriptionDaysLeft else { return .secondary }
        if days > 10 { return .green }
        if days > 5 { return .yellow }
        if days > 3 { return .orange }
        return .red
    }

    private var statusColor: Color {
        switch monitor.state {
        case .idle: return .gray
        case .working: return .green
        case .waitingInput: return .orange
        }
    }

    // MARK: - X Axis Formatting

    private var xAxisStrideComponent: Calendar.Component {
        switch selectedTimeRange {
        case .oneHour: return .minute
        case .sixHours: return .hour
        case .oneDay: return .hour
        case .sevenDays: return .day
        case .thirtyDays: return .day
        }
    }

    private var xAxisStrideCount: Int {
        switch selectedTimeRange {
        case .oneHour: return 15
        case .sixHours: return 2
        case .oneDay: return 6
        case .sevenDays: return 2
        case .thirtyDays: return 7
        }
    }

    private func xAxisLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        switch selectedTimeRange {
        case .oneHour, .sixHours:
            formatter.dateFormat = "HH:mm"
        case .oneDay:
            formatter.dateFormat = "HH:mm"
        case .sevenDays:
            formatter.dateFormat = "E dd"
        case .thirtyDays:
            formatter.dateFormat = "dd MMM"
        }
        return formatter.string(from: date)
    }

    // MARK: - Launch at Login

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silently handle - common to fail in dev builds
        }
    }
}
