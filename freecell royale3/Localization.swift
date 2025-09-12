import Foundation

// Uygulama içindeki metinleri telefon diline göre yönetmek için kullanılır.
enum L10n {
    private static var isTurkish: Bool {
        Locale.preferredLanguages.first?.hasPrefix("tr") ?? false
    }

    // Metin anahtarları
    enum StringKey {
        // Genel
        case selectGame
        case newGame
        case newGamePromptTitle
        case newGamePromptMessage
        case confirm
        case cancel
        case gamePaused
        case continueGame
        case bannerArea

        // Solitaire
        case solitaire
        case noMovesFound
        
        // FreeCell
        case freecell
        case invalidMove
        case maxCardsDraggable(Int)
    }

    static func string(for key: StringKey) -> String {
        switch key {
        // Genel
        case .selectGame:
            return isTurkish ? "Bir Oyun Seçin" : "Select a Game"
        case .newGame:
            return isTurkish ? "Yeni Oyun" : "New Game"
        case .newGamePromptTitle:
            return isTurkish ? "Yeni Oyun Başlatılsın mı?" : "Start a New Game?"
        case .newGamePromptMessage:
            return isTurkish ? "Mevcut oyun ilerlemeniz kaybolacak. Emin misiniz?" : "Your current game progress will be lost. Are you sure?"
        case .confirm:
            return isTurkish ? "Onayla" : "Confirm"
        case .cancel:
            return isTurkish ? "İptal" : "Cancel"
        case .gamePaused:
            return isTurkish ? "Oyun Duraklatıldı" : "Game Paused"
        case .continueGame:
            return isTurkish ? "Devam Et" : "Continue"
        case .bannerArea:
            return isTurkish ? "Banner Alanı" : "Banner Area"
            
        // Solitaire
        case .solitaire:
            return "Solitaire"
        case .noMovesFound:
            return isTurkish ? "Oynanacak hamle bulunamadı." : "No moves available."
            
        // FreeCell
        case .freecell:
            return "FreeCell"
        case .invalidMove:
            return isTurkish ? "Geçersiz Hamle." : "Invalid Move."
        case .maxCardsDraggable(let count):
            return isTurkish ? "En fazla \(count) kart taşıyabilirsiniz." : "You can move at most \(count) cards."
        }
    }
}
