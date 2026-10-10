import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Aparência da referência

enum Theme {
    static let accent = Color(red: 0.97, green: 0.85, blue: 0.22)
    static let track = Color.white.opacity(0.20)
    static let barFill = Color.black.opacity(0.20)
    static let panelFill = Color(white: 0.16).opacity(0.72)
    static let barWidth: CGFloat = 54

    static func usageColor(_ percent: Double) -> Color {
        switch percent {
        case ..<75: return accent
        case ..<90: return Color(red: 1.0, green: 0.67, blue: 0.24)
        default: return Color(red: 1.0, green: 0.36, blue: 0.33)
        }
    }
}

/// A aba se une à borda da tela com uma curva em S adaptada ao lado ancorado.
/// Todos os lados utilizam a mesma curva canônica da borda direita através de transformação rígida,
/// garantindo simetria e curvatura idênticas na direita, esquerda, topo e base.
private struct SidebarShape: Shape {
    let edge: DockEdge

    func path(in rect: CGRect) -> Path {
        if edge == .floating {
            var path = Path()
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: 18, height: 18), style: .continuous)
            return path
        }

        // Espessura T (perpendicular à borda da tela) e comprimento L (ao longo da borda da tela).
        let T = edge.isHorizontal ? rect.height : rect.width
        let L = edge.isHorizontal ? rect.width : rect.height

        let cap = min(T * 1.30, L / 2)
        let middle = T * 0.60

        // Mapeia coordenadas do lado direito canônico (x in [0, T], y in [0, L]) para qualquer borda:
        // x = T é a face plana colada na tela; x = 0 é a face interna arredondada.
        // y = 0 é o início do comprimento; y = L é o final do comprimento.
        func mapPoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            switch edge {
            case .right:
                return CGPoint(x: rect.minX + x, y: rect.minY + y)
            case .left:
                return CGPoint(x: rect.minX + (T - x), y: rect.minY + y)
            case .top:
                return CGPoint(x: rect.minX + y, y: rect.minY + (T - x))
            case .bottom:
                return CGPoint(x: rect.minX + y, y: rect.minY + x)
            case .floating:
                return .zero
            }
        }

        var path = Path()
        path.move(to: mapPoint(T, 0))
        path.addCurve(
            to: mapPoint(middle, cap * 0.54),
            control1: mapPoint(T, cap * 0.48),
            control2: mapPoint(T * 0.90, cap * 0.54)
        )
        path.addCurve(
            to: mapPoint(0, cap),
            control1: mapPoint(T * 0.16, cap * 0.54),
            control2: mapPoint(0, cap * 0.72)
        )
        path.addLine(to: mapPoint(0, L - cap))
        path.addCurve(
            to: mapPoint(middle, L - cap * 0.54),
            control1: mapPoint(0, L - cap * 0.72),
            control2: mapPoint(T * 0.16, L - cap * 0.54)
        )
        path.addCurve(
            to: mapPoint(T, L),
            control1: mapPoint(T * 0.90, L - cap * 0.54),
            control2: mapPoint(T, L - cap * 0.48)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Barra vertical / horizontal

struct BarView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var state: BarState

    var body: some View {
        let active = state.isPointerInsideBar || state.openID != nil || state.isDragging
        let isHorizontal = state.dockEdge.isHorizontal

        Group {
            if isHorizontal {
                HStack(spacing: 12) {
                    ForEach(store.providers) { provider in
                        RingItem(provider: provider, store: store, state: state)
                    }
                }
                .padding(.leading, 46)
                .padding(.trailing, 42)
                .padding(.vertical, 2)
                .frame(height: Theme.barWidth)
            } else {
                VStack(spacing: 10) {
                    ForEach(store.providers) { provider in
                        RingItem(provider: provider, store: store, state: state)
                    }
                }
                .padding(.top, 46)
                .padding(.bottom, 42)
                .frame(width: Theme.barWidth)
            }
        }
        .background {
            ZStack {
                SidebarShape(edge: state.dockEdge).fill(.ultraThinMaterial).opacity(active ? 1 : 0.35)
                SidebarShape(edge: state.dockEdge).fill(Theme.barFill).opacity(active ? 1 : 0.40)
            }
        }
        .overlay(
            SidebarShape(edge: state.dockEdge)
                .stroke(Color.white.opacity(active ? 0.08 : 0.02), lineWidth: 0.5)
        )
        .opacity(active ? 1.0 : 0.40)
        .animation(.easeInOut(duration: 0.20), value: active)
        .animation(.easeInOut(duration: 0.25), value: state.dockEdge)
        .onHover { state.isPointerInsideBar = $0 }
        .contextMenu { BarMenuItems(store: store, state: state) }
        .environment(\.colorScheme, .dark)
    }
}

