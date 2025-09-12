import SwiftUI

// Belirli bir "seed" ile her zaman aynı rastgele sayı dizisini üreten yardımcı struct.
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    var seed: UInt64
    init(seed: Int) { self.seed = UInt64(seed) }
    mutating func next() -> UInt64 {
        seed = 6364136223846793005 &* seed &+ 1442695040888963407
        return seed
    }
}

// Card modeline yardımcı fonksiyon ekleniyor.
extension Card {
    static func rankFromInt(_ rankInt: Int) -> String? {
        let ranks = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
        guard (1...13).contains(rankInt) else { return nil }
        return ranks[rankInt - 1]
    }
}

// Animasyonun nereden başladığını belirtmek için enum.
enum FreeCellAnimationSource {
    case column(index: Int)
    case freeCell(index: Int)
    case home(index: Int)
}

// Otomatik hareketin hedefini belirtmek için enum.
// Equatable protokolü, iki hedefin aynı olup olmadığını karşılaştırmak için eklendi.
enum AutoMoveTarget: Equatable {
    case home(index: Int)
    case column(index: Int)
}

// Bir ipucunu temsil eden struct.
struct Hint {
    let cardStack: [Card]
    let target: AutoMoveTarget
}

// Kart animasyonlarının detaylarını tutmak için yeni bir struct.
// Hedef (target), animasyonun nereye gittiğini belirtir (undo için nil olabilir).
// Sıra (order), aynı anda hareket eden kartların z-index'ini yönetmek için kullanılır.
struct AnimationDetails: Equatable {
    var target: AutoMoveTarget?
    var order: Int
}


class FreeCellGame: ObservableObject {
    @Published var columns: [[Card]] = Array(repeating: [], count: 8)
    @Published var freeCells: [Card?] = Array(repeating: nil, count: 4)
    @Published var homeCells: [[Card]] = Array(repeating: [], count: 4)
    
    @Published var cardOffsets: [UUID: CGSize] = [:]
    @Published var errorMessage: String? = nil
    @Published var isGameOver: Bool = false
    @Published var isSolveable: Bool = false
    
    @Published var draggedStack: [Card] = []
    
    // Değiştirildi: fcAnimatingCardIDs yerine daha detaylı bilgi tutan animatingCards kullanılıyor.
    // Bu, animasyon hedefi çakışmalarını kontrol etmeyi sağlar.
    @Published var animatingCards: [UUID: AnimationDetails] = [:]
    private var animationCounter: Int = 0

    @Published var fcAnimationSources: [UUID: FreeCellAnimationSource] = [:]
    
    @Published var elapsedTime: Int = 0
    @Published var isGameActive: Bool = false
    @Published var isUndoAnimationActive: Bool = false
    private var gameTimer: Timer?
    @Published private(set) var moveHistory: [GameState] = []
    
    // İpucu için özellikler
    @Published var hintCardID: UUID? = nil
    private var currentHintIndex: Int = 0
    
    var columnFrames: [CGRect] = Array(repeating: .zero, count: 8)
    var freeCellFrames: [CGRect] = Array(repeating: .zero, count: 4)
    var homeCellFrames: [CGRect] = Array(repeating: .zero, count: 4)

    var cardWidth: CGFloat = 0
    var cardHeight: CGFloat = 0

    private var seed: Int = 0

    struct GameState: Equatable {
        let freeCells: [Card?]
        let homeCells: [[Card]]
        let columns: [[Card]]
        let isSolveable: Bool
    }

    init() {
        newGame()
    }
    
    func newGame() {
        stopGameTimer()
        elapsedTime = 0
        isGameActive = false
        
        seed = Int.random(in: 1...100000)
        let deck = createShuffledDeck(seed: seed)
        dealCards(deck: deck)

        freeCells = Array(repeating: nil, count: 4)
        homeCells = Array(repeating: [], count: 4)
        resetSelectionsAndDrag()
        errorMessage = nil
        isGameOver = false
        isSolveable = false
        moveHistory.removeAll()
        clearAllAnimations()
        saveStateForUndo()
        updateSolveableState()
        
        hintCardID = nil
        currentHintIndex = 0
        
        SoundManager.instance.playSound(sound: .place)
    }
    
