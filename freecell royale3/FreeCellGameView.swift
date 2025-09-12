import SwiftUI

struct FreeCellGameView: View {
    @EnvironmentObject var game: FreeCellGame
    @State private var showNewGamePopup = false
    @Namespace private var cardAnimationNamespace

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    
    @StateObject private var soundManager = SoundManager.instance
    @StateObject private var hapticManager = HapticManager.instance
    
    @State private var draggedColumnIndex: Int? = nil
    @State private var draggedFreeCellIndex: Int? = nil
    
    // Aynı anda tek bir sürüklemeye izin vermek için.
    @State private var activeDragID: UUID? = nil
    
    private let cardCornerRadius: CGFloat = 4
    
    private enum NoirButtonColors {
        static let undo = [Color(red: 0.3, green: 0.3, blue: 0.8), Color(red: 0.15, green: 0.15, blue: 0.4)]
        static let solve = [Color(red: 0.5, green: 0.2, blue: 0.6), Color(red: 0.3, green: 0.1, blue: 0.4)]
        static let hint = [Color(red: 0.7, green: 0.2, blue: 0.2), Color(red: 0.4, green: 0.1, blue: 0.1)]
        static let audio = [Color(red: 0.1, green: 0.5, blue: 0.5), Color(red: 0.05, green: 0.3, blue: 0.3)]
        static let home = [Color(red: 0.8, green: 0.3, blue: 0.1), Color(red: 0.5, green: 0.15, blue: 0.05)]
        static let newGame = [Color(red: 0.2, green: 0.6, blue: 0.3), Color(red: 0.1, green: 0.4, blue: 0.15)]
    }
    
    private func zIndexForCard(_ card: Card, in pile: [Card]) -> Double {
        if game.isUndoAnimationActive && game.animatingCards.keys.contains(card.id) {
            return 1500
        }
        
        if card.isDragging {
            if let dragIndex = game.draggedStack.firstIndex(of: card) {
                return 1000 + Double(dragIndex)
            }
            return 1000
        }
        
        if let animationDetails = game.animatingCards[card.id] {
            return 500 + Double(animationDetails.order)
        }
        
        if let cardIndex = pile.firstIndex(of: card) {
            return Double(cardIndex)
        }
        
        return 0
    }

    var body: some View {
        ZStack {
            GameBackgroundView()
            
            GeometryReader { geometry in
                let cardSize = calculateCardSize(for: geometry.size)
                
                let (topZ, columnsZ) = { () -> (Double, Double) in
                    if !game.draggedStack.isEmpty {
                        if draggedFreeCellIndex != nil {
                            return (10, 5)
                        }
                        return (5, 10)
                    }
                    return (1, 2)
                }()
                
                VStack(spacing: 15) {
                    HStack {
                        Text(L10n.string(for: .freecell))
                            .font(.custom("Palatino-Bold", size: 28))
                            .foregroundColor(.white.opacity(0.9))
                        Spacer()
                        TimerView(elapsedTime: game.elapsedTime)
                    }
                    .padding(.horizontal)

                    topCellsView(cardSize: cardSize)
                        .zIndex(topZ)

                    columnsView(cardSize: cardSize)
                        .zIndex(columnsZ)
                    
                    Spacer(minLength: 0)
                    
                    bottomControlsView(cardSize: cardSize)
                    
                    // DEĞİŞİKLİK: Yer tutucu metin AdBannerView ile değiştirildi.
                    AdBannerView()
                        .padding(.bottom, 8)
                }
                .padding(.vertical)
                .offset(x: -geometry.size.width * 0.015)
                .onAppear {
                    let calculatedSize = calculateCardSize(for: geometry.size)
                    game.cardWidth = calculatedSize.width
                    game.cardHeight = calculatedSize.height
                }
                .onChange(of: geometry.size) { newSize in
                    let calculatedSize = calculateCardSize(for: newSize)
                    game.cardWidth = calculatedSize.width
                    game.cardHeight = calculatedSize.height
                }
            }
            
            if let message = game.errorMessage {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.custom("Palatino-Bold", size: 20))
                        .padding()
                        .background(Color.red.opacity(0.9))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(20_000)
                    Spacer().frame(height: 150)
                }
                .allowsHitTesting(false)
            }
            
            if game.isGameOver {
                FireworksView()
            }
            
