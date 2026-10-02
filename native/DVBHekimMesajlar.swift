import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000272 — HEKİM MODU, 4. AŞAMA: MESAJLAR VE BİLDİRİMLER.
//
// Kullanıcı (30 Eyl 2026): "tamam mesajlar ve bildirimler aşamasına geç".
//
// MESAJLAR: web "Mesajlar" ile aynı görünürlük sunucuda (HekimSohbetleri). WhatsApp yazışmalarını şu an merkez ekip
// yürütüyor (DVB-000222) — uygulama onları göstermez, yanıtlatmaz; sunucu da reddeder.
//
// BİLDİRİMLER: hekim bildirimleri `/panel/...` adreslerine gider; uygulamanın web görünümünde panel oturumu yok,
// dokununca giriş sayfası çıkıyordu. Sunucu bilinen adresleri `target` olarak verir (sohbet, ajanda, sorular, hasta
// kartı, tahsilat) → yerli ekran açılır; bilinmeyen adres eskisi gibi web sayfasıdır. Eşleme kuralı SUNUCUDA tek yerde
// (HekimMesajApiController::hedef) — istemcide ikinci kopya yok; push dokunuşu da hedefi bildirim listesinden bulur.
// ═══════════════════════════════════════════════════════════════════════════════

// MARK: - Modeller

struct DVBHekimSohbetOzet: Decodable, Identifiable {
    let id: Int
    let name: String?
    let lastMessage: String?
    let lastFrom: String?
    let lastMessageAt: Date?
    let unread: Int

    enum CodingKeys: String, CodingKey {
        case id, name, unread
        case lastMessage = "last_message"
        case lastFrom = "last_from"
        case lastMessageAt = "last_message_at"
    }
}

struct DVBHekimSohbetListesi: Decodable {
    let data: [DVBHekimSohbetOzet]
    let whatsappNote: String?

    enum CodingKeys: String, CodingKey {
        case data
        case whatsappNote = "whatsapp_note"
    }
}

struct DVBHekimMesaj: Decodable, Identifiable {
    let id: Int
    let from: String
    let body: String
    let channel: String?
    let createdAt: Date?

    var bendenMi: Bool { from == "doctor" }

    enum CodingKeys: String, CodingKey {
        case id, from, body, channel
        case createdAt = "created_at"
    }
}

private struct DVBHekimSohbetCevabi: Decodable {
    let conversation: Baslik
    let messages: [DVBHekimMesaj]
    struct Baslik: Decodable { let id: Int; let name: String? }
}

private struct DVBHekimYanitCevabi: Decodable { let message: DVBHekimMesaj }

// `DVBHekimHedef` DVBModels.swift'te: bildirim modeli onu kullanıyor ve DVBModels widget hedefinde de derleniyor
// (scripts/add-widget-target.rb SHARED) — widget'ın görmediği bir dosyadaki türe başvurmak derlemeyi kırıyordu (#31).

/// `sheet(item:)` için kimlik: aynı hedef iki kez açılabilsin.
struct DVBHedefSunumu: Identifiable {
    let id = UUID()
    let hedef: DVBHekimHedef
}

// MARK: - Sohbet

struct DVBHekimSohbetView: View {
    let sohbetId: Int
    let ad: String
    /// DVB-000290 — hasta tarafı: aynı ekran hastanın sohbetini açar (uç my/conversations, kendi balonu hastanınki).
    /// Kullanıcı: "hasta tarafından ... mesajlara yine siteyi açıyor ... aynı şekilde doktorlardaki gibi olmalı".
    var hastaModu: Bool = false

    @EnvironmentObject private var session: DVBSession

    private var kok: String { hastaModu ? "my/conversations" : "my/doctor/conversations" }

    private func bendenMi(_ m: DVBHekimMesaj) -> Bool { hastaModu ? m.from == "patient" : m.bendenMi }

    @State private var mesajlar: [DVBHekimMesaj] = []
    @State private var baslik: String?
    @State private var metin = ""
    @State private var yuklendi = false
    @State private var gonderiliyor = false
    @State private var hata: String?
    @State private var gonderimHatasi: String?

    var body: some View {
        VStack(spacing: 0) {
            if let hata, !yuklendi {
                DVBStateView(icon: "bubble.left.and.exclamationmark.bubble.right", title: "Sohbet açılamadı", message: hata) {
                    Task { await yukle() }
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(mesajlar) { m in
                                balon(m).id(m.id)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: mesajlar.count) { _ in
                        if let son = mesajlar.last { withAnimation { proxy.scrollTo(son.id, anchor: .bottom) } }
                    }
                    .onAppear {
                        if let son = mesajlar.last { proxy.scrollTo(son.id, anchor: .bottom) }
                    }
                }
                Divider()
                yazmaAlani
            }
        }
        .navigationTitle(baslik ?? ad)
        .navigationBarTitleDisplayMode(.inline)
        .task { await yukle() }
    }

