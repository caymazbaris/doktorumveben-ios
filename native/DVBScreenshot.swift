import SwiftUI

/// Tur 241 — Mağaza ekran görüntüsü modu. YALNIZ CI/Simulator içindir.
///
/// Neden var: ekipte iPhone da Mac de yok. App Store 2.3.8 ekran görüntülerinin
/// uygulamanın GERÇEK ekranlarını göstermesini istiyor; elimizdeki eski görüntüler
/// hem uydurma bir hekim ("Op. Dr. Ayşe Yılmaz") hem de artık kullanılmayan WebView
/// arayüzünü gösteriyordu — yani tekrar 2.3.8 riski.
///
/// Çözüm: Codemagic'in Mac mini'sinde Simulator'da uygulamayı doğrudan istenen
/// ekranda açmak; `xcrun simctl io … screenshot` gerçek ekranı yakalıyor. Böylece
/// görüntüler gerçek native ekranlar + CANLI veri oluyor, tek bir kare bile
/// elle çizilmiyor.
///
/// Hasta akışına etkisi YOK: yalnız `-DVBScreenshot <ekran>` başlatma argümanı
/// verildiğinde devreye girer, bunu da yalnız CI verir. Argüman yoksa
/// `DVBRootView` her zamanki sekmeli arayüzü kurar.
enum DVBScreenshotMode {

    /// "arama" | "profil" | "randevu"
    static var ekran: String? { deger("-DVBScreenshot") }

    /// Hangi hekim gösterilecek (canlı slug). Verilmezse makul bir varsayılan.
    static var slug: String { deger("-DVBScreenshotDoctor") ?? "erkan-kulduk-84ix" }

    /// Argüman adının HEMEN ardından gelen değer. Bir sonraki öğe de "-" ile
    /// başlıyorsa değer verilmemiş sayılır (yanlışlıkla bayrağı değer sanmayalım).
    private static func deger(_ ad: String) -> String? {
        let argv = ProcessInfo.processInfo.arguments
        guard let i = argv.firstIndex(of: ad), i + 1 < argv.count else { return nil }
        let v = argv[i + 1]
        return v.hasPrefix("-") ? nil : v
    }
}

/// Ekran görüntüsü modunda kökü devralan kabuk: istenen ekranı, canlı veriyle,
/// tek adımda açar (tıklama otomasyonu gerekmez — `simctl` tıklayamaz).
@MainActor
struct DVBScreenshotHost: View {

    let ekran: String
    let slug: String

    @StateObject private var session = DVBSession()

    @State private var doctor: DVBDoctor?
    @State private var hata: String?

    var body: some View {
        icerik
            .tint(DVBTheme.brand)
            .environmentObject(session)
            .task { await hekimiGetir() }
    }

    @ViewBuilder
    private var icerik: some View {
        if ekran == "profil" || ekran == "randevu" {
            // Bu iki ekran .navigationTitle kullanıyor → bir gezinme kabı şart.
            NavigationView {
                if let doctor {
                    if ekran == "profil" {
                        DVBDoctorDetailView(doctor: doctor)
                    } else {
                        DVBBookingView(doctor: doctor)
                    }
                } else if let hata {
                    DVBStateView(icon: "exclamationmark.triangle", title: "Ekran görüntüsü modu", message: hata)
                } else {
                    ProgressView()
                }
            }
            .navigationViewStyle(.stack)
        } else {
            // DVBSearchView kendi NavigationView'ını kuruyor — ikinci kez sarmalamıyoruz.
            DVBSearchView()
        }
    }

    /// Profil/randevu ekranları bir `DVBDoctor` (kart modeli) istiyor. Detay ucundan
    /// tek istekle çekip kart modeline dönüştürüyoruz: arama ucunu isimle sorgulamak
    /// Türkçe karakter + sıralama yüzünden kırılgan olurdu, slug ise kesin.
    private func hekimiGetir() async {
        guard ekran == "profil" || ekran == "randevu" else { return }

        do {
            let detay: DVBDoctorDetail = try await DVBAPI.shared.get("doctors/\(slug)")
            let d = detay.doctor
            doctor = DVBDoctor(
                slug: d.slug,
                name: d.name,
                specialty: d.specialty,
                avatar: d.avatar,
                rating: d.rating,
                ratingCount: d.ratingCount,
                isVerified: d.isVerified,
                district: d.district,
                experience: d.experience,
                distanceKm: nil
            )
        } catch {
            hata = (error as? DVBError)?.errorDescription ?? "Hekim yüklenemedi."
        }
    }
}
