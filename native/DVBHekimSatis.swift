import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000345 — SATIŞ ADAYLARI (lead) ve SEKRETER YETKİLERİ.
//
// Kullanıcı (9 Eki 2026): "eksik kalan ne varsa app de yap en son derle ve son sürüm olarak gönder".
//
// Kurallar sunucuda (HekimSatisApiController — web LeadController / SecretaryController ile aynı). Sekreter yetkilerini
// yalnız hekimin kendisi değiştirir; verilebilen alanlar sunucudan gelir.
// ═══════════════════════════════════════════════════════════════════════════════

struct DVBAdayKarti: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let phone: String?
    let source: String?
    let sourceLabel: String?
    let interest: String?
    let estimatedValue: Double?
    let status: String?
    let stageId: Int?
    let stage: String?
    let assignee: String?
    let nextFollowUpAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, phone, source, interest, status, stage, assignee
        case sourceLabel = "source_label"
        case estimatedValue = "estimated_value"
        case stageId = "stage_id"
        case nextFollowUpAt = "next_follow_up_at"
    }
}

struct DVBSatisSecenek: Decodable, Hashable {
    let key: String
    let label: String
}

private struct DVBSatisVerisi: Decodable {
    let summary: Ozet
    let stages: [Asama]
    let sources: [DVBSatisSecenek]
    let activityTypes: [DVBSatisSecenek]
    let assignees: [Kisi]

    struct Ozet: Decodable {
        let open: Int
        let won: Int
        let lost: Int
        let pipelineValue: Double
        let wonValue: Double
        let conversion: Double

        enum CodingKeys: String, CodingKey {
            case open, won, lost, conversion
            case pipelineValue = "pipeline_value"
            case wonValue = "won_value"
        }
    }

    struct Asama: Decodable, Identifiable, Hashable {
        let id: Int
        let name: String
        let isWon: Bool
        let isLost: Bool
        let leads: [DVBAdayKarti]

        enum CodingKeys: String, CodingKey {
            case id, name, leads
            case isWon = "is_won"
            case isLost = "is_lost"
        }
    }

    struct Kisi: Decodable, Identifiable, Hashable {
        let id: Int
        let name: String
    }

    enum CodingKeys: String, CodingKey {
        case summary, stages, sources, assignees
        case activityTypes = "activity_types"
    }
}

struct DVBSatisAdaylariView: View {
    @EnvironmentObject private var session: DVBSession
    @State private var veri: DVBSatisVerisi?
    @State private var hata: String?
    @State private var bilgi: String?
    @State private var yeniAcik = false

