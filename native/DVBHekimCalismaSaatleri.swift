import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000341 — ÇALIŞMA SAATLERİ VE İZİNLER (hekim).
//
// Kullanıcı (8 Eki 2026): "3 günlük işleri de yapalm" (hasta talepleri, çalışma saatleri ve izinler, hizmetler, randevu taşıma).
//
// Web /panel/calisma-saatleri ile AYNI kurallar (HekimIsleriApiController): haftalık saatler bir bütün olarak kaydedilir
// (kapsam silinip yeniden yazılır); gün başına en çok iki blok (öğle arası). Hatalı blok varsa sunucu HİÇBİR ŞEY yazmaz ve
// nedenini söyler. Ekipte saf sağlayıcı yalnız kendi saatlerini, sahip/sekreter seçtiği sağlayıcınınkini düzenler.
// İzinler: tam gün ya da saat aralığı; geçmiş güne izin eklenmez. Dış takvimden gelen dolu saatler burada listelenmez.
// ═══════════════════════════════════════════════════════════════════════════════

struct DVBCalismaSaatleri: Decodable {
    let staffId: Int?
    let providers: [DVBTakvimDurumu.Saglayici]?
    let days: [Gun]
    let exceptions: [Izin]

    struct Gun: Decodable {
        let weekday: Int
        let name: String
        let enabled: Bool
        let blocks: [Blok]
        let slot: Int?
    }

    struct Blok: Decodable {
        let start: String
        let end: String
    }

    struct Izin: Decodable, Identifiable {
        let id: Int
        let date: String?
        let fullDay: Bool
        let startTime: String?
        let endTime: String?
        let reason: String?

        enum CodingKeys: String, CodingKey {
            case id, date, reason
            case fullDay = "full_day"
            case startTime = "start_time"
            case endTime = "end_time"
        }
    }

    enum CodingKeys: String, CodingKey {
        case providers, days, exceptions
        case staffId = "staff_id"
    }
}

private struct DVBSaatIslemCevabi: Decodable {
    let ok: Bool
    let message: String?
}

/// Ekranda düzenlenen gün (saatler klinik saat diliminde Date olarak tutulur; sunucuya "HH:mm" gider).
private struct DVBDuzenGun: Identifiable {
    let weekday: Int
    let name: String
    var enabled: Bool
    var bas: Date
    var bit: Date
    var ogleArasi: Bool
    var bas2: Date
    var bit2: Date
    var slot: Int
    var id: Int { weekday }
}

enum DVBSaatCevir {
    /// "09:30" → klinik saat diliminde sabit bir günün 09:30'u (DatePicker yalnız saat/dakikayı gösterir).
    static func tarih(_ hhmm: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = DVBTime.klinik
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: "2026-01-05 " + hhmm) ?? Date()
    }

    static func metin(_ d: Date) -> String { DVBSaat.gun(d, "HH:mm") }
}

struct DVBHekimCalismaSaatleriView: View {
    @EnvironmentObject private var session: DVBSession

    @State private var veri: DVBCalismaSaatleri?
    @State private var gunler: [DVBDuzenGun] = []
    @State private var saglayiciId: Int?
    @State private var hata: String?
    @State private var bilgi: String?
    @State private var kaydediliyor = false
    @State private var degisti = false
    @State private var izinAcik = false
    @State private var silinecekIzin: DVBCalismaSaatleri.Izin?

    var body: some View {
        Group {
            if let v = veri {
                form(v)
            } else if let hata {
                DVBStateView(icon: "clock.badge.exclamationmark", title: "Çalışma saatleri alınamadı", message: hata) {
                    Task { await yukle() }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Çalışma saatleri")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await kaydet() }
                } label: {
                    if kaydediliyor { ProgressView() } else { Text("Kaydet").bold() }
                }
                .disabled(!degisti || kaydediliyor || veri == nil)
            }
        }
        .task { await yukle() }
        .alert("Çalışma saatleri", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(bilgi ?? "")
        }
        .confirmationDialog(
            "İzin kaldırılsın mı?",
            isPresented: Binding(get: { silinecekIzin != nil }, set: { if !$0 { silinecekIzin = nil } }),
            titleVisibility: .visible
        ) {
            Button("İzni kaldır", role: .destructive) {
                if let i = silinecekIzin { Task { await izinSil(i.id) } }
                silinecekIzin = nil
            }
            Button("Vazgeç", role: .cancel) { silinecekIzin = nil }
        }
        .sheet(isPresented: $izinAcik) {
            DVBIzinEkleView(saglayiciId: saglayiciId) { m in
                bilgi = m
                Task { await yukle() }
            }
            .environmentObject(session)
        }
    }

