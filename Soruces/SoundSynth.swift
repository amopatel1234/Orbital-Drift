//
//  SoundSynth.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//


import AVFoundation
import SwiftUI

// MARK: - Procedural Sound Synth
@MainActor
final class SoundSynth {
    static let shared = SoundSynth()

    // Respect your Settings toggle
    @AppStorage("soundEnabled") private var soundEnabled: Bool = true

    private let engine = AVAudioEngine()
    private let mainMixer: AVAudioMixerNode
    private var players: [AVAudioPlayerNode] = []
    private let sampleRate: Double = 44_100

    private init() {
        mainMixer = engine.mainMixerNode
        engine.connect(mainMixer, to: engine.outputNode, format: nil)
        try? engine.start()
    }

    // Reusable lightweight player
    private func player() -> AVAudioPlayerNode {
        if let idle = players.first(where: { !$0.isPlaying }) {
            return idle
        }
        let p = AVAudioPlayerNode()
        engine.attach(p)
        engine.connect(p, to: mainMixer, format: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        players.append(p)
        return p
    }

    // Public cues (use these in your game)
    func pickup()     { guard soundEnabled else { return }; play(buffer: Self.makePickup(sr: sampleRate)) }
    func shieldSave() { guard soundEnabled else { return }; play(buffer: Self.makeShieldSave(sr: sampleRate)) }
    func crash()      { guard soundEnabled else { return }; play(buffer: Self.makeCrash(sr: sampleRate)) }
    func nearMiss()   { guard soundEnabled else { return }; play(buffer: Self.makeNearMiss(sr: sampleRate)) }
    func tick()       { guard soundEnabled else { return }; play(buffer: Self.makeTick(sr: sampleRate)) }

    // Core playback
    private func play(buffer: AVAudioPCMBuffer) {
        let p = player()
        if !engine.isRunning { try? engine.start() }
        p.stop()
        p.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        p.play()
    }
}

// MARK: - DSP helpers
fileprivate enum Wave { case sine, square, triangle, saw, noise }

fileprivate struct ADSR {
    var attack: Double   // seconds
    var decay: Double
    var sustain: Double  // [0,1]
    var release: Double
}

// Generate a buffer by providing a per-sample closure
fileprivate func makeBuffer(duration: Double, sr: Double) -> AVAudioPCMBuffer {
    let frames = AVAudioFrameCount(max(1, Int(duration * sr)))
    let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
    buf.frameLength = frames
    return buf
}

fileprivate func applyADSR(_ adsr: ADSR, sr: Double, frame: Int, totalFrames: Int) -> Float {
    let t = Double(frame) / sr
    let dur = Double(totalFrames) / sr
    let attack = max(adsr.attack, 1.0/sr)
    let decay = max(adsr.decay, 1.0/sr)
    let releaseStart = max(0, dur - adsr.release)

    if t < attack {
        return Float(t / attack)
    } else if t < attack + decay {
        let d = (t - attack) / decay
        return Float(1.0 + (adsr.sustain - 1.0) * d)
    } else if t < releaseStart {
        return Float(adsr.sustain)
    } else {
        let r = (t - releaseStart) / max(adsr.release, 1.0/sr)
        return Float(max(0, adsr.sustain * (1.0 - r)))
    }
}

fileprivate func osc(_ wave: Wave, phase: Double) -> Float {
    switch wave {
    case .sine:     return Float(sin(phase))
    case .square:   return sin(phase) >= 0 ? 1 : -1
    case .triangle: return Float(2 / .pi * asin(sin(phase)))
    case .saw:      return Float((2 / .pi) * atan(tan(phase / 2)))
    case .noise:    return Float(Double.random(in: -1...1))
    }
}

// Simple 1-pole lowpass for noise shaping
fileprivate func lowpass(input: Float, state: inout Float, cutoffNorm: Float) -> Float {
    // cutoffNorm in (0,1); closer to 0 = stronger smoothing
    state += cutoffNorm * (input - state)
    return state
}

// Pitch sweep helper (linear in Hz)
fileprivate func phaseStep(f0: Double, f1: Double?, sr: Double, frame: Int, totalFrames: Int) -> Double {
    if let f1 = f1 {
        let t = Double(frame) / Double(totalFrames)
        let f = f0 + (f1 - f0) * t
        return (2.0 * .pi * f) / sr
    } else {
        return (2.0 * .pi * f0) / sr
    }
}

// Build a tone with optional sweep, waveform, ADSR, and gain
fileprivate func toneBuffer(duration: Double, f0: Double, f1: Double? = nil, wave: Wave, adsr: ADSR, gain: Float = 0.9, sr: Double) -> AVAudioPCMBuffer {
    let buf = makeBuffer(duration: duration, sr: sr)
    let ch = buf.floatChannelData![0]
    let n = Int(buf.frameLength)
    var phase = 0.0
    for i in 0..<n {
        phase += phaseStep(f0: f0, f1: f1, sr: sr, frame: i, totalFrames: n)
        let env = applyADSR(adsr, sr: sr, frame: i, totalFrames: n)
        var s = osc(wave, phase: phase) * env * gain
        // Gentle soft clip to avoid clicks/overs
        s = max(-1, min(1, s * 1.2))
        ch[i] = s
    }
    return buf
}

fileprivate func noiseBuffer(duration: Double, adsr: ADSR, gain: Float = 0.8, lowpassCutoff: Float = 0.12, sr: Double) -> AVAudioPCMBuffer {
    let buf = makeBuffer(duration: duration, sr: sr)
    let ch = buf.floatChannelData![0]
    let n = Int(buf.frameLength)
    var lpState: Float = 0
    for i in 0..<n {
        let env = applyADSR(adsr, sr: sr, frame: i, totalFrames: n)
        let raw = osc(.noise, phase: 0)
        let filtered = lowpass(input: raw, state: &lpState, cutoffNorm: lowpassCutoff)
        ch[i] = filtered * Float(env) * gain
    }
    return buf
}

// Mix multiple buffers (same format/length) into one
fileprivate func mix(_ buffers: [AVAudioPCMBuffer], sr: Double) -> AVAudioPCMBuffer {
    guard let first = buffers.first else { return makeBuffer(duration: 0.01, sr: sr) }
    let out = makeBuffer(duration: Double(first.frameLength) / sr, sr: sr)
    let dst = out.floatChannelData![0]
    for i in 0..<Int(out.frameLength) {
        var sum: Float = 0
        for b in buffers {
            sum += b.floatChannelData![0][i]
        }
        // Soft-limit
        dst[i] = max(-1, min(1, sum))
    }
    return out
}

// MARK: - Patch designs for your game cues
extension SoundSynth {
    // Pickup: short bright square chirp sweeping up
    static func makePickup(sr: Double) -> AVAudioPCMBuffer {
        let a = toneBuffer(duration: 0.12, f0: 660, f1: 1100, wave: .square,
                           adsr: .init(attack: 0.002, decay: 0.06, sustain: 0.2, release: 0.04),
                           gain: 0.6, sr: sr)
        let b = toneBuffer(duration: 0.12, f0: 1320, f1: 1760, wave: .triangle,
                           adsr: .init(attack: 0.002, decay: 0.05, sustain: 0.0, release: 0.03),
                           gain: 0.35, sr: sr)
        return mix([a,b], sr: sr)
    }

