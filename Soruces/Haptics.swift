//
//  Haptics.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//


import UIKit
import CoreHaptics

final class Haptics {
    static let shared = Haptics()
    private let notif = UINotificationFeedbackGenerator()
    private let impactSoft = UIImpactFeedbackGenerator(style: .soft)
    private let impactRigid = UIImpactFeedbackGenerator(style: .rigid)

    func nearMiss()  { impactSoft.impactOccurred(intensity: 0.6) }
    func crash()     { notif.notificationOccurred(.error) }
    func scoreTick() { impactRigid.impactOccurred(intensity: 0.3) }
}