struct RingItem: View {
    let provider: ProviderUsage
    @ObservedObject var store: UsageStore
    @ObservedObject var state: BarState

    private var displayedWindow: UsageWindow? {
        state.showsWeeklyUsage ? (provider.weeklyWindow ?? provider.operationalWindow) : provider.operationalWindow
    }

    var body: some View {
        let pct = displayedWindow?.usedPercent
        let isOpen = state.openID == provider.id

        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(isOpen ? 0.065 : 0.015))
                Circle()
                    .strokeBorder(Theme.track, lineWidth: 3.5)

                if let pct, pct > 0 {
                    Circle()
                        .inset(by: 1.75)
                        .trim(from: 0, to: min(max(pct / 100, 0), 1))
                        .stroke(Theme.usageColor(pct), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }

                ProviderIcon(id: provider.id, size: 17, color: .white.opacity(pct == nil ? 0.40 : 0.96))
            }
            .frame(width: 36, height: 36)

            Text(pct.map(Fmt.pct) ?? "—")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(pct == nil ? 0.40 : 0.98))
        }
        .frame(width: Theme.barWidth - 10)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(isOpen ? 0.035 : 0))
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provider.name), \(displayedWindow?.label ?? "uso"), \(pct.map(Fmt.pct) ?? "sem dados")")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { state.togglePanel(provider.id) }
        .onHover { inside in
            state.hoverItem(provider.id, inside: inside)
            if inside { store.refreshIfStale(maxAge: 30) }
        }
        .popover(
            isPresented: Binding(
                get: { state.openID == provider.id },
                set: { shown in if !shown, state.openID == provider.id { state.closeNow() } }),
            arrowEdge: popoverArrowEdge
        ) {
            DetailView(provider: provider, store: store, preferredWindowID: displayedWindow?.id)
                .onHover { state.hoverPanel(inside: $0) }
                .environment(\.colorScheme, .dark)
        }
    }

    private var popoverArrowEdge: Edge {
        switch state.dockEdge {
        case .right: return .leading
        case .left: return .trailing
        case .top: return .bottom
        case .bottom: return .top
        case .floating: return .leading
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
        Button(store.isLoading ? "Atualizando…" : "Atualizar agora") { store.refresh(forceActivity: true) }
            .disabled(store.isLoading)
        if let updated = store.lastUpdated {
            Text("Atualizado \(Fmt.ago(updated, now: Date()))")
        }
        Divider()
        Menu("Intervalo de atualização") {
            Button("30 segundos" + (Int(store.refreshInterval) == 30 ? " ✓" : "")) {
                store.refreshInterval = 30
            }
            Button("1 minuto (padrão)" + (Int(store.refreshInterval) == 60 ? " ✓" : "")) {
                store.refreshInterval = 60
            }
            Button("2 minutos" + (Int(store.refreshInterval) == 120 ? " ✓" : "")) {
                store.refreshInterval = 120
            }
            Button("5 minutos" + (Int(store.refreshInterval) == 300 ? " ✓" : "")) {
                store.refreshInterval = 300
            }
        }
        Divider()
        Menu("Posição na tela") {
            Button("Lado direito" + (state.dockEdge == .right ? " ✓" : "")) {
                state.dockEdge = .right
            }
            Button("Lado esquerdo" + (state.dockEdge == .left ? " ✓" : "")) {
                state.dockEdge = .left
            }
            Button("Topo (cima)" + (state.dockEdge == .top ? " ✓" : "")) {
                state.dockEdge = .top
            }
            Button("Base (baixo)" + (state.dockEdge == .bottom ? " ✓" : "")) {
                state.dockEdge = .bottom
            }
        }
        Divider()
        Toggle("Mostrar consumo semanal no Claude", isOn: $state.showsWeeklyUsage)
        Divider()
        Toggle("Mostrar só com o Orca aberto", isOn: $state.onlyWithOrca)
        Toggle("Ocultar ao sair do Orca", isOn: $state.onlyWhenActive)
            .disabled(!state.onlyWithOrca)
        Toggle("Alertas de limite (80%, 90% e 95%)", isOn: $state.notifyOnLimits)
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

// MARK: - Painel de uso

struct DetailView: View {
    let provider: ProviderUsage
    @ObservedObject var store: UsageStore
    var preferredWindowID: String?

    private var windows: [UsageWindow] {
        provider.windows.filter { $0.id == preferredWindowID }
            + provider.windows.filter { $0.id != preferredWindowID }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    ProviderIcon(id: provider.id, size: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Uso do \(provider.name)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                        if let plan = provider.plan {
                            Text(plan)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 16)
                .help(provider.accountEmail ?? provider.name)

                if let alert = provider.depletionMessage {
                    Label(alert, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.usageColor(100))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.usageColor(100).opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.bottom, 12)
                }

                if let error = provider.errorMessage {
                    Text(store.isLoading && provider.windows.isEmpty ? "Consultando uso…" : error)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(windows) { window in
                        WindowRow(window: window, now: now)
                    }
                }

                if let count = provider.resetCreditsCount, count > 0 {
                    sectionDivider
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Resets disponíveis")
                            .font(.system(size: 12, weight: .semibold))
                        Text(count == 1 ? "1 reset não utilizado" : "\(count) resets não utilizados")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.78))
                        if let expiry = provider.resetCreditsExpireAt {
                            Text("Expira em \(expiry.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "pt_BR"))))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let activity = store.activity[provider.id] {
                    sectionDivider
                    TokenActivityView(activity: activity, now: now)
                }

                let recentProjects = Array((store.recent[provider.id] ?? []).prefix(3))
                if !recentProjects.isEmpty {
                    sectionDivider
                    Text("Projetos recentes")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.bottom, 7)
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(recentProjects) { project in
                            ProjectRow(project: project, brandColor: Theme.accent, now: now)
                        }
                    }
                }

                sectionDivider
                HStack(spacing: 6) {
                    if store.isLoading {
                        ProgressView().controlSize(.mini)
                        Text("Atualizando…")
                    } else if store.lastError != nil {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(Theme.accent)
                        Text(provider.windows.isEmpty ? "Falha ao consultar" : "Dados da última consulta")
                    } else if let updated = store.lastUpdated {
                        Circle().fill(Theme.accent).frame(width: 4, height: 4)
                        Text("Atualizado \(Fmt.ago(updated, now: now))")
                    } else {
                        Text("Aguardando atualização")
                    }
                    Spacer(minLength: 4)
                    Button { store.refresh(forceActivity: true) } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 22, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isLoading)
                    .help("Atualizar uso")
                    .accessibilityLabel("Atualizar uso")
                }
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.50))
                .help(store.lastError ?? "Atualização automática a cada \(Int(store.refreshInterval))s")
            }
            .padding(14)
            .frame(width: 300)
            .background(Theme.panelFill.gradient)
        }
    }

    private var sectionDivider: some View {
        Rectangle().fill(Color.white.opacity(0.14))
            .frame(height: 1)
            .padding(.vertical, 12)
    }
}

