//
//  MotionParallax.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 27/08/2025.
//


import CoreMotion
import SwiftUI

@MainActor
final class MotionParallax: ObservableObject {
    @Published var offset: CGSize = .zero

    private let manager = CMMotionManager()
    private let maxOffset: CGFloat = 24       // px at the far layer (tweak)
    private let responsiveness: Double = 0.45 // 0–1, lower feels heavier

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            // Map pitch/roll to x/y; clamp and ease a little.
            let x = CGFloat(m.attitude.roll)    // left/right tilt
            let y = CGFloat(m.attitude.pitch)   // forward/back tilt
            let nx = max(-1, min(1, x))         // normalize-ish
            let ny = max(-1, min(1, y))
            let target = CGSize(width: -nx * self.maxOffset, height: ny * self.maxOffset)
            // simple critically-damped lerp
            offset.width  += (target.width  - offset.width)  * responsiveness
            offset.height += (target.height - offset.height) * responsiveness
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}