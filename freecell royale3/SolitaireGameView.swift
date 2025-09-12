import SwiftUI

struct SolitaireGameView: View {
    @EnvironmentObject var game: SolitaireGame
    @State private var showNewGamePopup = false
    @Namespace private var cardAnimationNamespace

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    
    @StateObject private var soundManager = SoundManager.instance
    @StateObject private var hapticManager = HapticManager.instance
    
    @State private var draggedColumnIndex: Int? = nil
    @State private var draggedTopPileIdentifier: AnyHashable? = nil
    
    // Aynı anda tek bir sürüklemeye izin vermek için.
    @State private var activeDragID: UUID? = nil
    
    // GÜNCELLEME: Sayaç durumu ve kontrolü SolitaireGame modeline taşındı.
    // @State private var elapsedTime: Int = 0
    // @State private var gameTimer: Timer?
    
    private let cardCornerRadius: CGFloat = 4
    
    private enum NoirButtonColors {
        static let undo = [Color(red: 0.3, green: 0.3, blue: 0.8), Color(red: 0.15, green: 0.15, blue: 0.4)]
        static let solve = [Color(red: 0.5, green: 0.2, blue: 0.6), Color(red: 0.3, green: 0.1, blue: 0.4)]
        static let hint = [Color(red: 0.7, green: 0.2, blue: 0.2), Color(red: 0.4, green: 0.1, blue: 0.1)]
        static let draw = [Color(red: 0.8, green: 0.2, blue: 0.5), Color(red: 0.5, green: 0.1, blue: 0.3)]
        static let audio = [Color(red: 0.1, green: 0.5, blue: 0.5), Color(red: 0.05, green: 0.3, blue: 0.3)]
        static let home = [Color(red: 0.8, green: 0.3, blue: 0.1), Color(red: 0.5, green: 0.15, blue: 0.05)]
        static let newGame = [Color(red: 0.2, green: 0.6, blue: 0.3), Color(red: 0.1, green: 0.4, blue: 0.15)]
    }

    private func zIndexForCard(_ card: Card, cardIndex: Int) -> Double {
        if let dragIndex = game.draggedStack.firstIndex(where: { $0.id == card.id }) {
            return 10_000 + Double(dragIndex)
        }
        if game.animatingCardIDs.contains(card.id) {
            return 9_000 + Double(cardIndex)
        }
        return Double(cardIndex)
    }