struct WindowRow: View {
    let window: UsageWindow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(window.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.90))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let reset = Fmt.reset(window, now: now) {
                    Text(reset)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize()
                }
            }
            ProgressBar(value: window.usedPercent, color: Theme.usageColor(window.usedPercent))
            Text("\(Fmt.pct(window.usedPercent)) usado · \(Fmt.pct(100 - window.usedPercent)) restante")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))

            if let runsOut = window.runsOutAt, runsOut > now {
                Label("No ritmo atual, acaba em \(Fmt.duration(runsOut.timeIntervalSince(now)))", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.usageColor(85))
            }
        }
    }
}

struct TokenActivityView: View {
    let activity: TokenActivity
    let now: Date

    var body: some View {
        let samples = activity.samples(now: now)
        let total = samples.reduce(0) { $0 + $1.tokens }
        let peak = samples.map(\.tokens).max() ?? 0
        let today = samples.last?.tokens ?? 0

        VStack(alignment: .leading, spacing: 7) {
            metric("Tokens locais · 30 dias", value: total)
            metric("Pico diário", value: peak)
            metric("Hoje", value: today)

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(samples) { sample in
                    Rectangle()
                        .fill(sample.id == samples.last?.id ? Theme.accent : Color.white.opacity(0.65))
                        .frame(maxWidth: .infinity)
                        .frame(height: peak > 0 ? 46 * CGFloat(sample.tokens) / CGFloat(peak) : 0)
                        .frame(height: 46, alignment: .bottom)
                        .help("\(sample.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "pt_BR")))): \(sample.tokens.formatted()) tokens")
                }
            }
            .padding(.top, 5)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tokens por dia nos últimos 30 dias")
            .accessibilityValue("Total \(total), pico diário \(peak), hoje \(today)")

            HStack {
                if let first = samples.first {
                    Text(first.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "pt_BR"))))
                }
                Spacer()
                Text("Hoje")
            }
            .font(.system(size: 9))
            .foregroundStyle(.white.opacity(0.40))
        }
    }

    private func metric(_ label: String, value: Int) -> some View {
        HStack {
            Text(label).foregroundStyle(.white.opacity(0.65))
            Spacer()
            Text(value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(Locale(identifier: "pt_BR"))))
                .foregroundStyle(.white.opacity(0.9))
                .monospacedDigit()
                .help("\(value.formatted()) tokens")
        }
        .font(.system(size: 11, weight: .medium))
    }
}