            if showNewGamePopup {
                CustomAlertView(
                    title: L10n.string(for: .newGamePromptTitle),
                    message: L10n.string(for: .newGamePromptMessage),
                    confirmButtonTitle: L10n.string(for: .confirm),
                    cancelButtonTitle: L10n.string(for: .cancel),
                    onConfirm: {
                        game.newGame()
                        showNewGamePopup = false
                    },
                    onCancel: { showNewGamePopup = false }
                )
                .zIndex(30_000)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            game.resumeTimer()
        }
        .onDisappear {
            game.pauseTimer()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                game.resumeTimer()
            } else {
                game.pauseTimer()
            }
        }
    }
    
    private func calculateCardSize(for size: CGSize) -> (width: CGFloat, height: CGFloat, spacing: CGFloat) {
        let totalHorizontalPadding = size.width * 0.04
        let totalUsableWidth = size.width - totalHorizontalPadding
        let cardWidth = totalUsableWidth / 8.5
        let spacing = cardWidth * 0.1
        let cardHeight = cardWidth * 1.5
        return (floor(cardWidth), floor(cardHeight), floor(spacing))
    }
    
    private func zIndexForColumn(at index: Int) -> Double {
        if game.isUndoAnimationActive {
            let columnCardIDs = Set(game.columns[index].map { $0.id })
            if !columnCardIDs.isDisjoint(with: Set(game.animatingCards.keys)) {
                return 200
            }
        }

        if draggedColumnIndex == index { return 100 }
        
        for source in game.fcAnimationSources.values {
            if case .column(let sourceIndex) = source, sourceIndex == index {
                return 50
            }
        }
        return 0
    }

    private func zIndexForFreeCell(at index: Int) -> Double {
        if draggedFreeCellIndex == index { return 100 }
        for source in game.fcAnimationSources.values {
            if case .freeCell(let sourceIndex) = source, sourceIndex == index {
                return 50
            }
        }
        return 0
    }
    
    private func zIndexForHomeCell(at index: Int) -> Double {
        for source in game.fcAnimationSources.values {
            if case .home(let sourceIndex) = source, sourceIndex == index {
                return 50
            }
        }
        return 0
    }

    private func topCellsView(cardSize: (width: CGFloat, height: CGFloat, spacing: CGFloat)) -> some View {
        HStack(spacing: cardSize.spacing) {
            ForEach(game.freeCells.indices, id: \.self) { index in
                ZStack {
                    EmptyCellView(cardSize: cardSize, cornerRadius: cardCornerRadius)
                    if let card = game.freeCells[index] {
                        FreeCellCardView(card: card, cardSize: cardSize, namespace: cardAnimationNamespace, draggedColumnIndex: .constant(nil), freeCellIndex: index, draggedFreeCellIndex: $draggedFreeCellIndex, activeDragID: $activeDragID, cornerRadius: cardCornerRadius)
                            .zIndex(zIndexForCard(card, in: game.freeCells.compactMap { $0 }))
                    }
                }
                .zIndex(zIndexForFreeCell(at: index))
                .background(GeometryReader { geo in Color.clear.onAppear { game.freeCellFrames[index] = geo.frame(in: .global) }.onChange(of: geo.frame(in: .global)) { newFrame in game.freeCellFrames[index] = newFrame } })
            }
            Spacer()
            ForEach(game.homeCells.indices, id: \.self) { index in
                 let suits = ["♠", "♥", "♦", "♣"]
                ZStack {
                    EmptyCellView(placeholder: suits[index], cardSize: cardSize, cornerRadius: cardCornerRadius)
                    ForEach(game.homeCells[index]) { card in
                         FreeCellCardView(card: card, cardSize: cardSize, isDraggable: false, namespace: cardAnimationNamespace, draggedColumnIndex: .constant(nil), draggedFreeCellIndex: .constant(nil), activeDragID: $activeDragID, cornerRadius: cardCornerRadius)
                             .zIndex(zIndexForCard(card, in: game.homeCells[index]))
                     }
                }
                .zIndex(zIndexForHomeCell(at: index))
                .background(GeometryReader { geo in Color.clear.onAppear { game.homeCellFrames[index] = geo.frame(in: .global) }.onChange(of: geo.frame(in: .global)) { newFrame in game.homeCellFrames[index] = newFrame } })
            }
        }
        .padding(.horizontal, cardSize.spacing)
    }

    private func columnsView(cardSize: (width: CGFloat, height: CGFloat, spacing: CGFloat)) -> some View {
        HStack(alignment: .top, spacing: cardSize.spacing) {
            ForEach(game.columns.indices, id: \.self) { index in
                let columnCards = game.columns[index]
                ZStack(alignment: .top) {
                    EmptyCellView(cardSize: cardSize, cornerRadius: cardCornerRadius).frame(maxHeight: .infinity, alignment: .top)
                    ForEach(columnCards.indices, id: \.self) { cardIndex in
                        let card = columnCards[cardIndex]
                        let yOffset = cardSize.height * 0.3 * CGFloat(cardIndex)
                        FreeCellCardView(card: card, cardSize: cardSize, namespace: cardAnimationNamespace, columnIndex: index, draggedColumnIndex: $draggedColumnIndex, draggedFreeCellIndex: .constant(nil), activeDragID: $activeDragID, cornerRadius: cardCornerRadius)
                            .offset(y: yOffset)
                            .zIndex(zIndexForCard(card, in: columnCards))
                    }
                }
                .zIndex(zIndexForColumn(at: index))
                .background(GeometryReader { geo in Color.clear.onAppear { game.columnFrames[index] = geo.frame(in: .global) }.onChange(of: geo.frame(in: .global)) { newFrame in game.columnFrames[index] = newFrame } })
            }
        }
        .padding(.horizontal, cardSize.spacing)
    }
    
    private func bottomControlsView(cardSize: (width: CGFloat, height: CGFloat, spacing: CGFloat)) -> some View {
        let isInteractionDisabled = !game.draggedStack.isEmpty
        let buttonSize = cardSize.width * 1.2
        
        return HStack(spacing: cardSize.spacing) {
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    game.undo()
                }
            }) {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(NoirButtonStyle(size: buttonSize, colors: NoirButtonColors.undo, isEnabled: game.moveHistory.count > 1 && !game.isGameOver))
            .disabled(game.moveHistory.count <= 1 || game.isGameOver)
            
            if game.isSolveable && !game.isGameOver {
                Button(action: { game.solveGame() }) {
                    Image(systemName: "wand.and.stars")
                        .foregroundColor(.purple.opacity(0.8))
                }
                .buttonStyle(NoirButtonStyle(size: buttonSize, colors: NoirButtonColors.solve))
                .transition(.scale.combined(with: .opacity))
            } else {
                Button(action: {
                    game.showNextHint()
                    soundManager.playSound(sound: .tick)
                    hapticManager.impact(style: .light)
                }) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                }
                .buttonStyle(NoirButtonStyle(size: buttonSize, colors: NoirButtonColors.hint, isEnabled: !game.isGameOver))
                .disabled(game.isGameOver)
                .transition(.scale.combined(with: .opacity))
            }

            Spacer(minLength: 0)

            Button(action: {
                soundManager.toggleAudioState()
                soundManager.playSound(sound: .tick)
                hapticManager.impact(style: .light)
            }) {
                Image(systemName: soundManager.audioHapticState.iconName)
            }
            .buttonStyle(NoirButtonStyle(size: buttonSize, colors: NoirButtonColors.audio))
            
            Button(action: { dismiss(); soundManager.playSound(sound: .tick); hapticManager.impact(style: .light) }) {
                Image(systemName: "house.fill")
            }
            .buttonStyle(NoirButtonStyle(size: buttonSize, colors: NoirButtonColors.home))

            Button(action: {
                showNewGamePopup = true
                soundManager.playSound(sound: .tick)
                hapticManager.impact(style: .light)
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(NoirButtonStyle(size: buttonSize, colors: NoirButtonColors.newGame))
        }
        .padding(.horizontal, cardSize.spacing)
        .animation(.default, value: game.isSolveable)
        .opacity(isInteractionDisabled ? 0.5 : 1.0)
        .disabled(isInteractionDisabled)
        .animation(.easeOut(duration: 0.2), value: isInteractionDisabled)
    }
}