    var body: some View {
        ZStack {
            GameBackgroundView()
            
            GeometryReader { geometry in
                let cardSize = calculateCardSize(for: geometry.size)
                
                let (topRowZ, tableauZ) = { () -> (Double, Double) in
                    if let draggedCard = game.draggedStack.first {
                        let isFromTableau = game.tableau.flatMap({ $0 }).contains(where: { $0.card.id == draggedCard.id })
                        return isFromTableau ? (3.0, 4.0) : (4.0, 3.0)
                    }
                    
                    if !game.animatingCardIDs.isEmpty {
                        if game.animationSourceGroup == .tableau { return (5.0, 6.0) }
                        else { return (6.0, 5.0) }
                    }
                    return (1.0, 2.0)
                }()

                VStack(spacing: 15) {
                    HStack {
                        Text(L10n.string(for: .solitaire))
                            .font(.custom("Palatino-Bold", size: 28))
                            .foregroundColor(.white.opacity(0.9))
                        Spacer()
                        // GÜNCELLEME: `game.elapsedTime` kullanılıyor.
                        TimerView(elapsedTime: game.elapsedTime)
                    }
                    .padding(.horizontal)

                    HStack(spacing: cardSize.spacing) {
                        let isDraggingFromFoundation = (draggedTopPileIdentifier as? Int) != nil
                        let isDraggingFromWaste = (draggedTopPileIdentifier as? String) == "waste"

                        foundationsView(cardSize: cardSize, namespace: cardAnimationNamespace, draggedTopPileIdentifier: $draggedTopPileIdentifier)
                            .zIndex(isDraggingFromFoundation ? 1.0 : 0.0)
                        
                        Spacer()
                        
                        stockAndWasteView(cardSize: cardSize, namespace: cardAnimationNamespace, draggedTopPileIdentifier: $draggedTopPileIdentifier)
                            .zIndex(isDraggingFromWaste ? 1.0 : 0.0)
                    }
                    .padding(.horizontal, cardSize.spacing)
                    .zIndex(topRowZ)

                    tableauView(cardSize: cardSize, namespace: cardAnimationNamespace, draggedColumnIndex: $draggedColumnIndex)
                        .zIndex(tableauZ)
                    
                    Spacer(minLength: 0)
                    
                    bottomControlsView(cardSize: cardSize)
                    
                    // DEĞİŞİKLİK: Yer tutucu metin AdBannerView ile değiştirildi.
                    AdBannerView()
                        .padding(.bottom, 8)
                }
                .padding(.vertical)
            }
            
            if let message = game.errorMessage {
                VStack {
                    Spacer()
                    Text(message)
                        .padding()
                        .background(Color.red.opacity(0.9))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(20_000)
                        .onAppear { HapticManager.instance.notification(type: .error) }
                    Spacer().frame(height: 150)
                }
                .allowsHitTesting(false)
            }
            
            if game.isGameOver { FireworksView() }
            
            if showNewGamePopup {
                CustomAlertView(
                    title: L10n.string(for: .newGamePromptTitle),
                    message: L10n.string(for: .newGamePromptMessage),
                    confirmButtonTitle: L10n.string(for: .confirm),
                    cancelButtonTitle: L10n.string(for: .cancel),
                    onConfirm: {
                        // GÜNCELLEME: `resetTimer` artık `newGame` içinde çağrılıyor.
                        game.newGame()
                        showNewGamePopup = false
                    },
                    onCancel: { showNewGamePopup = false }
                )
                .zIndex(30_000)
            }
        }
        .navigationBarHidden(true)
        // GÜNCELLEME: View yaşam döngüsü olayları artık `game` nesnesindeki sayaç fonksiyonlarını çağırıyor.
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                if !game.isGameOver && game.moveHistory.count > 0 {
                    game.startTimer()
                }
            } else if newPhase == .inactive || newPhase == .background {
                game.stopTimer()
            }
        }
        .onAppear {
            if !game.isGameOver && game.moveHistory.count > 0 {
                game.startTimer()
            }
        }
        .onDisappear {
            game.stopTimer()
        }
        .onChange(of: game.isGameOver) { isOver in
            if isOver {
                game.stopTimer()
            }
        }
    }
    
    // GÜNCELLEME: Bu fonksiyonlar `SolitaireGame` modeline taşındı.
    // private func startTimer() { ... }
    // private func stopTimer() { ... }
    // private func resetTimer() { ... }
    
    private func calculateCardSize(for size: CGSize) -> (width: CGFloat, height: CGFloat, spacing: CGFloat) {
        let totalHorizontalPadding = size.width * 0.04
        let totalUsableWidth = size.width - totalHorizontalPadding
        let cardWidth = totalUsableWidth / 7.4
        let spacing = cardWidth * 0.1
        let cardHeight = cardWidth * 1.5
        return (floor(cardWidth), floor(cardHeight), floor(spacing))
    }

    private func stockAndWasteView(cardSize: (width: CGFloat, height: CGFloat, spacing: CGFloat),
                                   namespace: Namespace.ID,
                                   draggedTopPileIdentifier: Binding<AnyHashable?>) -> some View {
        HStack(spacing: cardSize.spacing) {
            ZStack(alignment: .trailing) {
                let wasteCount = game.waste.count
                let emptyViewOffset: CGFloat = wasteCount == 0 ? 0 : (wasteCount == 1 ? 0 : (wasteCount == 2 ? -(cardSize.width * 0.3) : -2 * (cardSize.width * 0.3)))
                
                EmptyCardView(cardSize: cardSize, cornerRadius: cardCornerRadius).offset(x: emptyViewOffset).zIndex(-1)

                ForEach(game.waste, id: \.id) { card in
                    let cardIndexInWaste = game.waste.firstIndex(of: card)!
                    let distanceFromEnd = game.waste.count - 1 - cardIndexInWaste
                    let isVisible = distanceFromEnd <= 2
                    
                    SolitaireCardView(card: card, cardSize: cardSize, isDraggable: card.id == game.waste.last?.id && !game.isGameOver, namespace: namespace, isFromWaste: true, draggedTopPileIdentifier: draggedTopPileIdentifier, activeDragID: $activeDragID, cornerRadius: cardCornerRadius)
                        .offset(x: isVisible ? CGFloat(distanceFromEnd) * -(cardSize.width * 0.3) : 0)
                        .opacity(isVisible ? 1 : 0)
                        .zIndex(Double(cardIndexInWaste))
                }
            }.frame(width: cardSize.width + 2 * (cardSize.width * 0.3), alignment: .trailing)
             .zIndex((draggedTopPileIdentifier.wrappedValue as? String) == "waste" ? 1.0 : 0.0)
            
            ZStack {
                if game.stock.isEmpty {
                    Image(systemName: "arrow.2.circlepath").font(.largeTitle).foregroundColor(.white.opacity(0.5))
                        .frame(width: cardSize.width, height: cardSize.height)
                        .background(RoundedRectangle(cornerRadius: cardCornerRadius).stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [5])))
                } else {
                    ForEach(game.stock, id: \.id) { card in
                        SolitaireCardView(card: card, isFaceUp: false, cardSize: cardSize, isDraggable: false, namespace: namespace, activeDragID: .constant(nil), cornerRadius: cardCornerRadius).allowsHitTesting(false)
                    }
                }
            }.contentShape(Rectangle())
             .onTapGesture { withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { game.drawCard() } }
        }
    }
    
    private func foundationsView(cardSize: (width: CGFloat, height: CGFloat, spacing: CGFloat), namespace: Namespace.ID, draggedTopPileIdentifier: Binding<AnyHashable?>) -> some View {
        HStack(spacing: cardSize.spacing) {
            ForEach(0..<4) { index in
                let suitForPlaceholder = game.foundations[index].first?.suit
                let isFoundationTargetOfAnimation = !game.animatingCardIDs.isEmpty && game.foundations[index].contains { card in game.animatingCardIDs.contains(card.id) }
                
                ZStack {
                    EmptyCardView(placeholder: suitForPlaceholder, cardSize: cardSize, cornerRadius: cardCornerRadius)
                    ForEach(game.foundations[index], id: \.id) { card in
                        SolitaireCardView(card: card, cardSize: cardSize, isDraggable: card.id == game.foundations[index].last?.id && !game.isGameOver, namespace: namespace, foundationIndex: index, draggedTopPileIdentifier: draggedTopPileIdentifier, activeDragID: $activeDragID, cornerRadius: cardCornerRadius)
                        .zIndex(zIndexForCard(card, cardIndex: game.foundations[index].firstIndex(where: { $0.id == card.id }) ?? 0))
                    }
                }
                .zIndex(isFoundationTargetOfAnimation || (draggedTopPileIdentifier.wrappedValue as? Int) == index ? 100.0 : Double(index))
                .background(GeometryReader { geo in Color.clear.onAppear { game.foundationFrames[index] = geo.frame(in: .global) }.onChange(of: geo.frame(in: .global)) { newFrame in game.foundationFrames[index] = newFrame } })
            }
        }
    }

    private func tableauView(cardSize: (width: CGFloat, height: CGFloat, spacing: CGFloat), namespace: Namespace.ID, draggedColumnIndex: Binding<Int?>) -> some View {
        HStack(alignment: .top, spacing: cardSize.spacing) {
            ForEach(0..<7) { index in
                let columnCards = game.tableau[index]
                let isColumnTargetOfAnimation = !game.animatingCardIDs.isEmpty && columnCards.contains { tuple in game.animatingCardIDs.contains(tuple.card.id) }
                let isColumnSourceOfAnimation = !game.animatingCardIDs.isEmpty && game.animationSourceGroup == .tableau && game.animationSourceTableauIndex == index
                
                ZStack(alignment: .top) {
                    EmptyCardView(cardSize: cardSize, cornerRadius: cardCornerRadius).frame(maxHeight: .infinity, alignment: .top)
                    ForEach(Array(columnCards.enumerated()), id: \.element.card.id) { cardIndex, tuple in
                        let faceDownOffset: CGFloat = cardSize.height * 0.12
                        let faceUpOffset: CGFloat = cardSize.height * 0.3
                        let faceDownCount = columnCards.prefix(cardIndex).filter { !$0.isFaceUp }.count
                        let faceUpCount = cardIndex - faceDownCount
                        let yOffset = CGFloat(faceDownCount) * faceDownOffset + CGFloat(faceUpCount) * faceUpOffset
                        
                        SolitaireCardView(card: tuple.card, isFaceUp: tuple.isFaceUp, cardSize: cardSize, namespace: namespace, columnIndex: index, draggedColumnIndex: draggedColumnIndex, activeDragID: $activeDragID, cornerRadius: cardCornerRadius)
                            .offset(y: yOffset)
                            .zIndex(zIndexForCard(tuple.card, cardIndex: cardIndex))
                            .animation(.spring(response: 0.45, dampingFraction: 0.65), value: tuple.isFaceUp)
                    }
                }
                .zIndex(isColumnTargetOfAnimation || isColumnSourceOfAnimation || draggedColumnIndex.wrappedValue == index ? 100.0 : Double(index))
                .background(GeometryReader { geo in Color.clear.onAppear { game.tableauFrames[index] = geo.frame(in: .global) }.onChange(of: geo.frame(in: .global)) { newFrame in game.tableauFrames[index] = newFrame } })
            }
        }
        .padding(.horizontal, cardSize.spacing)
    }
    
    private func bottomControlsView(cardSize: (width: CGFloat, height: CGFloat, spacing: CGFloat)) -> some View {
        let isInteractionDisabled = !game.draggedStack.isEmpty
        let buttonSize = cardSize.width * 1.1
        
        return HStack(spacing: cardSize.spacing) {
            Button(action: {
                let token = UUID()
                game.animationToken = token
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { game.undo() } completion: {
                    if game.animationToken == token {
                        game.clearAnimationState()
                        game.isUndoAnimationActive = false
                    }
                }
            }) {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(NoirButtonStyle(size: buttonSize, colors: NoirButtonColors.undo, isEnabled: !game.moveHistory.isEmpty && !game.isGameOver))
            .disabled(game.moveHistory.isEmpty || game.isGameOver)
            
            if game.isSolveable && !game.isGameOver {
                Button(action: { game.solveGame() }) {
                    Image(systemName: "wand.and.stars")
                        .foregroundColor(.purple.opacity(0.8))
                }
                .buttonStyle(NoirButtonStyle(size: buttonSize, colors: NoirButtonColors.solve))
                .transition(.scale.combined(with: .opacity))
            } else {
                Button(action: { game.findHint() }) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                }
                .buttonStyle(NoirButtonStyle(size: buttonSize, colors: NoirButtonColors.hint, isEnabled: !game.isGameOver))
                .disabled(game.isGameOver)
                .transition(.scale.combined(with: .opacity))
            }

            Spacer(minLength: 0)
            
            Button(action: { game.toggleDrawCount(); soundManager.playSound(sound: .tick); hapticManager.impact(style: .light) }) {
                Text(game.drawCount == 1 ? "1" : "3")
            }
            .buttonStyle(NoirButtonStyle(size: buttonSize, colors: NoirButtonColors.draw))
            
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
}

struct NoirButtonStyle: ButtonStyle {
    let size: CGFloat
    var colors: [Color]
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed && isEnabled

        ZStack {
            Circle()
                .fill(Color.black)
                .frame(width: size, height: size)
                .blur(radius: isPressed ? 1 : 3)
                .opacity(isEnabled ? 0.5 : 0.2)
                .offset(x: isPressed ? 3 : 6, y: isPressed ? 3 : 6)
            
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: colors),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [Color(white: 0.6), Color(white: 0.1)]),
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2
                        )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isPressed ? 0 : 0.1), lineWidth: 2)
                        .blur(radius: 3)
                        .offset(x: -1, y: -1)
                        .mask(Circle())
                )
                .brightness(isPressed ? -0.2 : 0)
                .frame(width: size, height: size)

            configuration.label
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundColor(.white.opacity(isEnabled ? 0.9 : 0.4))
                .shadow(color: .black.opacity(0.8), radius: 2, x: 1, y: 1)
        }
        .offset(x: isPressed ? 3 : 0, y: isPressed ? 3 : 0)
        .opacity(isEnabled ? 1.0 : 0.6)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
    }
}


