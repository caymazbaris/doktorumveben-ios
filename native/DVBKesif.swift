import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000344 — HASTANELER ve SAÇ EKİMİ (hasta tarafı, giriş gerektirmez).
//
// Kullanıcı (9 Eki 2026): "saç ekimi ve hastaneler ile ilgili kısımları da ekle".
//
// Veri ve kurallar sunucuda (KesifApiController; web /hastaneler ve /izmir-sac-ekimi sayfalarıyla aynı):
// · hastane telefonu / web adresi ŞİMDİLİK gösterilmez (kullanıcı kararı); hekim kartı arama listesiyle aynı biçim;
// · saç ekimi: fiyat ve üstünlük ifadesi yok, merkez telefonu yok; talep web formuyla aynı yöntemden kaydedilir,
//   kişinin açık onayı olmadan gönderilmez; talepten sonra merkezin WhatsApp hattı önerilir.
// ═══════════════════════════════════════════════════════════════════════════════

struct DVBGorselKalemi: Decodable, Hashable {
    let thumb: String
    let full: String
}

// MARK: - Hastane modelleri

struct DVBHastaneKarti: Decodable, Identifiable, Hashable {
    let slug: String
    let name: String
    let type: String?
    let city: String?
    let district: String?
    let summary: String?
    let doctorCount: Int?
    let logo: String?
    let cover: String?

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, name, type, city, district, summary, logo, cover
        case doctorCount = "doctor_count"
    }
}

private struct DVBHastaneDizini: Decodable {
    let groups: [Grup]
    let total: Int

    struct Grup: Decodable {
        let city: String
        let hospitals: [DVBHastaneKarti]
    }
}

struct DVBHastaneProfili: Decodable {
    let slug: String
    let name: String
    let type: String?
    let city: String?
    let district: String?
    let summary: String?
    let doctorCount: Int?
    let logo: String?
    let cover: String?
    let paragraphs: [String]?
    let address: String?
    let gallery: [DVBGorselKalemi]?
    let specialties: [Brans]
    let insurances: [String]?
    let url: String?

    struct Brans: Decodable, Identifiable, Hashable {
        let slug: String
        let name: String
        let note: String?
        let doctorCount: Int?
        var id: String { slug }

        enum CodingKeys: String, CodingKey {
            case slug, name, note
            case doctorCount = "doctor_count"
        }
    }

    enum CodingKeys: String, CodingKey {
        case slug, name, type, city, district, summary, logo, cover, paragraphs, address, gallery, specialties, insurances, url
        case doctorCount = "doctor_count"
    }
}

private struct DVBHastaneCevabi: Decodable {
    let hospital: DVBHastaneProfili
}

private struct DVBHastaneBransCevabi: Decodable {
    let specialty: Bilgi
    let data: [DVBDoctor]
    let meta: DVBDoctorPage.Meta?

    struct Bilgi: Decodable {
        let slug: String
        let name: String
        let note: String?
    }
}

// MARK: - Hastane dizini

struct DVBHastanelerView: View {
    @State private var dizin: DVBHastaneDizini?
    @State private var hata: String?

