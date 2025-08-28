# Orbital Drift – SwiftUI Game

A minimalist SwiftUI + Canvas based arcade game.  
All gameplay state lives behind a **single observable orchestrator** (`GameState`), with specialized subsystems for motion, combat, effects, spawning, and scoring.

## Architecture

All gameplay state lives behind a **single observable orchestrator**:

| File                  | Responsibility |
|-----------------------|----------------|
| `GameState.swift`     | Central coordinator, main loop, owns `asteroids` array |
| `MotionSystem.swift`  | Angle/radius motion, momentum + spring |
| `CombatSystem.swift`  | Bullets, powerups, shields, invulnerability |
| `EffectsSystem.swift` | Particles, shockwaves, toasts, shake/zoom + hit-stop `timeScale` |
| `SpawningSystem.swift`| Time-ramped spawns, population caps (via `inout` array) |
| `ScoringSystem.swift` | Score, multiplier, decay, high-score |
| `OrbiterGameView.swift` | SwiftUI view, Canvas rendering, UI |
| `GameModels.swift`    | Data models: Player, Asteroid, Bullet, Powerup, Particle, etc. |

## Ownership rules

- `GameState` owns: `player`, **authoritative** `asteroids`, and all UI-exposed values.  
- `CombatSystem` owns: `bullets`, `powerups`, `shields`, `i-frames`.  
- `EffectsSystem` owns: `particles`, `shockwaves`, `toasts`, **and** the global `timeScale`.  
- `SpawningSystem` does **not** own arrays; it mutates `asteroids` via `inout`.  
- `ScoringSystem` owns: `score`, `highScore`, `scoreMultiplier`.

All subsystems are reset independently (`.reset()`), with `GameState.reset()` orchestrating the top-level reset.

## Time model (important)

Each frame:

- `dt` = **real** clamped delta (≤ 1/30s). Use for **visual decays** (shake, zoom, toasts).  
- `simDt = dt * effectsSystem.timeScale` → **gameplay** delta slowed by hit-stop. Used for enemies, bullets, powerups, collisions.

### Hit-stop presets (`EffectsSystem`):
- Big enemy kill → `timeScale = 0.33` for `0.12s`.  
- Evader kill → `timeScale = 0.6` for `0.08s`.  
- Recovery back to `1.0` is smooth (`+2.5 per second`).

## Systems

### MotionSystem
- Angular velocity with accel/decel, per-second damping (`pow(friction, dt)`).
- Radial movement uses a critically-damped spring toward `targetRadius`.
- Orbit bump haptics on min/max orbit edges.

### CombatSystem
- Shooting: fixed fire rate (`fireRate`), adds bullets toward world center.
- Powerups: spawn every ~6.5s, capped to 2, collected within player radius.
- Shields: up to 5 charges; consuming one gives `0.7s` invulnerability.
- Invulnerability pulse exposed via computed property.

### EffectsSystem
- Particles, shockwaves, score toasts, camera shake, zoom spring.
- Hit-stop control via `timeScale` + `hitStopTimer`.
- Particle budget clamped to `maxParticles`.

### SpawningSystem
- Procedural difficulty ramp: spawn rate rises over `60s` from `0.6/s` → `1.8/s`.
- Grace period (`8s`) with reduced caps.
- Weighted enemy type distribution: 65% small, 25% big, 10% evader.
- Population cap grows from 5 → 10 over first minute.
- Does not own arrays, only mutates via `inout`.

### ScoringSystem
- Additive scoring with multiplier boost per kill.
- Multiplier decays back to 1.0 if no kills.
- High score persisted via `UserDefaults`.

## Minimal usage

### Update loop (already wired in `GameState.update`)
```swift
let rawDt = now - lastUpdate
let dt = min(max(rawDt, 0), 1.0/30.0)
let simDt = dt * effectsSystem.timeScale

effectsSystem.updateEffects(dt: dt, particleBudget: 1.0)
scoringSystem.updateMultiplier(dt: dt)

spawningSystem.updateSpawning(dt: simDt, size: size, asteroids: &asteroids, worldCenter: worldCenter)
// + motion, enemies, bullets, collisions, powerups (all simDt)

---

## Controls hook
```swift
// UI events call:
game.setInnerPress(true/false)
game.setOuterPress(true/false)
game.holdRotateCCW = true/false
game.holdRotateCW = true/false
```

## Debugging
- `_debugFrameMs` is updated every frame (raw delta in ms).
- Particle budget scale enforced; reduce counts in `emitBurst` / `emitDirectionalBurst` if needed.
- Use `print(asteroids.count)` etc. inside `GameState.update()` to check spawn/culling behavior.

## Extending the game
- Add new enemy types → extend `EnemyType`, update `spawnAsteroid` + `applyHitStopForEnemy`, `addShakeForEnemy`.
- Add new effects → extend `EffectsSystem` with new entity arrays + update loop.
- Add score mechanics → hook into `ScoringSystem.addKillScore`.

## Build & targets
- Built with Xcode 16+, Swift 5.10, iOS 18 SDK.
- Uses SwiftUI `Canvas` for rendering, `@Observable` for state, and QuartzCore for timing.

## Release checklist
- [ ] Test hit-stop + zoom combos.
- [ ] Confirm score persistence via `UserDefaults`.
- [ ] Verify particle budget on older devices.
- [ ] Screenshots updated for App Store Connect.

## Troubleshooting
- **Game feels too slow after kills** → reduce `hitStopDurBig` / `hitStopDurMed`.  
- **Too many particles** → lower `maxParticles` or particle count multipliers.  
- **Player orbit bump feels harsh** → reduce `orbitBumpHaptic` intensity or increase cooldown.  
- **High score not saving** → check `UserDefaults` key `"highScore"`.  

## Contributing

Contributions are welcome! Please follow these guidelines:

### Branching
- Use feature branches (`feature/xyz`) for new systems or mechanics.
- Use fix branches (`fix/bug-description`) for bug fixes.

### Code style
- Swift 5.10+ with explicit access control (`private`, `fileprivate`, `internal`).
- Use `// MARK:` and emoji tags (📦, 🎮, 🌍, etc.) to group related properties/methods.
- Keep system responsibilities narrow: one job per class (`MotionSystem`, `CombatSystem`, etc.).
- Avoid singletons except for platform APIs (`Haptics.shared`, `SoundSynth.shared`).

### Documentation
- Every system file should have a header docblock with:
  - Responsibility
  - Ownership notes (who owns which arrays/state)
  - Update ordering (which `dt` to use)
- Use triple-slash `///` for public APIs, `//` for internal commentary.

### Testing
- Use debug overlays/logs (`print(asteroids.count)`) when validating spawns/culling.
- Simulate edge cases: 
  - Max shields, back-to-back powerups.
  - High spawn ramp (≥60s).
  - Hit-stop overlapping with zoom kicks.

### Commit messages
- Use short imperative style:
  - `Add hit-stop recovery smoothing`
  - `Fix shield not consuming correctly`
  - `Refactor SpawningSystem docs`

### Pull requests
- Keep PRs scoped to one system or concern.
- Update README and system-level docs if behavior changes.
