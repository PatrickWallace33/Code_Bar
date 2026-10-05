import Foundation

/// Busca o uso rodando o CLI que vem dentro do CodexBar.
enum UsageFetcher {
    static let cliPath = "/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI"

    enum FetchError: LocalizedError {
        case cliMissing
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cliMissing: return "CodexBar não encontrado em /Applications."
            case .failed(let message): return message
            }
        }
    }

    static func fetchRaw(timeout: TimeInterval = 90) async throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: cliPath) else { throw FetchError.cliMissing }
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: cliPath)
                p.arguments = ["usage", "--json", "--no-credits"]

                // Apps abertos pelo Finder herdam um PATH mínimo; o CLI pode precisar de claude/codex/agy.
                var env = ProcessInfo.processInfo.environment
                let home = NSHomeDirectory()
                env["PATH"] = [
                    "\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin",
                    "/usr/bin", "/bin", "/usr/sbin", "/sbin", env["PATH"] ?? "",
                ].joined(separator: ":")
                p.environment = env

                let out = Pipe()
                p.standardOutput = out
                p.standardError = FileHandle.nullDevice
                do {
                    try p.run()
                } catch {
                    cont.resume(throwing: error)
                    return
                }

                let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                killer.cancel()

                guard let start = data.firstIndex(of: UInt8(ascii: "[")) else {
                    cont.resume(throwing: FetchError.failed("CodexBar não retornou dados (código \(p.terminationStatus))."))
                    return
                }
                cont.resume(returning: Data(data[start...]))
            }
        }
    }

    static func decode(_ data: Data) throws -> [ProviderUsage] {
        let items = try decoder.decode([Lossy<ProviderPayload>].self, from: data)
        return items.compactMap(\.value).map(ProviderUsage.init(payload:))
    }

    private static let decoder: JSONDecoder = {
        let iso = ISO8601DateFormatter()
        let isoFraction = ISO8601DateFormatter()
        isoFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = iso.date(from: s) ?? isoFraction.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Data inválida: \(s)"))
        }
        return d
    }()
}