struct CustomAlertView: View {
    let title: String
    let message: String
    let confirmButtonTitle: String
    let cancelButtonTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
                .background(.ultraThinMaterial)

            VStack(spacing: 15) {
                Text(title)
                    .font(.custom("Palatino-Bold", size: 24))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(message)
                    .font(.custom("Palatino-Roman", size: 16))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                HStack(spacing: 20) {
                    Button(action: {
                        SoundManager.instance.playSound(sound: .tick)
                        HapticManager.instance.impact(style: .light)
                        onCancel()
                    }) {
                        Text(cancelButtonTitle)
                            .font(.custom("Palatino-Bold", size: 18))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    
                    Button(action: {
                        SoundManager.instance.playSound(sound: .tick)
                        HapticManager.instance.impact(style: .light)
                        onConfirm()
                    }) {
                        Text(confirmButtonTitle)
                            .font(.custom("Palatino-Bold", size: 18))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.9))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding(.top)
            }
            .padding(25)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.12, green: 0.45, blue: 0.32))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.3)))
            )
            .shadow(color: .black.opacity(0.5), radius: 10)
            .padding(.horizontal, 40)
        }
    }
}

struct SolitaireCardView: View {
    @ObservedObject var card: Card
    var isFaceUp: Bool = true
    let cardSize: (width: CGFloat, height: CGFloat, spacing: CGFloat)
    var isDraggable: Bool = true
    var namespace: Namespace.ID

