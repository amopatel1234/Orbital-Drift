//
//  AppScreen.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//


import SwiftUI

enum AppScreen: Hashable {
    case menu
    case game
    case highScores
    case settings
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var path = NavigationPath()
    func go(_ screen: AppScreen) { path.append(screen) }
    func backToRoot() { path = .init() }
}