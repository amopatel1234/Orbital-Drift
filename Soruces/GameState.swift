//
//  GameState.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//
import SwiftUI
import Combine

@MainActor
final class GameState: ObservableObject {
    
    // MARK: - Published state
    @Published var phase: GamePhase = .menu
    @Published var score: Int = 0
    @Published var highScore: Int = UserDefaults.standard.integer(forKey: "highScore")
    @Published var player = Player()
    @Published var asteroids: [Asteroid] = []
    @Published var particles: [Particle] = []
    @Published var powerups: [Powerup] = []
    
    // Shields
    @Published var shieldCharges: Int = 0
    let maxShields: Int = 5
    @Published var invulnerability: TimeInterval = 0 // seconds of i-frames
    @Published var shockwaves: [Shockwave] = []
    // GameState.swift
    var invulnerabilityPulse: Double {
        guard invulnerability > 0 else { return 0 }
        // oscillate between 0…1 based on time remaining
        let t = CACurrentMediaTime()
        return (sin(t * 10) * 0.5 + 0.5)
    }
    
    // World / control
    @Published var worldCenter: CGPoint = .zero
    @Published var orbitRadiusRange: ClosedRange<CGFloat> = 90...150
    
    // Theme (if you’re using it in rendering)
    @AppStorage("theme") var theme: Theme = .classic
    
    // Juice
    @Published var shake: CGFloat = 0
    @Published var nearMissFlash: Double = 0
    
    // MARK: - Timing
    private var lastUpdate: TimeInterval = 0
    private var spawnAccumulator: TimeInterval = 0
    private var powerupTimer: TimeInterval = 0
    private var scoreAccumulator: TimeInterval = 0
    
    // MARK: - Difficulty
    private var spawnInterval: TimeInterval = 0.9
    private var minSpawnInterval: TimeInterval = 0.25
    
    // Near-miss
    private let nearMissThreshold: CGFloat = 14
    private var lastNearMissAt: TimeInterval = 0
    
    // MARK: - Public API
    func reset(in size: CGSize) {
        worldCenter = CGPoint(x: size.width/2, y: size.height/2)
        player = Player(angle: .pi/2, radius: 120)
        asteroids.removeAll()
        particles.removeAll()
        powerups.removeAll()
        shieldCharges = 0
        shockwaves.removeAll()
        invulnerability = 0
        score = 0
        
        spawnInterval = 0.9
        spawnAccumulator = 0
        powerupTimer = 0
        scoreAccumulator = 0
        lastUpdate = 0
        
        phase = .playing
    }
    
    func update(now: TimeInterval, size: CGSize) {
        guard phase == .playing else {
            lastUpdate = now
            return
        }
        if lastUpdate == 0 { lastUpdate = now }
        var dt = now - lastUpdate
        lastUpdate = now
        // clamp dt to avoid stalls
        dt = min(max(dt, 0), 1.0/30.0)
        
        // Tick invulnerability down
        if invulnerability > 0 {
            invulnerability = max(0, invulnerability - dt)
        }
        
        // Move asteroids
        for i in asteroids.indices {
            asteroids[i].pos.x += asteroids[i].vel.x * dt
            asteroids[i].pos.y += asteroids[i].vel.y * dt
        }
        
        // Cull off-screen or dead
        let pad: CGFloat = 60
        asteroids.removeAll { a in
            a.pos.x < -pad || a.pos.x > size.width + pad ||
            a.pos.y < -pad || a.pos.y > size.height + pad ||
            !a.alive
        }
        
        // Spawn logic (smoother progression)
        spawnAccumulator += dt
        if spawnAccumulator >= spawnInterval {
            spawnAccumulator = 0
            spawnAsteroid(size: size)
            spawnInterval = max(minSpawnInterval, spawnInterval - dt * 0.02)
        }
        
        // Powerup spawn timer (same as before; tweak as desired)
        powerupTimer += dt
        if powerupTimer > 6.5 {
            powerupTimer = 0
            if Bool.random(), powerups.count < 2 {
                let angle = CGFloat.random(in: 0...(2*CGFloat.pi))
                let r: CGFloat = CGFloat.random(in: 70...170)
                let p = CGPoint(x: worldCenter.x + cos(angle)*r, y: worldCenter.y + sin(angle)*r)
                powerups.append(Powerup(pos: .init(x: p.x, y: p.y)))
            }
        }
        
        // Particles update
        for i in particles.indices {
            particles[i].pos.x += particles[i].vel.x * dt
            particles[i].pos.y += particles[i].vel.y * dt
            particles[i].life -= CGFloat(dt * 1.8)
        }
        particles.removeAll { $0.life <= 0 }
        
        // Shockwaves update (NEW)
        for i in shockwaves.indices {
            shockwaves[i].age += CGFloat(dt * 1.6)    // speed of expansion
        }
        shockwaves.removeAll { $0.age >= 1 }
        
        // Collisions + near-miss
        let playerPos = playerPosition()
        var collided = false
        
        // Iterate by index; if shield triggers, mark asteroid dead and continue
        for i in asteroids.indices {
            let d = (asteroids[i].pos - Vector2(x: playerPos.x, y: playerPos.y)).length()
            let hitDist = (player.size + asteroids[i].size)
            
            if d < hitDist {
                // If invulnerable, pass through and delete the asteroid to prevent re-hit
                if invulnerability > 0 {
                    asteroids[i].alive = false
                    continue
                }
                
                if shieldCharges > 0 {
                    // Consume one shield, grant i-frames, delete the asteroid
                    shieldCharges -= 1
                    invulnerability = 0.7    // brief invulnerability window
                    asteroids[i].alive = false
                    
                    emitBurst(at: playerPos, count: 16, speed: 140...220)
                    emitShockwave(at: playerPos, maxRadius: 90)
                    Haptics.shared.nearMiss()
                    SoundSynth.shared.shieldSave()
                    
                    // Micro knockback to feel impactful
                    player.radius = min(player.radius + 8, orbitRadiusRange.upperBound)
                    
                    // OPTIONAL: small score reward for shield save
                    score += 10
                    continue
                } else {
                    // No shield → game over
                    collided = true
                    break
                }
            } else if d < hitDist + nearMissThreshold, now - lastNearMissAt > 0.35 {
                lastNearMissAt = now
                score += 5
                nearMissFlash = 1
                withAnimation(.easeOut(duration: 0.25)) { shake = 6 }
                Haptics.shared.nearMiss()
                SoundSynth.shared.nearMiss()
                emitBurst(at: playerPos, count: 6, speed: 50...120)
                // ensure we stay in playing state
                if phase != .playing { phase = .playing }
            }
        }
        
        // Powerup collect (now stacks up to 5)
        for i in powerups.indices {
            let d = (powerups[i].pos - Vector2(x: playerPos.x, y: playerPos.y)).length()
            if d < (player.size + powerups[i].size) {
                powerups[i].alive = false
                if shieldCharges < maxShields {
                    shieldCharges += 1
                    Haptics.shared.nearMiss()
                    SoundSynth.shared.pickup()
                    emitBurst(at: playerPos, count: 10, speed: 80...140)
                } else {
                    // Already full — optional sparkle
                    emitBurst(at: playerPos, count: 6, speed: 60...120)
                }
            }
        }
        powerups.removeAll { !$0.alive }
        
        if collided {
            player.isAlive = false
            phase = .gameOver
            highScore = max(highScore, score)
            UserDefaults.standard.set(highScore, forKey: "highScore")
            Haptics.shared.crash()
            SoundSynth.shared.crash()
        }
        
        // Score ticks (pulses)
        scoreAccumulator += dt
        if scoreAccumulator >= 0.5 {
            scoreAccumulator = 0
            score += 5
            Haptics.shared.scoreTick()
        }
        
        // Fade juice
        nearMissFlash = max(0, nearMissFlash - dt*3.0)
        shake = max(0, shake - CGFloat(dt*16))
    }
    