    // Shield save: “zap” — downward saw sweep + airy noise whoosh
    static func makeShieldSave(sr: Double) -> AVAudioPCMBuffer {
        let zap = toneBuffer(duration: 0.28, f0: 2000, f1: 220, wave: .saw,
                             adsr: .init(attack: 0.004, decay: 0.12, sustain: 0.25, release: 0.1),
                             gain: 0.75, sr: sr)
        let fizz = noiseBuffer(duration: 0.30,
                               adsr: .init(attack: 0.0, decay: 0.20, sustain: 0.15, release: 0.12),
                               gain: 0.35, lowpassCutoff: 0.18, sr: sr)
        return mix([zap, fizz], sr: sr)
    }

    // Crash: low boom + noisy thud
    static func makeCrash(sr: Double) -> AVAudioPCMBuffer {
        let boom = toneBuffer(duration: 0.45, f0: 110, f1: 60, wave: .sine,
                              adsr: .init(attack: 0.002, decay: 0.18, sustain: 0.25, release: 0.22),
                              gain: 0.85, sr: sr)
        let thud = noiseBuffer(duration: 0.35,
                               adsr: .init(attack: 0.0, decay: 0.18, sustain: 0.0, release: 0.08),
                               gain: 0.5, lowpassCutoff: 0.08, sr: sr)
        return mix([boom, thud], sr: sr)
    }

    // Near miss: short airy whoosh
    static func makeNearMiss(sr: Double) -> AVAudioPCMBuffer {
        noiseBuffer(duration: 0.18,
                    adsr: .init(attack: 0.0, decay: 0.12, sustain: 0.0, release: 0.06),
                    gain: 0.35, lowpassCutoff: 0.22, sr: sr)
    }

    // Tick: tiny high blip
    static func makeTick(sr: Double) -> AVAudioPCMBuffer {
        toneBuffer(duration: 0.05, f0: 2000, f1: 2200, wave: .sine,
                   adsr: .init(attack: 0.001, decay: 0.02, sustain: 0.0, release: 0.02),
                   gain: 0.25, sr: sr)
    }
}