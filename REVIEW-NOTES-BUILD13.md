# App Review Notes — build 13 (DVB-000110/111/113)

> Bu dosya, **App Store Connect → App Review Information → Notes** alanına girilecek
> metnin birebir kopyasıdır. Alan sınırı **4.000 karakter**.
> Önceki sürüm için yazılan `REVIEW-NOTES.md` build 11'e aittir ve ARTIK GEÇERSİZDİR —
> içinde "Push notifications are NOT in this build" gibi bu sürümde değişmiş ifadeler var.
> Alanı güncellerken burayı da güncelle; ikisi ayrışırsa hangisinin doğru olduğu bilinemez.

## Neden bu metin böyle yazıldı

31.07.2026 reddi iki maddeden ibaretti (2.3.8 ve 4.8.0 ÇÖZÜLDÜ, listede yok):

- **4.2** — "not sufficiently different from a web browsing experience... Including features
  such as **push notifications**, Core Location, or sharing **do not provide a robust enough
  experience**."
- **4.2.2** — "the app only includes **links, images, or content aggregated from the Internet**
  with limited or no native functionality... review the **app concept**."

Bu yüzden metin iki şeyi kanıtlamaya odaklanıyor:

1. Uygulamanın ANA akışı artık web değil (reddin ölçülen kök nedeni buydu: yayındaki
   165.985 hekimin 165.983'ü aday ve onlarda tek eylem web sheet açıyordu).
2. Cihazın yapabildiği, bir tarayıcının YAPISAL OLARAK yapamayacağı işler var.

Apple push'un yetmediğini açıkça yazdığı için metin push'u öne çıkarmıyor.

---

## Gönderilecek metin (birebir — EN)

```text
BUILD 13 — RESUBMISSION. The previously reviewed build was 11 (rejected 31 July 2026 under 4.2 and 4.2.2). This build changes what the app actually does, not how it is described.

WHAT WAS ACTUALLY WRONG, AND WHAT WE CHANGED
Your 4.2.2 note said the app is mostly aggregated web content. That was a fair description of build 11, and we measured why: our directory lists 165,985 practitioners, and 165,983 of them are not yet members. For those practitioners the only action was "Request an appointment", and in build 11 that action opened a web view. So whichever doctor a reviewer tapped, the app's PRIMARY action showed a web page. The native screens existed but were reachable only for the two member doctors — which is why our previous notes had to name specific doctors for you to find them.

In build 13 that flow is native. Tapping any practitioner and choosing "Randevu Talebi" (Request an appointment) opens a native SwiftUI form — name, phone, preferred day, preferred time-of-day, first-visit flag, note, explicit consent — which posts to our API and returns a reference number shown on a native confirmation screen. No web view is involved anywhere in the primary path: search -> practitioner -> request/booking -> confirmation are all native.

DEVICE CAPABILITIES A WEB PAGE CANNOT PROVIDE
1) Face ID / Touch ID lock. Account -> "Face ID ile kilitle". When enabled, the app requires biometric (or device passcode) authentication on launch and whenever it returns from the background, and it blurs its own content in the app switcher. Off by default, user-controlled.
2) Offline access to your own appointments. Upcoming appointments and pending requests are cached in a shared App Group container and remain readable with no network at all. Put the device in Airplane Mode and open the app: your appointments are still there. Build 11 showed an error screen — indistinguishable from a website.
3) Home-screen widget (WidgetKit). Add the "Randevularım" widget. For a patient it shows the next appointment or a pending request; for a practitioner it shows today's schedule. The widget reads the shared container and works offline. Patient names are masked server-side ("Ba*** Ca***") and no diagnosis, complaint, speciality, phone or e-mail is ever sent to the widget, because a home screen is visible without unlocking the device.
4) The confirmed appointment is written into the iPhone's own Calendar (EventKit, write-only) with a reminder the day before — unchanged from build 11.
5) Sign in with Apple, native and in-app, with Apple's private e-mail relay — unchanged from build 11.

HOW TO SEE IT WITHOUT AN ACCOUNT
Signing in is optional. Open the app, tap "Doktor Bul", search any name, open a practitioner, tap the button at the bottom. You will get either a native appointment calendar (practitioners with online booking) or the native request form. Both complete without an account.

PRIVACY
No third-party advertising or analytics SDKs run in the native app, so no tracking occurs and no ATT prompt is shown. Health-adjacent data (appointments) is never shared with third parties. Region: Turkey. Content is in Turkish. Support: destek@doktorumveben.com

PAYMENTS
Appointment fees are payments for real-world medical services (Guideline 3.1.3(e)), taken by our licensed Turkish payment provider. No digital goods or subscriptions are sold to patients in this app.
```

---

## Gerçeklik denetimi (iddia ≠ kod olmasın)

| Nottaki iddia | Dayanağı |
| --- | --- |
| Talep akışı native, web sheet yok | `native/DVBRequestView.swift`; `DVBDoctorDetailView`/`DVBBookingView` içindeki `DVBWebSheet` çağrıları kaldırıldı |
| Sunucu ucu var | `POST /api/v1/doctors/{slug}/request` — `Dvb110NativeTalepTest` 6/6 yeşil |
| Face ID kilidi | `native/DVBBiometricLock.swift` + Hesabım'daki anahtar |
| Çevrimdışı randevu | `native/DVBOfflineStore.swift` (App Group) |
| Widget | `widget/DVBWidget.swift` + `scripts/add-widget-target.rb`; build #13 günlüğü: "[widget] DVBWidgetExtension eklendi" |
| Ad maskeleme sunucuda | `NameMasker::mask($ad, 2)`; `Dvb111HekimWidgetTest` ham gövdede tam adın geçmediğini sınıyor |
| 165.983 / 165.985 sayısı | 05.09.2026 canlı sayım |

⚠ **HENÜZ DOĞRULANMAMIŞ:** yukarıdaki maddelerin hiçbiri GERÇEK CİHAZDA denenmedi.
Build #13 derlendi ve App Store Connect'e yüklendi, ama TestFlight'ta açılmadı.
"Derlendi" ile "çalışıyor" arasındaki fark bu notun güvenilirliğini belirler:
reviewer tarif edilen bir şeyi bulamazsa 4.2'ye 2.3.8 (yanıltıcı metadata) eklenir.
