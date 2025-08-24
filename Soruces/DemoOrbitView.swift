//
//  DemoOrbitView.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//


import SwiftUI

// MARK: - 1) Drag-to-Orbit demo
struct DemoOrbitView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            starfield
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let center = CGPoint(x: size.width/2, y: size.height/2)
                    let radius: CGFloat = min(size.width, size.height) * 0.28

                    // Orbit ring
                    let ring = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                      width: radius*2, height: radius*2))
                    context.stroke(ring, with: .color(.white.opacity(0.25)), lineWidth: 2)

                    // Animate the ship around the ring
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let angle = reduceMotion ? .pi/3 : CGFloat(t).truncatingRemainder(dividingBy: .pi*2)
                    let pos = CGPoint(x: center.x + cos(angle) * radius,
                                      y: center.y + sin(angle) * radius)
                    // Ship
                    let r: CGFloat = 10
                    context.fill(Path(ellipseIn: CGRect(x: pos.x - r, y: pos.y - r, width: r*2, height: r*2)),
                                 with: .color(.white))
                }
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12), lineWidth: 1))
    }

    private var starfield: some View {
        LinearGradient(colors: [.black, .purple.opacity(0.45)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(
                StarsLayer()
                    .blendMode(.screen)
                    .opacity(0.7)
            )
    }
}

// MARK: - 2) Dodge asteroids demo
struct DemoDodgeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Rock { var p: CGPoint; var v: CGVector; var s: CGFloat }
    @State private var rocks: [Rock] = []

    var body: some View {
        ZStack { starBG
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    var rocksLocal = rocks
                    if rocksLocal.isEmpty { rocksLocal = seed(size: size) }

                    // Player point in lower-left moving gently
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let px = size.width*0.25 + sin(t*1.2) * 16
                    let py = size.height*0.70 + cos(t*0.8) * 12
                    let player = CGPoint(x: px, y: py)
                    context.fill(Path(ellipseIn: CGRect(x: player.x-7, y: player.y-7, width: 14, height: 14)),
                                 with: .color(.white))

                    // Update/draw rocks
                    let dt: CGFloat = reduceMotion ? 0 : 1/60
                    var updated: [Rock] = []
                    for r in rocksLocal {
                        var p = r.p
                        p.x += r.v.dx * dt
                        p.y += r.v.dy * dt

                        // respawn if offscreen
                        if p.x < -40 || p.x > size.width+40 || p.y < -40 || p.y > size.height+40 {
                            // skip; new one will be added
                        } else {
                            updated.append(Rock(p: p, v: r.v, s: r.s))
                            context.fill(Path(ellipseIn: CGRect(x: p.x-r.s, y: p.y-r.s, width: r.s*2, height: r.s*2)),
                                         with: .color(.white.opacity(0.9)))
                        }
                    }
                    // top up to 6
                    while updated.count < 6 { updated.append(randomRock(size: size)) }
                    rocks = updated
                }
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12), lineWidth: 1))
    }

    private var starBG: some View {
        LinearGradient(colors: [.black, .indigo.opacity(0.4)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(StarsLayer().opacity(0.8))
    }

    private func seed(size: CGSize) -> [Rock] { (0..<6).map { _ in randomRock(size: size) } }
    private func randomRock(size: CGSize) -> Rock {
        let edge = Int.random(in: 0..<4)
        let start: CGPoint
        switch edge {
        case 0: start = CGPoint(x: CGFloat.random(in: 0...size.width), y: -20)
        case 1: start = CGPoint(x: size.width + 20, y: CGFloat.random(in: 0...size.height))
        case 2: start = CGPoint(x: CGFloat.random(in: 0...size.width), y: size.height + 20)
        default: start = CGPoint(x: -20, y: CGFloat.random(in: 0...size.height))
        }
        let target = CGPoint(x: size.width*0.45, y: size.height*0.45)
        let dir = CGVector(dx: target.x - start.x, dy: target.y - start.y)
        let len = max(1, sqrt(dir.dx*dir.dx + dir.dy*dir.dy))
        let speed = CGFloat.random(in: 60...120)
        return Rock(p: start, v: CGVector(dx: dir.dx/len * speed, dy: dir.dy/len * speed),
                    s: CGFloat.random(in: 6...12))
    }
}

// MARK: - 3) Near-miss + shield demo
struct DemoBonusView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var angle: CGFloat = .pi * 0.15
    @State private var nearMissFlash: CGFloat = 0

    var body: some View {
        ZStack { bg
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let center = CGPoint(x: size.width*0.52, y: size.height*0.55)
                    let radius: CGFloat = min(size.width, size.height) * 0.26

                    // ring
                    let ring = Path(ellipseIn: CGRect(x: center.x-radius, y: center.y-radius,
                                                      width: radius*2, height: radius*2))
                    let c = Color.white.opacity(0.18 + 0.25 * nearMissFlash)
                    context.stroke(ring, with: .color(c), lineWidth: 2 + 1 * nearMissFlash)

                    // player & shield halo
                    let p = CGPoint(x: center.x + cos(angle)*radius, y: center.y + sin(angle)*radius)
                    context.fill(Path(ellipseIn: CGRect(x: p.x-7, y: p.y-7, width: 14, height: 14)),
                                 with: .color(.white))
                    let haloRect = CGRect(x: p.x-13, y: p.y-13, width: 26, height: 26)
                    context.stroke(Path(ellipseIn: haloRect), with: .color(.white.opacity(0.6)), lineWidth: 2)

                    // "asteroid" passes close once per cycle
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let a = CGFloat((t*1.2).truncatingRemainder(dividingBy: .pi*2))
                    let aPos = CGPoint(x: center.x + cos(a) * (radius + 26),
                                       y: center.y + sin(a) * (radius + 26))
                    context.fill(Path(ellipseIn: CGRect(x: aPos.x-6, y: aPos.y-6, width: 12, height: 12)),
                                 with: .color(.white.opacity(0.9)))

                    // update local angle slowly
                    if !reduceMotion { angle += 0.02 }

                    // trigger flash when near
                    let dist = hypot(aPos.x - p.x, aPos.y - p.y)
                    if dist < 34 { nearMissFlash = 1 }
                    nearMissFlash = max(0, nearMissFlash - 0.06)
                }
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12), lineWidth: 1))
    }

    private var bg: some View {
        LinearGradient(colors: [.black, .orange.opacity(0.35)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(StarsLayer().opacity(0.75))
    }
}

// MARK: - Shared stars (cheap procedural layer)
fileprivate struct StarsLayer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let seed = UInt64(abs(Int64(timeline.date.timeIntervalSinceReferenceDate * (reduceMotion ? 0 : 0.15))))
                var rng = SeededRandom(seed: seed)
                for _ in 0..<160 {
                    let x = CGFloat(rng.next()) * size.width
                    let y = CGFloat(rng.next()) * size.height
                    let r = CGFloat(rng.next()) * 1.2 + 0.2
                    let alpha = 0.6 + Double(rng.next()) * 0.4
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                                 with: .color(.white.opacity(alpha)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

fileprivate struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1 }
    mutating func next() -> CGFloat {
        state = state &* 2862933555777941757 &+ 3037000493
        return CGFloat((state >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
    }
}