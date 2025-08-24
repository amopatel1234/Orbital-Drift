//
//  ScoreEntry.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//


import Foundation

struct ScoreEntry: Codable, Identifiable {
    let id = UUID()
    let value: Int
    let date: Date
}

@MainActor
final class ScoresStore: ObservableObject {
    @Published private(set) var entries: [ScoreEntry] = []
    private let key = "orbitaldrift.scores.v1"
    private let maxCount = 10

    init() { load() }

    func add(score: Int) {
        guard score > 0 else { return }
        entries.append(ScoreEntry(value: score, date: Date()))
        entries.sort { $0.value > $1.value }
        if entries.count > maxCount { entries = Array(entries.prefix(maxCount)) }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        if let decoded = try? JSONDecoder().decode([ScoreEntry].self, from: data) {
            entries = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func clearAll() {
        entries.removeAll()
        save()
    }

    var best: Int { entries.first?.value ?? 0 }
}
