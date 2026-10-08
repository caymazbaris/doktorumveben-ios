import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000343 — MUHASEBE (hekim).
//
// Kullanıcı (8 Eki 2026): "profil düzenleme, muhasebe ve e-Fatura. da yapalım".
//
// Web /panel/muhasebe ile aynı servis (HekimMuhasebeApiController → AccountingService): bugün/bu ay özeti, kasa bakiyeleri,
// gelir/gider listesi, kayıt, gün sonu ve aylık rapor. Uygulamadan yalnız ELLE girilen kayıt silinir; tahsilattan ya da
// satıştan gelen kayıtlar korunur. Tutarlar 10.000,00 ₺ biçiminde (İksero para standardı).
// ═══════════════════════════════════════════════════════════════════════════════

struct DVBMuhasebeOzeti: Decodable {
    let income: Double
    let expense: Double
    let net: Double
}

struct DVBMuhasebe: Decodable {
    let from: String
    let to: String
    let today: DVBMuhasebeOzeti
    let month: DVBMuhasebeOzeti
    let range: DVBMuhasebeOzeti
    let balances: [Bakiye]
    let data: [Islem]
    let page: Int
    let lastPage: Int

    struct Bakiye: Decodable, Identifiable {
        let id: Int
        let name: String
        let type: String?
        let balance: Double
    }

    struct Islem: Decodable, Identifiable {
        let id: Int
        let direction: String
        let amount: Double
        let occurredOn: String?
        let category: String?
        let account: String?
        let paymentType: String?
        let description: String?
        let patient: String?
        let deletable: Bool

        enum CodingKeys: String, CodingKey {
            case id, direction, amount, category, account, description, patient, deletable
            case occurredOn = "occurred_on"
            case paymentType = "payment_type"
        }
    }

    enum CodingKeys: String, CodingKey {
        case from, to, today, month, range, balances, data, page
        case lastPage = "last_page"
    }
}

struct DVBMuhasebeSecenekleri: Decodable {
    let incomeCategories: [Secenek]
    let expenseCategories: [Secenek]
    let accounts: [Hesap]
    let paymentTypes: [OdemeTipi]

    struct Secenek: Decodable, Identifiable, Hashable {
        let id: Int
        let name: String
    }

    struct Hesap: Decodable, Identifiable, Hashable {
        let id: Int
        let name: String
        let type: String?
    }

    struct OdemeTipi: Decodable, Hashable {
        let key: String
        let label: String
        let accountType: String

        enum CodingKeys: String, CodingKey {
            case key, label
            case accountType = "account_type"
        }
    }

    enum CodingKeys: String, CodingKey {
        case accounts
        case incomeCategories = "income_categories"
        case expenseCategories = "expense_categories"
        case paymentTypes = "payment_types"
    }
}

private struct DVBMuhasebeCevabi: Decodable {
    let ok: Bool
    let message: String?
}

/// "2026-10-09" → "9 Ekim 2026".
enum DVBGunMetni {
    static func yaz(_ ymd: String?, _ bicim: String = "d MMMM yyyy") -> String {
        guard let ymd else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = DVBTime.klinik
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: ymd) else { return ymd }
        return DVBSaat.gun(d, bicim)
    }
}

struct DVBHekimMuhasebeView: View {
    @EnvironmentObject private var session: DVBSession

    @State private var veri: DVBMuhasebe?
    @State private var islemler: [DVBMuhasebe.Islem] = []
    @State private var yon = ""
    @State private var hata: String?
    @State private var bilgi: String?
    @State private var ekle: String?
    @State private var silinecek: DVBMuhasebe.Islem?
    @State private var dahaYukleniyor = false

