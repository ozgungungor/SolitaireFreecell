import AVFoundation
import SwiftUI

// GÜNCELLEME: AudioHapticState enum'u buraya taşındı ve UserDefaults ile uyumlu hale getirildi.
// Her iki oyun tarafından da kullanılacak ortak ses/titreşim durumunu yönetir.
enum AudioHapticState: Int, CaseIterable {
    case soundAndHaptics, soundOnly, hapticsOnly, muted

    var next: AudioHapticState {
        let all = Self.allCases
        if let idx = all.firstIndex(of: self) {
            let nextIdx = (idx + 1) % all.count
            return all[nextIdx]
        }
        return .soundAndHaptics
    }

    var iconName: String {
        switch self {
        case .soundAndHaptics: return "speaker.wave.3.fill"
        case .soundOnly: return "speaker.fill"
        case .hapticsOnly: return "iphone.radiowaves.left.and.right"
        case .muted: return "speaker.slash.fill"
        }
    }
    
    var isSoundMuted: Bool {
        return self == .hapticsOnly || self == .muted
    }
    
    var areHapticsMuted: Bool {
        return self == .soundOnly || self == .muted
    }
}


// SES PERFORMANSI İÇİN İYİLEŞTİRİLMİŞ SOUNDMANAGER
// Bu yapı, her ses efekti için önceden bir "AVAudioPlayer" havuzu oluşturur.
// Ses çalınacağı zaman, yeni bir nesne oluşturmak yerine bu havuzdan hazır bir player kullanılır.
// Bu, özellikle animasyonlar sırasında art arda ses çalındığında takılmaları ve ağırlaşmayı önler.
class SoundManager: NSObject, ObservableObject {
    static let instance = SoundManager()

    // Ses ayarlarını kaydetmek için UserDefaults anahtarı.
    private let audioStateKey = "globalAudioHapticState"

    // Tüm ses ve titreşim ayarlarının merkezi.
    // Değiştirildiğinde ayarı UserDefaults'e kaydeder ve ilgili isMuted durumlarını günceller.
    @Published var audioHapticState: AudioHapticState {
        didSet {
            UserDefaults.standard.set(audioHapticState.rawValue, forKey: audioStateKey)
            updateMutedStates()
        }
    }
    
    // Bu özellik artık doğrudan değiştirilmiyor, audioHapticState tarafından kontrol ediliyor.
    @Published private(set) var isSoundMuted: Bool
    
    // GÜNCELLEME: Player havuzu ve bir sonraki player'ı takip eden index.
    // Her ses efekti için önceden oluşturulmuş bir dizi player tutar.
    private var playerPool: [SoundOption: [AVAudioPlayer]] = [:]
    private var nextPlayerIndex: [SoundOption: Int] = [:]
    private let playerPoolSize = 5 // Her ses için 5 adet player oluştur, bu çoğu durum için yeterli olacaktır.

    enum SoundOption: String, CaseIterable {
        case place, error, undo, win, hold, foundation, tick, tock
    }

    override private init() {
        // Başlangıçta kaydedilmiş ayarı UserDefaults'tan yükle.
        let savedStateRaw = UserDefaults.standard.object(forKey: audioStateKey) as? Int ?? AudioHapticState.soundAndHaptics.rawValue
        let initialState = AudioHapticState(rawValue: savedStateRaw) ?? .soundAndHaptics
        self.audioHapticState = initialState
        self.isSoundMuted = initialState.isSoundMuted
        
        super.init()

        // Başlangıçta HapticManager'ın durumunu da ayarla.
        updateMutedStates()
        configureAudioSession()
        
        // GÜNCELLEME: Ses verilerini değil, doğrudan player'ları önceden yükle.
        preloadSoundPlayers()
    }

    // Ses durumunu değiştirmek için merkezi fonksiyon.
    func toggleAudioState() {
        self.audioHapticState = audioHapticState.next
    }

    // Hem SoundManager hem de HapticManager için isMuted durumlarını günceller.
    private func updateMutedStates() {
        self.isSoundMuted = audioHapticState.isSoundMuted
        HapticManager.instance.isMuted = audioHapticState.areHapticsMuted
    }
    
    /// Uygulamanın genel ses oturumunu ayarlar.
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch let error {
            print("AVAudioSession ayarlanırken hata oluştu. \(error.localizedDescription)")
        }
    }

    // GÜNCELLEME: Bu fonksiyon artık her ses için bir player havuzu oluşturur.
    private func preloadSoundPlayers() {
        for sound in SoundOption.allCases {
            guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav") else {
                print("Hata: Ön yükleme için '\(sound.rawValue).wav' ses dosyası bulunamadı.")
                continue
            }
            
            do {
                // Her ses için bir player dizisi oluştur.
                var players: [AVAudioPlayer] = []
                for _ in 0..<playerPoolSize {
                    let player = try AVAudioPlayer(contentsOf: url)
                    // Player'ı çalmaya hazırla, bu ilk çalma gecikmesini azaltır.
                    player.prepareToPlay()
                    players.append(player)
                }
                playerPool[sound] = players
                nextPlayerIndex[sound] = 0
            } catch let error {
                print("'\(sound.rawValue)' için player havuzu oluşturulurken hata oluştu. \(error.localizedDescription)")
            }
        }
    }

    // GÜNCELLEME: Bu fonksiyon artık yeni bir player oluşturmak yerine havuzdan hazır bir player kullanır.
    func playSound(sound: SoundOption) {
        guard !isSoundMuted else { return }

        // İlgili ses için player havuzunu ve bir sonraki index'i al.
        guard let pool = playerPool[sound],
              !pool.isEmpty,
              let index = nextPlayerIndex[sound] else {
            print("Hata: '\(sound.rawValue)' için player havuzu bulunamadı.")
            return
        }
        
        let player = pool[index]
        
        // Bir sonraki ses çalma isteği için index'i güncelle (dairesel olarak).
        nextPlayerIndex[sound] = (index + 1) % pool.count
        
        // Arayüz takılmalarını önlemek için çalma işlemini yine de arka planda yap,
        // ancak bu sefer player oluşturma maliyeti olmadığı için çok daha hızlı olacak.
        DispatchQueue.global(qos: .userInitiated).async {
            // Player'ı başa sar ve çal.
            if player.isPlaying {
                player.stop()
            }
            player.currentTime = 0
            player.play()
        }
    }
}

