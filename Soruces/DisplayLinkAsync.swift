//
//  DisplayLinkAsync.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 25/08/2025.
//

import UIKit

/// CADisplayLink as AsyncSequence (no Combine), Swift 6 Sendable-safe.
enum DisplayLinkAsync {
    static func ticks() -> AsyncStream<CFTimeInterval> {
        AsyncStream { continuation in
            let box = Box(continuation)

            // Create + configure the CADisplayLink on the main actor.
            Task { @MainActor in
                let link = CADisplayLink(target: box, selector: #selector(Box.tick(_:)))
                if #available(iOS 15.0, *) {
                    link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 0)
                } else {
                    link.preferredFramesPerSecond = 0 // automatic
                }
                link.add(to: .main, forMode: .common)
                box.setLink(link) // now called on the main actor ✅
            }

            continuation.onTermination = { @Sendable _ in
                // Always invalidate on the main actor.
                Task { @MainActor in
                    box.invalidateLink()
                }
            }
        }
    }

    /// Holds continuation + link; all link access stays on the main actor.
    private final class Box: NSObject, @unchecked Sendable {
        let continuation: AsyncStream<CFTimeInterval>.Continuation

        @MainActor private var link: CADisplayLink?

        init(_ c: AsyncStream<CFTimeInterval>.Continuation) { self.continuation = c }

        // CADisplayLink calls this on the runloop thread (main). Annotate for clarity.
        @MainActor @objc func tick(_ link: CADisplayLink) {
            continuation.yield(link.timestamp)
        }

        @MainActor func setLink(_ l: CADisplayLink) { self.link = l }

        @MainActor func invalidateLink() {
            link?.invalidate()
            link = nil
        }
    }
}