    private func form(_ v: DVBCalismaSaatleri) -> some View {
        Form {
            if let saglayicilar = v.providers, !saglayicilar.isEmpty {
                Section {
                    Picker("Sağlayıcı", selection: $saglayiciId) {
                        ForEach(saglayicilar) { p in Text(p.name).tag(Int?.some(p.id)) }
                    }
                    .onChange(of: saglayiciId) { _ in Task { await yukle() } }
                } footer: {
                    Text("Seçtiğiniz sağlayıcının saatleri düzenlenir.")
                }
            }

            ForEach($gunler) { $g in
                Section {
                    Toggle(g.name, isOn: $g.enabled.degisince { degisti = true })
                    if g.enabled {
                        DatePicker("Başlangıç", selection: $g.bas.degisince { degisti = true }, displayedComponents: .hourAndMinute)
                            .environment(\.timeZone, DVBTime.klinik)
                        DatePicker("Bitiş", selection: $g.bit.degisince { degisti = true }, displayedComponents: .hourAndMinute)
                            .environment(\.timeZone, DVBTime.klinik)
                        Toggle("Öğle arası var", isOn: $g.ogleArasi.degisince { degisti = true })
                        if g.ogleArasi {
                            DatePicker("Öğleden sonra başlangıç", selection: $g.bas2.degisince { degisti = true }, displayedComponents: .hourAndMinute)
                                .environment(\.timeZone, DVBTime.klinik)
                            DatePicker("Öğleden sonra bitiş", selection: $g.bit2.degisince { degisti = true }, displayedComponents: .hourAndMinute)
                                .environment(\.timeZone, DVBTime.klinik)
                        }
                        Stepper("Randevu aralığı: \(g.slot) dk", value: $g.slot.degisince { degisti = true }, in: 5...240, step: 5)
                    }
                }
            }

            Section {
                if v.exceptions.isEmpty {
                    Text("Yaklaşan izin yok.").foregroundColor(.secondary)
                } else {
                    ForEach(v.exceptions) { i in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(izinGunu(i)).font(.subheadline.weight(.semibold))
                                Text(izinAraligi(i)).font(.caption).foregroundColor(.secondary)
                                if let n = i.reason, !n.isEmpty { Text(n).font(.caption) }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                silinecekIzin = i
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("İzni kaldır")
                        }
                    }
                }
                Button {
                    izinAcik = true
                } label: {
                    Label("İzin / kapalı gün ekle", systemImage: "calendar.badge.minus")
                }
            } header: {
                Text("İzinler ve kapalı günler")
            } footer: {
                Text("İzinli saatlerde randevu alınamaz. Mevcut randevular kendiliğinden iptal edilmez.")
            }
        }
    }

    private func izinGunu(_ i: DVBCalismaSaatleri.Izin) -> String {
        guard let g = i.date else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = DVBTime.klinik
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: g) else { return g }
        return DVBSaat.gun(d, "d MMMM yyyy EEEE")
    }

    private func izinAraligi(_ i: DVBCalismaSaatleri.Izin) -> String {
        if i.fullDay { return "Tam gün" }
        return (i.startTime ?? "?") + "–" + (i.endTime ?? "?")
    }

    // MARK: - Ağ

    private func yukle() async {
        guard let token = session.token else { return }
        var q: [String: String] = [:]
        if let saglayiciId { q["staff_id"] = String(saglayiciId) }
        do {
            let v: DVBCalismaSaatleri = try await DVBAPI.shared.get("my/doctor/schedule", query: q, token: token)
            veri = v
            if saglayiciId == nil { saglayiciId = v.staffId }
            gunler = v.days.map { g in
                let b1 = g.blocks.first
                let b2 = g.blocks.count > 1 ? g.blocks[1] : nil
                return DVBDuzenGun(
                    weekday: g.weekday, name: g.name, enabled: g.enabled,
                    bas: DVBSaatCevir.tarih(b1?.start ?? "09:00"),
                    bit: DVBSaatCevir.tarih(b1?.end ?? "17:00"),
                    ogleArasi: b2 != nil,
                    bas2: DVBSaatCevir.tarih(b2?.start ?? "13:00"),
                    bit2: DVBSaatCevir.tarih(b2?.end ?? "17:00"),
                    slot: g.slot ?? 20
                )
            }
            degisti = false
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func kaydet() async {
        guard let token = session.token, !kaydediliyor else { return }
        kaydediliyor = true
        defer { kaydediliyor = false }
        let gunListesi: [[String: Any]] = gunler.map { g in
            var bloklar: [[String: String]] = [["start": DVBSaatCevir.metin(g.bas), "end": DVBSaatCevir.metin(g.bit)]]
            if g.ogleArasi {
                bloklar.append(["start": DVBSaatCevir.metin(g.bas2), "end": DVBSaatCevir.metin(g.bit2)])
            }
            return ["weekday": g.weekday, "enabled": g.enabled, "slot": g.slot, "blocks": g.enabled ? bloklar : []]
        }
        var govde: [String: Any] = ["days": gunListesi]
        if let saglayiciId { govde["staff_id"] = saglayiciId }
        do {
            let c: DVBSaatIslemCevabi = try await DVBAPI.shared.put("my/doctor/schedule", body: govde, token: token)
            bilgi = c.message ?? "Çalışma saatleri güncellendi."
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }

    private func izinSil(_ id: Int) async {
        guard let token = session.token else { return }
        do {
            let c: DVBSaatIslemCevabi = try await DVBAPI.shared.delete("my/doctor/schedule/exceptions/\(id)", token: token)
            bilgi = c.message ?? "İzin kaldırıldı."
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }
}

// MARK: - İzin ekleme

struct DVBIzinEkleView: View {
    let saglayiciId: Int?
    var eklendi: (String) -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss

    @State private var gun = Date()
    @State private var tamGun = true
    @State private var bas = DVBSaatCevir.tarih("09:00")
    @State private var bit = DVBSaatCevir.tarih("12:00")
    @State private var neden = ""
    @State private var calisiyor = false
    @State private var hata: String?

    private var bugun: Date { Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    DatePicker("Gün", selection: $gun, in: bugun..., displayedComponents: .date)
                        .environment(\.timeZone, DVBTime.klinik)
                        .environment(\.locale, Locale(identifier: "tr_TR"))
                        .id(gun)
                    Toggle("Tam gün", isOn: $tamGun)
                    if !tamGun {
                        DatePicker("Başlangıç", selection: $bas, displayedComponents: .hourAndMinute)
                            .environment(\.timeZone, DVBTime.klinik)
                        DatePicker("Bitiş", selection: $bit, displayedComponents: .hourAndMinute)
                            .environment(\.timeZone, DVBTime.klinik)
                    }
                    TextField("Neden (isteğe bağlı, ör. Kongre)", text: $neden)
                }

                if let hata {
                    Section { Text(hata).foregroundColor(.red).font(.subheadline) }
                }
            }
            .navigationTitle("İzin ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await ekle() }
                    } label: {
                        if calisiyor { ProgressView() } else { Text("Ekle").bold() }
                    }
                    .disabled(calisiyor)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func ekle() async {
        guard let token = session.token, !calisiyor else { return }
        calisiyor = true
        defer { calisiyor = false }
        var govde: [String: Any] = ["date": DVBSaat.anahtar(gun), "full_day": tamGun]
        if !tamGun {
            govde["start_time"] = DVBSaatCevir.metin(bas)
            govde["end_time"] = DVBSaatCevir.metin(bit)
        }
        let temiz = neden.trimmingCharacters(in: .whitespacesAndNewlines)
        if !temiz.isEmpty { govde["reason"] = temiz }
        if let saglayiciId { govde["staff_id"] = saglayiciId }
        do {
            let c: DVBSaatIslemCevabi = try await DVBAPI.shared.post("my/doctor/schedule/exceptions", body: govde, token: token)
            eklendi(c.message ?? "İzin eklendi.")
            dismiss()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

// MARK: - Bağlama yardımcısı

extension Binding {
    /// Değer değişince yan etki (ör. "kaydedilmemiş değişiklik var" işareti). iOS 15'te `onChange` her satıra ayrı ayrı
    /// bağlanamadığı için bağlamanın kendisine eklenir.
    func degisince(_ yap: @escaping () -> Void) -> Binding<Value> {
        Binding(get: { wrappedValue }, set: { yeni in
            wrappedValue = yeni
            yap()
        })
    }
}
