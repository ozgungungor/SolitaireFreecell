import SwiftUI
import AppTrackingTransparency // İçe aktarılması gereken framework

struct GameSelectionView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                GameBackgroundView()

                VStack(spacing: 25) {
                    Text(L10n.string(for: .selectGame))
                        .font(.custom("Palatino-Bold", size: 40))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 5, x: 0, y: 2)
                        .padding(.bottom, 30)

                    NavigationLink(destination: SolitaireGameView().environmentObject(SolitaireGame())) {
                        GameButtonView(title: L10n.string(for: .solitaire), icon: "suit.spade.fill", color: Color(red: 0.12, green: 0.45, blue: 0.32))
                    }

                    NavigationLink(destination: FreeCellGameView().environmentObject(FreeCellGame())) {
                        GameButtonView(title: L10n.string(for: .freecell), icon: "dial.low.fill", color: Color(red: 0.3, green: 0.3, blue: 0.8))
                    }
                }
                .padding()
            }
            .navigationBarHidden(true)
            // YENİ EKLENEN KISIM: Görünüm yüklendiğinde izleme izni ister.
            .onAppear {
                requestTrackingAuthorization()
            }
        }
    }

    // YENİ EKLENEN FONKSİYON
    private func requestTrackingAuthorization() {
        // iOS 14 ve üzeri için ATTrackingManager'ı kullan
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { status in
                switch status {
                case .authorized:
                    // Takip izni verildi.
                    // (Örn: Reklamları başlat, analitik verilerini topla)
                    print("Kullanıcı takip için izin verdi.")
                case .denied:
                    // Takip izni reddedildi.
                    print("Kullanıcı takip için izin vermedi.")
                case .notDetermined:
                    // Kullanıcı henüz karar vermedi.
                    print("Kullanıcı henüz kararını belirtmedi.")
                case .restricted:
                    // Cihaz ayarları (örn: ebeveyn denetimleri) nedeniyle takip kısıtlandı.
                    print("Takip kısıtlandı.")
                @unknown default:
                    // Gelecekteki olası durumlar için
                    print("Bilinmeyen bir durum oluştu.")
                }
            }
        }
    }
}

// Oyun seçimi ekranı için özel buton stili
struct GameButtonView: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.title)
            Text(title)
                .font(.custom("Palatino-Bold", size: 24))
        }
        .foregroundColor(.white)
        .frame(maxWidth: 280)
        .padding()
        .background(
            ZStack {
                color
                LinearGradient(gradient: Gradient(colors: [.white.opacity(0.2), .clear]), startPoint: .top, endPoint: .bottom)
            }
        )
        .cornerRadius(15)
        .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
    }
}

// Solitaire'den uyarlanan arkaplan görünümü
private struct GameBackgroundView: View {
    var body: some View {
        ZStack {
            Color(red: 0.1, green: 0.1, blue: 0.2).ignoresSafeArea()
            RadialGradient(gradient: Gradient(colors: [Color(red: 0.3, green: 0.2, blue: 0.5).opacity(0.7), .clear]), center: .center, startRadius: 50, endRadius: 400).ignoresSafeArea()
            Canvas { context, size in
                let patternColor = Color.black.opacity(0.1); let spacing: CGFloat = 4; let lineWidth: CGFloat = 1
                for i in stride(from: -size.height, through: size.width, by: spacing) {
                    var path = Path(); path.move(to: CGPoint(x: i, y: 0)); path.addLine(to: CGPoint(x: i + size.height, y: size.height)); context.stroke(path, with: .color(patternColor), lineWidth: lineWidth)
                }
            }.blendMode(.multiply).opacity(0.8).ignoresSafeArea()
        }
    }
}

struct GameSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        GameSelectionView()
    }
}