    var body: some View {
        Group {
            if let v = veri {
                liste(v)
            } else if let hata {
                DVBStateView(icon: "turkishlirasign.circle", title: "Muhasebe alınamadı", message: hata) {
                    Task { await yukle() }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Muhasebe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { ekle = "in" } label: { Label("Gelir ekle", systemImage: "plus.circle") }
                    Button { ekle = "out" } label: { Label("Gider ekle", systemImage: "minus.circle") }
                } label: {
                    Label("Ekle", systemImage: "plus")
                }
                .disabled(veri == nil)
            }
        }
        .task { await yukle() }
        .onChange(of: yon) { _ in Task { await yukle() } }
        .alert("Muhasebe", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(bilgi ?? "")
        }
        .confirmationDialog(
            "Kayıt silinsin mi?",
            isPresented: Binding(get: { silinecek != nil }, set: { if !$0 { silinecek = nil } }),
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive) {
                if let i = silinecek { Task { await sil(i.id) } }
                silinecek = nil
            }
            Button("Vazgeç", role: .cancel) { silinecek = nil }
        }
        .sheet(isPresented: Binding(get: { ekle != nil }, set: { if !$0 { ekle = nil } })) {
            DVBIslemEkleView(yon: ekle ?? "in") { m in
                bilgi = m
                Task { await yukle() }
            }
            .environmentObject(session)
        }
    }

    private func liste(_ v: DVBMuhasebe) -> some View {
        List {
            Section {
                ozetSatiri("Bugün", v.today)
                ozetSatiri("Bu ay", v.month)
            } header: {
                Text("Özet")
            }

            if !v.balances.isEmpty {
                Section("Hesap bakiyeleri") {
                    ForEach(v.balances) { b in
                        HStack {
                            Text(b.name)
                            Spacer()
                            Text(DVBPara.bicim(b.balance)).monospacedDigit()
                                .foregroundColor(b.balance < 0 ? .red : .primary)
                        }
                    }
                }
            }

            Section {
                NavigationLink(destination: DVBMuhasebeRaporView()) {
                    Label("Gün sonu ve aylık rapor", systemImage: "chart.bar.doc.horizontal")
                }
            }

            Section {
                Picker("Tür", selection: $yon) {
                    Text("Tümü").tag("")
                    Text("Gelir").tag("in")
                    Text("Gider").tag("out")
                }
                .pickerStyle(.segmented)
                if islemler.isEmpty {
                    Text("Bu ay kayıt yok.").foregroundColor(.secondary)
                } else {
                    ForEach(islemler) { islemSatiri($0) }
                    if v.page < v.lastPage {
                        Button {
                            Task { await dahaFazla(v.page + 1) }
                        } label: {
                            if dahaYukleniyor { ProgressView().frame(maxWidth: .infinity) } else { Text("Daha fazla göster").frame(maxWidth: .infinity) }
                        }
                        .disabled(dahaYukleniyor)
                    }
                }
            } header: {
                Text("Kayıtlar · \(DVBGunMetni.yaz(v.from, "d MMM")) – \(DVBGunMetni.yaz(v.to, "d MMM"))")
            } footer: {
                Text("Silmek için kaydı sola kaydırın. Tahsilattan ya da satıştan gelen kayıtlar uygulamadan silinmez.")
            }
        }
        .refreshable { await yukle() }
    }

    private func ozetSatiri(_ baslik: String, _ o: DVBMuhasebeOzeti) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(baslik).font(.subheadline.weight(.semibold))
            HStack {
                deger("Gelir", o.income, DVBTheme.accent)
                Spacer()
                deger("Gider", o.expense, .red)
                Spacer()
                deger("Net", o.net, o.net < 0 ? .red : .primary)
            }
        }
        .padding(.vertical, 2)
    }

    private func deger(_ etiket: String, _ tutar: Double, _ renk: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(etiket).font(.caption2).foregroundColor(.secondary)
            Text(DVBPara.bicim(tutar)).font(.caption.weight(.semibold)).monospacedDigit().foregroundColor(renk)
        }
    }

    private func islemSatiri(_ i: DVBMuhasebe.Islem) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(i.category ?? (i.direction == "in" ? "Gelir" : "Gider")).font(.subheadline.weight(.semibold))
                Text(altSatir(i)).font(.caption).foregroundColor(.secondary)
                if let d = i.description, !d.isEmpty { Text(d).font(.caption).lineLimit(2) }
            }
            Spacer(minLength: 8)
            Text((i.direction == "in" ? "+" : "−") + DVBPara.bicim(i.amount))
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundColor(i.direction == "in" ? DVBTheme.accent : .red)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if i.deletable {
                Button(role: .destructive) { silinecek = i } label: { Label("Sil", systemImage: "trash") }
            }
        }
    }

    private func altSatir(_ i: DVBMuhasebe.Islem) -> String {
        var p: [String] = [DVBGunMetni.yaz(i.occurredOn, "d MMM yyyy")]
        if let a = i.account { p.append(a) }
        if let t = i.paymentType { p.append(t) }
        if let h = i.patient { p.append(h) }
        return p.joined(separator: " · ")
    }

    // MARK: - Ağ

    private func sorgu(_ sayfa: Int) -> [String: String] {
        var q = ["page": String(sayfa)]
        if !yon.isEmpty { q["direction"] = yon }
        return q
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            let v: DVBMuhasebe = try await DVBAPI.shared.get("my/doctor/accounting", query: sorgu(1), token: token)
            veri = v
            islemler = v.data
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func dahaFazla(_ sayfa: Int) async {
        guard let token = session.token, !dahaYukleniyor else { return }
        dahaYukleniyor = true
        defer { dahaYukleniyor = false }
        do {
            let v: DVBMuhasebe = try await DVBAPI.shared.get("my/doctor/accounting", query: sorgu(sayfa), token: token)
            veri = v
            islemler.append(contentsOf: v.data.filter { yeni in !islemler.contains(where: { $0.id == yeni.id }) })
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }

    private func sil(_ id: Int) async {
        guard let token = session.token else { return }
        do {
            let c: DVBMuhasebeCevabi = try await DVBAPI.shared.delete("my/doctor/accounting/transactions/\(id)", token: token)
            bilgi = c.message ?? "İşlem silindi."
            await yukle()
        } catch {
            if let m = DVBError.mesaj(error) { bilgi = m }
        }
    }
}

// MARK: - Gelir / gider ekleme

struct DVBIslemEkleView: View {
    let yon: String
    var kaydedildi: (String) -> Void

    @EnvironmentObject private var session: DVBSession
    @Environment(\.dismiss) private var dismiss

    @State private var secenekler: DVBMuhasebeSecenekleri?
    @State private var tutar = ""
    @State private var tarih = Date()
    @State private var odemeTipi = "cash"
    @State private var hesapId: Int?
    @State private var kategoriId: Int?
    @State private var aciklama = ""
    @State private var calisiyor = false
    @State private var hata: String?

    private var gelir: Bool { yon == "in" }

    private var uygunHesaplar: [DVBMuhasebeSecenekleri.Hesap] {
        guard let s = secenekler else { return [] }
        let tur = s.paymentTypes.first(where: { $0.key == odemeTipi })?.accountType ?? "cash"
        let uygun = s.accounts.filter { $0.type == tur }
        return uygun.isEmpty ? s.accounts : uygun
    }

    private var hazir: Bool { DVBPara.coz(tutar) != nil && hesapId != nil }

    var body: some View {
        NavigationView {
            Form {
                if let s = secenekler {
                    Section {
                        TextField("Tutar (ör. 1.500,00)", text: $tutar).keyboardType(.decimalPad)
                        DatePicker("Tarih", selection: $tarih, displayedComponents: .date)
                            .environment(\.timeZone, DVBTime.klinik)
                            .environment(\.locale, Locale(identifier: "tr_TR"))
                        Picker("Kategori", selection: $kategoriId) {
                            Text("Kategorisiz").tag(Int?.none)
                            ForEach(gelir ? s.incomeCategories : s.expenseCategories) { c in Text(c.name).tag(Int?.some(c.id)) }
                        }
                    }
                    Section {
                        Picker("Ödeme tipi", selection: $odemeTipi) {
                            ForEach(s.paymentTypes, id: \.key) { t in Text(t.label).tag(t.key) }
                        }
                        Picker(gelir ? "Paranın gireceği hesap" : "Paranın çıktığı hesap", selection: $hesapId) {
                            ForEach(uygunHesaplar) { h in Text(h.name).tag(Int?.some(h.id)) }
                        }
                    }
                    Section {
                        TextField("Açıklama (isteğe bağlı)", text: $aciklama)
                    }
                } else if let hata {
                    Text(hata).foregroundColor(.red)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }

                if secenekler != nil, let hata {
                    Section { Text(hata).foregroundColor(.red).font(.subheadline) }
                }
            }
            .navigationTitle(gelir ? "Gelir ekle" : "Gider ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await kaydet() }
                    } label: {
                        if calisiyor { ProgressView() } else { Text("Kaydet").bold() }
                    }
                    .disabled(!hazir || calisiyor)
                }
            }
            .task { await seceneklerYukle() }
            .onChange(of: odemeTipi) { _ in hesapId = uygunHesaplar.first?.id }
        }
        .navigationViewStyle(.stack)
    }

    private func seceneklerYukle() async {
        guard let token = session.token, secenekler == nil else { return }
        do {
            let s: DVBMuhasebeSecenekleri = try await DVBAPI.shared.get("my/doctor/accounting/options", token: token)
            secenekler = s
            hesapId = uygunHesaplar.first?.id
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func kaydet() async {
        guard let token = session.token, !calisiyor, let t = DVBPara.coz(tutar), let hesapId else { return }
        calisiyor = true
        defer { calisiyor = false }
        var govde: [String: Any] = [
            "direction": yon,
            "amount": DVBPara.makine(t),
            "occurred_on": DVBSaat.anahtar(tarih),
            "cash_account_id": hesapId,
            "payment_type": odemeTipi,
        ]
        if let kategoriId { govde["finance_category_id"] = kategoriId }
        let a = aciklama.trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty { govde["description"] = a }
        do {
            let c: DVBMuhasebeCevabi = try await DVBAPI.shared.post("my/doctor/accounting/transactions", body: govde, token: token)
            kaydedildi(c.message ?? (gelir ? "Gelir kaydedildi." : "Gider kaydedildi."))
            dismiss()
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}

// MARK: - Rapor

struct DVBMuhasebeRaporu: Decodable {
    let daily: Gunluk
    let monthly: Aylik

    struct Gunluk: Decodable {
        let date: String
        let totalIn: Double
        let totalOut: Double
        let net: Double
        let accounts: [Hesap]

        enum CodingKeys: String, CodingKey {
            case date, net, accounts
            case totalIn = "total_in"
            case totalOut = "total_out"
        }
    }

    struct Hesap: Decodable, Hashable {
        let name: String
        let opening: Double
        let giren: Double
        let cikan: Double
        let closing: Double

        enum CodingKeys: String, CodingKey {
            case name, opening, closing
            case giren = "in"
            case cikan = "out"
        }
    }

    struct Aylik: Decodable {
        let month: String
        let income: Double
        let expense: Double
        let net: Double
        let incomeByCategory: [Kalem]
        let expenseByCategory: [Kalem]

        enum CodingKeys: String, CodingKey {
            case month, income, expense, net
            case incomeByCategory = "income_by_category"
            case expenseByCategory = "expense_by_category"
        }
    }

    struct Kalem: Decodable, Hashable {
        let name: String
        let amount: Double
    }
}

struct DVBMuhasebeRaporView: View {
    @EnvironmentObject private var session: DVBSession

    @State private var gun = Date()
    @State private var ay = Date()
    @State private var rapor: DVBMuhasebeRaporu?
    @State private var hata: String?

    private var anahtar: String { DVBSaat.anahtar(gun) + "|" + DVBSaat.gun(ay, "yyyy-MM") }

    var body: some View {
        List {
            Section {
                DatePicker("Gün", selection: $gun, in: ...Date(), displayedComponents: .date)
                    .environment(\.timeZone, DVBTime.klinik)
                    .environment(\.locale, Locale(identifier: "tr_TR"))
                if let g = rapor?.daily {
                    ForEach(g.accounts, id: \.self) { h in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(h.name).font(.subheadline.weight(.semibold))
                            Text("Açılış \(DVBPara.bicim(h.opening)) · Giren \(DVBPara.bicim(h.giren)) · Çıkan \(DVBPara.bicim(h.cikan))")
                                .font(.caption).foregroundColor(.secondary)
                            Text("Kapanış \(DVBPara.bicim(h.closing))").font(.caption.weight(.semibold))
                        }
                    }
                    satir("Günün neti", g.net)
                }
            } header: {
                Text("Gün sonu kasa raporu")
            }

            Section {
                DatePicker("Ay", selection: $ay, in: ...Date(), displayedComponents: .date)
                    .environment(\.timeZone, DVBTime.klinik)
                    .environment(\.locale, Locale(identifier: "tr_TR"))
                if let a = rapor?.monthly {
                    satir("Gelir", a.income)
                    satir("Gider", a.expense)
                    satir("Net", a.net)
                    if !a.incomeByCategory.isEmpty {
                        Text("Gelir kalemleri").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                        ForEach(a.incomeByCategory, id: \.self) { k in satir(k.name, k.amount) }
                    }
                    if !a.expenseByCategory.isEmpty {
                        Text("Gider kalemleri").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                        ForEach(a.expenseByCategory, id: \.self) { k in satir(k.name, k.amount) }
                    }
                }
            } header: {
                Text("Aylık kâr / zarar")
            } footer: {
                Text("Ay için o aydan herhangi bir gün seçmeniz yeterli.")
            }

            if let hata {
                Section { Text(hata).foregroundColor(.red) }
            }
        }
        .navigationTitle("Rapor")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: anahtar) { await yukle() }
    }

    private func satir(_ etiket: String, _ tutar: Double) -> some View {
        HStack {
            Text(etiket)
            Spacer()
            Text(DVBPara.bicim(tutar)).monospacedDigit().foregroundColor(tutar < 0 ? .red : .primary)
        }
        .font(.subheadline)
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            rapor = try await DVBAPI.shared.get(
                "my/doctor/accounting/report", query: ["date": DVBSaat.anahtar(gun), "month": DVBSaat.gun(ay, "yyyy-MM")], token: token
            )
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }
}