private struct GameBackgroundView: View {
    var body: some View {
        ZStack {
            Color(red: 0.12, green: 0.45, blue: 0.32).ignoresSafeArea()
            RadialGradient(gradient: Gradient(colors: [Color(red: 0.2, green: 0.6, blue: 0.45).opacity(0.9), .clear]), center: .center, startRadius: 50, endRadius: 400).ignoresSafeArea()
            Canvas { context, size in
                let patternColor = Color.black.opacity(0.1); let spacing: CGFloat = 4; let lineWidth: CGFloat = 1
                for i in stride(from: -size.height, through: size.width, by: spacing) {
                    var path = Path(); path.move(to: CGPoint(x: i, y: 0)); path.addLine(to: CGPoint(x: i + size.height, y: size.height)); context.stroke(path, with: .color(patternColor), lineWidth: lineWidth)
                }
            }.blendMode(.multiply).opacity(0.8).ignoresSafeArea()
            Rectangle().stroke(Color.black.opacity(0.8), lineWidth: 200).blur(radius: 80).blendMode(.multiply).ignoresSafeArea()
        }
    }
}

private struct TimerView: View {
    let elapsedTime: Int
    var body: some View {
        Text(formattedTime).font(.custom("Palatino-Bold", size: 22)).foregroundColor(.white.opacity(0.8)).padding(.horizontal, 10).padding(.vertical, 5).background(.black.opacity(0.3)).cornerRadius(8).fixedSize()
    }
    private var formattedTime: String { String(format: "%02d:%02d", elapsedTime / 60, elapsedTime % 60) }
}

