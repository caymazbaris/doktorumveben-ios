import LocalAuthentication
import SwiftUI

/// DVB-000111 — FACE ID / TOUCH ID KİLİDİ.
///
/// İKİ SEBEP:
///  1) KVKK/güvenlik: uygulama randevu ve sağlık bağlamı taşıyor. Telefonu bir an
///     eline alan kişinin bunları görmemesi savunulabilir bir kontroldür.
///  2) App Store 4.2: cihazın donanımını kullanan, tarayıcının YAPAMAYACAĞI bir işlev.
///     Apple 31.07.2026 reddinde "push/Core Location/sharing yetmez" dedi; biyometrik
///     kilit bunlardan farklı olarak uygulamanın KENDİ verisini koruyan bir yetenektir.
///
/// ⚠ VARSAYILAN KAPALI — bilinçli. Açık gelseydi Face ID'si olmayan/izin vermeyen
/// kullanıcı uygulamaya giremezdi. Kilit kullanıcının kendi tercihidir.
///
/// ⚠ KİLİT BİR YETKİ KAPISI DEĞİLDİR: verinin kendisi sunucuda oturumla korunuyor.
/// Bu yalnız "omuz üstünden bakma"ya karşı bir perdedir; öyle anlatılmalı.
@MainActor
final class DVBBiometricLock: ObservableObject {

    static let ayarAnahtari = "dvb.biyometrik.kilit"

    /// Kullanıcı kilidi açtı mı (ayar)?
    @Published var etkin: Bool {
        didSet { UserDefaults.standard.set(etkin, forKey: Self.ayarAnahtari) }
    }

    /// Şu an kilitli mi (oturum durumu)?
    @Published private(set) var kilitli: Bool

    /// Son deneme başarısızsa kullanıcıya gösterilecek metin.
    @Published var hata: String?

    init() {
        let acik = UserDefaults.standard.bool(forKey: Self.ayarAnahtari)
        etkin = acik
        // Uygulama kilitli AÇILIR; aksi hâlde ilk kare veriyi gösterip sonra kapatırdı.
        kilitli = acik
    }

    /// Cihaz biyometri destekliyor mu ve kullanılabilir mi?
    static func kullanilabilir() -> (evet: Bool, ad: String) {
        let ctx = LAContext()
        var err: NSError?
        let evet = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)

        let ad: String
        switch ctx.biometryType {
        case .faceID: ad = "Face ID"
        case .touchID: ad = "Touch ID"
        default: ad = "Biyometrik kilit"
        }
        return (evet, ad)
    }

    /// Uygulama arka plana giderse tekrar kilitle.
    func arkaPlanaGitti() {
        if etkin { kilitli = true }
    }

    func coz() async {
        guard etkin else { kilitli = false; return }

        let ctx = LAContext()
        ctx.localizedCancelTitle = "Vazgeç"

        // ⚠ POLİTİKA SEÇİMİ: deviceOwnerAuthentication (biyometri + PAROLA yedeği).
        // Yalnız biyometri seçseydik, yüzü tanınmayan kullanıcı (maske, karanlık, yaralanma)
        // kendi verisine erişemezdi ve uygulamayı silmekten başka çaresi kalmazdı.
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            // Cihazda ekran kilidi bile yoksa kilidi zorlamak kullanıcıyı dışarıda bırakır.
            hata = nil
            kilitli = false
            return
        }

        do {
            let ok = try await ctx.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Randevularınızı görmek için kimliğinizi doğrulayın."
            )
            kilitli = !ok
            hata = ok ? nil : "Doğrulanamadı."
        } catch {
            hata = "Doğrulanamadı. Tekrar deneyin."
        }
    }
}

/// Kilitliyken içeriğin ÜSTÜNE çizilen perde.
///
/// İçerik hiyerarşiden kaldırılmıyor (durum korunsun diye) ama tamamen örtülüyor —
/// ekran görüntüsü/uygulama değiştirici önizlemesinde de veri görünmesin.
struct DVBLockGate: ViewModifier {
    @ObservedObject var lock: DVBBiometricLock

    func body(content: Content) -> some View {
        ZStack {
            content
                .blur(radius: lock.kilitli ? 24 : 0)
                .allowsHitTesting(!lock.kilitli)

            if lock.kilitli {
                VStack(spacing: 18) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 44, weight: .light))
                        .foregroundColor(DVBTheme.brand)

                    Text("Doktorum Ve Ben kilitli")
                        .font(.headline)

                    Text("Randevularınızı görmek için kimliğinizi doğrulayın.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    if let hata = lock.hata {
                        Text(hata).font(.footnote).foregroundColor(.red)
                    }

                    Button("Kilidi Aç") {
                        Task { await lock.coz() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DVBTheme.brand)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: lock.kilitli)
        .task(id: lock.kilitli) {
            // Kilitlendiği anda doğrulamayı kendiliğinden başlat; kullanıcı her seferinde
            // "Kilidi Aç"a basmak zorunda kalmasın.
            if lock.kilitli { await lock.coz() }
        }
    }
}

extension View {
    func dvbKilit(_ lock: DVBBiometricLock) -> some View {
        modifier(DVBLockGate(lock: lock))
    }
}
