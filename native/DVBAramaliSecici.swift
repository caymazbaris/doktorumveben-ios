import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000281 — ARANABİLİR SEÇİCİ (uzun listeler: branş, şehir, ilçe, ilgi alanı, sigorta, dil).
//
// Kullanıcı (1 Eki 2026): "branş kısımlarında ve selectbox olan her yerde serachable değil o şekilde yapalım birde
// alfabetik sıralama yapalım , önce popüler branşlar sonrası alfabetik"; kapsam kararı "Her yerde".
//
// Yerel `Picker` aranamıyordu: 81 il, 58 branş, 72 dil kaydırarak bulunuyordu. Bu satır formda Picker gibi görünür
// (başlık · seçili değer · ok); dokununca arama kutulu liste açılır.
//
// SIRA (sitedekiyle aynı mantık): sunucu bir kaydı `popular` işaretlediyse (branş: anasayfadaki "Popüler Branşlar",
// il: İstanbul/İzmir/Ankara) o kayıtlar üstte SUNUCU SIRASIYLA; geri kalanı TÜRKÇE alfabetik (Ç C'den, Ş S'den sonra;
// ı i'den önce) — sunucunun harmanlamasına bırakılmaz, burada sıralanır. Sitede aynı kural:
// Specialty::secimGruplari + <x-brans-secenekleri> ve aranabilir kutu (resources/js/aranabilir-secim.js).
//
// ⚠ Kısa listeler (cinsiyet, görüşme türü, sıralama…) yerel Picker'da kalır — 3 seçenekte arama kutusu kalabalık.
// ═══════════════════════════════════════════════════════════════════════════════

struct DVBSecenek<Kimlik: Hashable>: Identifiable {
    let id: Kimlik
    let ad: String
    var populer = false
}

enum DVBArama {
    static let tr = Locale(identifier: "tr_TR")

    /// Türkçe duyarlı katlama: büyük/küçük harf ve şapka/nokta farkı yok; "ı" → "i" (DVBCografya.normal ile aynı).
    static func katla(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: tr)
            .replacingOccurrences(of: "ı", with: "i")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Türkçe alfabetik sıra (ICU harmanlaması: Ç C'den sonra, ı i'den önce). Büyük harfle başlayan ADLAR önce:
    /// hekim dil verisi kirli ("en", "tr" kodları, "arnavutça") — sunucu da aynı kuralla dizer (TurkceMetin::adlarOnde),
    /// kodlar adların arasına karışmaz. Diğer listelerde (il, branş…) her ad büyük harfle başladığı için etkisiz.
    static func once(_ a: String, _ b: String) -> Bool {
        let ka = kucukBaslar(a), kb = kucukBaslar(b)
        if ka != kb { return !ka }
        return a.compare(b, options: [.caseInsensitive], range: nil, locale: tr) == .orderedAscending
    }

    private static func kucukBaslar(_ s: String) -> Bool {
        guard let ilk = s.first.map({ String($0) }) else { return true }
        return ilk.lowercased(with: tr) == ilk && ilk.uppercased(with: tr) != ilk
    }

    /// Arama sırası (siteyle aynı): 0 baştan eşleşen · 1 kelime başı · 2 içinde geçen. Eşleşmiyorsa nil.
    static func kademe(_ ad: String, _ q: String) -> Int? {
        let t = katla(ad)
        if t.hasPrefix(q) { return 0 }
        if t.split(whereSeparator: { " (-/.,".contains($0) }).contains(where: { $0.hasPrefix(q) }) { return 1 }
        if t.contains(q) { return 2 }
        return nil
    }
}

extension Binding where Value == String {
    /// `""` = seçim yok kuralını kullanan alanlar (DVBAramaFiltresi) için aranabilir seçici bağı.
    var bossaNil: Binding<String?> {
        Binding<String?>(get: { wrappedValue.isEmpty ? nil : wrappedValue }, set: { wrappedValue = $0 ?? "" })
    }
}

/// Form satırı: başlık + seçili değer. Dokununca aranabilir liste İTİLİR (çevresinde NavigationView olmalı).
struct DVBAramaliSecici<Kimlik: Hashable>: View {
    let baslik: String
    let secenekler: [DVBSecenek<Kimlik>]
    @Binding var secili: Kimlik?
    /// Seçimsiz durumun adı ("Seçin", "Tümü", "Fark etmez"); listede en üstte satır olur. nil → seçimsiz satır yok.
    var bosEtiket: String? = "Seçin"
    var populerBaslik = "Popüler"
    var digerBaslik = "Tümü (A–Z)"

