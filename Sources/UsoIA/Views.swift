import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Cores Oficiais e Sutis de Cada IA

enum ProviderColors {
    static func color(for id: String) -> Color {
        switch id.lowercased() {
        case "claude":
            // Azul céu elegante (#3B82F6), exatamente como o anel do Claude no vídeo de referência
            return Color(red: 0.23, green: 0.51, blue: 0.96)
        case "codex", "openai":
            // Verde esmeralda suave da OpenAI (#10A37F)
            return Color(red: 0.08, green: 0.66, blue: 0.50)
        case "antigravity":
            // Índigo suave do Google Antigravity (#6366F1), sutil e sem arco-íris
            return Color(red: 0.40, green: 0.40, blue: 0.95)
        default:
            return Color(red: 0.40, green: 0.40, blue: 0.95)
        }
    }

    /// Retorna a cor correspondente para janelas específicas de modelos
    static func windowColor(label: String, fallback: Color) -> Color {
        let l = label.lowercased()
        if l.contains("claude") {
            return color(for: "claude")
        } else if l.contains("gpt") || l.contains("codex") || l.contains("openai") {
            return color(for: "codex")
        } else if l.contains("antigravity") {
            return color(for: "antigravity")
        }
        return fallback
    }
}

extension ProviderUsage {
    var brandColor: Color {
        ProviderColors.color(for: id)
    }
}

// MARK: - Tema e Estilos

enum Theme {
    static let track = Color(white: 0.22)
    static let barFill = Color(white: 0.12).opacity(0.92)
    static let panelFill = Color(white: 0.14)
    static let cornerRadius: CGFloat = 18

    /// Determina a cor visual baseada no consumo:
    /// - Normal (<75%): cor oficial sutil da IA
    /// - Alerta moderado (75-89%): âmbar suave
    /// - Crítico (>=90%): vermelho alerta suave (idêntico ao 92% da imagem de referência)
    static func usageColor(_ percent: Double, brand: Color? = nil) -> Color {
        let official = brand ?? Color(red: 0.23, green: 0.51, blue: 0.96)
        switch percent {
        case ..<75:
            return official
        case ..<90:
            return Color(red: 0.98, green: 0.73, blue: 0.20)
        default:
            return Color(red: 0.95, green: 0.32, blue: 0.30)
        }
    }

    static func color(_ percent: Double) -> Color {
        usageColor(percent, brand: nil)
    }
}

/// Colada na borda: cantos arredondados só do lado esquerdo. Solta na tela: todos arredondados.
private func barShape(docked: Bool) -> UnevenRoundedRectangle {
    let r = Theme.cornerRadius
    return UnevenRoundedRectangle(
        topLeadingRadius: r, bottomLeadingRadius: r,
        bottomTrailingRadius: docked ? 0 : r, topTrailingRadius: docked ? 0 : r)
}

// MARK: - Barra vertical

struct BarView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var state: BarState

    var body: some View {
        VStack(spacing: 12) {
            if store.providers.isEmpty {
                if let error = store.lastError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(red: 1.0, green: 0.35, blue: 0.32))
                        .help(error)
                } else {
                    ProgressView().controlSize(.small)
                }
            }

            ForEach(store.providers) { provider in
                RingItem(provider: provider, store: store, state: state)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: 50)
        .background(
            barShape(docked: state.docked)
                .fill(Theme.barFill)
                .shadow(color: Color.black.opacity(0.28), radius: 6, x: -2, y: 1)
        )
        .overlay(
            barShape(docked: state.docked)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .contextMenu { BarMenuItems(store: store, state: state) }
        .environment(\.colorScheme, .dark)
    }
}

struct RingItem: View {
    let provider: ProviderUsage
    @ObservedObject var store: UsageStore
    @ObservedObject var state: BarState

    var body: some View {
        let pct = provider.main?.usedPercent
        let isOpen = state.openID == provider.id
        let brandColor = provider.brandColor
        let ringColor = pct.map { Theme.usageColor($0, brand: brandColor) } ?? brandColor

        VStack(spacing: 4) {
            ZStack {
                // 1. Círculo de fundo escuro sutil
                Circle()
                    .fill(Color(white: isOpen ? 0.22 : 0.16))
                    .frame(width: 36, height: 36)

                // 2. Trilho do anel
                Circle()
                    .stroke(Theme.track, lineWidth: 2.2)
                    .frame(width: 36, height: 36)

                // 3. Arco de progresso sutil (sem reflexos ou sombras pesadas)
                if let pct {
                    Circle()
                        .trim(from: 0, to: min(max(pct / 100, 0.001), 1))
                        .stroke(
                            ringColor,
                            style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 36, height: 36)
                }

                // 4. Logo oficial nítido e monocromático branco
                ProviderIcon(id: provider.id, size: 16, color: .white.opacity(pct == nil ? 0.45 : 0.95))
            }
            .frame(width: 38, height: 38)

            // Porcentagem limpa abaixo do anel
            if let pct {
                Text(Fmt.pct(pct))
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.95))
            } else {
                Text("—")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
        }
        .frame(width: 48)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isOpen ? Color.white.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { state.hoverItem(provider.id, inside: $0) }
        .popover(
            isPresented: Binding(
                get: { state.openID == provider.id },
                set: { shown in if !shown, state.openID == provider.id { state.openID = nil } }),
            arrowEdge: .leading
        ) {
            DetailView(provider: provider, store: store)
                .onHover { state.hoverPanel(inside: $0) }
        }
    }
}

