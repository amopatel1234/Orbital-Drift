//
//  DisplayLinkAsync.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 25/08/2025.
//


import UIKit

/// AsyncSequence wrapper around CADisplayLink. One value per screen refresh.
enum DisplayLinkAsync {
    static func ticks() -> AsyncStream<CFTimeInterval> {
        AsyncStream { continuation in
            let link = CADisplayLink(target: Box(continuation), selector: #selector(Box.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 0)
            link.add(to: .main, forMode: .common)
            
            continuation.onTermination = { @Sendable _ in
                link.invalidate()
            }
        }
    }
    
    private final class Box {
        let continuation: AsyncStream<CFTimeInterval>.Continuation
        init(_ c: AsyncStream<CFTimeInterval>.Continuation) { continuation = c }
        @objc func tick(_ link: CADisplayLink) { continuation.yield(link.timestamp) }
    }
}
