import SwiftUI

extension View {
    func screenShake(_ amount: CGFloat) -> some View {
        // Respect Reduce Motion
        if UIAccessibility.isReduceMotionEnabled || amount <= 0 { return AnyView(self) }
        let x = CGFloat.random(in: -amount...amount)
        let y = CGFloat.random(in: -amount...amount)
        return AnyView(self.offset(x: x, y: y))
    }
}