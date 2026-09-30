import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000268 — SİTEDEKİ ARAMA FİLTRELERİ.
//
// Kullanıcı (30 Eyl 2026): "filtreleme de ekleyelim şehir branş vs gibi sitedeki". Sitedeki dizinde 12 filtre var;
// uygulamada şehir/ilçe/branş vardı. Buradakiler sitenin AYNI parametreleri — sunucuda web ile aynı sorgu servisinden
// geçer (sonuçlar birebir aynı olsun). Değerler sunucudaki anahtarlarla BİREBİR aynı; değiştirmeyin.
//
// "Yakınımdakiler" (koordinat) bilerek YOK: uygulama "konumunuz cihazdan çıkmaz" diyor (DVB-000264); konum cihazda
// il/ilçeye çevriliyor.
// ═══════════════════════════════════════════════════════════════════════════════

/// Arama filtresi — şehir/ilçe DVBKonumSecimi'nde (talep formu da kullandığı için), geri kalanı burada.
@MainActor
final class DVBAramaFiltresi: ObservableObject {
    static let shared = DVBAramaFiltresi()

    @Published var cinsiyet = ""        // "" | female | male
    @Published var kanal = ""           // "" | in_person | online
    @Published var dogrulanmis = false
    @Published var dil = ""             // "" | sunucudaki dil adı
    @Published var sigorta = ""         // "" | sigorta şirketi slug
    @Published var ilgiAlani = ""       // "" | expertise slug
    @Published var siralama = ""        // "" (puan) | experience | reviews

    private init() {}

    /// Arama isteğine eklenecek parametreler (boşlar gönderilmez).
    var parametreler: [String: String] {
        var p: [String: String] = [:]
        if !cinsiyet.isEmpty { p["gender"] = cinsiyet }
        if !kanal.isEmpty { p["channel"] = kanal }
        if dogrulanmis { p["verified"] = "1" }
        if !dil.isEmpty { p["language"] = dil }
        if !sigorta.isEmpty { p["insurance"] = sigorta }
        if !ilgiAlani.isEmpty { p["expertise"] = ilgiAlani }
        if !siralama.isEmpty { p["sort"] = siralama }
        return p
    }

    /// Filtre düğmesindeki sayı (sıralama filtre sayılmaz).
    var etkinSayisi: Int {
        [!cinsiyet.isEmpty, !kanal.isEmpty, dogrulanmis, !dil.isEmpty, !sigorta.isEmpty, !ilgiAlani.isEmpty]
            .filter { $0 }.count
    }

    func temizle() {
        cinsiyet = ""; kanal = ""; dogrulanmis = false; dil = ""; sigorta = ""; ilgiAlani = ""; siralama = ""
    }
}

/// `GET /doctors/filters` — seçenek listeleri (sunucu web'deki önbellekle üretir).
struct DVBFiltreSecenekleri: Decodable {
    let languages: [String]
    let insurances: [Oge]
    let expertises: [Oge]

    struct Oge: Decodable, Identifiable, Hashable {
        /// Sunucudaki kayıt numarası (hekimsiz talep `expertise_id` ister). Arama ise slug ile süzer.
        let numara: Int?
        let slug: String
        let name: String
        var id: String { slug }

        enum CodingKeys: String, CodingKey {
            case slug, name
            case numara = "id"
        }
    }

    @MainActor private static var onbellek: DVBFiltreSecenekleri?

    /// Oturum boyunca bir kez çekilir; ağ yoksa nil (filtre sayfası o bölümleri göstermez, çökmez).
    @MainActor static func getir() async -> DVBFiltreSecenekleri? {
        if let onbellek { return onbellek }
        let s: DVBFiltreSecenekleri? = try? await DVBAPI.shared.get("doctors/filters")
        onbellek = s
        return s
    }
}

/// Filtre sayfasındaki şehir/ilçe dışı bölümler. `DVBFiltreSayfasi` (DVBKonum.swift) bunu gömer.
struct DVBEkFiltreler: View {
    @ObservedObject var filtre: DVBAramaFiltresi
    @State private var secenekler: DVBFiltreSecenekleri?

    var body: some View {
        Group {
            Section("Hekim") {
                Picker("Cinsiyet", selection: $filtre.cinsiyet) {
                    Text("Fark etmez").tag("")
                    Text("Kadın").tag("female")
                    Text("Erkek").tag("male")
                }
                Picker("Görüşme türü", selection: $filtre.kanal) {
                    Text("Fark etmez").tag("")
                    Text("Yüz yüze").tag("in_person")
                    Text("Online").tag("online")
                }
                Toggle("Yalnız doğrulanmış hekimler", isOn: $filtre.dogrulanmis)
            }

            if let s = secenekler {
                Section("Daha fazla") {
                    if !s.expertises.isEmpty {
                        Picker("İlgi alanı", selection: $filtre.ilgiAlani) {
                            Text("Fark etmez").tag("")
                            ForEach(s.expertises) { Text($0.name).tag($0.slug) }
                        }
                    }
                    if !s.insurances.isEmpty {
                        Picker("Anlaşmalı sigorta", selection: $filtre.sigorta) {
                            Text("Fark etmez").tag("")
                            ForEach(s.insurances) { Text($0.name).tag($0.slug) }
                        }
                    }
                    if !s.languages.isEmpty {
                        Picker("Konuştuğu dil", selection: $filtre.dil) {
                            Text("Fark etmez").tag("")
                            ForEach(s.languages, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }
            }

            Section("Sıralama") {
                Picker("Sırala", selection: $filtre.siralama) {
                    Text("En yüksek puan").tag("")
                    Text("En çok değerlendirilen").tag("reviews")
                    Text("En deneyimli").tag("experience")
                }
            }

            if filtre.etkinSayisi > 0 || !filtre.siralama.isEmpty {
                Section {
                    Button("Diğer filtreleri temizle", role: .destructive) { filtre.temizle() }
                }
            }
        }
        .task { secenekler = await DVBFiltreSecenekleri.getir() }
    }
}
