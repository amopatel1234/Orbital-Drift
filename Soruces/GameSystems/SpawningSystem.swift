//
//  SpawningSystem.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 27/08/2025.
//

import SwiftUI

/// Manages procedural enemy spawning with difficulty progression and population limits.
///
/// `SpawningSystem` controls the rate and placement of enemy asteroids based on elapsed time:
/// - **Spawn Rate**: starts slow (`baseSpawnRate`) and ramps up over `rampDuration` seconds
///   by adding `rampSpawnBonus` to create increasing pressure.
/// - **Population Cap**: limits concurrent enemies via `maxEnemies(now:)`, with a reduced
///   cap during the initial `gracePeriod` for gentler onboarding.
/// - **Edge Spawning**: places enemies randomly along screen edges, aimed toward the center
///   with jitter to create natural variety.
/// - **Type Distribution**: weighted random selection (65% small, 25% big, 10% evader).
///
/// **Important**: This system does **not** own the asteroid array. It modifies the
/// authoritative array passed via `inout` from `GameState` to prevent sync issues.
/// The system only tracks timing state internally.
///
/// Ownership & interaction notes:
/// - `GameState` owns the canonical `asteroids` array and passes it via `inout`.
/// - Call `updateSpawning(dt:size:asteroids:worldCenter:)` with **simulation dt**
///   (affected by hit-stop) so spawning slows during dramatic moments.
/// - Enemy movement/AI is handled elsewhere; this system only handles creation and placement.
@MainActor
@Observable
final class SpawningSystem {
    // MARK: - Spawning State

    /// Total time elapsed since the last reset (seconds). Drives difficulty progression.
    private var elapsed: TimeInterval = 0

    /// Time accumulator for spawn intervals. When it exceeds `1.0 / spawnRate`,
    /// a new enemy is spawned (if population cap allows).
    private var spawnAcc: TimeInterval = 0
    
    // MARK: - Spawn Configuration

    /// Initial spawn rate (enemies per second) at the start of a run.
    var baseSpawnRate: Double = 0.6

    /// Additional spawn rate (enemies per second) added over `rampDuration`.
    /// Final rate = `baseSpawnRate + rampSpawnBonus`.
    var rampSpawnBonus: Double = 1.2

    /// Time (seconds) over which spawn rate ramps from `baseSpawnRate` to maximum.
    var rampDuration: Double = 60

    /// Time (seconds) during which enemy population is reduced for gentler onboarding.
    var gracePeriod: Double = 8
    
    // MARK: - Public Interface

    /// Updates spawn timing and creates new enemies if conditions are met.
    ///
    /// **Spawn Logic:**
    /// 1. Advances elapsed time and calculates current spawn rate (ramped over time).
    /// 2. Accumulates spawn time; when interval elapses, attempts to spawn.
    /// 3. Checks population cap (`maxEnemies`) vs. living asteroids before spawning.
    /// 4. Creates enemy via `spawnAsteroid(...)` with random type, edge placement, and stats.
    ///
    /// - Parameters:
    ///   - dt: Simulation delta time (affected by hit-stop for dramatic pacing).
    ///   - size: Screen/world bounds for edge spawning calculations.
    ///   - asteroids: **Authoritative** asteroid array (modified in-place via `inout`).
    ///   - worldCenter: Center point for enemy targeting with jitter.
    /// - Order: Call once per simulation frame from `GameState.update(...)`.
    func updateSpawning(dt: TimeInterval, size: CGSize, asteroids: inout [Asteroid], worldCenter: CGPoint) {
        elapsed += dt
        
        // Calculate ramped spawn rate
        let ramp = min(1.0, elapsed / rampDuration)
        let spawnRate = baseSpawnRate + ramp * rampSpawnBonus
        let spawnInterval = 1.0 / spawnRate
        
        spawnAcc += dt
        
        // Determine population cap (reduced during grace period)
        let cap = (elapsed < gracePeriod)
            ? max(3, maxEnemies(now: elapsed) - 2)
            : maxEnemies(now: elapsed)
        
        // Spawn enemies if interval elapsed and under population cap
        while spawnAcc >= spawnInterval {
            spawnAcc -= spawnInterval
            
            if asteroids.count(where: { $0.alive}) < cap {
                spawnAsteroid(size: size, asteroids: &asteroids, worldCenter: worldCenter)
            }
        }
    }
    
    /// Resets all timing state to defaults for a new run. Does **not** modify asteroid arrays.
    ///
    /// - Note: `GameState` is responsible for clearing the authoritative asteroid array.
    func reset() {
        elapsed = 0
        spawnAcc = 0
    }
    
    // MARK: - Private Implementation

    /// Creates a single enemy asteroid with random type, edge placement, and targeting.
    ///
    /// **Placement Strategy:**
    /// - Random edge (top/right/bottom/left) with slight off-screen positioning.
    /// - Aims toward `worldCenter` with jitter (±40 units) for natural movement variation.
    ///
    /// **Type Distribution:**
    /// - 65%: Small (fast, weak, 1 HP)
    /// - 25%: Big (slow, tanky, 3 HP)
    /// - 10%: Evader (medium speed/HP, special AI behavior)
    ///
    /// - Parameters:
    ///   - size: Screen bounds for edge spawn calculations.
    ///   - asteroids: Target array to append the new enemy.
    ///   - worldCenter: Center point for targeting (with jitter applied).
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
    
    /// Calculates the maximum concurrent enemies allowed based on elapsed time.
    ///
    /// Linearly interpolates from 5 enemies (start) to 10 enemies (60+ seconds)
    /// to create smooth difficulty progression.
    ///
    /// - Parameter t: Time elapsed since run start (seconds).
    /// - Returns: Maximum enemy population cap.
    private func maxEnemies(now t: TimeInterval) -> Int {
        let start = 5
        let end = 10
        let k = min(1.0, t / 60.0)
        return Int(round(Double(start) + (Double(end - start) * k)))
    }
}