    var body: some View {
        Group {
            if let d = dizin {
                if d.groups.isEmpty {
                    DVBStateView(icon: "building.2", title: "Henüz hastane yok", message: "Hastane profilleri eklendikçe burada görünecek.")
                } else {
                    List {
                        ForEach(d.groups, id: \.city) { g in
                            Section(g.city) {
                                ForEach(g.hospitals) { h in
                                    NavigationLink(destination: DVBHastaneProfilView(slug: h.slug, ad: h.name)) {
                                        DVBHastaneSatiri(h: h)
                                    }
                                }
                            }
                        }
                    }
                    .refreshable { await yukle() }
                }
            } else if let hata {
                DVBStateView(icon: "building.2", title: "Hastaneler alınamadı", message: hata) { Task { await yukle() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Hastaneler")
        .navigationBarTitleDisplayMode(.inline)
        .task { if dizin == nil { await yukle() } }
    }

    private func yukle() async {
        do {
            dizin = try await DVBAPI.shared.get("hospitals")
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

struct DVBHastaneSatiri: View {
    let h: DVBHastaneKarti

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: h.logo ?? "")) { r in
                r.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "building.2.crop.circle").resizable().scaledToFit().foregroundColor(.secondary)
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(h.name).font(.subheadline.weight(.semibold))
                Text([h.type, h.district, h.doctorCount.map { "\($0) hekim" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundColor(.secondary)
                if let s = h.summary, !s.isEmpty { Text(s).font(.caption).lineLimit(2) }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Hastane profili

struct DVBHastaneProfilView: View {
    let slug: String
    let ad: String

    @State private var p: DVBHastaneProfili?
    @State private var hata: String?
    @State private var buyutulen: DVBGorselKalemi?

    var body: some View {
        Group {
            if let p {
                icerik(p)
            } else if let hata {
                DVBStateView(icon: "building.2", title: "Hastane bilgisi alınamadı", message: hata) { Task { await yukle() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(ad)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let u = p?.url, let url = URL(string: u) {
                    DVBPaylasDugmesi(url: url)
                }
            }
        }
        .task { if p == nil { await yukle() } }
        .sheet(item: $buyutulen) { g in DVBGorselBuyut(url: g.full) }
    }

    private func icerik(_ p: DVBHastaneProfili) -> some View {
        List {
            if let kapak = p.cover, let url = URL(string: kapak) {
                AsyncImage(url: url) { r in r.resizable().scaledToFill() } placeholder: { Color(.secondarySystemBackground) }
                    .frame(height: 170).clipped()
                    .listRowInsets(EdgeInsets())
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.name).font(.title3.bold())
                    Text([p.type, p.district, p.city].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundColor(.secondary)
                    if let a = p.address, !a.isEmpty { Text(a).font(.caption).foregroundColor(.secondary) }
                }
                .padding(.vertical, 4)
            }

            if let par = p.paragraphs, !par.isEmpty {
                Section("Hakkımızda") {
                    ForEach(Array(par.enumerated()), id: \.offset) { _, t in
                        Text(t).font(.subheadline)
                    }
                }
            }

            if !p.specialties.isEmpty {
                Section {
                    ForEach(p.specialties) { b in
                        NavigationLink(destination: DVBHastaneBransView(hastaneSlug: p.slug, hastaneAdi: p.name, brans: b)) {
                            HStack {
                                Text(b.name)
                                Spacer()
                                if let n = b.doctorCount, n > 0 {
                                    Text("\(n) hekim").font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Branşlar")
                } footer: {
                    Text("Branşa dokunun; bu branştaki hekimleri görün ve randevu alın.")
                }
            }

            if let g = p.gallery, !g.isEmpty {
                Section("Fotoğraflar") {
                    DVBGaleriSeridi(gorseller: g) { buyutulen = $0 }
                }
            }

            if let s = p.insurances, !s.isEmpty {
                Section("Anlaşmalı sigortalar") {
                    Text(s.joined(separator: " · ")).font(.subheadline)
                }
            }
        }
    }

    private func yukle() async {
        do {
            let c: DVBHastaneCevabi = try await DVBAPI.shared.get("hospitals/\(slug)")
            p = c.hospital
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

struct DVBHastaneBransView: View {
    let hastaneSlug: String
    let hastaneAdi: String
    let brans: DVBHastaneProfili.Brans

    @State private var hekimler: [DVBDoctor] = []
    @State private var not: String?
    @State private var yuklendi = false
    @State private var hata: String?

    var body: some View {
        List {
            if let not, !not.isEmpty {
                Section { Text(not).font(.subheadline) }
            }
            Section {
                if !yuklendi && hata == nil {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let hata {
                    Text(hata).foregroundColor(.red)
                } else if hekimler.isEmpty {
                    Text("Bu branşta listelenen hekim yok.").foregroundColor(.secondary)
                } else {
                    ForEach(hekimler) { d in
                        NavigationLink(destination: DVBDoctorDetailView(doctor: d)) { DVBDoctorRow(doctor: d) }
                    }
                }
            } header: {
                Text("Bu branştaki doktorlarımız")
            }
        }
        .navigationTitle(brans.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { if !yuklendi { await yukle() } }
    }

    private func yukle() async {
        do {
            let c: DVBHastaneBransCevabi = try await DVBAPI.shared.get("hospitals/\(hastaneSlug)/specialties/\(brans.slug)")
            hekimler = c.data
            not = c.specialty.note
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
        yuklendi = true
    }
}

// MARK: - Saç ekimi modelleri

struct DVBSacMerkezKarti: Decodable, Identifiable, Hashable {
    let slug: String
    let name: String
    let place: String?
    let summary: String?
    let logo: String?
    let cover: String?
    var id: String { slug }
}

private struct DVBSacEkimiSayfasi: Decodable {
    let title: String
    let image: String?
    let summary: [String]
    let faq: [SSS]
    let centers: [DVBSacMerkezKarti]

    struct SSS: Decodable, Hashable {
        let q: String
        let a: String
    }
}

struct DVBSacMerkezi: Decodable {
    let slug: String
    let name: String
    let place: String?
    let summary: String?
    let logo: String?
    let cover: String?
    let address: String?
    let founded: String?
    let paragraphs: [String]?
    let services: [Baslikli]?
    let steps: [Baslikli]?
    let highlights: [String]?
    let languages: [String]?
    let locations: [Lokasyon]?
    let gallery: [DVBGorselKalemi]?
    let instagram: String?
    let url: String?

    struct Baslikli: Decodable, Hashable {
        let title: String
        let text: String?
    }

    struct Lokasyon: Decodable, Hashable {
        let name: String
        let note: String?
    }
}

private struct DVBSacMerkezCevabi: Decodable {
    let center: DVBSacMerkezi
}

private struct DVBSacTalepCevabi: Decodable {
    let ok: Bool
    let message: String?
    let refCode: String?
    let whatsappUrl: String?

    enum CodingKeys: String, CodingKey {
        case ok, message
        case refCode = "ref_code"
        case whatsappUrl = "whatsapp_url"
    }
}

// MARK: - Saç ekimi sayfası

struct DVBSacEkimiView: View {
    @State private var sayfa: DVBSacEkimiSayfasi?
    @State private var hata: String?
    @State private var acikSoru: String?

    var body: some View {
        Group {
            if let s = sayfa {
                icerik(s)
            } else if let hata {
                DVBStateView(icon: "scissors", title: "Sayfa alınamadı", message: hata) { Task { await yukle() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Saç ekimi")
        .navigationBarTitleDisplayMode(.inline)
        .task { if sayfa == nil { await yukle() } }
    }

    private func icerik(_ s: DVBSacEkimiSayfasi) -> some View {
        List {
            if let g = s.image, let url = URL(string: g) {
                AsyncImage(url: url) { r in r.resizable().scaledToFill() } placeholder: { Color(.secondarySystemBackground) }
                    .frame(height: 180).clipped()
                    .listRowInsets(EdgeInsets())
            }

            Section {
                Text(s.title).font(.title3.bold())
                ForEach(Array(s.summary.enumerated()), id: \.offset) { _, t in
                    Text(t).font(.subheadline)
                }
            }

            Section {
                if s.centers.isEmpty {
                    Text("Henüz merkez eklenmedi.").foregroundColor(.secondary)
                } else {
                    ForEach(s.centers) { m in
                        NavigationLink(destination: DVBSacMerkeziView(slug: m.slug, ad: m.name)) {
                            HStack(spacing: 12) {
                                AsyncImage(url: URL(string: m.logo ?? "")) { r in r.resizable().scaledToFit() } placeholder: {
                                    Image(systemName: "cross.case").resizable().scaledToFit().foregroundColor(.secondary)
                                }
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(m.name).font(.subheadline.weight(.semibold))
                                    if let p = m.place { Text(p).font(.caption).foregroundColor(.secondary) }
                                    if let o = m.summary { Text(o).font(.caption).lineLimit(2) }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            } header: {
                Text("Saç ekim merkezleri")
            } footer: {
                Text("Merkezler sitemizde tanıtılan sağlık kuruluşlarıdır; sıralama bir üstünlük ifade etmez.")
            }

            Section("Sık sorulan sorular") {
                ForEach(s.faq, id: \.q) { f in
                    DisclosureGroup(isExpanded: Binding(get: { acikSoru == f.q }, set: { acikSoru = $0 ? f.q : nil })) {
                        Text(f.a).font(.subheadline).foregroundColor(.secondary)
                    } label: {
                        Text(f.q).font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .refreshable { await yukle() }
    }

    private func yukle() async {
        do {
            sayfa = try await DVBAPI.shared.get("hair-transplant")
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

// MARK: - Merkez profili + talep

struct DVBSacMerkeziView: View {
    let slug: String
    let ad: String

    @EnvironmentObject private var session: DVBSession
    @Environment(\.openURL) private var openURL
    @State private var m: DVBSacMerkezi?
    @State private var hata: String?
    @State private var talepTuru: String?
    @State private var buyutulen: DVBGorselKalemi?

    var body: some View {
        Group {
            if let m {
                icerik(m)
            } else if let hata {
                DVBStateView(icon: "cross.case", title: "Merkez bilgisi alınamadı", message: hata) { Task { await yukle() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(ad)
        .navigationBarTitleDisplayMode(.inline)
        .task { if m == nil { await yukle() } }
        .sheet(item: Binding(get: { talepTuru.map { DVBTalepTuru(tur: $0) } }, set: { talepTuru = $0?.tur })) { t in
            DVBSacTalepView(slug: slug, merkezAdi: ad, tur: t.tur)
                .environmentObject(session)
        }
        .sheet(item: $buyutulen) { g in DVBGorselBuyut(url: g.full) }
    }

    private func icerik(_ m: DVBSacMerkezi) -> some View {
        List {
            if let kapak = m.cover, let url = URL(string: kapak) {
                AsyncImage(url: url) { r in r.resizable().scaledToFill() } placeholder: { Color(.secondarySystemBackground) }
                    .frame(height: 170).clipped()
                    .listRowInsets(EdgeInsets())
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(m.name).font(.title3.bold())
                    Text([m.place, m.founded].compactMap { $0 }.joined(separator: " · ")).font(.subheadline).foregroundColor(.secondary)
                    if let s = m.summary { Text(s).font(.subheadline) }
                }
                .padding(.vertical, 4)
                Button { talepTuru = "on_gorusme" } label: {
                    Label("Ücretsiz ön görüşme talep et", systemImage: "calendar.badge.plus").font(.body.weight(.semibold))
                }
                Button { talepTuru = "fiyat" } label: {
                    Label("Fiyat bilgisi iste", systemImage: "text.bubble")
                }
            }

            if let par = m.paragraphs, !par.isEmpty {
                Section("Hakkında") {
                    ForEach(Array(par.enumerated()), id: \.offset) { _, t in Text(t).font(.subheadline) }
                }
            }
            baslikliBolum("Hizmetler", m.services)
            baslikliBolum("Süreç", m.steps)
            if let h = m.highlights, !h.isEmpty {
                Section("Öne çıkanlar") {
                    ForEach(h, id: \.self) { t in Label(t, systemImage: "checkmark.circle").font(.subheadline) }
                }
            }
            if let g = m.gallery, !g.isEmpty {
                Section("Fotoğraflar") { DVBGaleriSeridi(gorseller: g) { buyutulen = $0 } }
            }
            Section("Bilgi") {
                if let d = m.languages, !d.isEmpty { bilgi("Diller", d.joined(separator: ", ")) }
                if let a = m.address, !a.isEmpty { bilgi("Adres", a) }
                if let l = m.locations, !l.isEmpty {
                    ForEach(l, id: \.self) { k in bilgi(k.name, k.note ?? "") }
                }
                if let i = m.instagram, let url = URL(string: i) {
                    Button { openURL(url) } label: { Label("Instagram", systemImage: "camera") }
                }
            }
        }
    }

    @ViewBuilder
    private func baslikliBolum(_ baslik: String, _ kalemler: [DVBSacMerkezi.Baslikli]?) -> some View {
        if let k = kalemler, !k.isEmpty {
            Section(baslik) {
                ForEach(k, id: \.self) { x in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(x.title).font(.subheadline.weight(.semibold))
                        if let t = x.text, !t.isEmpty { Text(t).font(.caption).foregroundColor(.secondary) }
                    }
                }
            }
        }
    }

    private func bilgi(_ etiket: String, _ deger: String) -> some View {
        HStack(alignment: .top) {
            Text(etiket).foregroundColor(.secondary)
            Spacer()
            Text(deger).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func yukle() async {
        do {
            let c: DVBSacMerkezCevabi = try await DVBAPI.shared.get("hair-transplant/centers/\(slug)")
            m = c.center
            hata = nil
        } catch {
            if let mesaj = DVBError.mesaj(error) { hata = mesaj }
        }
    }
}

struct DVBTalepTuru: Identifiable {
    let tur: String
    var id: String { tur }
}

struct DVBSacTalepView: View {
    let slug: String
    let merkezAdi: String
    let tur: String

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var ad = ""
    @State private var telefon = ""
    @State private var eposta = ""
    @State private var mesaj = ""
    @State private var onay = false
    @State private var calisiyor = false
    @State private var hata: String?
    @State private var sonuc: DVBSacTalepCevabi?

    private var hazir: Bool {
        !ad.trimmingCharacters(in: .whitespaces).isEmpty && telefon.filter(\.isNumber).count >= 10 && onay
    }

    var body: some View {
        NavigationView {
            Form {
                if let s = sonuc {
                    Section {
                        Label("Talebiniz alındı", systemImage: "checkmark.seal.fill").foregroundColor(DVBTheme.accent).font(.headline)
                        Text(s.message ?? "").font(.subheadline)
                        if let w = s.whatsappUrl, let url = URL(string: w) {
                            Button { openURL(url) } label: { Label("Merkeze WhatsApp'tan yazın", systemImage: "message") }
                        }
                    }
                } else {
                    Section {
                        TextField("Ad soyad", text: $ad).textContentType(.name)
                        TextField("Telefon (05XX XXX XX XX)", text: $telefon).keyboardType(.phonePad).textContentType(.telephoneNumber)
                        TextField("E-posta (isteğe bağlı)", text: $eposta).keyboardType(.emailAddress).autocapitalization(.none).disableAutocorrection(true)
                        TextField("Mesajınız (isteğe bağlı)", text: $mesaj)
                    } header: {
                        Text(tur == "fiyat" ? "Fiyat bilgisi" : "Ücretsiz ön görüşme")
                    }
                    Section {
                        Toggle(isOn: $onay) {
                            Text("Bilgilerimin işlenmesini ve \(merkezAdi) ile paylaşılmasını onaylıyorum.").font(.footnote)
                        }
                    } footer: {
                        Text("Talebiniz Doktorum Ve Ben ekibine ve merkeze iletilir; merkez sizinle iletişime geçer.")
                    }
                    if let hata {
                        Section { Text(hata).foregroundColor(.red).font(.subheadline) }
                    }
                }
            }
            .navigationTitle("Talep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sonuc == nil ? "Vazgeç" : "Kapat") { dismiss() }
                }
                if sonuc == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task { await gonder() }
                        } label: {
                            if calisiyor { ProgressView() } else { Text("Gönder").bold() }
                        }
                        .disabled(!hazir || calisiyor)
                    }
                }
            }
            .onAppear {
                if ad.isEmpty { ad = session.user?.name ?? "" }
                if eposta.isEmpty { eposta = session.user?.email ?? "" }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func gonder() async {
        guard hazir, !calisiyor else { return }
        calisiyor = true
        defer { calisiyor = false }
        var govde: [String: Any] = [
            "tur": tur,
            "ad": ad.trimmingCharacters(in: .whitespacesAndNewlines),
            "telefon": telefon.trimmingCharacters(in: .whitespacesAndNewlines),
            "onay": true,
        ]
        let e = eposta.trimmingCharacters(in: .whitespacesAndNewlines)
        if !e.isEmpty { govde["eposta"] = e }
        let mm = mesaj.trimmingCharacters(in: .whitespacesAndNewlines)
        if !mm.isEmpty { govde["mesaj"] = mm }
        do {
            sonuc = try await DVBAPI.shared.post("hair-transplant/centers/\(slug)/request", body: govde)
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

// MARK: - Ortak parçalar

/// Yatay kaydırılan küçük resimler; dokununca büyük hâli açılır.
struct DVBGaleriSeridi: View {
    let gorseller: [DVBGorselKalemi]
    var secildi: (DVBGorselKalemi) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(gorseller, id: \.self) { g in
                    Button { secildi(g) } label: {
                        AsyncImage(url: URL(string: g.thumb)) { r in r.resizable().scaledToFill() } placeholder: { Color(.secondarySystemBackground) }
                            .frame(width: 140, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

extension DVBGorselKalemi: Identifiable {
    var id: String { full }
}

struct DVBGorselBuyut: View {
    let url: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            AsyncImage(url: URL(string: url)) { r in r.resizable().scaledToFit() } placeholder: { ProgressView() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                }
                .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}

/// iOS 15'te ShareLink yok: paylaş menüsü UIActivityViewController ile.
struct DVBPaylasDugmesi: View {
    let url: URL
    @State private var acik = false

    var body: some View {
        Button { acik = true } label: { Image(systemName: "square.and.arrow.up") }
            .accessibilityLabel("Paylaş")
            .sheet(isPresented: $acik) { DVBPaylasSayfasi(ogeler: [url]) }
    }
}

struct DVBPaylasSayfasi: UIViewControllerRepresentable {
    let ogeler: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: ogeler, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
