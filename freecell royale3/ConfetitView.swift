import SwiftUI

// --- Farklı parçacık davranışlarını tanımlamak için bir enum ---
enum ParticleType {
    case launcher // Fırlatılan ana fişek
    case explosion // Patlama sonrası saçılan kıvılcımlar
}

// Orijinal ConfettiView bu yeni, daha gerçekçi ve optimize edilmiş havai fişek mantığıyla değiştirildi.
struct FireworksView: View {
    @State private var particles: [Particle] = []
    @State private var timer: Timer?

    var body: some View {
        // PERFORMANS İYİLEŞTİRMESİ: Yüzlerce View yerine tüm parçacıkları tek bir Canvas'ta çiziyoruz.
        // Bu, SwiftUI üzerindeki yükü önemli ölçüde azaltır ve animasyonu akıcı hale getirir.
        Canvas { context, size in
            // Tüm çizimlere daha parlak bir "alev" efekti vermek için blend mode'u ayarla.
            context.blendMode = .screen
            
            for particle in particles {
                // HATA DÜZELTMESİ: saveGState/restoreGState yerine, her parçacığın çizimini
                // kendi katmanında (layer) yaparak durumu yalıtıyoruz.
                // Bu, dönüşümlerin ve filtrelerin bir sonraki parçacığı etkilemesini önler.
                context.drawLayer { g in
                    if particle.type == .explosion {
                        // Patlama parçacıkları için çizim mantığı
                        let width = particle.size * particle.opacity * 2
                        let height = particle.size * particle.opacity
                        let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
                        
                        let gradient = Gradient(colors: [.white, .yellow, particle.color.opacity(0.5)])
                        let radialGradient = GraphicsContext.Shading.radialGradient(gradient, center: .zero, startRadius: 0, endRadius: (particle.size * particle.opacity) / 1.5)
                        
                        // Katmanın context'ini parçacığın konumuna taşı ve hareket yönüne göre döndür.
                        g.translateBy(x: particle.position.x, y: particle.position.y)
                        g.rotate(by: .radians(atan2(particle.velocity.dy, particle.velocity.dx)))
                        
                        // HATA DÜZELTMESİ: 'Path(capsuleIn:)' yerine 'Path(roundedRect:cornerRadius:)' kullanılıyor.
                        g.fill(Path(roundedRect: rect, cornerRadius: height / 2), with: radialGradient)
                        
                    } else { // Yükselen fişek (Launcher)
                        let rect = CGRect(x: particle.position.x - particle.size / 2,
                                          y: particle.position.y - particle.size / 2,
                                          width: particle.size, height: particle.size)
                        
                        let gradient = Gradient(colors: [.white, .yellow.opacity(0.5)])
                        let radialGradient = GraphicsContext.Shading.radialGradient(gradient, center: particle.position, startRadius: 0, endRadius: particle.size)

                        // Yükselen fişeğe bulanıklık efektini sadece bu katman içinde uygula.
                        g.addFilter(.blur(radius: particle.size / 4))
                        
                        // Şekli (daireyi) çiz.
                        g.fill(Path(ellipseIn: rect), with: radialGradient)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: startFireworks)
        .onDisappear(perform: stopFireworks)
        .allowsHitTesting(false)
    }

    private func startFireworks() {
        HapticManager.instance.notification(type: .success)
        
        // GECİKME DÜZELTMESİ: Animasyon başlar başlamaz anında 2 havai fişek fırlat.
        // Bu, kullanıcının anında geri bildirim almasını sağlar.
        particles.append(Particle(type: .launcher))
        particles.append(Particle(type: .launcher))
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            updateAndCreateParticles()
        }
    }

    private func stopFireworks() {
        timer?.invalidate()
        timer = nil
        particles.removeAll()
    }
    
    private func updateAndCreateParticles() {
        // Her saniye ortalama bir yeni havai fişek fırlatılma olasılığı.
        if Int.random(in: 0..<60) == 0 {
            particles.append(Particle(type: .launcher))
        }

        var newExplosionParticles: [Particle] = []
        
        // Geriye doğru döngü, döngü sırasında eleman silerken oluşabilecek hataları önler.
        for index in particles.indices.reversed() {
            if let explosion = particles[index].update() {
                newExplosionParticles.append(contentsOf: explosion)
            }
            
            if particles[index].isDead {
                particles.remove(at: index)
            }
        }
        
        particles.append(contentsOf: newExplosionParticles)
    }
}

struct Particle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var velocity: CGVector
    var opacity: Double = 1.0
    var color: Color
    var size: CGFloat
    var type: ParticleType
    
    var isDead: Bool { opacity <= 0 }

    private static let launcherGravity = CGVector(dx: 0, dy: 0.22)
    private static let explosionGravity = CGVector(dx: 0, dy: 0.08)
    private static let airResistance: CGFloat = 0.985
    private static let opacityDecay: Double = 0.015

    init(type: ParticleType, position: CGPoint? = nil, baseHue: Double? = nil) {
        self.type = type
        
        if type == .launcher {
            let screenBounds = UIScreen.main.bounds
            self.position = CGPoint(x: CGFloat.random(in: screenBounds.width * 0.2...screenBounds.width * 0.8), y: screenBounds.height)
            
            // YÜKSEKLİK İYİLEŞTİRMESİ: Dikey hız (dy) aralığı artırıldı.
            // Bu, fişeklerin daha yükseğe çıkmasını ve ekranın tepesine yakın patlamasını sağlar.
            // Önceki Değer: -CGFloat.random(in: 13...18)
            self.velocity = CGVector(dx: CGFloat.random(in: -1.5...1.5), dy: -CGFloat.random(in: 18...24))
            
            self.color = .yellow
            self.size = CGFloat.random(in: 4...6)
        } else { // type == .explosion
            self.position = position ?? .zero
            let angle = Double.random(in: 0...(2 * .pi))
            // Patlama gücünü daha doğal kılmak için üstel bir dağılım kullanılıyor.
            let speed = CGFloat.random(in: 1...7) * (1.0 - pow(CGFloat.random(in: 0...1), 2.0))
            self.velocity = CGVector(dx: CGFloat(cos(angle)) * speed, dy: CGFloat(sin(angle)) * speed)
            
            let hue = baseHue ?? Double.random(in: 0...1.0)
            let hueVariation = Double.random(in: -0.03...0.03)
            self.color = Color(hue: (hue + hueVariation).truncatingRemainder(dividingBy: 1.0), saturation: 0.9, brightness: 1.0)
            self.size = CGFloat.random(in: 4...8)
        }
    }

    // Parçacığın durumunu günceller ve gerekirse yeni parçacıklar (patlama) döndürür.
    mutating func update() -> [Particle]? {
        velocity.dx *= Self.airResistance
        velocity.dy *= Self.airResistance
        
        velocity.dy += (type == .launcher ? Self.launcherGravity.dy : Self.explosionGravity.dy)
        
        position.x += velocity.dx
        position.y += velocity.dy
        
        // Yükselen fişek zirveye ulaştığında (yavaşladığında) patlat.
        if type == .launcher && velocity.dy >= -2.0 {
            self.opacity = 0 // Yükselen fişeği yok et.
            
            var explosionParticles: [Particle] = []

            // İSTEK ÜZERİNE GÜNCELLEME: Her patlama için rastgele bir renk paleti seçiliyor.
            let colorPalettes: [ClosedRange<Double>] = [
                0...0.05,       // Kırmızı
                0.3...0.4,      // Yeşil
                0.75...0.85,    // Mor/Eflatun
                0.1...0.15      // Sarı/Turuncu
            ]
            let chosenPalette = colorPalettes.randomElement()!
            
            // PERFORMANS İYİLEŞTİRMESİ: Parçacık sayısı hafifçe azaltıldı.
            let particleCount = Int.random(in: 80...150)
            
            for _ in 0..<particleCount {
                // Seçilen paletten rastgele bir ana renk tonu (hue) alınıyor.
                let baseHue = Double.random(in: chosenPalette)
                explosionParticles.append(Particle(type: .explosion, position: self.position, baseHue: baseHue))
            }
            // Patlamadan doğan yeni parçacıkların listesini döndür.
            return explosionParticles
        }
        
        // Patlama kıvılcımlarını yavaşça soldur.
        if type == .explosion {
            opacity -= Self.opacityDecay
        }
        
        return nil
    }
}

