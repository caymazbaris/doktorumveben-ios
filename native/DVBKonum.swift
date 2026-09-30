import SwiftUI
import CoreLocation

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000264 — KONUMDAN İL/İLÇE + İL/İLÇE FİLTRESİ.
//
// Kullanıcı (30 Eyl 2026): "filtreleme yok hiç bişey yok" · "konum seçme yok konum isteyip ona göre il ilçeyi
// belirlesin otomatik". API il/ilçe filtresini ve il/ilçe listelerini (Tur 234) zaten sunuyordu; uygulama hiç
// kullanmıyordu.
//
// ⛔ GİZLİLİK: yalnız YAKLAŞIK konum istenir (`kCLLocationAccuracyReduced`). Koordinat cihazdan ÇIKMAZ:
// Apple'ın ters kodlamasıyla il/ilçe ADINA çevrilir, sunucuya yalnız il/ilçe filtresi gider (kullanıcının elle de
// seçebildiği bilgi). Seçim yalnız bu cihazda saklanır. App Store gizlilik etiketi bu yüzden değişmez.
// ═══════════════════════════════════════════════════════════════════════════════

struct DVBIl: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let slug: String
    let lat: Double?
    let lng: Double?
}

struct DVBIlce: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let slug: String
    let lat: Double?
    let lng: Double?
}

/// Seçili il/ilçe — arama filtresi VE talep formundaki şehrin varsayılanı. Tek kaynak.
@MainActor
final class DVBKonumSecimi: ObservableObject {
    static let shared = DVBKonumSecimi()

    @Published var il: DVBIl? { didSet { kaydet() } }
    @Published var ilce: DVBIlce? { didSet { kaydet() } }
    /// Seçim konumdan mı geldi (etikette "Konumunuz" yazmak için).
    @Published var konumdan = false

    private let anahtar = "dvb.konumSecimi.v1"

    private init() {
        // Seçim cihazda saklanır; uygulama her açılışta yeniden konum sormasın.
        if let veri = UserDefaults.standard.data(forKey: anahtar),
           let kayit = try? JSONDecoder().decode(DVBKonumKaydi.self, from: veri) {
            il = kayit.il.map(DVBIl.init)
            ilce = kayit.ilce.map(DVBIlce.init)
        }
    }

    var ozet: String? {
        guard let il else { return nil }
        if let ilce { return "\(il.name) · \(ilce.name)" }
        return il.name
    }

    func temizle() {
        il = nil
        ilce = nil
        konumdan = false
    }

    private func kaydet() {
        let kayit = DVBKonumKaydi(il: il.map(DVBIlKayit.init), ilce: ilce.map(DVBIlceKayit.init))
        if let veri = try? JSONEncoder().encode(kayit) {
            UserDefaults.standard.set(veri, forKey: anahtar)
        }
    }
}

/// Cihazda saklanan seçim. `DVBIl`/`DVBIlce` yalnız Decodable ve lat/lng taşır; saklamak için sade Codable kopya
/// (lat/lng saklanmaz — eşleştirme sonrası gerekmez).
private struct DVBKonumKaydi: Codable {
    let il: DVBIlKayit?
    let ilce: DVBIlceKayit?
}

private struct DVBIlKayit: Codable {
    let id: Int, name: String, slug: String
    init(_ i: DVBIl) { id = i.id; name = i.name; slug = i.slug }
}

private struct DVBIlceKayit: Codable {
    let id: Int, name: String, slug: String
    init(_ i: DVBIlce) { id = i.id; name = i.name; slug = i.slug }
}

extension DVBIl {
    fileprivate init(_ k: DVBIlKayit) { self.init(id: k.id, name: k.name, slug: k.slug, lat: nil, lng: nil) }
}

extension DVBIlce {
    fileprivate init(_ k: DVBIlceKayit) { self.init(id: k.id, name: k.name, slug: k.slug, lat: nil, lng: nil) }
}


// MARK: - Konum

