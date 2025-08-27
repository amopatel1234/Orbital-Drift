//
//  StarfieldBackground.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 27/08/2025.
//


import SwiftUI

struct StarfieldBackground: View {
    
    @AppStorage("motionParallaxEnabled") private var motionParallaxEnabled = true
    
    var seed: UInt64 = 0xA51CED
    var density: CGFloat = 0.0018   // stars per pt² across all layers
    var driftSpeed: CGFloat = 8     // px/sec (base layer)
    var twinkle: Bool = true

    @StateObject private var motion = MotionParallax()

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { ctx, _ in
                    draw(layer: .back, in: size, t: t, context: &ctx)
                    draw(layer: .mid,  in: size, t: t, context: &ctx)
                    draw(layer: .fore, in: size, t: t, context: &ctx)
                }
            }
            .onAppear { motion.start() }
            .onDisappear { motion.stop() }
            .onChange(of: motionParallaxEnabled) {
                          if motionParallaxEnabled {
                              motion.start()
                          } else {
                              motion.stop()
                              motion.offset = .zero   // snap back when disabled
                          }
                      }
        }
        .ignoresSafeArea()
    }

    // MARK: - Drawing

    private enum Layer { case back, mid, fore }

    private func draw(layer: Layer, in size: CGSize, t: TimeInterval, context ctx: inout GraphicsContext) {
        // Per-layer tuning
        let parallax: CGFloat
        let speed: CGFloat
        let radius: ClosedRange<CGFloat>
        let brightness: ClosedRange<Double>
        let layerDensity: CGFloat

        switch layer {
        case .back:
            parallax = 0.33; speed = driftSpeed * 0.6
            radius = 0.6...1.2
            brightness = 0.25...0.45
            layerDensity = density * 0.35
        case .mid:
            parallax = 0.66; speed = driftSpeed * 1.0
            radius = 0.8...1.6
            brightness = 0.40...0.70
            layerDensity = density * 0.40
        case .fore:
            parallax = 1.00; speed = driftSpeed * 1.4
            radius = 1.0...2.2
            brightness = 0.65...1.00
            layerDensity = density * 0.25
        }

        // Deterministic RNG
        var rng = LCG(seed: mix(seed, tag: layerTag(layer)))
        let count = Int(layerDensity * size.width * size.height)

        let parallaxOffset = CGSize(width: motion.offset.width * parallax,
                                    height: motion.offset.height * parallax)

        // Slow vertical drift, wrap around
        let drift = CGFloat(t) * speed
        for i in 0..<count {
            let px = CGFloat(rng.nextFraction()) * size.width
            let py = CGFloat(rng.nextFraction()) * size.height

            var x = px + parallaxOffset.width
            var y = (py + parallaxOffset.height + drift).truncatingRemainder(dividingBy: size.height)
            if y < 0 { y += size.height }

            let r  = CGFloat(rng.nextFraction()) * (radius.upperBound - radius.lowerBound) + radius.lowerBound
            var a  = rng.nextFraction() * (brightness.upperBound - brightness.lowerBound) + brightness.lowerBound

            if twinkle {
                // tiny per-star twinkle using hashed phase
                let phase = Double((i & 255)) * 0.37
                a *= 0.85 + 0.15 * (0.5 + 0.5 * sin(t * 3.0 + phase))
            }

            let rect = CGRect(x: x, y: y, width: r, height: r)
            ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(a)))
        }
    }

    // MARK: - Utilities

    private func layerTag(_ l: Layer) -> UInt64 {
        switch l {
        case .back:
            return 1
        case .mid:
            return 2
        case .fore:
            return 3
        }
    }
    private func mix(_ s: UInt64, tag: UInt64) -> UInt64 { (s &* 6364136223846793005) &+ tag &+ 1 }

    // Tiny deterministic RNG
    private struct LCG: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { self.state = seed &* 2862933555777941757 &+ 3037000493 }
        mutating func next() -> UInt64 { state = state &* 2862933555777941757 &+ 3037000493; return state }
        mutating func nextFraction() -> Double { Double(next() >> 11) / Double(1 << 53) }
    }
}