/// Lançador de ações externas (Terminal, VS Code).
enum TerminalLauncher {
    static func resume(command: String, in directory: String) {
        let escapedDir = directory
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedCmd = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "cd \"\(escapedDir)\" && \(escapedCmd)"
        end tell
        """
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
            }
        }
    }

    static func openFolderInTerminal(directory: String) {
        let escapedDir = directory
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "cd \"\(escapedDir)\""
        end tell
        """
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
            }
        }
    }

    static func openInVSCode(path: String) {
        let appURL = URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["code", path]
            try? p.run()
        }
    }
}

/// Menu do clique direito na barra.
struct BarMenuItems: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var state: BarState

    var body: some View {
        Button(store.isLoading ? "Atualizando…" : "Atualizar agora") { store.refresh() }
            .disabled(store.isLoading)
        if let updated = store.lastUpdated {
            Text("Atualizado \(Fmt.ago(updated, now: Date()))")
        }
        Divider()
        Toggle("Mostrar só com o Orca aberto", isOn: $state.onlyWithOrca)
        Toggle("Ocultar ao sair do Orca", isOn: $state.onlyWhenActive)
        Toggle("Alertas de limite (80% e 90%)", isOn: $state.notifyOnLimits)
        Toggle("Abrir ao iniciar o Mac", isOn: Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enable in
                do {
                    if enable { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    NSLog("UsoIA: login item: \(error.localizedDescription)")
                }
            }))
        Divider()
        Button("Sair do Uso IA") { NSApp.terminate(nil) }
    }
}

// MARK: - Painel "Uso do …"

struct DetailView: View {
    let provider: ProviderUsage
    @ObservedObject var store: UsageStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let brandColor = provider.brandColor

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    ProviderIcon(id: provider.id, size: 16)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Uso do \(provider.name)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)

                        if let email = provider.accountEmail {
                            Text(email)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 6)

                    if let count = provider.resetCreditsCount, count > 0 {
                        Text("\(count) reset")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(red: 0.10, green: 0.70, blue: 0.40).opacity(0.20)))
                            .foregroundStyle(Color(red: 0.20, green: 0.85, blue: 0.45))
                    }

                    if let plan = provider.plan {
                        Text(plan)
                            .font(.system(size: 9.5, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(brandColor.opacity(0.20)))
                            .foregroundStyle(brandColor)
                            .overlay(Capsule().stroke(brandColor.opacity(0.40), lineWidth: 0.8))
                    }
                }
                .padding(.bottom, 10)

                // Alerta se alguma cota estiver esgotada (ex.: semanal atingida)
                if let alert = provider.depletionMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .font(.system(size: 10.5))
                        Text(alert)
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.35, blue: 0.32))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color(red: 1.0, green: 0.35, blue: 0.32).opacity(0.14))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(red: 1.0, green: 0.35, blue: 0.32).opacity(0.35), lineWidth: 0.8))
                    )
                    .padding(.bottom, 10)
                }

                if let error = provider.errorMessage {
                    Text(error)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 10)
                }

                VStack(alignment: .leading, spacing: 13) {
                    ForEach(provider.windows) { window in
                        WindowRow(window: window, brandColor: brandColor, now: now)
                    }
                }

                let recentProjects = Array((store.recent[provider.id] ?? []).prefix(3))
                if !recentProjects.isEmpty {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                        .padding(.vertical, 10)

                    HStack(spacing: 5) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(brandColor)
                        Text("Projetos recentes")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("clique copia ID")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.bottom, 6)

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(recentProjects) { project in
                            ProjectRow(project: project, brandColor: brandColor, now: now)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(width: 280)
            .background(
                ZStack {
                    Theme.panelFill
                    VStack {
                        LinearGradient(
                            colors: [brandColor.opacity(0.8), brandColor.opacity(0.0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 2)
                        Spacer()
                    }
                }
            )
        }
    }
}

struct WindowRow: View {
    let window: UsageWindow
    let brandColor: Color
    let now: Date