/// Tek seferlik YAKLAŞIK konum. İzin gerekiyorsa sorar; red/hata/zaman aşımında nil döner (hiç asılı kalmaz).
@MainActor
final class DVBKonum: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = DVBKonum()

    @Published private(set) var durum: CLAuthorizationStatus
    @Published private(set) var calisiyor = false

    private let yonetici: CLLocationManager
    private var bekleyen: CheckedContinuation<CLLocation?, Never>?

    override private init() {
        // ⚠ super.init'ten ÖNCE self'in özelliği okunamaz: yöneticiyi yerel değişkende kur.
        let y = CLLocationManager()
        yonetici = y
        durum = y.authorizationStatus
        super.init()
        yonetici.delegate = self
        yonetici.desiredAccuracy = kCLLocationAccuracyReduced
    }

    var reddedildi: Bool { durum == .denied || durum == .restricted }

    func konumAl() async -> CLLocation? {
        if reddedildi || bekleyen != nil { return nil }
        calisiyor = true
        defer { calisiyor = false }

        // ⚠ Devam kapanışı eski derleyicilerde ana aktöre YALITILMIŞ değil; ana aktör durumunu orada değiştirmek
        // derlemeyi kırar. Kapanış yalnız bir ana-aktör görevi başlatır, işi `baslat` yapar.
        return await withCheckedContinuation { (devam: CheckedContinuation<CLLocation?, Never>) in
            Task { @MainActor in self.baslat(devam) }
        }
    }

    private func baslat(_ devam: CheckedContinuation<CLLocation?, Never>) {
        bekleyen = devam
        if durum == .notDetermined {
            yonetici.requestWhenInUseAuthorization()   // sonuç aşağıdaki temsilcide
        } else {
            yonetici.requestLocation()
        }
        // Emniyet: hiçbir geri çağrı gelmezse ekran "konum bulunuyor…"da ASILI kalmasın.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            self.bitir(nil)
        }
    }

    private func bitir(_ konum: CLLocation?) {
        bekleyen?.resume(returning: konum)
        bekleyen = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let yeni = manager.authorizationStatus
        Task { @MainActor in
            self.durum = yeni
            guard self.bekleyen != nil else { return }
            switch yeni {
            case .authorizedWhenInUse, .authorizedAlways: self.yonetici.requestLocation()
            case .denied, .restricted: self.bitir(nil)
            default: break   // .notDetermined: kullanıcı henüz yanıtlamadı
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let son = locations.last
        Task { @MainActor in self.bitir(son) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.bitir(nil) }
    }
}

// MARK: - Coğrafi liste + eşleştirme

@MainActor
enum DVBCografya {
    private static var ilOnbellek: [DVBIl] = []

    static func iller() async -> [DVBIl] {
        if !ilOnbellek.isEmpty { return ilOnbellek }
        // Sunucu City::ordered() sırasıyla döner (İstanbul, İzmir, Ankara üstte) — burada yeniden SIRALANMAZ.
        if let liste: DVBList<DVBIl> = try? await DVBAPI.shared.get("geo/cities") {
            ilOnbellek = liste.data
        }
        return ilOnbellek
    }

    static func ilceler(_ il: DVBIl) async -> [DVBIlce] {
        let liste: DVBList<DVBIlce>? = try? await DVBAPI.shared.get("geo/districts", query: ["city": il.slug])
        return liste?.data ?? []
    }

    /// Konumu il/ilçeye çevirir. Önce ADLA eşleştirir (Apple'ın ters kodlaması: il = administrativeArea,
    /// ilçe = subAdministrativeArea); ad tutmazsa KOORDİNATA en yakın il/ilçe seçilir.
    static func esle(_ konum: CLLocation) async -> (DVBIl, DVBIlce?)? {
        let iller = await iller()
        guard !iller.isEmpty else { return nil }

        let yer = try? await CLGeocoder().reverseGeocodeLocation(konum, preferredLocale: Locale(identifier: "tr_TR")).first

        let il = iller.first { normal($0.name) == normal(yer?.administrativeArea) }
            ?? enYakin(iller, konum, lat: \.lat, lng: \.lng)
        guard let il else { return nil }

        let ilceler = await ilceler(il)
        let adlar = [yer?.subAdministrativeArea, yer?.locality].compactMap { $0 }.map(normal)
        let ilce = ilceler.first { adlar.contains(normal($0.name)) }
            ?? enYakin(ilceler, konum, lat: \.lat, lng: \.lng)

        return (il, ilce)
    }

    /// Türkçe ad karşılaştırması: büyük/küçük harf ve aksan duyarsız; "ı" → "i".
    static func normal(_ s: String?) -> String {
        guard let s else { return "" }
        return s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func enYakin<T>(_ liste: [T], _ konum: CLLocation,
                                   lat: KeyPath<T, Double?>, lng: KeyPath<T, Double?>) -> T? {
        liste
            .compactMap { o -> (T, CLLocationDistance)? in
                guard let a = o[keyPath: lat], let b = o[keyPath: lng] else { return nil }
                return (o, konum.distance(from: CLLocation(latitude: a, longitude: b)))
            }
            .min { $0.1 < $1.1 }?.0
    }
}

// MARK: - Filtre sayfası

struct DVBFiltreSayfasi: View {
    @ObservedObject var secim: DVBKonumSecimi
    @ObservedObject var konum = DVBKonum.shared
    var uygula: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var iller: [DVBIl] = []
    @State private var ilceler: [DVBIlce] = []
    @State private var konumHatasi: String?

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Button {
                        Task { await konumuKullan() }
                    } label: {
                        HStack {
                            Label("Konumumu kullan", systemImage: "location.fill")
                            Spacer()
                            if konum.calisiyor { ProgressView() }
                        }
                    }
                    .disabled(konum.calisiyor)
                } footer: {
                    if let konumHatasi {
                        Text(konumHatasi).foregroundColor(.red)
                    } else {
                        Text("Yaklaşık konumunuzdan il ve ilçe bulunur. Konumunuz kaydedilmez, cihazınızdan çıkmaz.")
                    }
                }

                Section("Konum") {
                    Picker("Şehir", selection: Binding(
                        get: { secim.il },
                        set: { yeni in
                            secim.il = yeni
                            secim.ilce = nil
                            secim.konumdan = false
                            Task { await ilceleriYukle() }
                        }
                    )) {
                        Text("Tümü").tag(DVBIl?.none)
                        ForEach(iller) { Text($0.name).tag(DVBIl?.some($0)) }
                    }

                    if secim.il != nil {
                        Picker("İlçe", selection: Binding(
                            get: { secim.ilce },
                            set: { secim.ilce = $0; secim.konumdan = false }
                        )) {
                            Text("Tümü").tag(DVBIlce?.none)
                            ForEach(ilceler) { Text($0.name).tag(DVBIlce?.some($0)) }
                        }
                    }
                }

                if secim.il != nil {
                    Section {
                        Button("Konum filtresini kaldır", role: .destructive) {
                            secim.temizle()
                            ilceler = []
                        }
                    }
                }
            }
            .navigationTitle("Filtrele")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uygula") {
                        uygula()
                        dismiss()
                    }
                }
            }
            .task {
                iller = await DVBCografya.iller()
                // Saklanan seçim lat/lng taşımaz ve eşitlik tüm alanlara bakar → listedeki kopyasıyla değiştir,
                // yoksa Picker seçili satırı bulamaz.
                if let il = secim.il, let tam = iller.first(where: { $0.id == il.id }) { secim.il = tam }
                await ilceleriYukle()
            }
        }
        .navigationViewStyle(.stack)
    }

    private func ilceleriYukle() async {
        guard let il = secim.il else { ilceler = []; return }
        ilceler = await DVBCografya.ilceler(il)
        if let ilce = secim.ilce { secim.ilce = ilceler.first { $0.id == ilce.id } }
    }

    private func konumuKullan() async {
        konumHatasi = nil
        guard let yer = await konum.konumAl() else {
            konumHatasi = konum.reddedildi
                ? "Konum izni kapalı. Ayarlar › Doktorum Ve Ben › Konum'dan açabilir ya da şehri elle seçebilirsiniz."
                : "Konum alınamadı. Şehri elle seçebilirsiniz."
            return
        }
        guard let eslesme = await DVBCografya.esle(yer) else {
            konumHatasi = "Konumunuz bir şehirle eşleştirilemedi. Şehri elle seçebilirsiniz."
            return
        }
        secim.il = eslesme.0
        secim.ilce = eslesme.1
        secim.konumdan = true
        await ilceleriYukle()
    }
}
