import SwiftUI

// MARK: - (Optional) small helper if you kept the shake modifier separate
extension View {
    func screenShake(_ amount: CGFloat) -> some View {
        if UIAccessibility.isReduceMotionEnabled || amount <= 0 { return AnyView(self) }
        let x = CGFloat.random(in: -amount...amount)
        let y = CGFloat.random(in: -amount...amount)
        return AnyView(self.offset(x: x, y: y))
    }
}