    var columnIndex: Int? = nil
    @Binding var draggedColumnIndex: Int?

    var foundationIndex: Int? = nil
    var isFromWaste: Bool = false
    @Binding var draggedTopPileIdentifier: AnyHashable?
    
    // Hangi kartın aktif olarak sürüklendiğini takip eder.
    @Binding var activeDragID: UUID?
    
    let cornerRadius: CGFloat

    @EnvironmentObject var game: SolitaireGame

    @State private var isInvalidDragAttempted = false
    @State private var xOffset: CGFloat = 0
    @State private var isTap = true
    @State private var isHintAnimating = false

    init(card: Card, isFaceUp: Bool = true, cardSize: (width: CGFloat, height: CGFloat, spacing: CGFloat), isDraggable: Bool = true, namespace: Namespace.ID, columnIndex: Int? = nil, draggedColumnIndex: Binding<Int?> = .constant(nil), foundationIndex: Int? = nil, isFromWaste: Bool = false, draggedTopPileIdentifier: Binding<AnyHashable?> = .constant(nil), activeDragID: Binding<UUID?>, cornerRadius: CGFloat = 8.0) {
        self.card = card; self.isFaceUp = isFaceUp; self.cardSize = cardSize; self.isDraggable = isDraggable; self.namespace = namespace; self.columnIndex = columnIndex; self._draggedColumnIndex = draggedColumnIndex; self.foundationIndex = foundationIndex; self.isFromWaste = isFromWaste; self._draggedTopPileIdentifier = draggedTopPileIdentifier; self._activeDragID = activeDragID; self.cornerRadius = cornerRadius
    }

