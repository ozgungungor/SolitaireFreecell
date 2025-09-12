import SwiftUI

@main
struct FreeCellGameApp: App {
    
    // YENİ: Bu satır, AdMob'u başlatmak için AppDelegate'i
    // SwiftUI yaşam döngüsüne bağlar.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            // Uygulama artık doğrudan oyun yerine seçim ekranıyla başlıyor.
            GameSelectionView()
        }
    }
}
