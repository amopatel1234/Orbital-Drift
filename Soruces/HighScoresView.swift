//
//  HighScoresView.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 24/08/2025.
//


import SwiftUI

struct HighScoresView: View {
    @EnvironmentObject var scores: ScoresStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if scores.entries.isEmpty {
                Text("No scores yet. Play a round!").foregroundStyle(.secondary)
            } else {
                ForEach(Array(scores.entries.enumerated()), id: \.element.id) { idx, entry in
                    HStack {
                        Text("#\(idx + 1)")
                            .font(.headline.monospaced())
                            .frame(width: 44, alignment: .trailing)
                        VStack(alignment: .leading) {
                            Text("\(entry.value)").font(.title3.bold()).monospacedDigit()
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .onDelete { indexSet in
                    var new = scores.entries
                    new.remove(atOffsets: indexSet)
                    // Write back to store (simple way)
                    scores.clearAll()
                    new.forEach { scores.add(score: $0.value) }
                }
            }
        }
        .navigationTitle("High Scores")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    scores.clearAll()
                } label: { Image(systemName: "trash") }
                .disabled(scores.entries.isEmpty)
            }
        }
    }
}