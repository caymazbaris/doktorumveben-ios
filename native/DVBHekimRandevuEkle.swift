import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000289 — HEKİM UYGULAMADAN RANDEVU EKLER.
//
// Kullanıcı (2 Eki 2026): "şimdi farkettim oldukça önemli 🙂 hekim randevu ekleyemiyor". Hekim modu yalnız mevcut
// randevuları gösteriyordu. Kapsam kararı: "1.3'e kat".
//
// Kurallar SUNUCUDA, web takviminden eklemeyle aynı yol (HekimRandevuEkleApiController → BookingService::book):
// boş saatler randevu sayfasının motorundan gelir; dış takvim (Google/Outlook) doluysa sunucu 409 ile sorar, hekim
// onaylarsa `busy_override` ile eklenir; ekipte sağlayıcı zorunlu; muhasebe görünümü ekleyemez (düğme de çıkmaz).
// ═══════════════════════════════════════════════════════════════════════════════

struct DVBRandevuSecenekleri: Decodable {
    let services: [Hizmet]
    let team: Bool
    let providers: [Saglayici]
    let ownProviderId: Int?

    struct Hizmet: Decodable, Identifiable {
        let id: Int
        let name: String
        let durationMinutes: Int
        let channel: String?

        enum CodingKeys: String, CodingKey {
            case id, name, channel
            case durationMinutes = "duration_minutes"
        }
    }

    struct Saglayici: Decodable, Identifiable {
        let id: Int
        let name: String
    }

    enum CodingKeys: String, CodingKey {
        case services, team, providers
        case ownProviderId = "own_provider_id"
    }

    /// Ekipte randevu bir sağlayıcıya bağlanır; sağlayıcının kendi girişinde sunucu kendisini yazar (seçim yok).
    var saglayiciSecilmeli: Bool { team && ownProviderId == nil }
}

private struct DVBRandevuSaatleri: Decodable {
    let slots: [String]
}

private struct DVBRandevuEkleCevabi: Decodable {
    let message: String?
}

/// Hasta arama sonucu (Hastalar sekmesiyle aynı uç; sayfa bilgisi burada gerekmiyor).
private struct DVBRandevuHastaSonuclari: Decodable {
    let data: [DVBHekimHastaOzet]
}