    private func balon(_ m: DVBHekimMesaj) -> some View {
        let benden = bendenMi(m)
        return HStack {
            if benden { Spacer(minLength: 40) }
            VStack(alignment: benden ? .trailing : .leading, spacing: 3) {
                Text(m.body)
                    .font(.subheadline)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(benden ? DVBTheme.brand : Color(.secondarySystemBackground))
                    .foregroundColor(benden ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack(spacing: 4) {
                    if m.channel == "whatsapp" { Text("WhatsApp") }
                    if let t = m.createdAt { Text(DVBSaat.gun(t, "d MMM HH:mm")) }
                }
                .font(.caption2).foregroundColor(.secondary)
            }
            if !benden { Spacer(minLength: 40) }
        }
    }

    private var yazmaAlani: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let gonderimHatasi {
                Text(gonderimHatasi).font(.caption).foregroundColor(.red)
            }
            HStack(spacing: 8) {
                TextField("Mesajınız", text: $metin)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit { Task { await gonder() } }
                Button { Task { await gonder() } } label: {
                    Image(systemName: "paperplane.fill").font(.title3)
                }
                .disabled(gonderiliyor || metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Gönder")
            }
        }
        .padding(10)
        .background(Color(.systemBackground))
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            let c: DVBHekimSohbetCevabi = try await DVBAPI.shared.get("\(kok)/\(sohbetId)", token: token)
            mesajlar = c.messages
            baslik = c.conversation.name
            yuklendi = true
            hata = nil
            // Sunucu okundu saydı → rozetler düşsün (hekimde Gelen Kutusu rozeti, hastada zil).
            if hastaModu { await session.okunmamisiYenile() } else { await session.hekimiYukle() }
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
    }

    private func gonder() async {
        let govde = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !govde.isEmpty, !gonderiliyor, let token = session.token else { return }
        gonderiliyor = true
        defer { gonderiliyor = false }
        do {
            let c: DVBHekimYanitCevabi = try await DVBAPI.shared.post(
                "\(kok)/\(sohbetId)/reply", body: ["body": govde], token: token
            )
            mesajlar.append(c.message)
            metin = ""
            gonderimHatasi = nil
        } catch {
            if let m = DVBError.mesaj(error) { gonderimHatasi = m }
        }
    }
}

// MARK: - Hastanın mesajları (DVB-000290)

/// Hastanın sohbet listesi (Hesabım → Mesajlarım). Uç `my/conversations` hekim ucuyla aynı biçimde döner; sohbet ekranı
/// hekimle ortak (`DVBHekimSohbetView(hastaModu: true)`).
struct DVBHastaMesajlarView: View {
    @EnvironmentObject private var session: DVBSession

    @State private var sohbetler: [DVBHekimSohbetOzet] = []
    @State private var yuklendi = false
    @State private var hata: String?

    var body: some View {
        List {
            if let hata, sohbetler.isEmpty {
                DVBStateView(icon: "wifi.exclamationmark", title: "Mesajlar alınamadı", message: hata) {
                    Task { await yukle() }
                }
            } else if yuklendi && sohbetler.isEmpty {
                Text("Henüz mesajınız yok.").foregroundColor(.secondary)
            } else if !yuklendi {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                ForEach(sohbetler) { s in
                    NavigationLink(destination: DVBHekimSohbetView(sohbetId: s.id, ad: s.name ?? "Hekim", hastaModu: true)) {
                        satir(s)
                    }
                }
            }
        }
        .navigationTitle("Mesajlarım")
        .refreshable { await yukle() }
        .task { await yukle() }
    }

    private func satir(_ s: DVBHekimSohbetOzet) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(s.name ?? "Hekim").font(.headline).lineLimit(1)
                if let son = s.lastMessage {
                    Text((s.lastFrom == "patient" ? "Siz: " : "") + son)
                        .font(.subheadline).foregroundColor(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if let t = s.lastMessageAt { Text(DVBSaat.gun(t, "d MMM")).font(.caption2).foregroundColor(.secondary) }
                if s.unread > 0 {
                    Text("\(s.unread)")
                        .font(.caption2.weight(.bold)).foregroundColor(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(DVBTheme.brand))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func yukle() async {
        guard let token = session.token else { return }
        do {
            let l: DVBHekimSohbetListesi = try await DVBAPI.shared.get("my/conversations", token: token)
            sohbetler = l.data
            hata = nil
        } catch {
            if let m = DVBError.mesaj(error) { hata = m }
        }
        yuklendi = true
    }
}

// MARK: - Bildirim hedefini yerli ekranda aç

struct DVBHekimHedefSayfasi: View {
    let hedef: DVBHekimHedef

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch hedef.screen {
        case "conversation":
            kapatilabilir { DVBHekimSohbetView(sohbetId: hedef.id ?? 0, ad: "Mesaj") }
        case "patient":
            kapatilabilir { DVBHekimHastaKartView(hastaId: hedef.id ?? 0, ad: "Hasta") }
        case "messages":
            DVBHekimTaleplerView(baslangic: .mesajlar)
        case "questions":
            DVBHekimTaleplerView(baslangic: .sorular)
        case "payments":
            DVBHekimTahsilatView()
        default:
            DVBHekimAjandaView()
        }
    }

    private func kapatilabilir<Icerik: View>(@ViewBuilder _ icerik: () -> Icerik) -> some View {
        NavigationView {
            icerik()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                }
        }
        .navigationViewStyle(.stack)
    }
}