    var body: some View {
        NavigationLink(destination: DVBAramaliListe(
            baslik: baslik, secenekler: secenekler, secili: $secili,
            bosEtiket: bosEtiket, populerBaslik: populerBaslik, digerBaslik: digerBaslik
        )) {
            HStack(spacing: 12) {
                Text(baslik).foregroundColor(.primary)
                Spacer(minLength: 8)
                Text(seciliAd)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .accessibilityHint("Aranabilir liste açılır")
    }

    private var seciliAd: String {
        if let secili, let s = secenekler.first(where: { $0.id == secili }) { return s.ad }
        return bosEtiket ?? ""
    }
}

/// Aranabilir liste sayfası. Seçince kapanır (itildiyse geri döner, sayfa olarak açıldıysa iner).
struct DVBAramaliListe<Kimlik: Hashable>: View {
    let baslik: String
    let secenekler: [DVBSecenek<Kimlik>]
    @Binding var secili: Kimlik?
    var bosEtiket: String? = "Seçin"
    var populerBaslik = "Popüler"
    var digerBaslik = "Tümü (A–Z)"
    /// Sayfa (sheet) olarak açıldığında sol üstte "Vazgeç".
    var vazgecDugmesi = false

    @Environment(\.dismiss) private var dismiss
    @State private var arama = ""

    private var populer: [DVBSecenek<Kimlik>] { secenekler.filter(\.populer) }

    private var diger: [DVBSecenek<Kimlik>] {
        secenekler.filter { !$0.populer }.sorted { DVBArama.once($0.ad, $1.ad) }
    }

    /// Arama sonucu: önce kademe (baştan · kelime başı · içinde), eşitlikte ekrandaki sıra (popüler → alfabetik).
    private var sonuclar: [DVBSecenek<Kimlik>] {
        let q = DVBArama.katla(arama)
        let adaylar: [(secenek: DVBSecenek<Kimlik>, kademe: Int, sira: Int)] = (populer + diger).enumerated()
            .compactMap { cift in
                guard let k = DVBArama.kademe(cift.element.ad, q) else { return nil }
                return (secenek: cift.element, kademe: k, sira: cift.offset)
            }
        return adaylar
            .sorted { $0.kademe != $1.kademe ? $0.kademe < $1.kademe : $0.sira < $1.sira }
            .map { $0.secenek }
    }

    private var aramaVar: Bool { !arama.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ScrollViewReader { kaydir in
            List {
                if aramaVar {
                    let bulunan = sonuclar
                    if bulunan.isEmpty {
                        Text("“\(arama)” için sonuç yok").foregroundColor(.secondary)
                    } else {
                        Section {
                            ForEach(bulunan) { satir($0.id, $0.ad) }
                        }
                    }
                } else {
                    if let bosEtiket {
                        Section { satir(nil, bosEtiket) }
                    }
                    if populer.isEmpty {
                        Section {
                            ForEach(diger) { satir($0.id, $0.ad) }
                        }
                    } else {
                        Section(populerBaslik) {
                            ForEach(populer) { satir($0.id, $0.ad) }
                        }
                        if !diger.isEmpty {
                            Section(digerBaslik) {
                                ForEach(diger) { satir($0.id, $0.ad) }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .onAppear {
                // Seçili satır görünür gelsin (81 ilde Zonguldak seçiliyken liste başta açılmasın).
                guard secili != nil else { return }
                DispatchQueue.main.async { kaydir.scrollTo(secili, anchor: .center) }
            }
        }
        .navigationTitle(baslik)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $arama, placement: .navigationBarDrawer(displayMode: .always), prompt: "\(baslik) ara")
        .autocorrectionDisabled()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if vazgecDugmesi { Button("Vazgeç") { dismiss() } }
            }
        }
    }

    private func satir(_ id: Kimlik?, _ ad: String) -> some View {
        Button {
            secili = id
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(ad).foregroundColor(.primary)
                Spacer(minLength: 8)
                if secili == id {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundColor(DVBTheme.brand)
                }
            }
            .contentShape(Rectangle())
        }
        .id(id)
        .accessibilityAddTraits(secili == id ? .isSelected : [])
    }
}
