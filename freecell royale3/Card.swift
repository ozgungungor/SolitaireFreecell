import Foundation
import SwiftUI

class Card: Identifiable, Equatable, Hashable, ObservableObject {
    let id = UUID()
    let suit: String
    let rank: String
    @Published var isDragging: Bool = false
    @Published var isSelectedForAutoMove: Bool = false

    init(suit: String, rank: String) {
        self.suit = suit
        self.rank = rank
    }

    func displayName() -> String {
        return "\(rank)\(suit)"
    }

    // Oyun mantığı için rank'ı sayıya çevirir
    func rankToInt() -> Int {
        switch rank {
        case "A": return 1
        case "J": return 11
        case "Q": return 12
        case "K": return 13
        default: return Int(rank) ?? 0
        }
    }

    // Kartların rengini belirler (kırmızı veya siyah)
    var color: Color {
        return suit == "♥" || suit == "♦" ? .red : .black
    }

    static func == (lhs: Card, rhs: Card) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
