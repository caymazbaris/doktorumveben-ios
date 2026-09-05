import SwiftUI
import WidgetKit

/// DVB-000111 — ANA EKRAN WIDGET'I.
///
/// Yönetici kararları (05.09.2026):
///   · "Hasta Adı Şfreli Görünsün BA*** Ca*** gibi"
///   · "user'a da varsa yazsın illa hekim olması şart değil"
///
/// ⚠ WIDGET AĞA ÇIKMAZ. App Group'taki önbelleği okur (DVBOfflineStore). Sebep üç katlı:
///   1) Uçak modunda/zayıf ağda boş görünmemeli — asıl amaç bu.
///   2) Widget uzantısının kendi oturum jetonu yok; ağ isteği için jetonu uzantıya
///      taşımak, jetonu ikinci bir sandbox'a kopyalamak demekti.
///   3) WidgetKit uzantıya çok kısa çalışma süresi verir; ağ beklemesi boş kare üretir.
/// Veriyi uygulama tazeler, widget yalnız gösterir.
///
/// ⚠ MASKELEME BURADA YAPILMAZ. Sunucu zaten maskeli gönderiyor
/// (DoctorAgendaApiController → NameMasker::mask($ad, 2)). Burada bir daha maskelemek,
/// "maskelenmiş sanıp maskelenmemiş veri gösterme" hatasına kapı açardı: tek kaynak sunucudur.

struct DVBAgendaEntry: TimelineEntry {
    let date: Date
    let ajanda: DVBAgenda?
    let guncelleme: Date?
    let appGroupVar: Bool
}

struct DVBAgendaProvider: TimelineProvider {

    func placeholder(in context: Context) -> DVBAgendaEntry {
        DVBAgendaEntry(date: Date(), ajanda: nil, guncelleme: nil, appGroupVar: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (DVBAgendaEntry) -> Void) {
        completion(oku())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DVBAgendaEntry>) -> Void) {
        let entry = oku()

        // Sunucu tazeleme aralığını kendisi söylüyor (refresh_after_seconds) ki
        // politikayı değiştirmek için mağaza güncellemesi beklemeyelim.
        let saniye = max(300, entry.ajanda?.refreshAfterSeconds ?? 900)
        let sonraki = Date().addingTimeInterval(TimeInterval(saniye))

        completion(Timeline(entries: [entry], policy: .after(sonraki)))
    }

    private func oku() -> DVBAgendaEntry {
        guard DVBOfflineStore.appGroupCalisiyor else {
            return DVBAgendaEntry(date: Date(), ajanda: nil, guncelleme: nil, appGroupVar: false)
        }
        let kayit = DVBOfflineStore.okuAjanda()
        return DVBAgendaEntry(
            date: Date(),
            ajanda: kayit?.veri,
            guncelleme: kayit?.zaman,
            appGroupVar: true
        )
    }
}

struct DVBWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DVBAgendaEntry

    private var hekimMi: Bool { entry.ajanda?.role == "doctor" }

    var body: some View {
        if !entry.appGroupVar {
            // Kurulum hatası kullanıcıya "boş widget" olarak görünmesin.
            durum("Widget yapılandırılmamış", "Uygulamayı güncelleyin.")
        } else if let a = entry.ajanda, (a.count ?? 0) > 0 {
            dolu(a)
        } else if entry.guncelleme == nil {
            durum(hekimMi ? "Ajanda" : "Randevum", "Uygulamayı bir kez açın.")
        } else {
            durum(hekimMi ? "Bugün randevu yok" : "Yaklaşan randevunuz yok", nil)
        }
    }

    private func dolu(_ a: DVBAgenda) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: hekimMi ? "stethoscope" : "calendar")
                    .font(.caption2)
                Text(a.title ?? (hekimMi ? "Bugün" : "Randevum"))
                    .font(.caption2.weight(.semibold))
                Spacer()
                if hekimMi, let c = a.count {
                    Text("\(c)").font(.caption2.bold())
                }
            }
            .foregroundColor(.secondary)

            if let n = a.next {
                Text(n.time ?? "—")
                    .font(.title2.bold())
                    .monospacedDigit()
                Text(n.name ?? "—")
                    .font(.caption)
                    .lineLimit(1)
                if let d = n.date, !hekimMi {
                    Text(d).font(.caption2).foregroundColor(.secondary)
                }
            }

            // Orta boyda birkaç satır daha sığar; küçükte yalnız "sıradaki" kalır.
            if family != .systemSmall, let items = a.items, items.count > 1 {
                Divider().padding(.vertical, 2)
                ForEach(items.dropFirst().prefix(3)) { s in
                    HStack(spacing: 8) {
                        Text(s.time ?? "—")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                        Text(s.name ?? "—")
                            .font(.caption2)
                            .lineLimit(1)
                        Spacer()
                    }
                }
            }

            Spacer(minLength: 0)

            if let g = entry.guncelleme {
                Text(DVBOfflineStore.bayatlikMetni(g))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func durum(_ baslik: String, _ alt: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(baslik).font(.caption.weight(.semibold))
            if let alt {
                Text(alt).font(.caption2).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DVBWidget: Widget {
    let kind = "DVBAgendaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DVBAgendaProvider()) { entry in
            // ⚠ containerBackground iOS 17+. iOS 17'de widget'lar bu olmadan
            // "yer tutucu" gibi görünür; ama daha düşük hedefte koşulsuz yazmak
            // DERLEME HATASI olur. Sürüm kapısı ikisini de karşılıyor.
            if #available(iOS 17.0, *) {
                DVBWidgetView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                DVBWidgetView(entry: entry)
                    .padding()
            }
        }
        .configurationDisplayName("Randevularım")
        .description("Hekimseniz bugünkü ajandanız, hastaysanız yaklaşan randevunuz. Hasta adları maskelidir.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct DVBWidgetBundle: WidgetBundle {
    var body: some Widget {
        DVBWidget()
    }
}
