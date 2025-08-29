//
//  Vector2.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//


import SwiftUI
import CoreGraphics

// MARK: - Entities

struct Player {
    var angle: CGFloat = .pi / 2
    var radius: CGFloat = 120
    let size: CGFloat = 14
    var isAlive: Bool = true
}


struct Bullet: Identifiable {
    let id = UUID()
    var pos: Vector2
    var vel: Vector2
    var life: CGFloat = 1.2     // seconds before auto-despawn
    var size: CGFloat = 3.5
    var tint: Color = .white
    var damage: Int = 1
}

enum EnemyType: Int {
    case small
    case big
    case evader
    
    var color: Color {
        switch self {
        case .small:
            return .blue
        case .big:
            return .red
        case .evader:
            return .purple
        }
    }
    
    var scoreValue: Int {
        switch self {
        case .small:
            15
        case .big:
            40
        case .evader:
            30
        }
    }
}

struct Asteroid: Identifiable {
    let id = UUID()
    var pos: Vector2
    var vel: Vector2
    var size: CGFloat
    var alive: Bool = true
    var type: EnemyType = .small
    var hp: Int = 1
}

struct Particle: Identifiable {
    let id = UUID()
    var pos: Vector2
    var vel: Vector2
    var life: CGFloat // 0...1
    var color: Color = .white
}

struct KillToast: Identifiable {
    let id = UUID()
    var pos: Vector2           // spawn position (world coords)
    var value: Int             // points to show
    var color: Color           // matches enemy color
    var age: CGFloat = 0       // seconds since spawn
    var lifetime: CGFloat = 0.6
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

enum GamePhase {
    case menu
    case playing
    case gameOver
    case paused
}
