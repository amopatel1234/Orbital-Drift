//
//  ScoringSystem.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 27/08/2025.
//


//
//  ScoringSystem.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//

import SwiftUI

@MainActor
@Observable
final class ScoringSystem {
    // MARK: - Score State
    var score: Int = 0
    var highScore: Int = UserDefaults.standard.integer(forKey: "highScore")
    var scoreMultiplier: Double = 1.0
    
    // MARK: - Multiplier Configuration
    private let maxMultiplier: Double = 10.0
    private let multiplierDecayPerSec: Double = 0.08
    
    // MARK: - Public Interface
    
    func addScore(_ points: Int) {
        let gained = Int(Double(points) * scoreMultiplier)
        score += gained
    }
    
    func addKillScore(_ baseValue: Int, for enemyType: EnemyType) -> Int {
        // Add multiplier boost first
        addMultiplierBoost(for: enemyType)
        
        // Calculate gained score with current multiplier
        let gained = Int(Double(baseValue) * scoreMultiplier)
        score += gained
        
        return gained
    }
    
    func addMultiplierBoost(for enemyType: EnemyType) {
        let boost = multiplierBoost(for: enemyType)
        scoreMultiplier = min(maxMultiplier, scoreMultiplier + boost)
    }
    
    func updateMultiplier(dt: TimeInterval) {
        if scoreMultiplier > 1.0 {
            scoreMultiplier = max(1.0, scoreMultiplier - multiplierDecayPerSec * dt)
        }
    }
    
    func finalizeScore() {
        highScore = max(highScore, score)
        UserDefaults.standard.set(highScore, forKey: "highScore")
    }
    
    func reset() {
        score = 0
        scoreMultiplier = 1.0
    }
    
    // MARK: - Private Implementation
    
    private func multiplierBoost(for type: EnemyType) -> Double {
        switch type {
        case .small:  return 0.12
        case .evader: return 0.18
        case .big:    return 0.25
        }
    }
}