struct FreeCellCardView: View {
    @ObservedObject var card: Card
    let cardSize: (width: CGFloat, height: CGFloat, spacing: CGFloat)
    var isDraggable: Bool = true
    var namespace: Namespace.ID

    var columnIndex: Int? = nil
    @Binding var draggedColumnIndex: Int?
    
    var freeCellIndex: Int? = nil
    @Binding var draggedFreeCellIndex: Int?

    let cornerRadius: CGFloat
    
    // Hangi kartın aktif olarak sürüklendiğini takip eder.
    @Binding var activeDragID: UUID?
    
    @EnvironmentObject var game: FreeCellGame
    @State private var xOffset: CGFloat = 0
    @State private var isInvalidDragBySize = false

    init(card: Card, cardSize: (width: CGFloat, height: CGFloat, spacing: CGFloat), isDraggable: Bool = true, namespace: Namespace.ID, columnIndex: Int? = nil, draggedColumnIndex: Binding<Int?>, freeCellIndex: Int? = nil, draggedFreeCellIndex: Binding<Int?>, activeDragID: Binding<UUID?>, cornerRadius: CGFloat = 4.0) {
        self.card = card
        self.cardSize = cardSize
        self.isDraggable = isDraggable
        self.namespace = namespace
        self.columnIndex = columnIndex
        self._draggedColumnIndex = draggedColumnIndex
        self.freeCellIndex = freeCellIndex
        self._draggedFreeCellIndex = draggedFreeCellIndex
        self._activeDragID = activeDragID
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        ZStack {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius).fill(Color.white).overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.black.opacity(0.7), lineWidth: 1))
                Text(card.rank).font(.custom("Palatino-Bold", size: cardSize.width * 0.45)).lineLimit(1).minimumScaleFactor(0.8).foregroundColor(card.color).position(x: cardSize.width * 0.24, y: cardSize.height * 0.14)
                Text(card.suit).font(.system(size: cardSize.width * 0.35, weight: .regular)).foregroundColor(card.color).position(x: cardSize.width * 0.76, y: cardSize.height * 0.14)
                if ["J", "Q", "K"].contains(card.rank) { Text(card.rank).font(.custom("Palatino-Bold", size: cardSize.width * 0.8)).foregroundColor(card.color.opacity(1)).position(x: cardSize.width / 2, y: cardSize.height * 0.65) }
                else { Text(card.suit).font(.system(size: cardSize.width * 0.8, weight: .heavy)).foregroundColor(card.color.opacity(1)).position(x: cardSize.width / 2, y: cardSize.height * 0.65) }
            }
            if card.isDragging {
                RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.yellow, lineWidth: 3)
            } else if game.hintCardID == card.id {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.cyan, lineWidth: 3)
                    .shadow(color: .cyan.opacity(0.8), radius: 4)
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .scaleEffect(card.isDragging ? 1.05 : 1.0)
        .shadow(color: .black.opacity(card.isDragging ? 0.4 : 0.2), radius: card.isDragging ? 8 : 2, x: card.isDragging ? 4 : 1, y: card.isDragging ? 4 : 1)
        .offset(x: xOffset)
        .offset(game.cardOffsets[card.id] ?? .zero)
        .animation(.none, value: game.cardOffsets[card.id])
        .matchedGeometryEffect(id: card.id, in: namespace)
        .gesture(isDraggable && !game.isGameOver ? cardActionGesture : nil)
        .animation(.easeOut(duration: 0.15), value: card.isDragging)
    }
    
    private var cardActionGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                // Yalnızca aktif bir sürükleme yoksa veya sürüklenen bu kartsa devam et
                if activeDragID == nil || activeDragID == card.id {
                    activeDragID = card.id // Bu kartı aktif sürüklenen olarak ayarla
                    
                    if game.isUndoAnimationActive { return }
                    
                    if game.animatingCards.keys.contains(card.id) { return }

                    if game.draggedStack.isEmpty {
                        isInvalidDragBySize = false

                        guard game.isCardDraggable(card: card) else { return }
                        guard let stack = game.findStackForCard(card: card) else { return }

                        SoundManager.instance.playSound(sound: .hold)
                        HapticManager.instance.impact()
                        if let colIndex = self.columnIndex { self.draggedColumnIndex = colIndex }
                        else if let cellIndex = self.freeCellIndex { self.draggedFreeCellIndex = cellIndex }

                        game.draggedStack = stack
                        for c in stack { c.isDragging = true }
                    }
                    
                    if isInvalidDragBySize { return }

                    let isDragging = value.translation.width * value.translation.width + value.translation.height * value.translation.height > 25

                    if isDragging {
                        if !game.draggedStack.isEmpty && game.draggedStack.count > game.maxDraggableStackSize() {
                            game.setErrorMessage("Taşınabilecek maksimum kart sayısını aştınız (\(game.maxDraggableStackSize()))")
                            SoundManager.instance.playSound(sound: .error)
                            HapticManager.instance.notification(type: .error)
                            
                            isInvalidDragBySize = true
                            
                            for c in game.draggedStack {
                                game.cardOffsets[c.id] = .zero
                            }
                            return
                        }
                    }

                    if !game.draggedStack.isEmpty {
                        for c in game.draggedStack {
                            game.cardOffsets[c.id] = value.translation
                        }
                    }
                }
            }
            .onEnded { value in
                // Yalnızca bu kart aktif olarak sürükleniyorsa bırakma işlemini yap
                if activeDragID == card.id {
                    if game.isUndoAnimationActive {
                        game.resetSelectionsAndDrag()
                        self.draggedColumnIndex = nil
                        self.draggedFreeCellIndex = nil
                        activeDragID = nil // Sürüklemeyi sıfırla
                        return
                    }

                    guard !game.draggedStack.isEmpty else {
                        if game.isCardDraggable(card: self.card) { handleTap() }
                        activeDragID = nil // Sürüklemeyi sıfırla
                        return
                    }
                    
                    let wasInvalidDrag = isInvalidDragBySize
                    isInvalidDragBySize = false

                    if !wasInvalidDrag {
                         let isTap = value.translation.width * value.translation.width + value.translation.height * value.translation.height < 25

                        if isTap {
                            handleTap()
                        } else {
                            if !game.animatingCards.isEmpty {
                                SoundManager.instance.playSound(sound: .tock)
                            } else {
                                game.handleDrop(for: game.draggedStack, dropLocation: value.location, sourceColumnIndex: self.columnIndex, sourceFreeCellIndex: self.freeCellIndex)
                            }
                        }
                    }
                    
                    game.resetSelectionsAndDrag()
                    self.draggedColumnIndex = nil
                    self.draggedFreeCellIndex = nil
                    
                    // Sürüklemeyi sıfırla
                    activeDragID = nil
                }
            }
    }
    
    private func handleTap() {
        game.resetSelectionsAndDrag()

        guard isDraggable && !game.isGameOver && xOffset == 0 else { return }
        guard game.isCardDraggable(card: self.card) else { return }
        
        guard let stackToAnimate = game.findStackForCard(card: self.card) else {
            shake(); return
        }

        let source: FreeCellAnimationSource?
        if let colIndex = self.columnIndex {
            source = .column(index: colIndex)
        } else if let freeCellIdx = self.freeCellIndex {
            source = .freeCell(index: freeCellIdx)
        } else {
            source = nil
        }
        
        guard let validSource = source else {
            shake()
            return
        }

        if game.findAutoMoveTarget(for: self.card, from: self.columnIndex) != nil {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                game.autoMoveOnClick(for: self.card, from: validSource)
            } completion: {
                for animatedCard in stackToAnimate {
                    game.endAnimation(for: animatedCard.id)
                }
            }
        } else {
            shake()
        }
    }
    
    private func shake() {
        SoundManager.instance.playSound(sound: .error); HapticManager.instance.notification(type: .error)
        let duration = 0.07, bounce: CGFloat = 6.0
        withAnimation(.linear(duration: duration)) { self.xOffset = -bounce }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { withAnimation(.linear(duration: duration)) { self.xOffset = bounce } }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 2) { withAnimation(.linear(duration: duration)) { self.xOffset = -bounce } }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 3) { withAnimation(.linear(duration: duration)) { self.xOffset = 0 } }
    }
}

struct EmptyCellView: View {
    var placeholder: String? = nil
    let cardSize: (width: CGFloat, height: CGFloat, spacing: CGFloat)
    let cornerRadius: CGFloat
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius).fill(Color.black.opacity(0.25))
            if let placeholder = placeholder { Text(placeholder).font(.system(size: cardSize.width * 0.7)).foregroundColor(.white.opacity(0.3)) }
        }.frame(width: cardSize.width, height: cardSize.height)
    }
}

