import Foundation
import CoreGraphics

struct HazardDetection: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let confidence: Double
    let boundingBox: CGRect

    let dangerScore: Double
    let isInFront: Bool
    let area: CGFloat
}
