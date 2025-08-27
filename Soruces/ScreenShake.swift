//
//  ScreenShake.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 27/08/2025.
//


import SwiftUI

struct ScreenShake: ViewModifier {
    var intensity: CGFloat   // 0…~3 (we’ll clamp in GameState)

    func body(content: Content) -> some View {
        // Smooth, deterministic wobble using time-based sines (no random jank).
        let t = Date.timeIntervalSinceReferenceDate
        let amp = max(0, intensity) * 6    // pixels; tweak 6 → taste
        let dx = CGFloat(sin(t * 33) + sin(t * 13) * 0.5) * amp
        let dy = CGFloat(sin(t * 29) + sin(t * 17) * 0.5) * amp
        content.offset(x: dx, y: dy)
    }
}

extension View {
    func screenShake(_ intensity: CGFloat) -> some View {
        modifier(ScreenShake(intensity: intensity))
    }
}