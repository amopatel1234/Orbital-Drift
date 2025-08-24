//
//  ScoreEntry.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//


import Foundation

struct ScoreEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let value: Int
    let date: Date
    
    // Normal initializer for new entries
    init(id: UUID = UUID(), value: Int, date: Date) {
        self.id = id
        self.value = value
        self.date = date
    }
    
    // Coding
    enum CodingKeys: String, CodingKey { case id, value, date }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.value = try c.decode(Int.self, forKey: .value)
        self.date  = try c.decode(Date.self,  forKey: .date)
        // If old data had no id, create one
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,    forKey: .id)
        try c.encode(value, forKey: .value)
        try c.encode(date,  forKey: .date)
    }
}

@MainActor
final class ScoresStore: ObservableObject {
    @Published private(set) var entries: [ScoreEntry] = []
    private let key = "orbitaldrift.scores.v1"
    private let maxCount = 10
    
    init() {
        load()
    }
    
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
