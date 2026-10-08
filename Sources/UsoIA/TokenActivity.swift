import Foundation

/// Totais locais fornecidos pelo CodexBar, sem armazenar prompts ou caminhos de projetos.
struct TokenActivity: Decodable {
    struct Day: Decodable {
        let date: String
        let totalTokens: Int?
    }

    struct Sample: Identifiable {
        let date: Date
        let tokens: Int
        var id: Date { date }
    }

    let provider: String
    let daily: [Day]?

    func samples(now: Date = Date(), calendar: Calendar = .current) -> [Sample] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let totals = (daily ?? []).reduce(into: [String: Int]()) { result, day in
            guard let tokens = day.totalTokens else { return }
            result[day.date, default: 0] += max(tokens, 0)
        }
        let today = calendar.startOfDay(for: now)
        return (0..<30).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset - 29, to: today) else { return nil }
            return Sample(date: date, tokens: totals[formatter.string(from: date)] ?? 0)
        }
    }

    static func fetch(provider: String) async throws -> TokenActivity? {
        let data = try await UsageFetcher.run(arguments: ["cost", "--provider", provider, "--days", "30", "--json"])
        let items = try JSONDecoder().decode([TokenActivity].self, from: data)
        return items.first { $0.provider == provider && $0.daily != nil }
    }
}
