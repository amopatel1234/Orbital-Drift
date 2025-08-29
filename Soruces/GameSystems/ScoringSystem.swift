//
//  ScoringSystem.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 27/08/2025.
//

import SwiftUI

/// Coordinates score, high score persistence, and a time-decaying score multiplier.
///
/// `ScoringSystem` owns the player's **score** and **scoreMultiplier** and defines
/// how they change over time:
/// - Kills: award points based on the **current** multiplier, then boost the multiplier
///   by an amount tied to enemy difficulty (small < evader < big).
/// - Decay: multiplier smoothly returns toward 1.0 using **real dt** (unaffected by hit-stop),
///   so UI feedback continues naturally during slow-motion.
/// - Persistence: `finalizeScore()` updates `highScore` at the end of a run.
///
/// Ownership & interaction notes:
/// - This system does **not** know about entities or timeScale; callers pass `dt`.
/// - `GameState` should call `updateMultiplier(dt:)` with **raw clamped dt** (not simDt)
///   so multiplier decay continues during hit-stop.
/// - Use `addScore(_:)` for additive, multiplier-scaled awards (e.g., shield save bonus).
///   If you later need *flat* (non-multiplied) awards, prefer adding a separate `addFlatScore(_:)`.
@MainActor
@Observable
final class ScoringSystem {
    // MARK: - Score State

    /// Current run score (in points). Mutated via `addScore(_:)` and `addKillScore(_:for:)`.
    var score: Int = 0

    /// Highest score recorded across app launches. Updated in `finalizeScore()`.
    var highScore: Int = UserDefaults.standard.integer(forKey: "highScore")

    /// Multiplicative factor applied to most scoring events (≥ 1.0).
    /// Decays toward 1.0 over time; boosted on kills by enemy difficulty.
    var scoreMultiplier: Double = 1.0

    // MARK: - Multiplier Configuration

    /// Upper bound for `scoreMultiplier` to avoid runaway growth.
    private let maxMultiplier: Double = 10.0

    /// Units per second by which the multiplier decays back toward 1.0.
    /// Applied using **real dt** (GameState should pass raw clamped dt).
    private let multiplierDecayPerSec: Double = 0.08
    
    // MARK: - Firepower progression (kills-based)
    var killCount: Int = 0
    var currentFireTier: Int = 0
    /// Total kills needed to unlock tiers 1, 2, 3, 4 (tier 0 is the baseline).
    let fireTierThresholds: [Int] = [8, 20, 40, 70]
    
    // MARK: - Firepower tier (read-only surface)
    var fireTier: Int { currentFireTier }

    /// Pure helper (does not mutate) in case you want to preview tier from an arbitrary kill count.
    func fireTier(forKillCount k: Int) -> Int {
        var tier = 0
        for (idx, threshold) in fireTierThresholds.enumerated() {
            if k >= threshold { tier = idx + 1 } else { break }
        }
        return tier
    }

    // MARK: - Public Interface

    /// Increments kill count and returns a new firepower tier if a threshold was crossed.
    /// - Returns: The new tier (0...N) if increased, otherwise `nil`.
    @discardableResult
    func registerKillAndMaybeTierUp(for enemyType: EnemyType) -> Int? {
        killCount += 1

        // Compute tier from total kills (simple threshold compare).
        var computedTier = 0
        for (idx, threshold) in fireTierThresholds.enumerated() {
            if killCount >= threshold { computedTier = idx + 1 }
            else { break }
        }

        if computedTier > currentFireTier {
            currentFireTier = computedTier
            return currentFireTier
        }
        return nil
    }
    
    /// Adds points scaled by the current `scoreMultiplier`.
    ///
    /// - Parameter points: The base points to add before multiplier scaling.
    /// - Important: This method uses the **current** multiplier at the time of the call.
    func addScore(_ points: Int) {
        let gained = Int(Double(points) * scoreMultiplier)
        score += gained
    }

    /// Adds kill score for an enemy and then boosts the multiplier for future kills.
    ///
    /// **Order of operations (intentional):**
    /// 1. Award points using the **current** multiplier (pre-boost).
    /// 2. Boost the multiplier based on enemy difficulty (for *subsequent* kills).
    ///
    /// - Parameters:
    ///   - baseValue: The enemy's base point value (before multiplier).
    ///   - enemyType: Enemy difficulty, which controls the multiplier boost.
    /// - Returns: The number of points awarded for this kill (post-multiplier).
    func addKillScore(_ baseValue: Int, for enemyType: EnemyType) -> Int {
        // 1) Score with current multiplier (pre-boost)
        let gained = Int(Double(baseValue) * scoreMultiplier)
        score += gained

        // 2) Boost multiplier for subsequent kills
        addMultiplierBoost(for: enemyType)
        return gained
    }

    /// Applies a multiplier boost based on enemy difficulty.
    ///
    /// - Parameter enemyType: Enemy difficulty (small/evader/big).
    /// - Note: The new multiplier is clamped to `maxMultiplier`.
    func addMultiplierBoost(for enemyType: EnemyType) {
        let boost = multiplierBoost(for: enemyType)
        scoreMultiplier = min(maxMultiplier, scoreMultiplier + boost)
    }

    /// Updates multiplier decay using **real dt** (unaffected by hit-stop).
    ///
    /// - Parameter dt: Real (clamped) frame delta in seconds. Do **not** scale by timeScale.
    /// - Order: Call once per frame from `GameState.update(...)` before or after gameplay steps.
    func updateMultiplier(dt: TimeInterval) {
        if scoreMultiplier > 1.0 {
            scoreMultiplier = max(1.0, scoreMultiplier - multiplierDecayPerSec * dt)
        }
    }

    /// Writes `highScore` if the current `score` exceeds it.
    ///
    /// - Call when a run ends (e.g., on transition to `.gameOver`).
    func finalizeScore() {
        highScore = max(highScore, score)
        UserDefaults.standard.set(highScore, forKey: "highScore")
    }

    /// Resets per-run scoring to defaults. Does **not** modify `highScore`.
    func reset() {
        score = 0
        scoreMultiplier = 1.0
        killCount = 0
        currentFireTier = 0
    }

    // MARK: - Private Implementation

    /// Enemy-type-specific multiplier boost magnitudes.
    ///
    /// - Returns: The amount to add to `scoreMultiplier` after a kill.
    /// - Design: Harder enemies yield larger boosts to reward riskier plays.
    private func multiplierBoost(for type: EnemyType) -> Double {
        switch type {
        case .small:  return 0.12
        case .evader: return 0.18
        case .big:    return 0.25
        }
    }
}
