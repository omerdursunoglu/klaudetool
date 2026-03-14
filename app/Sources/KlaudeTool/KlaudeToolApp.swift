import SwiftUI

@MainActor
let sharedMonitor: ClaudeSessionMonitor = {
    let m = ClaudeSessionMonitor()
    m.start()
    return m
}()

@MainActor
let sharedUsageManager: UsageDataManager = {
    let m = UsageDataManager()
    m.start()
    return m
}()

@main
struct KlaudeToolApp: App {
    var body: some Scene {
        MenuBarExtra {
            MenuBarView(monitor: sharedMonitor, usageManager: sharedUsageManager)
                .onAppear {
                    sharedMonitor.clearNotification()
                }
        } label: {
            let img = renderMenuBarIcon(
                fiveHour: sharedUsageManager.fiveHourUtil,
                sevenDay: sharedUsageManager.sevenDayUtil
            )
            Image(nsImage: img)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
func renderMenuBarIcon(fiveHour: Double, sevenDay: Double) -> NSImage {
    let height: CGFloat = 22
    let barWidth: CGFloat = 28
    let barHeight: CGFloat = 4
    let labelFont = NSFont.monospacedSystemFont(ofSize: 8, weight: .bold)

    let attrs5h: [NSAttributedString.Key: Any] = [.font: labelFont]
    let size5h = ("5h" as NSString).size(withAttributes: attrs5h)
    let size7d = ("7d" as NSString).size(withAttributes: attrs5h)
    let labelW = max(size5h.width, size7d.width)

    let barGap: CGFloat = 2
    let totalWidth = labelW + barGap + barWidth

    let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { rect in
        let textX: CGFloat = 0
        let barX = textX + labelW + barGap

        let row1Y = height / 2 + 1
        let drawAttrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: NSColor.labelColor]
        ("5h" as NSString).draw(at: NSPoint(x: textX, y: row1Y), withAttributes: drawAttrs)

        let bar1Y = row1Y + size5h.height / 2 - barHeight / 2
        NSColor.labelColor.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: NSRect(x: barX, y: bar1Y, width: barWidth, height: barHeight), xRadius: 1.5, yRadius: 1.5).fill()
        barColor(for: fiveHour, isFiveHour: true).setFill()
        NSBezierPath(roundedRect: NSRect(x: barX, y: bar1Y, width: barWidth * min(fiveHour, 1.0), height: barHeight), xRadius: 1.5, yRadius: 1.5).fill()

        let row2Y = height / 2 - size7d.height - 1
        ("7d" as NSString).draw(at: NSPoint(x: textX, y: row2Y), withAttributes: drawAttrs)

        let bar2Y = row2Y + size7d.height / 2 - barHeight / 2
        NSColor.labelColor.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: NSRect(x: barX, y: bar2Y, width: barWidth, height: barHeight), xRadius: 1.5, yRadius: 1.5).fill()
        barColor(for: sevenDay, isFiveHour: false).setFill()
        NSBezierPath(roundedRect: NSRect(x: barX, y: bar2Y, width: barWidth * min(sevenDay, 1.0), height: barHeight), xRadius: 1.5, yRadius: 1.5).fill()

        return true
    }

    image.isTemplate = false
    return image
}

func barColor(for value: Double, isFiveHour: Bool = true) -> NSColor {
    if value >= 0.75 { return .systemRed }
    if value >= 0.50 { return .systemOrange }
    return isFiveHour ? .systemGreen : .systemPurple
}