/// Projetos usados recentemente, lidos dos logs locais do Claude Code, Codex e Antigravity.
enum RecentProjects {
    static func loadAll(limit: Int = 3) -> [String: [RecentProject]] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return [
            "claude": scan(root: home.appendingPathComponent(".claude/projects"), prefixBytes: 65_536, limit: limit, provider: "claude"),
            "codex": scan(root: home.appendingPathComponent(".codex/sessions"), prefixBytes: 98_304, limit: limit, provider: "codex"),
            "antigravity": scanAntigravity(limit: limit),
        ]
    }

    private static let uuidPattern = try! NSRegularExpression(pattern: #"([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})"#)

    private static func extractSessionId(from string: String) -> String? {
        let range = NSRange(string.startIndex..., in: string)
        if let m = uuidPattern.firstMatch(in: string, range: range),
           let r = Range(m.range(at: 1), in: string) {
            return String(string[r])
        }
        return nil
    }

    private static func scan(root: URL, prefixBytes: Int, limit: Int, provider: String) -> [RecentProject] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return [] }

        var files: [(URL, Date)] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            if let date = try? url.resourceValues(forKeys: Set(keys)).contentModificationDate {
                files.append((url, date))
            }
        }
        files.sort { $0.1 > $1.1 }

        let home = NSHomeDirectory()
        var seen = Set<String>()
        var result: [RecentProject] = []
        for (url, date) in files.prefix(300) {
            guard let cwd = readCwd(url, prefixBytes: prefixBytes), seen.insert(cwd).inserted else { continue }
            let urlProj = URL(fileURLWithPath: cwd)
            let name = cwd == home ? "~" : urlProj.lastPathComponent
            let parent = cwd == home ? "" : urlProj.deletingLastPathComponent().lastPathComponent
            let sessionId = extractSessionId(from: url.lastPathComponent)
            let summary = readSummary(from: url)
            result.append(RecentProject(
                id: cwd,
                name: name,
                parent: parent,
                lastUsed: date,
                sessionId: sessionId,
                provider: provider,
                summary: summary
            ))
            if result.count >= limit { break }
        }
        return result
    }

    private static func scanAntigravity(limit: Int) -> [RecentProject] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let root = home.appendingPathComponent(".gemini/antigravity-cli/brain")
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        else { return [] }

        var entries: [(URL, Date, String)] = []
        for dir in dirs {
            let transcript = dir.appendingPathComponent(".system_generated/logs/transcript.jsonl")
            guard FileManager.default.fileExists(atPath: transcript.path) else { continue }
            let date = (try? transcript.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            entries.append((transcript, date, dir.lastPathComponent))
        }
        entries.sort { $0.1 > $1.1 }

        let homePath = NSHomeDirectory()
        var seen = Set<String>()
        var result: [RecentProject] = []
        for (transcript, date, uuid) in entries {
            guard let cwd = readAntigravityCwd(transcript), seen.insert(cwd).inserted else { continue }
            let urlProj = URL(fileURLWithPath: cwd)
            let name = cwd == homePath ? "~" : urlProj.lastPathComponent
            let parent = cwd == homePath ? "" : urlProj.deletingLastPathComponent().lastPathComponent
            let summary = readSummary(from: transcript)
            result.append(RecentProject(
                id: cwd,
                name: name,
                parent: parent,
                lastUsed: date,
                sessionId: uuid,
                provider: "antigravity",
                summary: summary
            ))
            if result.count >= limit { break }
        }
        return result
    }

    private static let textRegex = try! NSRegularExpression(pattern: #""(?:text|content)"\s*:\s*"((?:[^"\\]|\\.)*)""#)

    private static func cleanSummary(_ raw: String) -> String? {
        var text = raw
        text = text.replacingOccurrences(of: "\\n", with: " ")
        text = text.replacingOccurrences(of: "\\\"", with: "\"")
        text = text.replacingOccurrences(of: "\\/", with: "/")

        if let envRange = text.range(of: "<environment_context>[\\s\\S]*?</environment_context>", options: .regularExpression) {
            text.removeSubrange(envRange)
        }
        if let reqRange = text.range(of: "<USER_REQUEST>([\\s\\S]*?)</USER_REQUEST>", options: .regularExpression) {
            let snippet = String(text[reqRange])
            text = snippet
                .replacingOccurrences(of: "<USER_REQUEST>", with: "")
                .replacingOccurrences(of: "</USER_REQUEST>", with: "")
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)

        if text.contains("/var/folders/") && text.contains(".png") {
            if let idx = text.range(of: ".png")?.upperBound {
                let after = String(text[idx...]).trimmingCharacters(in: .whitespacesAndNewlines)
                text = after.isEmpty ? "Captura de tela enviada" : after
            } else {
                text = "Captura de tela enviada"
            }
        }

        let lower = text.lowercased()
        let skipList = [
            "caveat:", "filesystem sandboxing", "# context from my ide",
            "a session-scoped stop hook", "permissions instructions",
            "# collaboration mode", "# codex desktop", "you are",
            "skills_instructions", "multi_agent",
            "the user changed setting", "the messages below were generated",
            "any earlier instruction"
        ]
        if skipList.contains(where: { lower.contains($0) }) { return nil }
        if text.hasPrefix("{") || text.hasPrefix("[") || text.hasPrefix("#") || text.hasPrefix("<") { return nil }
        if text.hasPrefix("/") && !text.contains(" ") { return nil }
        guard !text.isEmpty, text.count > 2 else { return nil }
        if text.count > 48 {
            return String(text.prefix(45)) + "…"
        }
        return text
    }

    private static func readSummary(from url: URL, maxBytes: Int = 98304) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes) else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n", maxSplits: 80, omittingEmptySubsequences: true)
        for line in lines {
            let str = String(line)
            if str.contains("\"user\"") || str.contains("\"USER_INPUT\"") || str.contains("input_text") || str.contains("USER_EXPLICIT") {
                let range = NSRange(str.startIndex..., in: str)
                let matches = textRegex.matches(in: str, range: range)
                for m in matches {
                    if let r = Range(m.range(at: 1), in: str) {
                        let candidate = String(str[r])
                        if let s = cleanSummary(candidate) {
                            return s
                        }
                    }
                }
            }
        }
        return nil
    }

    private static let agyCwdPattern = try! NSRegularExpression(pattern: #""(?:Cwd|DirectoryPath|TargetFile)"\s*:\s*"?\\?"?([^"\\,}]+)"#)

    private static func readAntigravityCwd(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 32768) else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = agyCwdPattern.firstMatch(in: text, range: range),
              let r = Range(match.range(at: 1), in: text)
        else { return nil }
        let cwd = text[r]
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        return cwd.isEmpty ? nil : cwd
    }

    private static let cwdPattern = try! NSRegularExpression(pattern: #""cwd"\s*:\s*"((?:[^"\\]|\\.)*)""#)

    private static func readCwd(_ url: URL, prefixBytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: prefixBytes) else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = cwdPattern.firstMatch(in: text, range: range),
              let r = Range(match.range(at: 1), in: text)
        else { return nil }
        let cwd = text[r].replacingOccurrences(of: "\\/", with: "/").replacingOccurrences(of: "\\\\", with: "\\")
        return cwd.isEmpty ? nil : cwd
    }
}
