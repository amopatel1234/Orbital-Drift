//
//  MusicLoop.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//


import AVFoundation
import SwiftUI

/// Lightweight ambient music loop rendered in-code (no assets).
@MainActor
final class MusicLoop {
    static let shared = MusicLoop()

    @AppStorage("musicEnabled") private var musicEnabled: Bool = true
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let mixer  = AVAudioMixerNode()

    private let sampleRate: Double = 44_100
    private var loopBuffer: AVAudioPCMBuffer?
    private var currentVolume: Float = 0.0
    private var targetVolume: Float = 0.0
    private var volumeTimer: CADisplayLink?

    private init() {
        engine.attach(player)
        engine.attach(mixer)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        engine.connect(player, to: mixer, format: format)
        engine.connect(mixer, to: engine.outputNode, format: format)
        mixer.outputVolume = 0.0
        try? engine.start()

        // Pre-render loop (8 bars at ~60 BPM ~= 8 seconds)
        loopBuffer = Self.renderAmbientLoop(sr: sampleRate, seconds: 8.0)

        // smooth volume tween
        volumeTimer = CADisplayLink(target: self, selector: #selector(stepVolume))
        volumeTimer?.add(to: .main, forMode: .common)
    }

    deinit { volumeTimer?.invalidate() }

    // MARK: Public control

    func playIfNeeded() {
        guard musicEnabled else { fade(to: 0); stopWhenSilent(); return }
        guard let buf = loopBuffer else { return }

        if !engine.isRunning { try? engine.start() }
        if player.isPlaying { return }

        player.stop()
        player.scheduleBuffer(buf, at: nil, options: [.loops], completionHandler: nil)
        player.play()
    }

    func stop() {
        fade(to: 0)
        stopWhenSilent()
    }

    /// Smoothly fade to a target volume (0...1)
    func fade(to volume: Float, duration: TimeInterval = 0.6) {
        targetVolume = max(0, min(1, volume))
        // We'll tween in stepVolume() based on CADisplayLink
    }

    /// Convenience: set scene-based volumes
    enum Scene { case menu, tutorial, game, gameOver }
    func setScene(_ s: Scene) {
        switch s {
        case .menu, .tutorial: playIfNeeded(); fade(to: 0.6)
        case .game:            playIfNeeded(); fade(to: 0.25) // duck under SFX
        case .gameOver:        playIfNeeded(); fade(to: 0.5)
        }
    }

    // MARK: Internal helpers

    @objc private func stepVolume() {
        guard mixer.outputVolume != targetVolume else { return }
        // simple critically-damped-ish approach
        let step: Float = 0.08
        let newVol = currentVolume + (targetVolume - currentVolume) * step
        currentVolume = newVol
        mixer.outputVolume = newVol
        if abs(targetVolume - currentVolume) < 0.002 {
            currentVolume = targetVolume
            mixer.outputVolume = targetVolume
            if targetVolume == 0 { stopWhenSilent() }
        }
    }

    private func stopWhenSilent() {
        // Delay a touch so tails finish
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            if self.targetVolume == 0, self.currentVolume == 0 {
                self.player.stop()
            }
        }
    }
}

// MARK: - Loop renderer

private extension MusicLoop {
    /// Build an 8-second stereo ambient pad loop at 44.1kHz.
    static func renderAmbientLoop(sr: Double, seconds: Double) -> AVAudioPCMBuffer {
        let frames = Int(seconds * sr)
        let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buf.frameLength = AVAudioFrameCount(frames)

        let left  = buf.floatChannelData![0]
        let right = buf.floatChannelData![1]

        // Chord progression (MIDI): Cmaj7 → Amin7 → Fmaj7 → Gsus2 (soothing)
        let chords: [[Int]] = [
            [60, 64, 67, 71], // C E G B
            [57, 60, 64, 69], // A C E A (min7 feel)
            [53, 57, 60, 65], // F A C F (maj7 color via 65=D)
            [55, 62, 67, 69], // G D G A (sus2-ish)
        ]
        let chordDur = seconds / Double(chords.count)

        // Pad voices: 3 detuned sines per note + slow filter LFO
        let voicesPerNote = 3
        let detunes: [Double] = [-0.4, 0.0, +0.4]  // Hz offsets
        var phases = Array(repeating: 0.0, count: chords.count * 4 * voicesPerNote)

        // Reverb-ish tail via feedback comb (very light)
        var combL: Float = 0, combR: Float = 0
        let combCoef: Float = 0.04

        for i in 0..<frames {
            let t = Double(i) / sr
            let chordIndex = min(Int(t / chordDur), chords.count - 1)
            let chord = chords[chordIndex]

            // slow LFO for gentle filter/brightness
            let lfo = 0.5 + 0.5 * sin(2 * .pi * t / 6.0) // 6s period
            let toneGain: Float = 0.12 + Float(lfo) * 0.06

            var sampleL: Float = 0
            var sampleR: Float = 0

            // Build the pad by summing notes * detuned voices
            var voiceIdx = 0
            for note in chord {
                let f0 = 440.0 * pow(2.0, (Double(note) - 69.0) / 12.0)
                for d in detunes {
                    phases[voiceIdx] += (2.0 * .pi * (f0 + d)) / sr
                    let s = Float(sin(phases[voiceIdx])) * toneGain
                    // small stereo spread by voice index
                    let pan: Float = (-0.5 + Float(voiceIdx % 6) * 0.2)
                    let cL = (1 - max(0,  pan)) // crude pan law
                    let cR = (1 - max(0, -pan))
                    sampleL += s * cL
                    sampleR += s * cR
                    voiceIdx += 1
                }
            }

            // Subtle noise shimmer
            let shimmer = (Float.random(in: -1...1) + Float.random(in: -1...1)) * 0.005
            sampleL += shimmer; sampleR += shimmer

            // Very light comb “verb”
            combL = combL * (1 - combCoef) + sampleL * combCoef
            combR = combR * (1 - combCoef) + sampleR * combCoef
            sampleL += combL * 0.12
            sampleR += combR * 0.12

            // Gentle master limiter
            left[i]  = tanh(sampleL * 1.1)
            right[i] = tanh(sampleR * 1.1)
        }

        return buf
    }
}