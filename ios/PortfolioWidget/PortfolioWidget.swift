import WidgetKit
import SwiftUI

// App group shared with the Flutter app (see WidgetUpdateService._kIosAppGroup
// and the home_widget setAppGroupId call). Data keys match the ones written by
// WidgetUpdateService.updatePortfolioWidget: portfolio_value, gain_loss,
// gain_loss_pct, is_positive.
private let appGroupId = "group.com.kashu.app.widget"

struct PortfolioEntry: TimelineEntry {
    let date: Date
    let value: String
    let gainLoss: String
    let gainLossPct: String
    let isPositive: Bool
    let hasData: Bool
}

struct Provider: TimelineProvider {
    private func read() -> PortfolioEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let value = defaults?.string(forKey: "portfolio_value")
        return PortfolioEntry(
            date: Date(),
            value: value ?? "—",
            gainLoss: defaults?.string(forKey: "gain_loss") ?? "—",
            gainLossPct: defaults?.string(forKey: "gain_loss_pct") ?? "",
            isPositive: defaults?.bool(forKey: "is_positive") ?? true,
            hasData: value != nil
        )
    }

    func placeholder(in context: Context) -> PortfolioEntry {
        PortfolioEntry(date: Date(), value: "₹0.00", gainLoss: "₹0.00",
                       gainLossPct: "+0.00%", isPositive: true, hasData: true)
    }

    func getSnapshot(in context: Context,
                     completion: @escaping (PortfolioEntry) -> Void) {
        completion(read())
    }

    func getTimeline(in context: Context,
                     completion: @escaping (Timeline<PortfolioEntry>) -> Void) {
        let entry = read()
        // The Flutter side calls HomeWidget.updateWidget() (which reloads the
        // timeline) after every refresh; this periodic policy is just a
        // fallback so the "updated" time doesn't go stale if the app isn't
        // opened.
        let next = Calendar.current.date(byAdding: .minute, value: 30,
                                         to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct PortfolioWidgetEntryView: View {
    var entry: PortfolioEntry

    private var gainColor: Color {
        entry.isPositive ? Color(red: 0.20, green: 0.83, blue: 0.60)
                         : Color(red: 0.97, green: 0.44, blue: 0.44)
    }

    private var updatedText: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return "Updated \(f.string(from: entry.date))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("KashU")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundColor(.secondary)

            Text(entry.value)
                .font(.system(size: 22, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            if entry.hasData {
                HStack(spacing: 4) {
                    Text(entry.isPositive ? "▲" : "▼")
                    Text(entry.gainLoss)
                    Text(entry.gainLossPct)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(gainColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            } else {
                Text("Open KashU to sync")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 2)
            Text(updatedText)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackgroundCompat()
    }
}

// Keeps the widget building on iOS 17 (required containerBackground) and
// earlier SDKs alike.
private extension View {
    @ViewBuilder
    func containerBackgroundCompat() -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(.fill.tertiary, for: .widget)
        } else {
            self
        }
    }
}

struct PortfolioWidget: Widget {
    // Must match the iOSName passed to HomeWidget.updateWidget in
    // WidgetUpdateService ("PortfolioWidget").
    let kind: String = "PortfolioWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PortfolioWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("KashU Portfolio")
        .description("Your total portfolio value and today's move.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
