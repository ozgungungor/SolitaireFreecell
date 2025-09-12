import UIKit
import GoogleMobileAds

// Google Mobile Ads SDK'sını başlatmak için AppDelegate kullanılır.
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        // Google Mobile Ads SDK'sını başlat.
        // Bu işlem, uygulama başlar başlamaz yalnızca bir kez yapılmalıdır.
        MobileAds.shared.start()
        return true
    }
}