    var body: some View {
        Group {
            if let v = veri {
                List {
                    Section {
                        HStack {
                            ozet("Açık", "\(v.summary.open)")
                            Spacer()
                            ozet("Kazanılan", "\(v.summary.won)")
                            Spacer()
                            ozet("Dönüşüm", "%" + DVBSayi.yaz(v.summary.conversion))
                        }
                        HStack {
                            Text("Açık fırsat değeri").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text(DVBPara.bicim(v.summary.pipelineValue)).font(.caption.monospacedDigit())
                        }
                    } footer: {
                        Text("Kazanılan ve dönüşüm bu ayın değerleridir.")
                    }
                    ForEach(v.stages) { a in
                        Section {
                            if a.leads.isEmpty { Text("Aday yok").font(.caption).foregroundColor(.secondary) }
                            ForEach(a.leads) { l in
                                NavigationLink(destination: DVBAdayAyrintiView(adayId: l.id, ad: l.name, asamalar: v.stages, turler: v.activityTypes,
                                                                                kaynaklar: v.sources, kisiler: v.assignees) { Task { await yukle() } }) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(l.name).font(.subheadline.weight(.semibold))
                                        Text(DVBAdayMetni.alt(l)).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        } header: {
                            Text("\(a.name) (\(a.leads.count))")
                        }
                    }
                }
                .refreshable { await yukle() }
            } else if let hata {
                DVBStateView(icon: "person.crop.circle.badge.plus", title: "Adaylar alınamadı", message: hata) { Task { await yukle() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Satış adayları")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { yeniAcik = true } label: { Label("Aday ekle", systemImage: "plus") }.disabled(veri == nil) }
        }
        .task { await yukle() }
        .alert("Satış adayları", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(bilgi ?? "") }
        .sheet(isPresented: $yeniAcik) {
            DVBAdayFormView(aday: nil, kaynaklar: veri?.sources ?? [], kisiler: veri?.assignees ?? []) { m in bilgi = m; Task { await yukle() } }
                .environmentObject(session)
        }
    }

    private func ozet(_ e: String, _ d: String) -> some View {
        VStack(alignment: .leading) {
            Text(e).font(.caption2).foregroundColor(.secondary)
            Text(d).font(.headline.monospacedDigit())
        }
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            veri = try await DVBAPI.shared.get("my/doctor/leads", token: token)
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

private enum DVBAdayMetni {
    static func alt(_ l: DVBAdayKarti) -> String {
        var p: [String] = []
        if let k = l.sourceLabel { p.append(k) }
        if let i = l.interest, !i.isEmpty { p.append(i) }
        if let v = l.estimatedValue, v > 0 { p.append(DVBPara.bicim(v)) }
        if let t = l.nextFollowUpAt { p.append("takip " + DVBSaat.gun(t, "d MMM")) }
        return p.joined(separator: " · ")
    }
}

private struct DVBAdayAyrintisi: Decodable {
    let lead: Aday
    let activities: [Aktivite]

    struct Aday: Decodable {
        let id: Int
        let name: String
        let phone: String?
        let source: String?
        let sourceLabel: String?
        let interest: String?
        let estimatedValue: Double?
        let status: String?
        let stageId: Int?
        let stage: String?
        let assignee: String?
        let nextFollowUpAt: Date?
        let email: String?
        let notes: String?
        let patient: String?
        let lostReason: String?
        let assignedTo: Int?

        enum CodingKeys: String, CodingKey {
            case id, name, phone, source, interest, status, stage, assignee, email, notes, patient
            case sourceLabel = "source_label"
            case estimatedValue = "estimated_value"
            case stageId = "stage_id"
            case nextFollowUpAt = "next_follow_up_at"
            case lostReason = "lost_reason"
            case assignedTo = "assigned_to"
        }

        var kart: DVBAdayKarti {
            DVBAdayKarti(id: id, name: name, phone: phone, source: source, sourceLabel: sourceLabel, interest: interest, estimatedValue: estimatedValue,
                         status: status, stageId: stageId, stage: stage, assignee: assignee, nextFollowUpAt: nextFollowUpAt)
        }
    }

    struct Aktivite: Decodable, Hashable {
        let type: String
        let content: String?
        let by: String?
        let occurredAt: Date?

        enum CodingKeys: String, CodingKey {
            case type, content, by
            case occurredAt = "occurred_at"
        }
    }
}

private struct DVBAdayAyrintiView: View {
    let adayId: Int
    let ad: String
    let asamalar: [DVBSatisVerisi.Asama]
    let turler: [DVBSatisSecenek]
    let kaynaklar: [DVBSatisSecenek]
    let kisiler: [DVBSatisVerisi.Kisi]
    var degisti: () -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.openURL) private var openURL
    @State private var a: DVBAdayAyrintisi?
    @State private var hata: String?
    @State private var bilgi: String?
    @State private var aktiviteTuru = "call"
    @State private var aktiviteMetni = ""
    @State private var duzenleAcik = false
    @State private var cevirOnayi = false
    @State private var kayipAcik = false
    @State private var kayipNedeni = ""

    var body: some View {
        Group {
            if let a {
                List {
                    Section {
                        if let t = a.lead.phone, !t.isEmpty {
                            HStack(spacing: 16) {
                                Button { if let u = URL(string: "tel:\(t.filter(\.isNumber))") { openURL(u) } } label: { Label("Ara", systemImage: "phone") }
                                Button { if let u = URL(string: "https://wa.me/\(DVBAdayTelefon.wa(t))") { openURL(u) } } label: { Label("WhatsApp", systemImage: "message") }
                            }
                            .buttonStyle(.borderless)
                        }
                        bilgiSatiri("Kaynak", a.lead.sourceLabel)
                        bilgiSatiri("İlgi", a.lead.interest)
                        bilgiSatiri("E-posta", a.lead.email)
                        bilgiSatiri("Sorumlu", a.lead.assignee)
                        bilgiSatiri("Hasta kaydı", a.lead.patient)
                        bilgiSatiri("Kayıp nedeni", a.lead.lostReason)
                        if let n = a.lead.notes, !n.isEmpty { Text(n).font(.caption) }
                    }
                    Section("Aşama") {
                        Picker("Aşama", selection: Binding(get: { a.lead.stageId ?? 0 }, set: { yeni in Task { await asamaDegistir(yeni) } })) {
                            ForEach(asamalar) { s in Text(s.name).tag(s.id) }
                        }
                    }
                    Section {
                        Picker("Tür", selection: $aktiviteTuru) { ForEach(turler, id: \.key) { t in Text(t.label).tag(t.key) } }
                        TextField("Not", text: $aktiviteMetni)
                        Button("Aktivite kaydet") { Task { await aktiviteEkle() } }
                        ForEach(a.activities, id: \.self) { x in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(x.type + (x.by.map { " · " + $0 } ?? "")).font(.caption.weight(.semibold))
                                if let c = x.content, !c.isEmpty { Text(c).font(.caption) }
                                if let t = x.occurredAt { Text(DVBSaat.gun(t, "d MMM yyyy HH:mm")).font(.caption2).foregroundColor(.secondary) }
                            }
                        }
                    } header: {
                        Text("Aktiviteler")
                    }
                    if a.lead.patient == nil && a.lead.status != "lost" {
                        Section {
                            Button { cevirOnayi = true } label: { Label("Hastaya dönüştür", systemImage: "person.badge.plus") }
                            Button(role: .destructive) { kayipAcik = true } label: { Label("Kaybedildi olarak işaretle", systemImage: "xmark.circle") }
                        }
                    }
                }
                .refreshable { await yukle() }
            } else if let hata {
                DVBStateView(icon: "person", title: "Aday alınamadı", message: hata) { Task { await yukle() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(ad)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Düzenle") { duzenleAcik = true }.disabled(a == nil) }
        }
        .task { await yukle() }
        .alert("Aday", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(bilgi ?? "") }
        .alert("Hastaya dönüştürülsün mü?", isPresented: $cevirOnayi) {
            Button("Vazgeç", role: .cancel) {}
            Button("Dönüştür") { Task { await islem("convert", [:]) } }
        } message: {
            Text("Aday telefonuyla hasta kaydı açılır (varsa mevcut kayda bağlanır) ve hasta listenize eklenir.")
        }
        .sheet(isPresented: $kayipAcik) {
            NavigationView {
                Form { TextField("Neden (isteğe bağlı, ör. Fiyat)", text: $kayipNedeni) }
                    .navigationTitle("Kaybedildi")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kayipAcik = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Kaydet") {
                                kayipAcik = false
                                Task { await islem("lost", ["lost_reason": DVBYonBicim.kirp(kayipNedeni)]) }
                            }
                        }
                    }
            }
            .navigationViewStyle(.stack)
        }
        .sheet(isPresented: $duzenleAcik) {
            if let k = a?.lead {
                DVBAdayFormView(aday: k, kaynaklar: kaynaklar, kisiler: kisiler) { m in bilgi = m; degisti(); Task { await yukle() } }
                    .environmentObject(session)
            }
        }
    }

    private func bilgiSatiri(_ e: String, _ d: String?) -> some View {
        Group {
            if let d, !d.isEmpty {
                HStack { Text(e).foregroundColor(.secondary); Spacer(); Text(d).multilineTextAlignment(.trailing) }.font(.subheadline)
            }
        }
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            a = try await DVBAPI.shared.get("my/doctor/leads/\(adayId)", token: token)
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func asamaDegistir(_ id: Int) async {
        guard let token = session.token, id != a?.lead.stageId else { return }
        do {
            let c: DVBYonCevap = try await DVBAPI.shared.post("my/doctor/leads/\(adayId)/stage", body: ["lead_stage_id": id], token: token)
            bilgi = c.message
            degisti()
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }

    private func aktiviteEkle() async {
        guard let token = session.token else { return }
        var govde: [String: Any] = ["type": aktiviteTuru]
        let m = DVBYonBicim.kirp(aktiviteMetni)
        if !m.isEmpty { govde["content"] = m }
        do {
            let c: DVBYonCevap = try await DVBAPI.shared.post("my/doctor/leads/\(adayId)/activities", body: govde, token: token)
            bilgi = c.message
            aktiviteMetni = ""
            await yukle()
        } catch {
            if let mesaj = DVBError.mesaj(error) { bilgi = mesaj }
        }
    }

    private func islem(_ ad: String, _ govde: [String: Any]) async {
        guard let token = session.token else { return }
        do {
            let c: DVBYonCevap = try await DVBAPI.shared.post("my/doctor/leads/\(adayId)/\(ad)", body: govde, token: token)
            bilgi = c.message
            degisti()
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }
}

enum DVBAdayTelefon {
    /// wa.me için uluslararası rakamlar: 05xx… → 905xx…, 5xx… → 905xx….
    static func wa(_ t: String) -> String {
        var r = t.filter(\.isNumber)
        if r.hasPrefix("0") { r.removeFirst() }
        if r.count == 10 { r = "90" + r }
        return r
    }
}

private struct DVBAdayFormView: View {
    let aday: DVBAdayAyrintisi.Aday?
    let kaynaklar: [DVBSatisSecenek]
    let kisiler: [DVBSatisVerisi.Kisi]
    var kaydedildi: (String) -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss
    @State private var ad: String
    @State private var telefon: String
    @State private var eposta: String
    @State private var kaynak: String
    @State private var ilgi: String
    @State private var deger: String
    @State private var sorumlu: Int?
    @State private var takipVar: Bool
    @State private var takip: Date
    @State private var notlar: String
    @State private var hata: String?
    @State private var calisiyor = false

    init(aday: DVBAdayAyrintisi.Aday?, kaynaklar: [DVBSatisSecenek], kisiler: [DVBSatisVerisi.Kisi], kaydedildi: @escaping (String) -> Void) {
        self.aday = aday
        self.kaynaklar = kaynaklar
        self.kisiler = kisiler
        self.kaydedildi = kaydedildi
        _ad = State(initialValue: aday?.name ?? "")
        _telefon = State(initialValue: aday?.phone ?? "")
        _eposta = State(initialValue: aday?.email ?? "")
        _kaynak = State(initialValue: aday?.source ?? (kaynaklar.first?.key ?? "instagram"))
        _ilgi = State(initialValue: aday?.interest ?? "")
        _deger = State(initialValue: aday?.estimatedValue.map { String(format: "%.2f", $0).replacingOccurrences(of: ".", with: ",") } ?? "")
        _sorumlu = State(initialValue: aday?.assignedTo)
        _takipVar = State(initialValue: aday?.nextFollowUpAt != nil)
        _takip = State(initialValue: aday?.nextFollowUpAt ?? Date().addingTimeInterval(86400))
        _notlar = State(initialValue: aday?.notes ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Ad soyad", text: $ad)
                    TextField("Telefon", text: $telefon).keyboardType(.phonePad)
                    TextField("E-posta", text: $eposta).keyboardType(.emailAddress).autocapitalization(.none)
                    Picker("Kaynak", selection: $kaynak) { ForEach(kaynaklar, id: \.key) { k in Text(k.label).tag(k.key) } }
                    TextField("İlgilendiği hizmet", text: $ilgi)
                    TextField("Tahmini değer (₺)", text: $deger).keyboardType(.decimalPad)
                }
                Section {
                    Picker("Sorumlu", selection: $sorumlu) {
                        Text("Atanmadı").tag(Int?.none)
                        ForEach(kisiler) { k in Text(k.name).tag(Int?.some(k.id)) }
                    }
                    Toggle("Takip tarihi", isOn: $takipVar)
                    if takipVar { DatePicker("Takip", selection: $takip, displayedComponents: [.date, .hourAndMinute]).environment(\.timeZone, DVBTime.klinik) }
                    TextField("Not", text: $notlar)
                }
                if let hata { Section { Text(hata).foregroundColor(.red).font(.subheadline) } }
            }
            .navigationTitle(aday == nil ? "Aday ekle" : "Adayı düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await kaydet() } } label: {
                        if calisiyor { ProgressView() } else { Text("Kaydet").bold() }
                    }
                    .disabled(calisiyor || DVBYonBicim.kirp(ad).isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func kaydet() async {
        guard let token = session.token else { return }
        calisiyor = true
        defer { calisiyor = false }
        var govde: [String: Any] = [
            "name": DVBYonBicim.kirp(ad), "phone": DVBYonBicim.kirp(telefon), "email": DVBYonBicim.kirp(eposta),
            "source": kaynak, "interest": DVBYonBicim.kirp(ilgi), "notes": DVBYonBicim.kirp(notlar),
        ]
        if let d = DVBPara.coz(deger) { govde["estimated_value"] = DVBPara.makine(d) }
        if let sorumlu { govde["assigned_to"] = sorumlu }
        if takipVar { govde["next_follow_up_at"] = DVBSaat.gun(takip, "yyyy-MM-dd HH:mm") }
        do {
            let c: DVBYonCevap
            if let aday {
                c = try await DVBAPI.shared.put("my/doctor/leads/\(aday.id)", body: govde, token: token)
            } else {
                c = try await DVBAPI.shared.post("my/doctor/leads", body: govde, token: token)
            }
            kaydedildi(c.message ?? "Kaydedildi.")
            dismiss()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

// MARK: - Sekreter yetkileri

private struct DVBSekreterVerisi: Decodable {
    let areas: [DVBSatisSecenek]
    let data: [Sekreter]

    struct Sekreter: Decodable, Identifiable, Hashable {
        let id: Int
        let name: String?
        let email: String?
        let permissions: [String]
    }
}

private struct DVBSekreterYetkiCevabi: Decodable {
    let message: String?
    let permissions: [String]?
}

struct DVBSekreterlerView: View {
    @EnvironmentObject private var session: DVBSession
    @State private var veri: DVBSekreterVerisi?
    @State private var izinler: [Int: Set<String>] = [:]
    @State private var hata: String?
    @State private var bilgi: String?

    var body: some View {
        Group {
            if let v = veri {
                List {
                    if v.data.isEmpty {
                        Text("Hesabınıza bağlı sekreter yok. Sekreter eklemek için web panelini kullanın.").foregroundColor(.secondary)
                    }
                    ForEach(v.data) { s in
                        Section {
                            ForEach(v.areas, id: \.key) { alan in
                                Toggle(alan.label, isOn: Binding(
                                    get: { izinler[s.id, default: []].contains(alan.key) },
                                    set: { yeni in
                                        var k = izinler[s.id, default: []]
                                        if yeni { k.insert(alan.key) } else { k.remove(alan.key) }
                                        izinler[s.id] = k
                                        Task { await kaydet(s.id, k) }
                                    }
                                ))
                            }
                        } header: {
                            Text(s.name ?? "Sekreter")
                        } footer: {
                            Text(s.email ?? "")
                        }
                    }
                }
            } else if let hata {
                DVBStateView(icon: "person.badge.key", title: "Sekreterler alınamadı", message: hata) { Task { await yukle() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Sekreter yetkileri")
        .navigationBarTitleDisplayMode(.inline)
        .task { await yukle() }
        .alert("Sekreter yetkileri", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(bilgi ?? "") }
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            let v: DVBSekreterVerisi = try await DVBAPI.shared.get("my/doctor/secretaries", token: token)
            veri = v
            var y: [Int: Set<String>] = [:]
            for s in v.data { y[s.id] = Set(s.permissions) }
            izinler = y
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func kaydet(_ id: Int, _ k: Set<String>) async {
        guard let token = session.token else { return }
        do {
            let _: DVBSekreterYetkiCevabi = try await DVBAPI.shared.put("my/doctor/secretaries/\(id)/permissions", body: ["permissions": Array(k)], token: token)
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
            await yukle()
        }
    }
}