final class ProjectRowState: ObservableObject {
    @Published var isCopied = false
    @Published var isHovered = false
}

struct ProjectRow: View {
    let project: RecentProject
    let brandColor: Color
    let now: Date
    @StateObject private var rowState = ProjectRowState()

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
            rowState.isCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.rowState.isCopied = false
            }
        }
    }

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resumeCommand, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) {
            rowState.isCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.rowState.isCopied = false
            }
        }
    }

    private func resumeDirectly() {
        TerminalLauncher.resume(command: resumeCommand, in: project.id)
    }

    var body: some View {
        Button(action: copyResumeId) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: rowState.isCopied ? "checkmark.circle.fill" : "folder.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(rowState.isCopied ? Color(red: 0.20, green: 0.85, blue: 0.45) : brandColor.opacity(0.85))
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

                if rowState.isCopied {
                    Text("Copiado!")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Color(red: 0.20, green: 0.85, blue: 0.45))
                } else if rowState.isHovered {
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
                    .fill(rowState.isCopied ? Color.white.opacity(0.12) : (rowState.isHovered ? Color.white.opacity(0.06) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { rowState.isHovered = $0 }
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
                    .frame(width: geo.size.width * min(max(value, 0), 100) / 100)
            }
        }
        .frame(height: 5)
        .accessibilityLabel("Consumo")
        .accessibilityValue(Fmt.pct(value))
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