    func pauseTimer() {
        gameTimer?.invalidate()
        gameTimer = nil
    }

    func resumeTimer() {
        guard isGameActive else { return }
        gameTimer?.invalidate()
        setupTimer()
    }
    
    func startGameTimerIfNeeded() {
        guard !isGameActive else { return }
        isGameActive = true
        setupTimer()
    }

    func stopGameTimer() {
        gameTimer?.invalidate()
        gameTimer = nil
        isGameActive = false
    }
    
    private func setupTimer() {
        gameTimer?.invalidate()
        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.elapsedTime += 1
        }
    }

    private func createShuffledDeck(seed: Int) -> [Card] {
        let suits = ["♠", "♥", "♦", "♣"]
        let ranks = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
        var deck = suits.flatMap { suit in ranks.map { rank in Card(suit: suit, rank: rank) } }
        var rng = SeededRandomNumberGenerator(seed: seed)
        return deck.shuffled(using: &rng)
    }

    private func dealCards(deck: [Card]) {
        columns = Array(repeating: [], count: 8)
        for (index, card) in deck.enumerated() {
            columns[index % 8].append(card)
        }
    }

    private func saveStateForUndo() {
        let currentState = GameState(freeCells: freeCells, homeCells: homeCells, columns: columns, isSolveable: isSolveable)
        if moveHistory.last != currentState {
            moveHistory.append(currentState)
        }
    }
    
    private func getAllCardIDsWithLocations() -> [UUID: String] {
        var locations: [UUID: String] = [:]
        columns.enumerated().forEach { (colIndex, pile) in
            pile.enumerated().forEach { (cardIndex, card) in
                locations[card.id] = "col_\(colIndex)_\(cardIndex)"
            }
        }
        freeCells.enumerated().forEach { (index, card) in
            if let card = card {
                locations[card.id] = "free_\(index)"
            }
        }
        homeCells.enumerated().forEach { (homeIndex, pile) in
            pile.enumerated().forEach { (cardIndex, card) in
                 locations[card.id] = "home_\(homeIndex)_\(cardIndex)"
            }
        }
        return locations
    }

    func undo() {
        guard moveHistory.count > 1 else { return }
        SoundManager.instance.playSound(sound: .undo)
        HapticManager.instance.impact(style: .soft)

        hintCardID = nil
        currentHintIndex = 0
        isUndoAnimationActive = true
        let cardLocationsBefore = getAllCardIDsWithLocations()

        _ = moveHistory.popLast()
        if let lastState = moveHistory.last {
            self.freeCells = lastState.freeCells
            self.homeCells = lastState.homeCells
            self.columns = lastState.columns
            self.isSolveable = lastState.isSolveable
        }

        let cardLocationsAfter = getAllCardIDsWithLocations()
        var movedCardIDs = Set<UUID>()
        for (id, oldLocation) in cardLocationsBefore {
            if let newLocation = cardLocationsAfter[id], oldLocation != newLocation {
                movedCardIDs.insert(id)
            } else if cardLocationsAfter[id] == nil {
                movedCardIDs.insert(id)
            }
        }
        
        animationCounter += 1
        for cardID in movedCardIDs {
            animatingCards[cardID] = AnimationDetails(target: nil, order: animationCounter)
        }

        for cardID in movedCardIDs {
            if let oldLocationString = cardLocationsBefore[cardID] {
                if oldLocationString.starts(with: "col") {
                    let components = oldLocationString.split(separator: "_")
                    if components.count > 1, let index = Int(components[1]) {
                        fcAnimationSources[cardID] = .column(index: index)
                    }
                } else if oldLocationString.starts(with: "free") {
                    let components = oldLocationString.split(separator: "_")
                    if components.count > 1, let index = Int(components[1]) {
                        fcAnimationSources[cardID] = .freeCell(index: index)
                    }
                } else if oldLocationString.starts(with: "home") {
                    let components = oldLocationString.split(separator: "_")
                    if components.count > 1, let index = Int(components[1]) {
                        fcAnimationSources[cardID] = .home(index: index)
                    }
                }
            }
        }
        
        let idsToCleanUp = movedCardIDs
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            for cardID in idsToCleanUp {
                self.endAnimation(for: cardID)
            }
            if self.animatingCards.isEmpty {
                self.isUndoAnimationActive = false
            }
        }
    }

    func findStackForCard(card: Card) -> [Card]? {
        for column in columns {
            if let cardIndex = column.firstIndex(of: card) {
                return Array(column[cardIndex...])
            }
        }
        if freeCells.contains(where: { $0 == card }) { return [card] }
        return nil
    }
    
    func isCardDraggable(card: Card) -> Bool {
        if freeCells.contains(where: { $0 == card }) {
            return true
        }
        for column in columns {
            if column.last == card {
                return true
            }
        }
        if let stack = findStackForCard(card: card), stack.count > 1 {
            for i in 0..<(stack.count - 1) {
                let topCard = stack[i]
                let bottomCard = stack[i+1]
                if topCard.color == bottomCard.color || topCard.rankToInt() != bottomCard.rankToInt() + 1 {
                    return false
                }
            }
            return true
        }
        return false
    }
    
    func isStackValidToDrag(stack: [Card]) -> Bool {
        guard !stack.isEmpty else { return true }
        if stack.count > maxDraggableStackSize() {
            setErrorMessage("Taşınabilecek maksimum kart sayısını aştınız (\(maxDraggableStackSize()))")
            SoundManager.instance.playSound(sound: .error)
            HapticManager.instance.notification(type: .error)
            return false
        }
        if stack.count == 1 { return true }
        
        for i in 0..<(stack.count - 1) {
            let topCard = stack[i]
            let bottomCard = stack[i+1]
            if topCard.color == bottomCard.color || topCard.rankToInt() != bottomCard.rankToInt() + 1 {
                setErrorMessage("Geçersiz hamle")
                SoundManager.instance.playSound(sound: .error)
                HapticManager.instance.notification(type: .error)
                return false
            }
        }
        return true
    }
    
    // GÜNCELLEME: Sürükle-bırak hassasiyeti artırıldı. Artık kart, en çok temas ettiği geçerli yuvaya bırakılıyor.
    func handleDrop(for cardStack: [Card], dropLocation: CGPoint, sourceColumnIndex: Int?, sourceFreeCellIndex: Int?) {
        guard let topCard = cardStack.first else { return }

        let draggedCardFrame = CGRect(x: dropLocation.x - cardWidth / 2, y: dropLocation.y - cardHeight / 2, width: cardWidth, height: cardHeight)

        var potentialTargets: [(type: String, index: Int, overlap: CGFloat)] = []

        // 1. Olası tüm hedefleri ve kesişim alanlarını topla
        // FreeCell'ler ve HomeCell'ler için tam çerçeve kesişimini kullan
        if cardStack.count == 1 {
            for (index, frame) in freeCellFrames.enumerated() {
                if draggedCardFrame.intersects(frame) {
                    let overlapArea = draggedCardFrame.intersection(frame).width * draggedCardFrame.intersection(frame).height
                    potentialTargets.append((type: "freeCell", index: index, overlap: overlapArea))
                }
            }
            for (index, frame) in homeCellFrames.enumerated() {
                if draggedCardFrame.intersects(frame) {
                    let overlapArea = draggedCardFrame.intersection(frame).width * draggedCardFrame.intersection(frame).height
                    potentialTargets.append((type: "homeCell", index: index, overlap: overlapArea))
                }
            }
        }
        
        // Sütunlar için tüm yığını bir hedef olarak kabul et
        for (index, frame) in columnFrames.enumerated() {
            let pile = columns[index]
            let pileHeight = cardHeight + (CGFloat(max(0, pile.count - 1)) * (cardHeight * 0.3))
            let targetRect = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: pile.isEmpty ? cardHeight : pileHeight)
            
            if draggedCardFrame.intersects(targetRect) {
                let overlapArea = draggedCardFrame.intersection(targetRect).width * draggedCardFrame.intersection(targetRect).height
                potentialTargets.append((type: "column", index: index, overlap: overlapArea))
            }
        }
        
        // 2. En yüksek kesişim alanına sahip GEÇERLİ hedefi bul
        let validTargets = potentialTargets.filter { target in
            switch target.type {
            case "freeCell":
                return canMoveToFreeCell(card: topCard, index: target.index) && sourceFreeCellIndex != target.index
            case "homeCell":
                return canMoveToHomeCell(card: topCard, index: target.index)
            case "column":
                return canMoveStack(stack: cardStack, toColumn: target.index) && sourceColumnIndex != target.index
            default:
                return false
            }
        }

        guard let bestTarget = validTargets.max(by: { $0.overlap < $1.overlap }) else {
            SoundManager.instance.playSound(sound: .tock)
            return
        }

        // 3. SADECE en iyi hedefe göre hareketi gerçekleştir
        switch bestTarget.type {
        case "freeCell":
            move(card: topCard, toFreeCell: bestTarget.index)
        case "homeCell":
            move(card: topCard, toHomeCell: bestTarget.index)
        case "column":
            moveStack(stack: cardStack, toColumn: bestTarget.index)
        default:
            SoundManager.instance.playSound(sound: .tock)
        }
    }

    func maxDraggableStackSize() -> Int {
        let emptyFreeCells = freeCells.filter { $0 == nil }.count
        let emptyColumns = columns.filter { $0.isEmpty }.count
        return (emptyFreeCells + 1) * (1 << emptyColumns)
    }
    
    private func canMoveStack(stack: [Card], toColumn colIndex: Int) -> Bool {
        guard let topCardOfStack = stack.first else { return false }
        if let lastCardInColumn = columns[colIndex].last {
            return topCardOfStack.color != lastCardInColumn.color && topCardOfStack.rankToInt() == lastCardInColumn.rankToInt() - 1
        }
        return true
    }
    
    private func moveStack(stack: [Card], toColumn toIndex: Int) {
        startGameTimerIfNeeded()
        remove(cards: stack)
        columns[toIndex].append(contentsOf: stack)
        saveStateForUndo()
        hintCardID = nil
        currentHintIndex = 0
        SoundManager.instance.playSound(sound: .place)
        HapticManager.instance.impact()
        updateSolveableState()
        checkGameOver()
    }
    
    private func canMoveToFreeCell(card: Card, index: Int) -> Bool {
        return freeCells[index] == nil
    }

    private func move(card: Card, toFreeCell index: Int) {
        startGameTimerIfNeeded()
        remove(cards: [card])
        freeCells[index] = card
        saveStateForUndo()
        hintCardID = nil
        currentHintIndex = 0
        SoundManager.instance.playSound(sound: .place)
        HapticManager.instance.impact()
        updateSolveableState()
    }

    private func canMoveToHomeCell(card: Card, index: Int) -> Bool {
        if let topCard = homeCells[index].last {
            return card.suit == topCard.suit && card.rankToInt() == topCard.rankToInt() + 1
        } else {
            let suitsOrder = ["♠", "♥", "♦", "♣"]
            return card.rank == "A" && card.suit == suitsOrder[index]
        }
    }

    private func move(card: Card, toHomeCell index: Int) {
        startGameTimerIfNeeded()
        remove(cards: [card])
        homeCells[index].append(card)
        saveStateForUndo()
        hintCardID = nil
        currentHintIndex = 0
        SoundManager.instance.playSound(sound: .place)
        SoundManager.instance.playSound(sound: .foundation)
        HapticManager.instance.impact()
        updateSolveableState()
        checkGameOver()
    }
    
    func findAutoMoveTarget(for card: Card, from sourceColumnIndex: Int?) -> AutoMoveTarget? {
        guard let stack = findStackForCard(card: card) else { return nil }
        if stack.count > 1 {
            for i in 0..<(stack.count - 1) {
                if stack[i].color == stack[i+1].color || stack[i].rankToInt() != stack[i+1].rankToInt() + 1 {
                    return nil
                }
            }
        }

        if stack.count == 1 {
            let singleCard = stack[0]
            for i in 0..<homeCells.count {
                if canMoveToHomeCell(card: singleCard, index: i) {
                    return .home(index: i)
                }
            }
        }

        for i in 0..<columns.count {
            if let sourceIndex = sourceColumnIndex, sourceIndex == i {
                continue
            }
            if !columns[i].isEmpty && canMoveStack(stack: stack, toColumn: i) {
                return .column(index: i)
            }
        }

        return nil
    }

    func autoMoveOnClick(for card: Card, from source: FreeCellAnimationSource) {
        var sourceColumnIndex: Int?
        if case .column(let index) = source {
            sourceColumnIndex = index
        }

        guard let stack = findStackForCard(card: card) else { return }
        
        if stack.count > maxDraggableStackSize() {
            setErrorMessage("Taşınabilecek maksimum kart sayısını aştınız (\(maxDraggableStackSize()))")
            SoundManager.instance.playSound(sound: .error)
            HapticManager.instance.notification(type: .error)
            return
        }
        
        guard let target = findAutoMoveTarget(for: card, from: sourceColumnIndex) else { return }
        
        animationCounter += 1
        for c in stack {
            fcAnimationSources[c.id] = source
            animatingCards[c.id] = AnimationDetails(target: target, order: animationCounter)
        }

        switch target {
        case .home(let index):
            move(card: stack[0], toHomeCell: index)
        case .column(let index):
            moveStack(stack: stack, toColumn: index)
        }
    }

    private func remove(cards: [Card]) {
        guard let firstCard = cards.first else { return }
        for i in 0..<columns.count {
            if let cardIndex = columns[i].firstIndex(of: firstCard) {
                if columns[i].count - cardIndex >= cards.count && Array(columns[i][cardIndex..<(cardIndex + cards.count)]) == cards {
                    columns[i].removeLast(cards.count); return
                }
            }
        }
        for i in 0..<freeCells.count where freeCells[i] == firstCard {
            freeCells[i] = nil; return
        }
        for i in 0..<homeCells.count {
            if homeCells[i].last == firstCard {
                homeCells[i].removeLast(); return
            }
        }
    }
    
    func setErrorMessage(_ message: String) {
        errorMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if self.errorMessage == message {
                self.errorMessage = nil
            }
        }
    }

    func checkGameOver() {
        let wasGameOver = isGameOver
        isGameOver = homeCells.flatMap { $0 }.count == 52
        if isGameOver && !wasGameOver {
            stopGameTimer()
            SoundManager.instance.playSound(sound: .win)
        }
    }
    
    func endAnimation(for cardID: UUID) {
        animatingCards.removeValue(forKey: cardID)
        fcAnimationSources.removeValue(forKey: cardID)
    }
    
    func clearAllAnimations() {
        animatingCards.removeAll()
        fcAnimationSources.removeAll()
        animationCounter = 0
    }
    
    func resetSelectionsAndDrag() {
        for card in draggedStack {
            card.isDragging = false
        }
        draggedStack = []
        cardOffsets = [:]
    }
    
    func updateSolveableState() {
        for column in columns {
            if column.count <= 1 { continue }
            for i in 1..<column.count {
                let topCard = column[i-1]
                let bottomCard = column[i]
                if topCard.color == bottomCard.color || topCard.rankToInt() != bottomCard.rankToInt() + 1 {
                    if isSolveable { isSolveable = false }
                    return
                }
            }
        }
        if !isSolveable { isSolveable = true }
    }

    @MainActor
    func solveGame() {
        guard isSolveable else { return }
        isSolveable = false
        Task {
            // GÜNCELLEME: Animasyon süresi artırılarak yavaşlatıldı (0.1s -> 0.25s).
            let animationDuration: UInt64 = 250_000_000

            while homeCells.flatMap({ $0 }).count < 52 {
                var cardMovedInLoop = false
                
                let suitsOrder = ["♠", "♥", "♦", "♣"]
                for homeIndex in 0..<homeCells.count {
                    let suit = suitsOrder[homeIndex]
                    let nextRankInt = (homeCells[homeIndex].last?.rankToInt() ?? 0) + 1
                    guard let nextRank = Card.rankFromInt(nextRankInt) else { continue }
                    
                    var foundCard: (card: Card, source: FreeCellAnimationSource)? = nil

                    if let freeCellIndex = freeCells.firstIndex(where: { $0?.suit == suit && $0?.rank == nextRank }) {
                        if let card = freeCells[freeCellIndex] {
                             foundCard = (card, .freeCell(index: freeCellIndex))
                        }
                    }

                    if foundCard == nil {
                        if let columnIndex = columns.firstIndex(where: { $0.last?.suit == suit && $0.last?.rank == nextRank }) {
                            if let card = columns[columnIndex].last {
                                foundCard = (card, .column(index: columnIndex))
                            }
                        }
                    }

                    if let (cardToMove, source) = foundCard {
                        self.fcAnimationSources[cardToMove.id] = source
                        let target: AutoMoveTarget = .home(index: homeIndex)
                        
                        animationCounter += 1
                        self.animatingCards[cardToMove.id] = AnimationDetails(target: target, order: animationCounter)
                        
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            move(card: cardToMove, toHomeCell: homeIndex)
                        }
                        
                        SoundManager.instance.playSound(sound: .foundation)
                        HapticManager.instance.impact(style: .soft)
                        try? await Task.sleep(nanoseconds: animationDuration)
                        self.endAnimation(for: cardToMove.id)
                        
                        cardMovedInLoop = true
                        break
                    }
                }
                
                if !cardMovedInLoop { break }
            }
            checkGameOver()
        }
    }

    private func findAllPossibleMoves() -> [Hint] {
        var moves: [Hint] = []

        for (colIndex, column) in columns.enumerated() {
            if column.isEmpty { continue }

            for i in (0..<column.count).reversed() {
                let stack = Array(column[i...])
                var isSubStackOrderValid = true
                if stack.count > 1 {
                    for j in 0..<(stack.count - 1) {
                        if stack[j].color == stack[j+1].color || stack[j].rankToInt() != stack[j+1].rankToInt() + 1 {
                            isSubStackOrderValid = false
                            break
                        }
                    }
                }
                
                if !isSubStackOrderValid { break }
                if stack.count > maxDraggableStackSize() { continue }

                if stack.count == 1 {
                    for homeIndex in 0..<homeCells.count {
                        if canMoveToHomeCell(card: stack[0], index: homeIndex) {
                            moves.append(Hint(cardStack: stack, target: .home(index: homeIndex)))
                        }
                    }
                }

                for destColIndex in 0..<columns.count {
                    if colIndex == destColIndex { continue }
                    if !columns[destColIndex].isEmpty && canMoveStack(stack: stack, toColumn: destColIndex) {
                        moves.append(Hint(cardStack: stack, target: .column(index: destColIndex)))
                    }
                }
            }
        }
        return moves
    }

    func showNextHint() {
        let allPossibleMoves = findAllPossibleMoves()

        guard !allPossibleMoves.isEmpty else {
            setErrorMessage("Olası hamle bulunamadı")
            return
        }

        SoundManager.instance.playSound(sound: .foundation)

        if currentHintIndex >= allPossibleMoves.count {
            currentHintIndex = 0
        }

        let hint = allPossibleMoves[currentHintIndex]
        let cardToHint = hint.cardStack.first!
        self.hintCardID = cardToHint.id
        
        currentHintIndex += 1
    }
}

