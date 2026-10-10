import Foundation
import CoreGraphics

@main
struct UsageTests {
    static func main() throws {
        let tests = UsageTests()
        try tests.testCodexWithOnlyWeeklyQuota()
        try tests.testClaudeSessionAndCodexWeeklyDifferentiation()
        try tests.testResetExpiryUsesUnusedCredits()
        try tests.testUnknownExpiryDoesNotDiscardResetCount()
        tests.testModelQuotaIsNotMislabelledAsWeekly()
        try tests.testActivityIncludesThirtyDaysWithGapsAndToday()
        try tests.testLastPositionSurvivesReload()
        try tests.testMoveWithoutOrcaClearsOldAnchor()
        tests.testFloatingPositionOutsideOrcaIsPreserved()
        tests.testChangedBarSizePreservesTopEdge()
        tests.testDockingLeftEdgeAdaptsPosition()
        tests.testDockingTopAndBottomEdgesAdaptPosition()
        try tests.testEdgePersistenceSurvivesReload()
        print("13 verificações de cotas, resets, histórico e posição passaram.")
    }

    func testCodexWithOnlyWeeklyQuota() throws {
        let data = Data(#"[{"provider":"codex","usage":{"loginMethod":"prolite","secondary":{"usedPercent":19,"resetsAt":"2026-10-10T21:00:00Z"}},"rateWindowLabels":{"secondary":"Weekly"}}]"#.utf8)
        let provider = try requireValue(UsageFetcher.decode(data).first)
        expectEqual(provider.weeklyWindow?.usedPercent, 19)
        expectEqual(provider.weeklyWindow?.label, "Limite semanal")
        expectEqual(provider.operationalWindow?.usedPercent, 19)
        expectEqual(provider.plan, "Prolite")
    }

    func testClaudeSessionAndCodexWeeklyDifferentiation() throws {
        let data = Data(#"[{"provider":"claude","usage":{"loginMethod":"Pro","primary":{"windowMinutes":300,"usedPercent":6},"secondary":{"windowMinutes":10080,"usedPercent":47}},"rateWindowLabels":{"primary":"Session","secondary":"Weekly"}}]"#.utf8)
        let provider = try requireValue(UsageFetcher.decode(data).first)
        expectEqual(provider.sessionWindow?.usedPercent, 6)
        expectEqual(provider.weeklyWindow?.usedPercent, 47)
        expectEqual(provider.operationalWindow?.usedPercent, 6)
        expectEqual(provider.sessionWindow?.label, "Sessão (5 horas)")
        expectEqual(provider.weeklyWindow?.label, "Semanal (todos os modelos)")
    }

    func testResetExpiryUsesUnusedCredits() throws {
        let data = Data(#"[{"provider":"codex","usage":{"codexResetCredits":{"availableCount":1,"credits":[{"status":"used","expires_at":"2026-10-08T00:00:00Z"},{"status":"available","expires_at":"2026-10-29T00:00:00.000Z"}]}}}]"#.utf8)
        let provider = try requireValue(UsageFetcher.decode(data).first)
        expectEqual(provider.resetCreditsCount, 1)
        expectEqual(provider.resetCreditsExpireAt, ISO8601DateFormatter().date(from: "2026-10-29T00:00:00Z"))
    }

    func testUnknownExpiryDoesNotDiscardResetCount() throws {
        let data = Data(#"[{"provider":"codex","usage":{"codexResetCredits":{"availableCount":1,"credits":[{"status":"available","expires_at":"unknown"}]}}}]"#.utf8)
        let provider = try requireValue(UsageFetcher.decode(data).first)
        expectEqual(provider.resetCreditsCount, 1)
        expectNil(provider.resetCreditsExpireAt)
    }

    func testModelQuotaIsNotMislabelledAsWeekly() {
        let provider = ProviderUsage(id: "antigravity", name: "Antigravity", windows: [
            UsageWindow(id: "gemini", label: "Gemini", usedPercent: 20, resetsAt: nil, runsOutAt: nil),
            UsageWindow(id: "claude", label: "Claude", usedPercent: 30, resetsAt: nil, runsOutAt: nil),
        ])
        expectNil(provider.weeklyWindow)
    }

    func testActivityIncludesThirtyDaysWithGapsAndToday() throws {
        let data = Data(#"{"provider":"codex","daily":[{"date":"2026-09-07","totalTokens":9999},{"date":"2026-09-08","totalTokens":50},{"date":"2026-10-06","totalTokens":100},{"date":"2026-10-07","totalTokens":250},{"date":"2026-10-08","totalTokens":9999}]}"#.utf8)
        let activity = try JSONDecoder().decode(TokenActivity.self, from: data)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try requireValue(TimeZone(identifier: "America/Fortaleza"))
        let now = try requireValue(ISO8601DateFormatter().date(from: "2026-10-08T01:00:00Z"))
        let samples = activity.samples(now: now, calendar: calendar)
        expectEqual(samples.count, 30)
        expectEqual(Set(samples.map(\.id)).count, 30)
        expectEqual(samples.first?.tokens, 50)
        expectEqual(samples.last?.tokens, 250)
        expectEqual(samples.filter { $0.tokens == 0 }.count, 27)
        expectEqual(samples.reduce(0) { $0 + $1.tokens }, 400)
    }

    func testLastPositionSurvivesReload() throws {
        let suite = "local.usoia.tests.\(UUID().uuidString)"
        let defaults = try requireValue(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = CGRect(x: 100, y: 100, width: 54, height: 256)
        let last = CGRect(x: 720, y: 430, width: 54, height: 256)
        BarPlacement(frame: first, docked: false, orcaFrame: nil, screenID: 1).save(to: defaults)
        let saved = BarPlacement(frame: last, docked: false, orcaFrame: nil, screenID: 1)
        saved.save(to: defaults)
        let reopenedDefaults = try requireValue(UserDefaults(suiteName: suite))
        let reopened = try requireValue(BarPlacement.load(from: reopenedDefaults))
        expectEqual(reopened, saved)
        expectEqual(reopened.restoredFrame(size: last.size, visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), orcaFrame: nil), last)
    }

    func testMoveWithoutOrcaClearsOldAnchor() throws {
        let suite = "local.usoia.tests.\(UUID().uuidString)"
        let defaults = try requireValue(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(110.0, forKey: "barX")
        defaults.set(600.0, forKey: "barTop")
        defaults.set(20.0, forKey: "barRelativeX")
        defaults.set(50.0, forKey: "barRelativeTop")
        expectEqual(BarPlacement.load(from: defaults)?.top, 600)
        let saved = BarPlacement(frame: CGRect(x: 600, y: 150, width: 54, height: 256), docked: false, orcaFrame: nil, screenID: 1)
        saved.save(to: defaults)
        expectNil(defaults.object(forKey: "barRelativeX"))
        expectNil(defaults.object(forKey: "barRelativeTop"))
        expectEqual(BarPlacement.load(from: defaults), saved)
    }

    func testFloatingPositionOutsideOrcaIsPreserved() {
        let frame = CGRect(x: 60, y: 50, width: 54, height: 256)
        let saved = BarPlacement(frame: frame, docked: false, orcaFrame: nil, screenID: 1)
        let result = saved.restoredFrame(size: frame.size,
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            orcaFrame: CGRect(x: 400, y: 400, width: 1200, height: 600))
        expectEqual(result, frame)
    }

    func testChangedBarSizePreservesTopEdge() {
        let saved = BarPlacement(frame: CGRect(x: 500, y: 400, width: 78, height: 388), docked: false, orcaFrame: nil, screenID: 1)
        let result = saved.restoredFrame(size: CGSize(width: 54, height: 256),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), orcaFrame: nil)
        expectEqual(result.minX, 500)
        expectEqual(result.maxY, 788)
    }

    func testDockingLeftEdgeAdaptsPosition() {
        let frame = CGRect(x: 15, y: 300, width: 54, height: 256)
        let saved = BarPlacement(frame: frame, docked: true, edge: .left, orcaFrame: nil, screenID: 1)
        let result = saved.restoredFrame(
            size: frame.size,
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            orcaFrame: nil)
        expectEqual(result.minX, 0)
        expectEqual(result.maxY, 556)
        expectEqual(result.width, 54)
        expectEqual(result.height, 256)
    }

    func testDockingTopAndBottomEdgesAdaptPosition() {
        let size = CGSize(width: 256, height: 54)
        // Borda superior (topo)
        let topFrame = CGRect(x: 400, y: 1026, width: 256, height: 54)
        let topSaved = BarPlacement(frame: topFrame, docked: true, edge: .top, orcaFrame: nil, screenID: 1)
        let topResult = topSaved.restoredFrame(
            size: size,
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            orcaFrame: nil)
        expectEqual(topResult.maxY, 1080)
        expectEqual(topResult.minX, 400)

        // Borda inferior (base)
        let bottomFrame = CGRect(x: 400, y: 5, width: 256, height: 54)
        let bottomSaved = BarPlacement(frame: bottomFrame, docked: true, edge: .bottom, orcaFrame: nil, screenID: 1)
        let bottomResult = bottomSaved.restoredFrame(
            size: size,
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            orcaFrame: nil)
        expectEqual(bottomResult.minY, 0)
        expectEqual(bottomResult.minX, 400)
    }

    func testEdgePersistenceSurvivesReload() throws {
        let suite = "local.usoia.tests.\(UUID().uuidString)"
        let defaults = try requireValue(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        for edge in [DockEdge.left, .right, .top, .bottom] {
            let frame = CGRect(x: 200, y: 200, width: 54, height: 256)
            let saved = BarPlacement(frame: frame, docked: true, edge: edge, orcaFrame: nil, screenID: 1)
            saved.save(to: defaults)
            let reloaded = try requireValue(BarPlacement.load(from: defaults))
            expectEqual(reloaded.edge, edge)
            expectEqual(reloaded.docked, true)
        }
    }
}

// Executável sem XCTest para funcionar apenas com Xcode Command Line Tools.
private func requireValue<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) throws -> T {
    guard let value else { fatalError("Valor ausente", file: file, line: line) }
    return value
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) {
    guard actual == expected else { fatalError("Esperado \(expected), recebido \(actual)", file: file, line: line) }
}

private func expectNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
    guard value == nil else { fatalError("Esperado nil", file: file, line: line) }
}
