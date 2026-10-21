import SwiftUI

final class FloatingPlacement: ObservableObject {
    static let shared = FloatingPlacement()
    @Published var pocketLocked: Bool { didSet { UserDefaults.standard.set(pocketLocked,forKey:"pocketPositionLocked");AppDelegate.shared?.pocketWindow?.isMovable = !pocketLocked } }
    @Published var miniLocked: Bool { didSet { UserDefaults.standard.set(miniLocked,forKey:"miniPositionLocked");AppDelegate.shared?.miniWindow?.isMovable = !miniLocked } }
    init() { pocketLocked=UserDefaults.standard.bool(forKey:"pocketPositionLocked");miniLocked=UserDefaults.standard.bool(forKey:"miniPositionLocked") }
}
