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

    /// "arama" | "profil" | "randevu" | "hesap" | "oneri" | "liste-sonuk"
    ///
    /// Tur 241'de "hesap" eklendi: App Store 4.8 için uygulama içi "Apple ile giriş"
    /// düğmesinin GERÇEKTEN çizildiğini görmenin tek yolu bu — ekipte cihaz yok,
    /// entitlement/kod doğru görünse de düğme çizilmiyorsa yine reddedilirdik.
    ///
    /// DVB-000498 — "oneri" ve "liste-sonuk" MAĞAZA karesi DEĞİL, kontrol karesi: DVB-000497'nin talep öncesi
    /// takvimli uzman önerisi bir düğmenin arkasında (simctl tıklayamaz) ve aramanın ilk ekranındaki hekimlerin
    /// hepsi takvimli (sönük satır kareye düşmüyor). Betik bunları ayrı klasöre çeker.
    static var ekran: String? { deger("-DVBScreenshot") }

    /// Hangi hekim gösterilecek (canlı slug). Verilmezse makul bir varsayılan.
    /// DVB-000498 — varsayılan takvimi AÇIK bir hekim: eski varsayılan (erkan-kulduk-84ix) DVB-000480'den beri
    /// randevuya kapalı, randevu karesi "Şu an uygun saat yok" çıkıyordu.
    static var slug: String { deger("-DVBScreenshotDoctor") ?? "bahar-selda-dogan-suxt" }

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
    // DVB-000264 — hekim sayfası artık talep formuna oturumla birlikte kilidi de geçiriyor; kök ne veriyorsa
    // kabuk da vermeli, yoksa talep sayfası açıldığı an "ObservableObject bulunamadı" ile çöker.
    @StateObject private var lock = DVBBiometricLock()

    @State private var doctor: DVBDoctor?
    @State private var hata: String?

    var body: some View {
        icerik
            .tint(DVBTheme.brand)
            .environmentObject(session)
            .environmentObject(lock)
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
        } else if ekran == "oneri" {
            // DVB-000498 kontrol karesi: takvimi kapalı hekimde "Randevu Talep Et"in açtığı sayfa.
            // DVBTalepOnerisiView kendi NavigationView'ını kurar; öneri yoksa formu açar (o da karede görülür).
            if let doctor {
                DVBTalepOnerisiView(doctorSlug: doctor.slug, doctorName: doctor.name ?? "", konu: .randevu)
            } else if let hata {
                DVBStateView(icon: "exclamationmark.triangle", title: "Ekran görüntüsü modu", message: hata)
            } else {
                ProgressView()
            }
        } else if ekran == "liste-sonuk" {
            DVBScreenshotSonukListe()
        } else if ekran == "hesap" {
            // Girişsiz hesap ekranı: e-posta/parola + "Apple ile giriş" düğmesi.
            // DVBAccountView kendi NavigationView'ını kurar.
            DVBAccountView()
        } else {
            // DVBSearchView kendi NavigationView'ını kuruyor — ikinci kez sarmalamıyoruz.
            DVBSearchView()
        }
    }

    /// Profil/randevu ekranları bir `DVBDoctor` (kart modeli) istiyor. Detay ucundan
    /// tek istekle çekip kart modeline dönüştürüyoruz: arama ucunu isimle sorgulamak
    /// Türkçe karakter + sıralama yüzünden kırılgan olurdu, slug ise kesin.
    private func hekimiGetir() async {
        guard ekran == "profil" || ekran == "randevu" || ekran == "oneri" else { return }

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

/// DVB-000498 kontrol karesi: takvimli hekimler önde + "Online randevu" etiketi, takvimsizler sönük.
/// Aramanın ilk ekranı yalnız takvimlileri gösteriyor; burada aynı satır bileşeni (DVBDoctorRow) ve aynı uç
/// (api/v1/doctors) dar bir sorguyla çağrılır: İzmir psikiyatri (canlı 24 Kas: ilk sayfada 3 takvimli + 12 takvimsiz).
@MainActor
private struct DVBScreenshotSonukListe: View {

    @State private var hekimler: [DVBDoctor] = []
    @State private var hata: String?

    var body: some View {
        NavigationView {
            List {
                if let hata {
                    DVBStateView(icon: "exclamationmark.triangle", title: "Ekran görüntüsü modu", message: hata)
                } else if hekimler.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ForEach(hekimler) { DVBDoctorRow(doctor: $0) }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Psikiyatri · İzmir")
        }
        .navigationViewStyle(.stack)
        .task { await yukle() }
    }

    private func yukle() async {
        do {
            let sayfa: DVBDoctorPage = try await DVBAPI.shared.get("doctors", query: ["city": "izmir", "specialty": "psikiyatri"])
            hekimler = sayfa.data
        } catch {
            hata = (error as? DVBError)?.errorDescription ?? "Liste yüklenemedi."
        }
    }
}
