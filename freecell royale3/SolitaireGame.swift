import SwiftUI
import UIKit

enum CardPileGroup {
    case topRow, tableau
}

class SolitaireGame: ObservableObject {
    
    struct GameState {
        let stock: [Card]
        let waste: [Card]
        let foundations: [[Card]]
        let tableau: [[(card: Card, isFaceUp: Bool)]]
        let drawCount: Int
        let isSolveable: Bool
    }
    
    @Published var stock: [Card] = []
    @Published var waste: [Card] = []
    @Published var foundations: [[Card]] = Array(repeating: [], count: 4)
    @Published var tableau: [[(card: Card, isFaceUp: Bool)]] = Array(repeating: [], count: 7)
    
    @Published var isGameOver: Bool = false
    @Published var isSolveable: Bool = false
    
    @Published var cardOffsets: [UUID: CGSize] = [:]
    @Published var draggedStack: [Card] = []
    
    @Published var errorMessage: String? = nil
    
    @Published private(set) var moveHistory: [GameState] = []
    @Published var drawCount: Int = 1
    
    // GÜNCELLEME: Sayaç durumu artık oyunun kendisine ait.
    @Published var elapsedTime: Int = 0
    private var gameTimer: Timer?
    
    @Published var animatingCardIDs: Set<UUID> = []
    @Published var isUndoAnimationActive: Bool = false
    @Published var animationSourceGroup: CardPileGroup? = nil
    @Published var animationSourceTableauIndex: Int? = nil
    @Published var animationSourceFoundationIndex: Int? = nil
    @Published var hintedCardIDs: Set<UUID> = []
    
    @Published var lockedTargetCardIDs: Set<UUID> = []
    
    var animationToken: UUID? = nil
    
    private var availableHints: [[UUID]] = []
    private var currentHintIndex: Int = -1

    var tableauFrames: [CGRect] = Array(repeating: .zero, count: 7)
    var foundationFrames: [CGRect] = Array(repeating: .zero, count: 4)
    
    var cardWidth: CGFloat = 70
    var cardHeight: CGFloat = 105

    private let faceDownOffsetFactor: CGFloat = 0.12
    private let faceUpOffsetFactor: CGFloat = 0.3

    init() {
        newGame()
    }

    func newGame() {
        let suits = ["♠", "♥", "♦", "♣"]
        let ranks = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]

        func makeDeck() -> [Card] {
            return suits.flatMap { suit in
                ranks.map { rank in Card(suit: suit, rank: rank) }
            }
        }

        func countSimpleVisibleMoves(_ openCards: [Card]) -> Int {
            var moves = 0
            for i in 0..<openCards.count {
                for j in 0..<openCards.count {
                    if i == j { continue }
                    let top = openCards[i], other = openCards[j]
                    if top.color != other.color && top.rankToInt() == other.rankToInt() + 1 {
                        moves += 1
                    }
                }
            }
            return moves
        }

        func visibleOpenCards(from tableau: [[(card: Card, isFaceUp: Bool)]]) -> [Card] {
            tableau.compactMap { $0.last?.card }
        }

        func isGoodStartingDeal(_ t: [[(card: Card, isFaceUp: Bool)]], strictness: Int) -> Bool {
            let open = visibleOpenCards(from: t)
            let aceCount = open.filter { $0.rank == "A" }.count
            let lowCount = open.filter { ["2","3"].contains($0.rank) }.count
            let moves = countSimpleVisibleMoves(open)
            let suitCounts = Dictionary(grouping: open, by: { $0.suit }).mapValues { $0.count }
            let maxSameSuit = suitCounts.values.max() ?? 0

            switch strictness {
            case 0:
                return (aceCount >= 2 || (aceCount >= 1 && lowCount >= 1)) && moves >= 3 && maxSameSuit <= 3
            case 1:
                return (aceCount >= 1 || lowCount >= 2) && moves >= 2 && maxSameSuit <= 4
            default:
                return moves >= 1 || lowCount >= 1
            }
        }

        let maxAttemptsStrict = 300
        let maxAttemptsRelaxed = 1000
        var attempts = 0
        var deck: [Card] = []
        var success = false