private func kirp(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

struct DVBHekimRandevuEkleView: View {
    /// Randevu eklenince ajanda o güne geçip yenilenir.
    let eklendi: (Date) -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss

    private enum HastaTuru: Hashable { case kayitli, yeni }

    @State private var secenekler: DVBRandevuSecenekleri?
    @State private var secenekHatasi: String?

    @State private var hastaTuru: HastaTuru = .kayitli
    @State private var hastaArama = ""
    @State private var hastaSonuclari: [DVBHekimHastaOzet] = []
    @State private var seciliHasta: DVBHekimHastaOzet?
    @State private var ad = ""
    @State private var soyad = ""
    @State private var telefon = ""
    @State private var eposta = ""

    @State private var hizmetId: Int?
    @State private var saglayiciId: Int?
    @State private var gun: Date
    @State private var saatler: [String] = []
    @State private var saatlerYukleniyor = false
    @State private var saatHatasi: String?
    @State private var seciliSaat: String?
    @State private var elleSaat = false
    @State private var elleSaatDegeri: Date

    @State private var not = ""
    @State private var gondermeBildirim = false
    @State private var gondermeHatirlatma = false
    @State private var gondermeYorum = false

    @State private var kaydediliyor = false
    @State private var hata: String?
    @State private var disTakvimUyarisi: String?
    @State private var sonuc: String?

    private let bugun = DVBSaat.takvim.startOfDay(for: Date())

    init(gun baslangic: Date, eklendi: @escaping (Date) -> Void) {
        self.eklendi = eklendi
        let bugun = DVBSaat.takvim.startOfDay(for: Date())
        let g = max(DVBSaat.takvim.startOfDay(for: baslangic), bugun)
        _gun = State(initialValue: g)
        _elleSaatDegeri = State(initialValue: DVBSaat.takvim.date(bySettingHour: 9, minute: 0, second: 0, of: g) ?? g)
    }

    /// Kayıtlı hasta seçimi Hastalar özelliğine bağlı (muhasebe/kapalı pakette hasta listesi yok → yalnız yeni hasta).
    private var kayitliHastaAcik: Bool { session.hekim?.hastalarAcik ?? false }

    var body: some View {
        NavigationView {
            Group {
                if let s = secenekler {
                    form(s)
                } else if let secenekHatasi {
                    DVBStateView(icon: "calendar.badge.exclamationmark", title: "Form açılamadı", message: secenekHatasi) {
                        Task { await secenekleriYukle() }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Yeni randevu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if kaydediliyor {
                        ProgressView()
                    } else {
                        Button("Kaydet") { Task { await kaydet() } }.disabled(!kaydedilebilir)
                    }
                }
            }
            .alert("Dış takviminiz dolu", isPresented: Binding(get: { disTakvimUyarisi != nil }, set: { if !$0 { disTakvimUyarisi = nil } })) {
                Button("Yine de ekle") { Task { await kaydet(disTakvimOnayli: true) } }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text(disTakvimUyarisi ?? "")
            }
            .task { await secenekleriYukle() }
        }
        .navigationViewStyle(.stack)
        // İkinci uyarı ayrı görünümde (aynı görünüme iki `alert` eski iOS'ta birini susturuyordu).
        .alert("Randevu eklendi", isPresented: Binding(get: { sonuc != nil }, set: { if !$0 { sonuc = nil } })) {
            Button("Tamam") { dismiss() }
        } message: {
            Text(sonuc ?? "")
        }
    }

    // MARK: - Form

    private func form(_ s: DVBRandevuSecenekleri) -> some View {
        Form {
            hastaBolumu

            Section("Hizmet") {
                if s.services.isEmpty {
                    Text("Randevuya açık hizmetiniz yok. Hizmetlerinizi web panelinden ekleyebilirsiniz.")
                        .font(.footnote).foregroundColor(.secondary)
                } else {
                    Picker("Hizmet", selection: $hizmetId) {
                        Text("Seçin").tag(Int?.none)
                        ForEach(s.services) { h in
                            Text("\(h.name) · \(h.durationMinutes) dk\(h.channel == "online" ? " · online" : "")").tag(Int?.some(h.id))
                        }
                    }
                }
                if s.saglayiciSecilmeli {
                    Picker("Sağlayıcı", selection: $saglayiciId) {
                        Text("Seçin").tag(Int?.none)
                        ForEach(s.providers) { p in Text(p.name).tag(Int?.some(p.id)) }
                    }
                }
            }

            Section {
                DatePicker("Gün", selection: $gun, in: bugun..., displayedComponents: .date)
                    .environment(\.timeZone, DVBTime.klinik)
                    .environment(\.locale, Locale(identifier: "tr_TR"))
                    // Kullanıcı (5 Eki 2026): "tarih seçerken takvimde tarihe bastığımda takvim kapanmıyor kapansa daha
                    // kullanışlı olabilir". iOS'un açılır takvimi seçimde kendiliğinden kapanmaz; kimlik seçilen güne
                    // bağlanınca gün değişince seçici yeniden kurulur ve açılır takvim kapanır (ay değiştirmek kapatmaz).
                    .id(gun)
                if !elleSaat { saatSecimi(s) }
                Toggle("Saati elle gir", isOn: $elleSaat)
                if elleSaat {
                    DatePicker("Saat", selection: $elleSaatDegeri, displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, DVBTime.klinik)
                        .environment(\.locale, Locale(identifier: "tr_TR"))
                }
            } header: {
                Text("Tarih ve saat")
            } footer: {
                if elleSaat {
                    Text("Elle girilen saat boş saat listesinde olmasa da eklenir; çakışmayı siz kontrol edin.")
                }
            }

            Section("Not (isteğe bağlı)") {
                TextField("Hastaya görünmeyen iç not", text: $not)
            }

            Section {
                Toggle("Hiçbir bildirim gönderilmesin", isOn: $gondermeBildirim)
                if !gondermeBildirim {
                    Toggle("Randevu hatırlatması gönderilmesin", isOn: $gondermeHatirlatma)
                    Toggle("Yorum/anket isteği gönderilmesin", isOn: $gondermeYorum)
                }
            } header: {
                Text("Bu hasta için")
            } footer: {
                Text("İşaretlediğiniz seçim bu hastanın sonraki randevularında da geçerli olur; hasta kartından kaldırılır.")
            }

            if let hata {
                Section { Text(hata).font(.footnote).foregroundColor(.red) }
            }
        }
        .task(id: saatAnahtari) { await saatleriYukle() }
        .task(id: hastaArama) { await hastaAra() }
    }

    @ViewBuilder
    private var hastaBolumu: some View {
        Section("Hasta") {
            if kayitliHastaAcik {
                Picker("Hasta", selection: $hastaTuru) {
                    Text("Kayıtlı hasta").tag(HastaTuru.kayitli)
                    Text("Yeni hasta").tag(HastaTuru.yeni)
                }
                .pickerStyle(.segmented)
            }
            if kayitliHastaAcik && hastaTuru == .kayitli {
                if let h = seciliHasta {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.name ?? "—").font(.subheadline.weight(.semibold))
                            Text([h.patientNo, h.phone].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Değiştir") { seciliHasta = nil }.buttonStyle(.borderless)
                    }
                } else {
                    TextField("Ad, telefon veya hasta no", text: $hastaArama)
                        .autocorrectionDisabled()
                    ForEach(hastaSonuclari) { h in
                        Button {
                            seciliHasta = h
                            hastaArama = ""
                            hastaSonuclari = []
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(h.name ?? "—").foregroundColor(.primary)
                                Text([h.patientNo, h.phone].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    if kirp(hastaArama).count >= 2 && hastaSonuclari.isEmpty {
                        Text("Eşleşen hasta yok. Yeni hasta olarak ekleyebilirsiniz.").font(.footnote).foregroundColor(.secondary)
                    }
                }
            } else {
                TextField("Ad", text: $ad).textContentType(.givenName)
                TextField("Soyad", text: $soyad).textContentType(.familyName)
                TextField("Cep telefonu", text: $telefon).keyboardType(.phonePad).textContentType(.telephoneNumber)
                TextField("E-posta (isteğe bağlı)", text: $eposta)
                    .keyboardType(.emailAddress).textContentType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
        }
    }

    @ViewBuilder
    private func saatSecimi(_ s: DVBRandevuSecenekleri) -> some View {
        if hizmetId == nil {
            Text("Boş saatleri görmek için hizmet seçin.").font(.footnote).foregroundColor(.secondary)
        } else if s.saglayiciSecilmeli && saglayiciId == nil {
            Text("Boş saatleri görmek için sağlayıcı seçin.").font(.footnote).foregroundColor(.secondary)
        } else if saatlerYukleniyor {
            ProgressView().frame(maxWidth: .infinity)
        } else if let saatHatasi {
            Text(saatHatasi).font(.footnote).foregroundColor(.red)
        } else if saatler.isEmpty {
            Text("Bu gün için boş saat yok. Başka gün seçin ya da saati elle girin.").font(.footnote).foregroundColor(.secondary)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                ForEach(saatler, id: \.self) { saat in
                    let secili = seciliSaat == saat
                    Button { seciliSaat = saat } label: {
                        Text(saat).font(.subheadline.monospacedDigit())
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(secili ? DVBTheme.brand : Color(.secondarySystemBackground))
                            .foregroundColor(secili ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityAddTraits(secili ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Durum

    private var saatAnahtari: String { "\(DVBSaat.anahtar(gun))|\(hizmetId ?? 0)|\(saglayiciId ?? 0)" }

    /// Sunucu `starts_at`'i uygulama saat diliminde (Türkiye) okur: "2026-10-03 14:30".
    private var baslangic: String? {
        if elleSaat { return "\(DVBSaat.anahtar(gun)) \(DVBSaat.gun(elleSaatDegeri, "HH:mm"))" }
        guard let seciliSaat else { return nil }
        return "\(DVBSaat.anahtar(gun)) \(seciliSaat)"
    }

    private var hastaHazir: Bool {
        if kayitliHastaAcik && hastaTuru == .kayitli { return seciliHasta != nil }
        return !kirp(ad).isEmpty && !kirp(soyad).isEmpty && telefon.filter(\.isNumber).count >= 10
    }

    private var kaydedilebilir: Bool {
        guard let s = secenekler, hizmetId != nil, baslangic != nil, hastaHazir else { return false }
        return !s.saglayiciSecilmeli || saglayiciId != nil
    }

    // MARK: - Ağ

    private func secenekleriYukle() async {
        guard let token = session.token else { return }
        do {
            let s: DVBRandevuSecenekleri = try await DVBAPI.shared.get("my/doctor/booking-options", token: token)
            secenekler = s
            secenekHatasi = nil
            // Tek hizmet / tek sağlayıcı varsa seçili gelsin.
            if hizmetId == nil, s.services.count == 1 { hizmetId = s.services.first?.id }
            if saglayiciId == nil, s.saglayiciSecilmeli, s.providers.count == 1 { saglayiciId = s.providers.first?.id }
            if !kayitliHastaAcik { hastaTuru = .yeni }
        } catch {
            if let m = DVBError.mesaj(error) { secenekHatasi = m }
        }
    }

    private func saatleriYukle() async {
        seciliSaat = nil
        guard let token = session.token, let s = secenekler, let hizmetId,
              !s.saglayiciSecilmeli || saglayiciId != nil else { saatler = []; return }
        saatlerYukleniyor = true
        defer { saatlerYukleniyor = false }
        var q = ["date": DVBSaat.anahtar(gun), "service_id": String(hizmetId)]
        if let saglayiciId { q["staff_id"] = String(saglayiciId) }
        do {
            let c: DVBRandevuSaatleri = try await DVBAPI.shared.get("my/doctor/booking-slots", query: q, token: token)
            saatler = c.slots
            saatHatasi = nil
        } catch {
            guard let m = DVBError.mesaj(error) else { return }
            saatler = []
            saatHatasi = m
        }
    }

    /// Yazarken her harfte istek atılmasın: 350 ms bekle; yeni harf gelirse önceki görev iptal olur.
    private func hastaAra() async {
        let q = kirp(hastaArama)
        guard q.count >= 2, let token = session.token else { hastaSonuclari = []; return }
        try? await Task.sleep(nanoseconds: 350_000_000)
        if Task.isCancelled { return }
        do {
            let c: DVBRandevuHastaSonuclari = try await DVBAPI.shared.get("my/doctor/patients", query: ["q": q], token: token)
            hastaSonuclari = Array(c.data.prefix(8))
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func kaydet(disTakvimOnayli: Bool = false) async {
        guard kaydedilebilir, !kaydediliyor, let token = session.token, let hizmetId, let baslangic else { return }
        kaydediliyor = true
        defer { kaydediliyor = false }

        var govde: [String: Any] = ["starts_at": baslangic, "service_id": hizmetId]
        if kayitliHastaAcik && hastaTuru == .kayitli, let h = seciliHasta {
            govde["patient_id"] = h.id
        } else {
            govde["first_name"] = kirp(ad)
            govde["last_name"] = kirp(soyad)
            govde["phone"] = kirp(telefon)
            if !kirp(eposta).isEmpty { govde["email"] = kirp(eposta) }
        }
        if let saglayiciId { govde["staff_id"] = saglayiciId }
        if !kirp(not).isEmpty { govde["notes"] = kirp(not) }
        // Alan adları web formuyla aynı (HastaBildirimTercihi::FORM_ALANLARI).
        if gondermeBildirim { govde["gonderme_bildirim"] = true }
        if gondermeHatirlatma && !gondermeBildirim { govde["gonderme_hatirlatma"] = true }
        if gondermeYorum && !gondermeBildirim { govde["gonderme_yorum_istegi"] = true }
        if disTakvimOnayli { govde["busy_override"] = true }

        do {
            let c: DVBRandevuEkleCevabi = try await DVBAPI.shared.post("my/doctor/appointments", body: govde, token: token)
            hata = nil
            eklendi(gun)
            await session.hekimiYukle()
            sonuc = c.message ?? "Randevu oluşturuldu."
        } catch let DVBError.server(kod, mesaj) where kod == 409 {
            disTakvimUyarisi = mesaj ?? "Bu saat dış takviminizde dolu görünüyor. Yine de eklemek ister misiniz?"
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}