    // NEW: Shockwave emitter
    func emitShockwave(at p: CGPoint, maxRadius: CGFloat = 80) {
        shockwaves.append(Shockwave(pos: .init(x: p.x, y: p.y), age: 0, maxRadius: maxRadius))
    }
    
    func playerPosition() -> CGPoint {
        let x = worldCenter.x + cos(player.angle) * player.radius
        let y = worldCenter.y + sin(player.angle) * player.radius
        return CGPoint(x: x, y: y)
    }
    
    func inputDrag(_ value: DragGesture.Value) {
        guard phase == .playing else { return }
        let v = Vector2(x: value.location.x - worldCenter.x, y: value.location.y - worldCenter.y)
        let angle = atan2(v.y, v.x)
        player.angle = angle
        let dist = v.length()
        player.radius = min(max(dist, orbitRadiusRange.lowerBound), orbitRadiusRange.upperBound)
    }
    
    func spawnAsteroid(size: CGSize) {
        let edge = Int.random(in: 0..<4)
        var pos = CGPoint.zero
        switch edge {
        case 0: pos = CGPoint(x: CGFloat.random(in: 0...size.width), y: -20)
        case 1: pos = CGPoint(x: size.width + 20, y: CGFloat.random(in: 0...size.height))
        case 2: pos = CGPoint(x: CGFloat.random(in: 0...size.width), y: size.height + 20)
        default: pos = CGPoint(x: -20, y: CGFloat.random(in: 0...size.height))
        }
        let target = CGPoint(x: worldCenter.x + CGFloat.random(in: -40...40),
                             y: worldCenter.y + CGFloat.random(in: -40...40))
        let dir = CGVector(dx: target.x - pos.x, dy: target.y - pos.y)
        let len = max(1, sqrt(dir.dx*dir.dx + dir.dy*dir.dy))
        let speed = CGFloat.random(in: 60...160)
        let vel = Vector2(x: (dir.dx/len) * speed, y: (dir.dy/len) * speed)
        asteroids.append(Asteroid(pos: .init(x: pos.x, y: pos.y),
                                  vel: vel,
                                  size: CGFloat.random(in: 10...22)))
    }
    
    func emitBurst(at p: CGPoint, count: Int = 12, speed: ClosedRange<CGFloat> = 90...180) {
        for _ in 0..<count {
            let a = CGFloat.random(in: 0...(2*CGFloat.pi))
            let s = CGFloat.random(in: speed)
            particles.append(Particle(
                pos: .init(x: p.x, y: p.y),
                vel: .init(x: cos(a)*s, y: sin(a)*s),
                life: 1
            ))
        }
    }
    
    func togglePause() {
        switch phase {
        case .playing: phase = .paused
        case .paused:  phase = .playing
        default: break
        }
    }
}