        foundations = Array(repeating: [], count: 4)
        tableau = Array(repeating: [], count: 7)
        waste = []
        stock = []

        while attempts < maxAttemptsRelaxed && !success {
            attempts += 1
            deck = makeDeck().shuffled()
            foundations = Array(repeating: [], count: 4)
            tableau = Array(repeating: [], count: 7)
            waste = []

            for i in 0..<7 {
                for j in i..<7 {
                    if let card = deck.popLast() {
                        tableau[j].append((card, i == j))
                    }
                }
            }
            stock = deck

            let strictness = (attempts <= maxAttemptsStrict) ? 0 : ((attempts <= maxAttemptsStrict + 300) ? 1 : 2)
            if isGoodStartingDeal(tableau, strictness: strictness) {
                success = true
            }
        }

        // GÜNCELLEME: Yeni oyun başladığında sayacı sıfırla.
        resetTimer()

        isGameOver = false
        isSolveable = false
        errorMessage = nil
        moveHistory.removeAll()
        hintedCardIDs.removeAll()
        availableHints.removeAll()
        currentHintIndex = -1
        resetSelectionsAndDrag()
        
        SoundManager.instance.playSound(sound: .place)
    }
    
    func clearAnimationState() {
        animatingCardIDs.removeAll()
        lockedTargetCardIDs.removeAll()
        // GÜNCELLEME: Animasyon kaynağı durumu artık ayrı bir fonksiyonla temizleniyor.
        clearAnimationSourceState()
    }
    
    // YENİ FONKSİYON: Yalnızca animasyon kaynağı durumunu temizleyerek,
    // devam eden diğer animasyonların durumunu etkilememeyi sağlar.
    func clearAnimationSourceState() {
        animationSourceGroup = nil
        animationSourceTableauIndex = nil
        animationSourceFoundationIndex = nil
    }
    
    func drawCard() {
        saveStateForUndo()
        if !stock.isEmpty {
            let cardsToMoveCount = min(drawCount, stock.count)
            for _ in 0..<cardsToMoveCount {
                if let card = stock.popLast() {
                    waste.append(card)
                }
            }
        } else {
            stock = waste.reversed()
            waste = []
        }
        SoundManager.instance.playSound(sound: .place)
        HapticManager.instance.impact(style: .soft)
        updateSolveableState()
    }

    func toggleDrawCount() {
        drawCount = (drawCount == 1) ? 3 : 1
    }
    
    private func saveStateForUndo() {
        // GÜNCELLEME: Oyunun ilk hamlesinde sayacı başlat.
        if moveHistory.isEmpty && elapsedTime == 0 {
            startTimer()
        }
        hintedCardIDs.removeAll()
        availableHints.removeAll()
        currentHintIndex = -1
        let currentState = GameState(stock: self.stock, waste: self.waste, foundations: self.foundations, tableau: self.tableau, drawCount: self.drawCount, isSolveable: self.isSolveable)
        moveHistory.append(currentState)
    }
    
    func undo() {
        guard let lastState = moveHistory.popLast() else { return }
        SoundManager.instance.playSound(sound: .undo)
        
        isUndoAnimationActive = true
        
        let stateBeforeUndo = GameState(stock: self.stock, waste: self.waste, foundations: self.foundations, tableau: self.tableau, drawCount: self.drawCount, isSolveable: self.isSolveable)
        let cardPositionsBefore = getAllCardIDsWithLocations()
        
        self.stock = lastState.stock
        self.waste = lastState.waste
        self.foundations = lastState.foundations
        self.tableau = lastState.tableau
        self.drawCount = lastState.drawCount
        self.isSolveable = lastState.isSolveable
        
        hintedCardIDs.removeAll()
        availableHints.removeAll()
        currentHintIndex = -1
        
        let cardPositionsAfter = getAllCardIDsWithLocations()
        
        var movedCardIDs = Set<UUID>()
        for (id, oldLocation) in cardPositionsBefore {
            if let newLocation = cardPositionsAfter[id], oldLocation != newLocation {
                movedCardIDs.insert(id)
            }
        }
        
        lockedTargetCardIDs.removeAll()
        for movedID in movedCardIDs {
            if let locationString = cardPositionsBefore[movedID] {
                if locationString.starts(with: "t") {
                    let components = locationString.split(separator: "_")
                    if components.count == 2, let tIndex = Int(String(components[0].dropFirst())), let cIndex = Int(components[1]), cIndex > 0 {
                        if stateBeforeUndo.tableau.indices.contains(tIndex), stateBeforeUndo.tableau[tIndex].indices.contains(cIndex - 1) {
                            let targetCard = stateBeforeUndo.tableau[tIndex][cIndex - 1].card
                            lockedTargetCardIDs.insert(targetCard.id)
                        }
                    }
                } else if locationString.starts(with: "f") {
                    let components = locationString.split(separator: "_")
                    if components.count == 2, let fIndex = Int(String(components[0].dropFirst())), let cIndex = Int(components[1]), cIndex > 0 {
                        if stateBeforeUndo.foundations.indices.contains(fIndex), stateBeforeUndo.foundations[fIndex].indices.contains(cIndex - 1) {
                            let targetCard = stateBeforeUndo.foundations[fIndex][cIndex - 1]
                            lockedTargetCardIDs.insert(targetCard.id)
                        }
                    }
                }
            }
            
            if let locationString = cardPositionsAfter[movedID] {
                if locationString.starts(with: "t") {
                    let components = locationString.split(separator: "_")
                    if components.count == 2, let tIndex = Int(String(components[0].dropFirst())), let cIndex = Int(components[1]), cIndex > 0 {
                        if self.tableau.indices.contains(tIndex), self.tableau[tIndex].indices.contains(cIndex - 1) {
                            let targetCard = self.tableau[tIndex][cIndex - 1].card
                            lockedTargetCardIDs.insert(targetCard.id)
                        }
                    }
                } else if locationString.starts(with: "f") {
                    let components = locationString.split(separator: "_")
                    if components.count == 2, let fIndex = Int(String(components[0].dropFirst())), let cIndex = Int(components[1]), cIndex > 0 {
                        if self.foundations.indices.contains(fIndex), self.foundations[fIndex].indices.contains(cIndex - 1) {
                            let targetCard = self.foundations[fIndex][cIndex - 1]
                            lockedTargetCardIDs.insert(targetCard.id)
                        }
                    }
                }
            }
        }
        
        if !movedCardIDs.isEmpty { HapticManager.instance.impact(style: .soft) }
        
        animatingCardIDs = movedCardIDs
        
        if let firstMovedID = movedCardIDs.first, let sourceLocation = cardPositionsBefore[firstMovedID] {
            if sourceLocation.starts(with: "t") {
                animationSourceGroup = .tableau
                let components = sourceLocation.split(separator: "_")
                if components.count > 1, let index = Int(String(components[0].dropFirst())) {
                    animationSourceTableauIndex = index
                }
                animationSourceFoundationIndex = nil
            } else {
                animationSourceGroup = .topRow
                animationSourceTableauIndex = nil
                if sourceLocation.starts(with: "f") {
                    let components = sourceLocation.split(separator: "_")
                    if components.count > 1, let index = Int(String(components[0].dropFirst())) {
                        animationSourceFoundationIndex = index
                    }
                } else { animationSourceFoundationIndex = nil }
            }
        } else {
            animationSourceGroup = nil
            animationSourceTableauIndex = nil
            animationSourceFoundationIndex = nil
        }
    }
    
    private func getAllCardIDsWithLocations() -> [UUID: String] {
        var locations: [UUID: String] = [:]
        stock.enumerated().forEach { (index, card) in locations[card.id] = "stock_\(index)" }
        waste.enumerated().forEach { (index, card) in locations[card.id] = "waste_\(index)" }
        foundations.enumerated().forEach { (fIndex, pile) in
            pile.enumerated().forEach { (cIndex, card) in locations[card.id] = "f\(fIndex)_\(cIndex)" }
        }
        tableau.enumerated().forEach { (tIndex, pile) in
            pile.enumerated().forEach { (cIndex, tuple) in locations[tuple.card.id] = "t\(tIndex)_\(cIndex)" }
        }
        return locations
    }

    func findStackForCard(card: Card) -> [Card]? {
        if waste.last == card { return [card] }
        
        for foundationPile in foundations { if foundationPile.last == card { return [card] } }
        
        for tableauPile in tableau {
            if let cardIndex = tableauPile.firstIndex(where: { $0.card == card && $0.isFaceUp }) {
                return tableauPile[cardIndex...].map { $0.card }
            }
        }
        return nil
    }
    
    func isStackValidToDrag(stack: [Card]) -> Bool {
        guard stack.count > 1 else { return true }

        for i in 0..<(stack.count - 1) {
            let topCard = stack[i]
            let bottomCard = stack[i+1]
            if topCard.color == bottomCard.color || topCard.rankToInt() != bottomCard.rankToInt() + 1 {
                setErrorMessage(L10n.string(for: .noMovesFound))
                return false
            }
        }
        return true
    }
    
    private func isStackValidForAutoMove(stack: [Card]) -> Bool {
        guard stack.count > 1 else { return true }
        for i in 0..<(stack.count - 1) {
            let topCard = stack[i]
            let bottomCard = stack[i+1]
            if topCard.color == bottomCard.color || topCard.rankToInt() != bottomCard.rankToInt() + 1 { return false }
        }
        return true
    }
    
    func handleDrop(for cardStack: [Card], dropLocation: CGPoint, sourceTableauIndex: Int?) {
        let originalState = GameState(stock: self.stock, waste: self.waste, foundations: self.foundations, tableau: self.tableau, drawCount: self.drawCount, isSolveable: self.isSolveable)
        var moveWasMade = false

        guard let topCard = cardStack.first else { return }
        
        let draggedCardFrame = CGRect(x: dropLocation.x - cardWidth / 2, y: dropLocation.y - cardHeight / 2, width: cardWidth, height: cardHeight)
        
        if cardStack.count == 1 {
            var bestFoundationIndex: Int? = nil
            var maxIntersectionArea: CGFloat = 0

            for (index, frame) in foundationFrames.enumerated() {
                if draggedCardFrame.intersects(frame) && canMove(card: topCard, toFoundation: index) {
                    let intersection = draggedCardFrame.intersection(frame)
                    let intersectionArea = intersection.width * intersection.height
                    if intersectionArea > maxIntersectionArea {
                        maxIntersectionArea = intersectionArea
                        bestFoundationIndex = index
                    }
                }
            }
            if let targetIndex = bestFoundationIndex {
                remove(cards: cardStack)
                foundations[targetIndex].append(topCard)
                checkGameOver()
                moveWasMade = true
            }
        }
        
        if !moveWasMade {
            var targetTableauIndex: Int?
            var maxIntersectionWidth: CGFloat = 0

            for i in 0..<tableauFrames.count {
                let columnXRange = tableauFrames[i].minX...tableauFrames[i].maxX
                let draggedCardXRange = draggedCardFrame.minX...draggedCardFrame.maxX
                
                if columnXRange.overlaps(draggedCardXRange) {
                    let overlapStart = max(columnXRange.lowerBound, draggedCardXRange.lowerBound)
                    let overlapEnd = min(columnXRange.upperBound, draggedCardXRange.upperBound)
                    let overlapWidth = overlapEnd - overlapStart
                    
                    if overlapWidth > maxIntersectionWidth {
                        maxIntersectionWidth = overlapWidth
                        targetTableauIndex = i
                    }
                }
            }
            
            if let tableauIndex = targetTableauIndex {
                let isDroppingOnItself = sourceTableauIndex != nil && sourceTableauIndex! == tableauIndex
                
                if !isDroppingOnItself {
                    let pile = tableau[tableauIndex]
                    let columnFrame = tableauFrames[tableauIndex]
                    let targetRect: CGRect

                    if pile.isEmpty { targetRect = columnFrame }
                    else {
                        let faceDownOffset = cardHeight * faceDownOffsetFactor
                        let faceUpOffset = cardHeight * faceUpOffsetFactor
                        let faceDownCount = pile.prefix(while: { !$0.isFaceUp }).count
                        let faceUpCount = pile.count - faceDownCount - 1
                        let lastCardYPosition = columnFrame.minY + (CGFloat(faceDownCount) * faceDownOffset) + (CGFloat(faceUpCount) * faceUpOffset)
                        let pileHeight = (lastCardYPosition + cardHeight) - columnFrame.minY
                        targetRect = CGRect(x: columnFrame.minX, y: columnFrame.minY, width: columnFrame.width, height: pileHeight)
                    }
                    
                    if draggedCardFrame.intersects(targetRect) && canMove(stack: cardStack, toTableau: tableauIndex) {
                        remove(cards: cardStack)
                        let newTuples = cardStack.map { (card: $0, isFaceUp: true) }
                        tableau[tableauIndex].append(contentsOf: newTuples)
                        moveWasMade = true
                    }
                }
            }
        }
        
        if moveWasMade {
             moveHistory.append(originalState)
             SoundManager.instance.playSound(sound: .place)
             HapticManager.instance.impact()
             updateSolveableState()
        } else { SoundManager.instance.playSound(sound: .tock) }
    }

    private func remove(cards: [Card]) {
        guard let firstCard = cards.first else { return }

        if waste.last == firstCard { waste.removeLast(); return }
        
        for i in 0..<foundations.count { if foundations[i].last == firstCard { foundations[i].removeLast(); return } }

        for i in 0..<tableau.count {
            if let cardIndex = tableau[i].firstIndex(where: { $0.card == firstCard }) {
                if tableau[i].count - cardIndex == cards.count {
                    tableau[i].removeLast(cards.count)
                    if let lastCard = tableau[i].last, !lastCard.isFaceUp {
                        tableau[i][tableau[i].count - 1].isFaceUp = true
                    }
                    return
                }
            }
        }
        updateSolveableState()
    }

    func resetSelectionsAndDrag() {
        for card in draggedStack { card.isDragging = false }
        draggedStack = []
        cardOffsets = [:]
    }
    
    func canAutoMove(for card: Card) -> Bool {
        guard let stack = findStackForCard(card: card) else { return false }
        if stack.count == 1 { if let _ = findValidFoundationFor(card: card) { return true } }
        if isStackValidForAutoMove(stack: stack) {
            for i in 0..<tableau.count {
                if tableau[i].contains(where: { $0.card.id == card.id }) { continue }
                if canMove(stack: stack, toTableau: i) { return true }
            }
        }
        return false
    }

    // HATA DÜZELTME: Silinen fonksiyon geri eklendi.
    private func findValidFoundationFor(card: Card) -> Int? {
        if let existingIndex = foundations.firstIndex(where: { !$0.isEmpty && $0.first!.suit == card.suit }) {
            if canMove(card: card, toFoundation: existingIndex) { return existingIndex }
        }
        else if card.rank == "A" { if let emptyIndex = foundations.firstIndex(where: { $0.isEmpty }) { return emptyIndex } }
        return nil
    }

    func autoMoveOnClick(for card: Card) {
        guard let stack = findStackForCard(card: card) else { return }
        
        var sourceTableauIndex: Int?
        for (index, pile) in tableau.enumerated() {
            if pile.contains(where: { $0.card.id == card.id }) { sourceTableauIndex = index; break }
        }
        
        var sourceFoundationIndex: Int?
        if sourceTableauIndex == nil {
            for (index, pile) in foundations.enumerated() {
                if pile.contains(where: { $0.id == card.id }) { sourceFoundationIndex = index; break }
            }
        }
        
        if let index = sourceTableauIndex {
            animationSourceGroup = .tableau
            animationSourceTableauIndex = index
            animationSourceFoundationIndex = nil
        } else {
            animationSourceGroup = .topRow
            animationSourceTableauIndex = nil
            animationSourceFoundationIndex = sourceFoundationIndex
        }
        
        // GÜNCELLEME: Mevcut animasyonlu kartların üzerine yazmak yerine set'e ekleme yapılıyor.
        // Bu, art arda tıklanan birden fazla kartın animasyonlarının birbirini bozmamasını sağlar.
        animatingCardIDs.formUnion(stack.map { $0.id })
        
        var moveMade = false

        if stack.count == 1, let targetIndex = findValidFoundationFor(card: card) {
            saveStateForUndo()
            remove(cards: [card])
            foundations[targetIndex].append(card)
            checkGameOver()
            updateSolveableState()
            moveMade = true
            SoundManager.instance.playSound(sound: .place)
            SoundManager.instance.playSound(sound: .foundation)
            HapticManager.instance.impact()
        }

        if !moveMade, isStackValidForAutoMove(stack: stack) {
            for i in 0..<tableau.count {
                if tableau[i].contains(where: { $0.card.id == card.id }) { continue }
                if canMove(stack: stack, toTableau: i) {
                    saveStateForUndo()
                    remove(cards: stack)
                    let newTuples = stack.map { (card: $0, isFaceUp: true) }
                    tableau[i].append(contentsOf: newTuples)
                    updateSolveableState()
                    moveMade = true
                    SoundManager.instance.playSound(sound: .place)
                    HapticManager.instance.impact()
                    break
                }
            }
        }
    }

    // GÜNCELLEME: Kartların takılmasını önlemek için 'solveGame' fonksiyonu yeniden yazıldı.
    // Artık her kartın animasyonu bittiğinde bir sonraki kart hareket ediyor.
    @MainActor
    func solveGame() {
        guard isSolveable else { return }
        isSolveable = false
        Task {
            await solveNextCard()
        }
    }

    @MainActor
    private func solveNextCard() async {
        let allPlayableCards = (waste + tableau.flatMap { $0.filter { $0.isFaceUp }.map { $0.card } }).sorted { $0.rankToInt() < $1.rankToInt() }
        
        var cardToMove: Card?
        var targetFoundation: Int?

        for card in allPlayableCards {
            if let fIndex = findValidFoundationFor(card: card) {
                cardToMove = card
                targetFoundation = fIndex
                break
            }
        }

        if let card = cardToMove, let fIndex = targetFoundation {
            await withCheckedContinuation { continuation in
                var sourceTableauIndex: Int?
                for (index, pile) in self.tableau.enumerated() {
                    if pile.contains(where: { $0.card.id == card.id }) { sourceTableauIndex = index; break }
                }
                 var sourceFoundationIndex: Int?
                if sourceTableauIndex == nil {
                    for (index, pile) in foundations.enumerated() { if pile.contains(where: { $0.id == card.id }) { sourceFoundationIndex = index; break } }
                }
                if let index = sourceTableauIndex {
                    self.animationSourceGroup = .tableau; self.animationSourceTableauIndex = index; self.animationSourceFoundationIndex = nil
                } else {
                    self.animationSourceGroup = .topRow; self.animationSourceTableauIndex = nil; self.animationSourceFoundationIndex = sourceFoundationIndex
                }
                self.animatingCardIDs = [card.id]
                
                SoundManager.instance.playSound(sound: .foundation)
                HapticManager.instance.impact(style: .soft)
                
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    remove(cards: [card])
                    foundations[fIndex].append(card)
                } completion: {
                    self.clearAnimationState()
                    continuation.resume()
                }
            }
            await solveNextCard()
        } else {
            checkGameOver()
        }
    }
    
    func canMove(card: Card, toFoundation index: Int) -> Bool {
        if let topCard = foundations[index].last {
            return card.suit == topCard.suit && card.rankToInt() == topCard.rankToInt() + 1
        } else { return card.rank == "A" }
    }
    
    func canMove(stack: [Card], toTableau index: Int) -> Bool {
        guard let bottomCardOfStack = stack.first else { return false }
        if let topCardTuple = tableau[index].last {
            guard topCardTuple.isFaceUp else { return false }
            return topCardTuple.card.color != bottomCardOfStack.color && bottomCardOfStack.rankToInt() == topCardTuple.card.rankToInt() - 1
        } else { return bottomCardOfStack.rank == "K" }
    }
    
    private func updateSolveableState() {
        let isDeckEmpty = stock.isEmpty && waste.isEmpty
        let areAllTableauCardsFaceUp = tableau.allSatisfy { pile in pile.allSatisfy { $0.isFaceUp } }
        isSolveable = isDeckEmpty && areAllTableauCardsFaceUp
    }
    
    func setErrorMessage(_ message: String) {
        errorMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if self.errorMessage == message { self.errorMessage = nil }
        }
    }
    
    func checkGameOver() {
        let wasGameOver = isGameOver
        isGameOver = foundations.allSatisfy { $0.count == 13 }
        if isGameOver && !wasGameOver {
            // GÜNCELLEME: Oyun bittiğinde sayacı durdur.
            stopTimer()
            SoundManager.instance.playSound(sound: .win)
            HapticManager.instance.notification(type: .success)
        }
    }

    func findHint() {
        if !availableHints.isEmpty {
            currentHintIndex = (currentHintIndex + 1) % availableHints.count
            hintedCardIDs = Set(availableHints[currentHintIndex])
            HapticManager.instance.impact(style: .soft)
            SoundManager.instance.playSound(sound: .foundation)
            return
        }

        var allPossibleMoves: [[UUID]] = []

        if let wasteCard = waste.last, findValidFoundationFor(card: wasteCard) != nil { allPossibleMoves.append([wasteCard.id]) }

        for pile in tableau {
            if let topCardTuple = pile.last, topCardTuple.isFaceUp, findValidFoundationFor(card: topCardTuple.card) != nil { allPossibleMoves.append([topCardTuple.card.id]) }
        }

        if let wasteCard = waste.last {
            for i in 0..<tableau.count { if canMove(stack: [wasteCard], toTableau: i) { allPossibleMoves.append([wasteCard.id]) } }
        }

        for sourceIndex in 0..<tableau.count {
            let sourcePile = tableau[sourceIndex]
            for (cardIndex, tuple) in sourcePile.enumerated() where tuple.isFaceUp {
                let stackToMove = Array(sourcePile[cardIndex...]).map { $0.card }
                if isStackValidForAutoMove(stack: stackToMove) {
                    for targetIndex in 0..<tableau.count where sourceIndex != targetIndex {
                        if canMove(stack: stackToMove, toTableau: targetIndex) { allPossibleMoves.append([tuple.card.id]) }
                    }
                }
            }
        }
        
        for foundation in foundations {
            if let foundationCard = foundation.last {
                for i in 0..<tableau.count { if canMove(stack: [foundationCard], toTableau: i) { allPossibleMoves.append([foundationCard.id]) } }
            }
        }
        
        if !allPossibleMoves.isEmpty {
            var uniqueMoves: [[UUID]] = []
            var seenCardIDs = Set<UUID>()
            for move in allPossibleMoves {
                if let cardID = move.first {
                    if !seenCardIDs.contains(cardID) {
                        uniqueMoves.append(move)
                        seenCardIDs.insert(cardID)
                    }
                }
            }
            
            if uniqueMoves.isEmpty {
                setErrorMessage(L10n.string(for: .noMovesFound))
                HapticManager.instance.notification(type: .warning)
                return
            }
            
            availableHints = uniqueMoves
            currentHintIndex = 0
            hintedCardIDs = Set(availableHints[currentHintIndex])
            SoundManager.instance.playSound(sound: .foundation)
        } else {
            setErrorMessage(L10n.string(for: .noMovesFound))
            HapticManager.instance.notification(type: .warning)
        }
    }
    
    // MARK: - Timer Controls
    func startTimer() {
        guard gameTimer == nil, !isGameOver else { return }
        DispatchQueue.main.async {
            self.gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.elapsedTime += 1
            }
        }
    }

    func stopTimer() {
        gameTimer?.invalidate()
        gameTimer = nil
    }

    func resetTimer() {
        stopTimer()
        elapsedTime = 0
    }
}

class HapticManager: ObservableObject {
    static let instance = HapticManager()
    private init() {}

    @Published var isMuted: Bool = false

    func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        guard !isMuted else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard !isMuted else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}

