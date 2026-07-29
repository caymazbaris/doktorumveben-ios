import EventKit
import Foundation
import UserNotifications

/// Tur 238 (Faz 3) — Cihaz yetenekleri.
///
/// App Store 4.2 "bir web sayfasından farkı ne?" sorusunun somut cevabı: randevu
/// alındıktan sonra hasta onu telefonunun KENDİ takvimine yazabiliyor ve
/// internet olmadan da çalışan YEREL bir hatırlatma kurabiliyor. İkisi de
/// tarayıcının yapamayacağı işler.
///
/// Tasarım kararları:
/// - Dönüş değeri kullanıcıya gösterilecek TEK cümle. Hata metni teknik değil.
/// - İzin reddedilirse uygulama ısrar etmez; hastanın kararı kayıtta zaten duruyor.
/// - iOS 17 takvim izinlerini ikiye böldü (tam erişim / yalnız-yazma). Bize yalnız
///   yazma yetiyor — daha az izin istemek doğru olan.
enum DVBCalendarKit {

    // MARK: - Takvim

    static func takvimeEkle(baslik: String, baslangic: Date, sure: Int = 30, not: String?) async -> String {
        let store = EKEventStore()

        guard await yazmaIzniIste(store) else {
            return "Takvim izni verilmedi. Ayarlar → Doktorumveben'den açabilirsiniz."
        }

        let etkinlik = EKEvent(eventStore: store)
        etkinlik.title = baslik
        etkinlik.startDate = baslangic
        etkinlik.endDate = baslangic.addingTimeInterval(TimeInterval(sure * 60))
        etkinlik.notes = not
        etkinlik.calendar = store.defaultCalendarForNewEvents
        // Takvimin kendi uyarısı: 1 saat önce. Yerel bildirimden bağımsızdır.
        etkinlik.addAlarm(EKAlarm(relativeOffset: -3600))

        guard etkinlik.calendar != nil else {
            return "Yazılabilir bir takvim bulunamadı."
        }

        do {
            try store.save(etkinlik, span: .thisEvent, commit: true)
            return "Takviminize eklendi."
        } catch {
            return "Takvime eklenemedi."
        }
    }

    private static func yazmaIzniIste(_ store: EKEventStore) async -> Bool {
        await withCheckedContinuation { devam in
            if #available(iOS 17.0, *) {
                store.requestWriteOnlyAccessToEvents { verildi, _ in devam.resume(returning: verildi) }
            } else {
                store.requestAccess(to: .event) { verildi, _ in devam.resume(returning: verildi) }
            }
        }
    }

    // MARK: - Yerel hatırlatma

    /// Randevudan bir gün önce (24 saatten yakınsa 2 saat önce) tetiklenir.
    /// Sunucu push'undan bağımsızdır: uçak modunda bile çalışır.
    static func hatirlatmaKur(baslik: String, govde: String, randevuZamani: Date, kimlik: String) async -> String {
        let merkez = UNUserNotificationCenter.current()

        let izinli: Bool = await withCheckedContinuation { devam in
            merkez.requestAuthorization(options: [.alert, .sound]) { verildi, _ in
                devam.resume(returning: verildi)
            }
        }
        guard izinli else {
            return "Bildirim izni verilmedi. Ayarlar → Doktorumveben'den açabilirsiniz."
        }

        guard let ani = tetiklemeAni(randevuZamani) else {
            return "Randevuya çok az kaldığı için hatırlatma kurulmadı."
        }

        let icerik = UNMutableNotificationContent()
        icerik.title = baslik
        icerik.body = govde
        icerik.sound = .default

        let parcalar = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: ani)
        let istek = UNNotificationRequest(
            identifier: "dvb-randevu-\(kimlik)",
            content: icerik,
            trigger: UNCalendarNotificationTrigger(dateMatching: parcalar, repeats: false)
        )

        do {
            try await merkez.add(istek)
            return "Hatırlatma kuruldu: \(ani.dvbLong)"
        } catch {
            return "Hatırlatma kurulamadı."
        }
    }

    /// 24 saat önce; o an geçmişse 2 saat önce; o da geçmişse hatırlatma yok.
    private static func tetiklemeAni(_ randevu: Date) -> Date? {
        let simdi = Date()
        for saat in [24.0, 2.0] {
            let an = randevu.addingTimeInterval(-saat * 3600)
            if an > simdi.addingTimeInterval(60) { return an }
        }
        return nil
    }
}
