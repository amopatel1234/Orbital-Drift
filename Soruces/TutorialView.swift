//
//  TutorialView.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//


import SwiftUI

enum TutorialMode { case onboarding, standalone }

struct TutorialView: View {
    let mode: TutorialMode
    @AppStorage("seenTutorial") private var seenTutorial: Bool = false
    @EnvironmentObject private var router: AppRouter

    @State private var page = 0

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .purple.opacity(0.4)],
                           startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()

            TabView(selection: $page) {
                TutorialPage(
                    title: "Drag to Orbit",
                    message: "Touch and drag anywhere to move your ship around the planet.",
                    demo: AnyView(DemoOrbitView())
                ).tag(0)

                TutorialPage(
                    title: "Avoid Asteroids",
                    message: "Dodge incoming asteroids. One hit ends the round (unless you have a shield).",
                    demo: AnyView(DemoDodgeView())
                ).tag(1)

                TutorialPage(
                    title: "Near Miss = Bonus",
                    message: "Skim past for bonus points. Collect shields for a second chance.",
                    demo: AnyView(DemoBonusView())
                ).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            // Bottom CTA
            VStack {
                Spacer()
                if page == 2 {
                    Button(action: primaryAction) {
                        Text(mode == .onboarding ? "Let’s Play" : "Done")
                            .font(.title3.bold())
                            .padding(.horizontal, 32).padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .foregroundStyle(.white)
    }

    private func primaryAction() {
        switch mode {
        case .onboarding:
            seenTutorial = true
            router.go(.game)
        case .standalone:
            router.backToRoot()
        }
    }
}

private struct TutorialPage: View {
    let title: String
    let message: String
    let demo: AnyView

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)
            demo
            Text(title).font(.title.bold())
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 30)
            Spacer()
        }
        .foregroundColor(.white)
        .accessibilityElement(children: .combine)
    }
}
