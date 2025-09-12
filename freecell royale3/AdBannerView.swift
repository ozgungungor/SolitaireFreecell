import SwiftUI
import GoogleMobileAds
import UIKit

// AdMob banner'ını SwiftUI içinde göstermek için bir UIViewControllerRepresentable.
private struct GADBannerViewController: UIViewControllerRepresentable {
    
    // Coordinator, zamanlayıcıyı, bildirimleri ve reklam isteklerini yönetir.
    class Coordinator: NSObject {
        var parent: GADBannerViewController
        var timer: Timer?
        // Reklam görünümüne zayıf bir referans tutarak bellek sızıntılarını önler.
        weak var bannerView: BannerView?

        init(_ parent: GADBannerViewController) {
            self.parent = parent
            super.init()
            // Uygulama aktif olduğunda reklamı yenilemek için bir gözlemci ekle.
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(requestNewAd),
                name: UIApplication.didBecomeActiveNotification,
                object: nil
            )
        }
        
        deinit {
            // Coordinator bellekten kaldırıldığında gözlemciyi ve zamanlayıcıyı temizle.
            NotificationCenter.default.removeObserver(self)
            timer?.invalidate()
        }

        // Yeni bir reklam istemek için merkezi fonksiyon.
        @objc func requestNewAd() {
            print("Yeni banner reklamı isteniyor...")
            bannerView?.load(Request())
        }

        // Zamanlayıcıyı başlatır ve reklam yönetimini üstlenir.
        func startManaging(banner: BannerView) {
            self.bannerView = banner
            
            // Mevcut bir zamanlayıcı varsa durdur.
            timer?.invalidate()
            
            // Her 60 saniyede bir `requestNewAd` fonksiyonunu çağıracak şekilde yeni bir zamanlayıcı oluştur.
            timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
                self?.requestNewAd()
            }
        }
        
        // Zamanlayıcıyı ve yönetimi durdurur.
        func stopManaging() {
            timer?.invalidate()
            timer = nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        let bannerView = BannerView(adSize: AdSizeBanner)

        // Reklam Birimi ID'sini ayarla.
        // Geliştirme (DEBUG) modunda test reklamları, yayın (RELEASE) modunda gerçek reklamlar gösterilir.
        #if DEBUG
        // Bu, Google tarafından sağlanan bir test ID'sidir. Geliştirme aşamasında bunu kullanın.
        bannerView.adUnitID = "ca-app-pub-3940256099942544/2934735716"
        #else
        // Bu, uygulamanız yayınlandığında kullanılacak olan gerçek AdMob Reklam Birimi ID'nizdir.
        bannerView.adUnitID = "ca-app-pub-4244659004257886/3557111092"
        #endif
        
        bannerView.rootViewController = viewController
        
        viewController.view.addSubview(bannerView)
        viewController.view.frame = CGRect(origin: .zero, size: AdSizeBanner.size)
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bannerView.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor),
            bannerView.centerYAnchor.constraint(equalTo: viewController.view.centerYAnchor)
        ])
        
        // İlk reklamı yükle.
        bannerView.load(Request())
        // Coordinator'ın reklamı yönetmesini başlat.
        context.coordinator.startManaging(banner: bannerView)
        
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Bu örnekte güncelleme için özel bir koda ihtiyaç yoktur.
    }
    
    // View SwiftUI hiyerarşisinden kaldırıldığında yönetimi durdur.
    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        coordinator.stopManaging()
    }
}

// Oyun ekranlarında kullanılacak son reklam banner'ı bileşeni.
struct AdBannerView: View {
    var body: some View {
        GADBannerViewController()
            .frame(width: 320, height: 50, alignment: .center) // Standart banner boyutu
            .background(Color.clear) // Arka planı temizle
    }
}
