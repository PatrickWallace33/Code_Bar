import Foundation
import CoreGraphics

/// Lado da tela onde a barra pode se fixar ou flutuar livremente.
enum DockEdge: String, Codable, Equatable {
    case right
    case left
    case top
    case bottom
    case floating

    var isHorizontal: Bool { self == .top || self == .bottom }
    var isDocked: Bool { self != .floating }
}

/// Uma posição completa evita misturar coordenadas de arrastes diferentes.
struct BarPlacement: Codable, Equatable {
    let x: Double
    let top: Double
    let docked: Bool
    let edge: DockEdge?
    let relativeX: Double?
    let relativeTop: Double?
    let screenID: UInt32?
    let savedAt: Date?

    static let storageKey = "barPlacementV1"

    init(frame: CGRect, docked: Bool, edge: DockEdge = .right, orcaFrame: CGRect?, screenID: UInt32?, now: Date = Date()) {
        x = frame.minX
        top = frame.maxY
        self.docked = docked
        self.edge = edge
        relativeX = orcaFrame.map { frame.minX - $0.minX }
        relativeTop = orcaFrame.map { $0.maxY - frame.maxY }
        self.screenID = screenID
        savedAt = now
    }

    init(frame: CGRect, docked: Bool, orcaFrame: CGRect?, screenID: UInt32?, now: Date = Date()) {
        self.init(frame: frame, docked: docked, edge: docked ? .right : .floating, orcaFrame: orcaFrame, screenID: screenID, now: now)
    }

    private init(x: Double, top: Double, docked: Bool, edge: DockEdge?, relativeX: Double?, relativeTop: Double?) {
        self.x = x
        self.top = top
        self.docked = docked
        self.edge = edge
        self.relativeX = relativeX
        self.relativeTop = relativeTop
        screenID = nil
        savedAt = nil
    }

    static func load(from defaults: UserDefaults = .standard) -> BarPlacement? {
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(Self.self, from: data) {
            return saved
        }
        // Preserva a última posição registrada pelas versões anteriores.
        guard let x = defaults.object(forKey: "barX") as? Double,
              let top = defaults.object(forKey: "barTop") as? Double else { return nil }
        let edgeRaw = defaults.string(forKey: "barEdge")
        let edge = edgeRaw.flatMap(DockEdge.init(rawValue:))
        let docked = defaults.object(forKey: "barDocked") as? Bool ?? true
        return Self(x: x, top: top,
                    docked: docked,
                    edge: edge ?? (docked ? .right : .floating),
                    relativeX: defaults.object(forKey: "barRelativeX") as? Double,
                    relativeTop: defaults.object(forKey: "barRelativeTop") as? Double)
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
        defaults.set(x, forKey: "barX")
        defaults.set(top, forKey: "barTop")
        defaults.set(docked, forKey: "barDocked")
        let activeEdge = edge ?? (docked ? .right : .floating)
        defaults.set(activeEdge.rawValue, forKey: "barEdge")
        // set(nil) remove âncoras antigas quando o arraste aconteceu sem o Orca.
        defaults.set(relativeX, forKey: "barRelativeX")
        defaults.set(relativeTop, forKey: "barRelativeTop")
    }

    func restoredFrame(size: CGSize, visibleFrame: CGRect, orcaFrame: CGRect?) -> CGRect {
        let target = orcaFrame ?? visibleFrame
        var restoredX = x
        var restoredTop = top
        let activeEdge = edge ?? (docked ? .right : .floating)

        switch activeEdge {
        case .right:
            restoredX = target.maxX - size.width
            if let orcaFrame, let relativeTop {
                restoredTop = orcaFrame.maxY - relativeTop
            }
        case .left:
            restoredX = target.minX
            if let orcaFrame, let relativeTop {
                restoredTop = orcaFrame.maxY - relativeTop
            }
        case .top:
            restoredTop = target.maxY
            if let orcaFrame, let relativeX {
                restoredX = orcaFrame.minX + relativeX
            }
        case .bottom:
            restoredTop = target.minY + size.height
            if let orcaFrame, let relativeX {
                restoredX = orcaFrame.minX + relativeX
            }
        case .floating:
            if let orcaFrame, let relativeX {
                restoredX = orcaFrame.minX + relativeX
            }
            if let orcaFrame, let relativeTop {
                restoredTop = orcaFrame.maxY - relativeTop
            }
        }

        // Garante que a barra permaneça dentro dos limites visíveis da tela / janela ancorada
        let verticalBounds = activeEdge.isDocked ? target.intersection(visibleFrame) : visibleFrame
        let minTop = (verticalBounds.isNull ? visibleFrame : verticalBounds).minY + size.height
        let maxTop = (verticalBounds.isNull ? visibleFrame : verticalBounds).maxY
        if !verticalBounds.isNull && maxTop >= minTop {
            restoredTop = min(max(restoredTop, minTop), maxTop)
        } else {
            restoredTop = min(max(restoredTop, visibleFrame.minY + size.height), visibleFrame.maxY)
        }

        let horizontalBounds = activeEdge.isDocked ? target.intersection(visibleFrame) : visibleFrame
        let minX = (horizontalBounds.isNull ? visibleFrame : horizontalBounds).minX
        let maxX = (horizontalBounds.isNull ? visibleFrame : horizontalBounds).maxX - size.width
        if !horizontalBounds.isNull && maxX >= minX {
            restoredX = min(max(restoredX, minX), maxX)
        } else {
            restoredX = min(max(restoredX, visibleFrame.minX), visibleFrame.maxX - size.width)
        }

        return CGRect(x: restoredX, y: restoredTop - size.height, width: size.width, height: size.height)
    }
}
