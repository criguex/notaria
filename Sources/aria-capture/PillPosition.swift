import Foundation

struct PillPosition: Equatable {
    var x: Double
    var y: Double

    static let defaultPosition = PillPosition(x: 24, y: 24)

    static func decode(_ raw: String?) -> PillPosition {
        guard let raw, let comma = raw.firstIndex(of: ",") else { return defaultPosition }
        let xPart = raw[raw.startIndex..<comma]
        let yPart = raw[raw.index(after: comma)...]
        guard let x = Double(xPart), let y = Double(yPart) else { return defaultPosition }
        return PillPosition(x: x, y: y)
    }

    func encoded() -> String { "\(x),\(y)" }

    func clamped(toScreenSize size: CGSize, pillSize: CGSize) -> PillPosition {
        guard size.width > 0, size.height > 0 else { return self }
        let maxX = max(0, size.width - pillSize.width)
        let maxY = max(0, size.height - pillSize.height)
        return PillPosition(x: min(max(0, x), maxX), y: min(max(0, y), maxY))
    }

    func moved(byDx dx: Double, dy: Double) -> PillPosition {
        PillPosition(x: x + dx, y: y + dy)
    }
}

enum PillPositionStore {
    static let defaultsKey = "aria.pill.position.v1"

    static func load(defaults: UserDefaults = .standard) -> PillPosition {
        PillPosition.decode(defaults.string(forKey: defaultsKey))
    }

    static func save(_ position: PillPosition, defaults: UserDefaults = .standard) {
        defaults.set(position.encoded(), forKey: defaultsKey)
    }
}
