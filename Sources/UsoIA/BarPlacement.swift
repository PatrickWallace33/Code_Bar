import Foundation
import CoreGraphics

/// Uma posição completa evita misturar coordenadas de arrastes diferentes.
struct BarPlacement: Codable, Equatable {
    let x: Double
    let top: Double
    let docked: Bool
    let relativeX: Double?
    let relativeTop: Double?
    let screenID: UInt32?
    let savedAt: Date?

    static let storageKey = "barPlacementV1"

    init(frame: CGRect, docked: Bool, orcaFrame: CGRect?, screenID: UInt32?, now: Date = Date()) {
        x = frame.minX
        top = frame.maxY
        self.docked = docked
        relativeX = orcaFrame.map { frame.minX - $0.minX }
        relativeTop = orcaFrame.map { $0.maxY - frame.maxY }
        self.screenID = screenID
        savedAt = now
    }

    private init(x: Double, top: Double, docked: Bool, relativeX: Double?, relativeTop: Double?) {
        self.x = x
        self.top = top
        self.docked = docked
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
        return Self(x: x, top: top,
                    docked: defaults.object(forKey: "barDocked") as? Bool ?? true,
                    relativeX: defaults.object(forKey: "barRelativeX") as? Double,
                    relativeTop: defaults.object(forKey: "barRelativeTop") as? Double)
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
        defaults.set(x, forKey: "barX")
        defaults.set(top, forKey: "barTop")
        defaults.set(docked, forKey: "barDocked")
        // set(nil) remove âncoras antigas quando o arraste aconteceu sem o Orca.
        defaults.set(relativeX, forKey: "barRelativeX")
        defaults.set(relativeTop, forKey: "barRelativeTop")
    }

    func restoredFrame(size: CGSize, visibleFrame: CGRect, orcaFrame: CGRect?) -> CGRect {
        let target = orcaFrame ?? visibleFrame
        var restoredX = x
        var restoredTop = top
        if docked {
            restoredX = target.maxX - size.width
        } else if let orcaFrame, let relativeX {
            restoredX = orcaFrame.minX + relativeX
        }
        if let orcaFrame, let relativeTop {
            restoredTop = orcaFrame.maxY - relativeTop
        }

        // Uma barra solta pode ficar fora do Orca, desde que continue visível na tela.
        let verticalBounds = docked ? target.intersection(visibleFrame) : visibleFrame
        let minTop = verticalBounds.minY + size.height
        let maxTop = verticalBounds.maxY
        if !verticalBounds.isNull && maxTop >= minTop {
            restoredTop = min(max(restoredTop, minTop), maxTop)
        } else {
            restoredTop = min(max(restoredTop, visibleFrame.minY + size.height), visibleFrame.maxY)
        }
        restoredX = min(max(restoredX, visibleFrame.minX), visibleFrame.maxX - size.width)
        return CGRect(x: restoredX, y: restoredTop - size.height, width: size.width, height: size.height)
    }
}
