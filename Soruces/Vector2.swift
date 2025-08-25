//
//  Vector2.swift
//  OrbitalDrift
//
//  Created by Amish Patel on 25/08/2025.
//


import CoreGraphics

/// A simple 2D vector type for game math.
struct Vector2: Equatable {
    var x: CGFloat
    var y: CGFloat

    // MARK: - Init
    init(x: CGFloat = 0, y: CGFloat = 0) {
        self.x = x
        self.y = y
    }

    // MARK: - Length & Normalization
    func length() -> CGFloat {
        sqrt(x * x + y * y)
    }

    func normalized() -> Vector2 {
        let len = length()
        guard len > 0 else { return Vector2(x: 0, y: 0) }
        return Vector2(x: x / len, y: y / len)
    }

    func distance(to other: Vector2) -> CGFloat {
        (self - other).length()
    }

    // MARK: - Arithmetic
    static func + (lhs: Vector2, rhs: Vector2) -> Vector2 {
        Vector2(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func - (lhs: Vector2, rhs: Vector2) -> Vector2 {
        Vector2(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func * (lhs: Vector2, rhs: CGFloat) -> Vector2 {
        Vector2(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    static func * (lhs: CGFloat, rhs: Vector2) -> Vector2 {
        Vector2(x: lhs * rhs.x, y: lhs * rhs.y)
    }

    static func / (lhs: Vector2, rhs: CGFloat) -> Vector2 {
        Vector2(x: lhs.x / rhs, y: lhs.y / rhs)
    }

    // MARK: - Mutating
    mutating func normalize() {
        self = normalized()
    }
}