//
//  SpawningSystem.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 27/08/2025.
//


//
//  SpawningSystem.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//

import SwiftUI

@MainActor
@Observable
final class SpawningSystem {
    // MARK: - Spawning State
    private var elapsed: TimeInterval = 0
    private var spawnAcc: TimeInterval = 0
    
    // MARK: - Spawn Configuration
    var baseSpawnRate: Double = 0.6
    var rampSpawnBonus: Double = 1.2
    var rampDuration: Double = 60
    var gracePeriod: Double = 8
    
    // MARK: - Public Interface
    
    func updateSpawning(dt: TimeInterval, size: CGSize, asteroids: inout [Asteroid], worldCenter: CGPoint) {
        elapsed += dt
        
        let ramp = min(1.0, elapsed / rampDuration)
        let spawnRate = baseSpawnRate + ramp * rampSpawnBonus
        let spawnInterval = 1.0 / spawnRate
        
        spawnAcc += dt
        
        let cap = (elapsed < gracePeriod)
            ? max(3, maxEnemies(now: elapsed) - 2)
            : maxEnemies(now: elapsed)
        
        while spawnAcc >= spawnInterval {
            spawnAcc -= spawnInterval
            
            if asteroids.count(where: { $0.alive}) < cap {
                spawnAsteroid(size: size, asteroids: &asteroids, worldCenter: worldCenter)
            }
        }
    }
    
    func reset() {
        elapsed = 0
        spawnAcc = 0
    }
    
    // MARK: - Private Implementation
    
    private func spawnAsteroid(size: CGSize, asteroids: inout [Asteroid], worldCenter: CGPoint) {
        // Spawn from random edge
        let edge = Int.random(in: 0..<4)
        var pos = CGPoint.zero
        switch edge {
        case 0: pos = CGPoint(x: CGFloat.random(in: 0...size.width), y: -20)
        case 1: pos = CGPoint(x: size.width + 20, y: CGFloat.random(in: 0...size.height))
        case 2: pos = CGPoint(x: CGFloat.random(in: 0...size.width), y: size.height + 20)
        default: pos = CGPoint(x: -20, y: CGFloat.random(in: 0...size.height))
        }
        
        // Weighted type selection
        let r = Double.random(in: 0...1)
        let type: EnemyType = (r < 0.65) ? .small : (r < 0.90) ? .big : .evader
        
        // Aim roughly at center with jitter
        let jitter: CGFloat = 40
        let target = CGPoint(
            x: worldCenter.x + CGFloat.random(in: -jitter...jitter),
            y: worldCenter.y + CGFloat.random(in: -jitter...jitter)
        )
        let dir = CGVector(dx: target.x - pos.x, dy: target.y - pos.y)
        let len = max(1, sqrt(dir.dx*dir.dx + dir.dy*dir.dy))
        
        // Type-specific stats
        let speed: CGFloat
        let hp: Int
        let radius: CGFloat
        switch type {
        case .small:
            speed = CGFloat.random(in: 100...170)
            hp = 1
            radius = 10
        case .big:
            speed = CGFloat.random(in: 60...110)
            hp = 3
            radius = 18
        case .evader:
            speed = CGFloat.random(in: 100...160)
            hp = 2
            radius = 12
        }
        
        let vel = Vector2(x: (dir.dx/len) * speed, y: (dir.dy/len) * speed)
        
        asteroids.append(Asteroid(
            pos: .init(x: pos.x, y: pos.y),
            vel: vel,
            size: radius,
            alive: true,
            type: type,
            hp: hp
        ))
    }
    
    private func maxEnemies(now t: TimeInterval) -> Int {
        let start = 5
        let end = 10
        let k = min(1.0, t / 60.0)
        return Int(round(Double(start) + (Double(end - start) * k)))
    }
}