    var body: some View {
        let winColor = ProviderColors.windowColor(label: window.label, fallback: brandColor)
        let usageColor = Theme.usageColor(window.usedPercent, brand: winColor)

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                if let reset = Fmt.reset(window, now: now) {
                    Text(reset)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            ProgressBar(value: window.usedPercent, color: usageColor)

            HStack {
                Text("\(Fmt.pct(window.usedPercent)) usado")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(usageColor)
                Text("·")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.3))
                Text("\(Fmt.pct(100 - window.usedPercent)) restante")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.55))
            }

            if let runsOut = window.runsOutAt, runsOut > now {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                    Text("No ritmo atual, acaba em \(Fmt.duration(runsOut.timeIntervalSince(now)))")
                        .font(.system(size: 9.5, weight: .medium))
                }
                .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.30))
            }
        }
    }
}

struct ProjectRow: View {
    let project: RecentProject
    let brandColor: Color
    let now: Date
    @State private var isCopied = false
    @State private var isHovered = false

    var resumeId: String {
        project.sessionId ?? project.id
    }

    var resumeCommand: String {
        if let sid = project.sessionId {
            if project.provider == "codex" {
                return "codex resume \(sid)"
            } else if project.provider == "antigravity" {
                return "agy resume \(sid)"
            } else {
                return "claude --resume \(sid)"
            }
        }
        return "cd \"\(project.id)\""
    }

    private func copyResumeId() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resumeId, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) {
            isCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied = false
            }
        }
    }

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resumeCommand, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) {
            isCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied = false
            }
        }
    }

    private func resumeDirectly() {
        TerminalLauncher.resume(command: resumeCommand, in: project.id)
    }

    var body: some View {
        Button(action: copyResumeId) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: isCopied ? "checkmark.circle.fill" : "folder.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(isCopied ? Color(red: 0.20, green: 0.85, blue: 0.45) : brandColor.opacity(0.85))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 4) {
                        Text(project.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if !project.parent.isEmpty {
                            Text("(\(project.parent))")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    if let summary = project.summary {
                        Text(summary)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.60))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 6)

                if isCopied {
                    Text("Copiado!")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Color(red: 0.20, green: 0.85, blue: 0.45))
                } else if isHovered {
                    Button(action: resumeDirectly) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 9.5))
                            .foregroundStyle(brandColor)
                            .padding(3)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .help("Retomar diretamente no Terminal")
                } else {
                    Text(Fmt.ago(project.lastUsed, now: now))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCopied ? Color.white.opacity(0.12) : (isHovered ? Color.white.opacity(0.06) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Clique para copiar o Resume ID (\(resumeId))")
        .contextMenu {
            Button("Retomar no Terminal (\(resumeCommand))") {
                resumeDirectly()
            }
            Button("Abrir no Visual Studio Code") {
                TerminalLauncher.openInVSCode(path: project.id)
            }
            Button("Abrir pasta no Terminal") {
                TerminalLauncher.openFolderInTerminal(directory: project.id)
            }
            Button("Abrir no Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.id)
            }
            Divider()
            Button("Copiar Resume ID (\(resumeId))") {
                copyResumeId()
            }
            Button("Copiar comando (\(resumeCommand))") {
                copyCommand()
            }
            Button("Copiar caminho da pasta") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(project.id, forType: .string)
            }
        }
    }
}

struct ProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(color)
                    .frame(width: max(4, geo.size.width * min(max(value, 0), 100) / 100))
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Logos Oficiais e Ícones

struct ProviderIcon: View {
    let id: String
    var size: CGFloat = 16
    var color: Color = Color.white.opacity(0.95)

    var body: some View {
        let key = id.lowercased()
        // Compensação óptica de densidade: o logo do Antigravity é uma massa sólida espessa,
        // enquanto Claude e OpenAI são traços finos vazados. Reduzir em ~25% equilibra o peso visual.
        let opticalSize: CGFloat = (key == "antigravity") ? (size * 0.74).rounded() : size

        if let image = IconCache.image(for: key) {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(color)
                .frame(width: opticalSize, height: opticalSize)
        } else {
            Text(id.prefix(1).uppercased())
                .font(.system(size: opticalSize * 0.8, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .frame(width: opticalSize, height: opticalSize)
        }
    }
}

/// Carrega os arquivos vetoriais de cada logo oficial.
@MainActor
enum IconCache {
    private static var cache: [String: NSImage?] = [:]

    static func image(for id: String) -> NSImage? {
        if let hit = cache[id] { return hit }
        let path = "/Applications/CodexBar.app/Contents/Resources/ProviderIcon-\(id).svg"
        if let image = NSImage(contentsOfFile: path) {
            image.isTemplate = true
            cache[id] = image
            return image
        }
        cache[id] = nil
        return nil
    }
}
