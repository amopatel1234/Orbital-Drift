//
//  Vector2.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//


import SwiftUI
import CoreGraphics

// MARK: - Math

struct Vector2: Hashable {
    var x: CGFloat
    var y: CGFloat
    static let zero = Vector2(x: 0, y: 0)
    var cgPoint: CGPoint { .init(x: x, y: y) }

    static func -(lhs: Vector2, rhs: Vector2) -> Vector2 { .init(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    static func +(lhs: Vector2, rhs: Vector2) -> Vector2 { .init(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    func length() -> CGFloat { sqrt(x*x + y*y) }
}

// MARK: - Entities

struct Player {
    var angle: CGFloat = .pi / 2
    var radius: CGFloat = 120
    let size: CGFloat = 14
    var isAlive: Bool = true
}

struct Asteroid: Identifiable {
    let id = UUID()
    var pos: Vector2
    var vel: Vector2
    var size: CGFloat
    var alive: Bool = true
}

struct Particle: Identifiable {
    let id = UUID()
    var pos: Vector2
    var vel: Vector2
    var life: CGFloat // 0...1
}

struct Powerup: Identifiable {
    let id = UUID()
    var pos: Vector2
    var size: CGFloat = 10
    var alive: Bool = true
}

struct Shockwave: Identifiable {
    let id = UUID()
    var pos: Vector2
    var age: CGFloat = 0       // 0...1
    var maxRadius: CGFloat = 60
}

// MARK: - Theme

enum Theme: String, CaseIterable, Identifiable {
    case classic, neon, solar
    var id: String { rawValue }

    var ringOpacity: Double {
        switch self {
        case .classic: return 0.15
        case .neon:    return 0.22
        case .solar:   return 0.18
        }
    }

    var asteroidAlpha: Double {
        switch self {
        case .classic: return 0.85
        case .neon:    return 0.95
        case .solar:   return 0.8
        }
    }
}

// MARK: - Phases

enum GamePhase { case menu, playing, gameOver, paused }