    private var isInteractionLocked: Bool {
        if !game.isUndoAnimationActive { return false }
        return game.animatingCardIDs.contains(card.id) || game.lockedTargetCardIDs.contains(card.id)
    }

    var body: some View {
        ZStack {
            if isFaceUp {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius).fill(Color.white).overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.black.opacity(0.7), lineWidth: 1))
                    Text(card.rank).font(.custom("Palatino-Bold", size: cardSize.width * 0.4)).lineLimit(1).minimumScaleFactor(0.8).foregroundColor(card.color).position(x: cardSize.width * 0.24, y: cardSize.height * 0.14)
                    Text(card.suit).font(.system(size: cardSize.width * 0.3, weight: .regular)).foregroundColor(card.color).position(x: cardSize.width * 0.76, y: cardSize.height * 0.14)
                    if ["J", "Q", "K"].contains(card.rank) { Text(card.rank).font(.custom("Palatino-Bold", size: cardSize.width * 0.75)).foregroundColor(card.color.opacity(1)).position(x: cardSize.width / 2, y: cardSize.height * 0.65) }
                    else { Text(card.suit).font(.system(size: cardSize.width * 0.75, weight: .heavy)).foregroundColor(card.color.opacity(1)).position(x: cardSize.width / 2, y: cardSize.height * 0.65) }
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius).fill(LinearGradient(gradient: Gradient(colors: [Color(red: 0.2, green: 0.2, blue: 0.4), Color.indigo]), startPoint: .top, endPoint: .bottom)).overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.white.opacity(0.7), lineWidth: 1))
                    RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.2)).padding(10).overlay(Image(systemName: "wand.and.stars").font(.system(size: cardSize.width * 0.5)).foregroundColor(.white.opacity(0.3)))
                }
            }
            if card.isDragging { RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.yellow, lineWidth: 3) }
            
            if game.hintedCardIDs.contains(card.id) {
                RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.cyan, lineWidth: 4).shadow(color: .cyan.opacity(0.8), radius: isHintAnimating ? 8 : 4, x: 0, y: 0)
                    .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { isHintAnimating = true } }.onDisappear { isHintAnimating = false }
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .scaleEffect(card.isDragging ? 1.05 : 1.0)
        .shadow(color: .black.opacity(card.isDragging ? 0.4 : 0.2), radius: card.isDragging ? 8 : 2, x: card.isDragging ? 4 : 1, y: card.isDragging ? 4 : 1)
        .offset(x: xOffset)
        .offset(game.cardOffsets[card.id] ?? .zero)
        .animation(.none, value: game.cardOffsets[card.id])
        .rotation3DEffect(.degrees(isFaceUp ? 0 : 180), axis: (x: 0.0, y: 1.0, z: 0.0))
        .matchedGeometryEffect(id: card.id, in: namespace)
        .gesture(isDraggable && isFaceUp && !game.isGameOver && !isInteractionLocked ? cardActionGesture : nil)
        .animation(.easeOut(duration: 0.15), value: card.isDragging)
    }
    
    private var cardActionGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                // Yalnızca aktif bir sürükleme yoksa veya sürüklenen bu kartsa devam et
                if activeDragID == nil || activeDragID == card.id {
                    activeDragID = card.id // Bu kartı aktif sürüklenen olarak ayarla
                    if game.draggedStack.isEmpty { self.isTap = true; self.startDrag() }
                    for c in game.draggedStack { game.cardOffsets[c.id] = value.translation }
                    if self.isTap { if (value.translation.width * value.translation.width + value.translation.height * value.translation.height) > 25 { self.isTap = false } }
                }
            }
            .onEnded { value in
                // Yalnızca bu kart aktif olarak sürükleniyorsa bırakma işlemini yap
                if activeDragID == card.id {
                    if self.isTap { self.handleTap() }
                    else {
                        if !game.draggedStack.isEmpty {
                            let foundationsCardCountBeforeDrop = game.foundations.flatMap { $0 }.count
                            game.handleDrop(for: game.draggedStack, dropLocation: value.location, sourceTableauIndex: self.columnIndex)
                            let foundationsCardCountAfterDrop = game.foundations.flatMap { $0 }.count
                            if foundationsCardCountAfterDrop > foundationsCardCountBeforeDrop { SoundManager.instance.playSound(sound: .foundation) }
                        }
                        game.resetSelectionsAndDrag()
                    }
                    self.isTap = true; self.isInvalidDragAttempted = false; self.draggedColumnIndex = nil; self.draggedTopPileIdentifier = nil
                    
                    // Sürüklemeyi sıfırla
                    activeDragID = nil
                }
            }
    }
    
    private func startDrag() {
        guard !isInteractionLocked else { return }
        game.hintedCardIDs.removeAll(); guard game.draggedStack.isEmpty else { return }
        game.animatingCardIDs.removeAll()
        if isInvalidDragAttempted { isInvalidDragAttempted = false; return }
        guard let stack = game.findStackForCard(card: card) else { isInvalidDragAttempted = true; return }
        guard game.isStackValidToDrag(stack: stack) else { HapticManager.instance.notification(type: .error); isInvalidDragAttempted = true; return }
        SoundManager.instance.playSound(sound: .hold)
        if let colIndex = self.columnIndex { self.draggedColumnIndex = colIndex }
        else if let foundIndex = self.foundationIndex { self.draggedTopPileIdentifier = foundIndex }
        else if self.isFromWaste { self.draggedTopPileIdentifier = "waste" }
        game.draggedStack = stack; for c in stack { c.isDragging = true }; HapticManager.instance.impact()
    }
    
    private func handleTap() {
        game.resetSelectionsAndDrag()
        guard isDraggable, isFaceUp, !game.isGameOver, !isInteractionLocked, xOffset == 0 else { return }
        if game.canAutoMove(for: card) {
            // GÜNCELLEME: Art arda gelen dokunma animasyonlarının takılmasını düzeltmek için
            // token tabanlı mantık kaldırıldı ve daha sağlam bir tamamlama (completion) bloğu eklendi.
            
            // Animasyon tamamlandığında durumunu temizlemek için taşınacak kartları al.
            guard let stack = game.findStackForCard(card: card) else { return }
            let animatedCardIDs = Set(stack.map { $0.id })

            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                game.autoMoveOnClick(for: card)
            } completion: {
                // Bu spesifik animasyon bittiğinde, ilgili kartları animasyon setinden çıkar.
                game.animatingCardIDs.subtract(animatedCardIDs)
                
                // Başka hiçbir kart animasyonda değilse, kaynak durumunu tamamen temizle.
                if game.animatingCardIDs.isEmpty {
                    game.clearAnimationSourceState()
                }
            }
        } else { shake() }
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

struct EmptyCardView: View {
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

