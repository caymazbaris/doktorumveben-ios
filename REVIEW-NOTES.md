# App Review Notes — Doktorumveben (com.doktorumveben.app)

> Paste the English block below into **App Store Connect → App Review Information → Notes**.
> Fill the demo credentials before submitting (see "Demo account").

---

## What changed since the previous submission (EN — copy/paste this first)

Thank you for the earlier review. We addressed every point:

**4.8 — Sign in with Apple.** Implemented and live. Apple is offered alongside our other sign-in
options on the same screen, and it is not required in order to browse or to book.

**4.2 / 4.2.2 — App is now a full native client with real, bookable doctors.**
Two separate problems were fixed:

1. *Native experience.* Doctor search, the doctor profile, the appointment calendar, the booking
   form and the confirmation screen are now implemented in **SwiftUI**, not a web view. The app also
   uses device capabilities a website cannot: writing the confirmed appointment into the iPhone's
   own Calendar, and setting a local reminder the day before.
2. *Real, bookable inventory.* Practitioners with a signed consent now have **live calendars with
   selectable times**. You can complete a real booking **without creating an account**. Verified
   examples (open the app, tap "Doktor Bul", and search the name):
   - **Op. Dr. Erkan Kulduk** — ENT, İzmir — 20-minute slots, Tue–Sat 11:00–19:00
   - **Uzm. Dr. Erhan Ergin** — Manisa — 20-minute slots, Mon–Sat 08:30–18:30
   - **Kl. Psk. Ekin Sökmen** — Psychologist, İzmir — 60-minute sessions, Mon–Sat 09:00–17:00

   Tap the doctor → "Randevu al" (Book) → pick a day → pick a time → enter a name and a Turkish
   mobile number → submit. The appointment is created immediately and shown with its appointment
   number.

**How confirmation works (important, and why it is not "instant").** In Turkey the practitioner
must confirm a medical appointment before it is final, so a new booking is created with the status
"awaiting approval". The patient is then notified by **WhatsApp and e-mail** the moment the doctor
(or our clinical operations team, for practitioners who do not manage the calendar themselves)
approves it. Doctors who prefer automatic confirmation can enable it in their own panel, in which
case the appointment is confirmed on the spot. Nothing about this flow is a placeholder — it is the
production behaviour used by real patients on doktorumveben.com.

**No dead ends.** For a practitioner who has not opened an online calendar, the app deliberately
does **not** show an empty calendar. It shows "Randevu Talep Et" (request an appointment) and a
WhatsApp option instead, so every doctor in the directory leads to a working way to get an
appointment.

**2.3.8 — Screenshots.** The screenshots have been recaptured from this build so that they show the
actual native screens.

**5.1.1(v) — Account deletion.** A signed-in patient can delete their account and data from inside
the app (Profile → account/data deletion), without contacting support.

---

## Notes to the App Review team (EN — copy/paste)

Doktorumveben is a doctor-appointment marketplace for Turkey. Patients find doctors by
city / district / specialty, view verified profiles, and book in-person or online (video)
appointments. The app is a native iOS client built with Capacitor; the following features are
implemented natively (not just web):

- **Push notifications (APNs):** appointment reminders and secure doctor↔patient messages.
- **Camera & microphone:** in-app video consultation (getUserMedia over WebRTC).
- **Photo library / document upload:** patients attach documents to appointments.
- **On-canvas signature:** informed-consent forms are signed inside the app.
- **Native offline screen:** a branded "No connection / Retry" screen (no blank web view).
- Native splash screen and status-bar integration.

**How to review**
1. Browsing **and booking** work **without login** — open the app, tap "Doktor Bul" (Find a Doctor),
   filter by city/specialty, open a doctor profile, then "Randevu al" to reach the native calendar.
   Search for **Erkan Kulduk** (İzmir), **Erhan Ergin** (Manisa) or **Ekin Sökmen** (İzmir) for
   practitioners with open calendars, and complete a booking end to end as a guest.
2. To see the signed-in patient features (My Appointments, messaging, video consultation, account
   deletion), sign in with the demo account below.

**Demo account**
- Login: open the menu → "Giriş" (Sign in).
- Email: `apple.review@doktorumveben.com`  ·  Password: *entered in App Store Connect → App Review Information*
- **No SMS or one-time code is required** for this account — signing in with the password above is enough.

<!--
İç not (Apple'a gitmiyor):
- Hesap prod'da user #321, rol `patient`, `is_active=true`, `two_factor_enabled=FALSE`.
- 2FA'yı bu hesapta ASLA açmayın. Açılırsa /api/v1/auth/login jeton yerine `requires_otp`
  döner ve SMS bekler; prod'da tanımlı SMS sağlayıcısı YOK (Netgsm boş) → incelemeci
  kalıcı olarak giriş yapamaz ve uygulama reddedilir.
- Şifre kasten bu depoda TUTULMUYOR; yalnız App Store Connect'te saklanır.
- Telefon 905550000000 bilinçli seçildi: oluşturmadan önce users ve patients tablolarında
  çakışma olmadığı doğrulandı (kayıt akışı telefonu eşleşen misafir hasta kaydını YUTAR;
  gerçek bir numara seçilse incelemeci başka birinin randevularını görebilirdi — yutulan
  kayıt sayısı 0 olarak doğrulandı).
-->


**Payments**
Appointment fees are payments for **real-world medical services** (Guideline 3.1.3(e)), processed
by our licensed Turkish payment provider (PayTR). There are no digital goods or subscriptions sold
to patients, so In-App Purchase does not apply. The doctor-side paid subscription is **not** offered
inside the iOS app.

**Privacy / tracking**
The app does **not** track users across other companies' apps or websites; third-party advertising
SDKs are disabled in the native app context, so no ATT prompt is shown and no "Data used to track
you" is declared. Health-related data (appointment reason) is used only for app functionality and is
not shared. Account deletion is available inside the app (Profile → account/data deletion).

**Region & language:** Turkey; content is in Turkish.
**Support:** destek@doktorumveben.com · https://doktorumveben.com

---

## Age rating guidance
Category **Medical**. In the Age Rating questionnaire, "Medical/Treatment-Focused Content" →
answer **Infrequent/Mild** (the app is an appointment directory, not medical advice/diagnosis).
Expected result 12+/13+. Do not overstate — no explicit treatment instructions are provided.

## Reminder before submission
- Fill the demo credentials above with a real working patient login.
- Export Compliance: `ITSAppUsesNonExemptEncryption=false` is already set (standard HTTPS only) →
  answer "No" to the encryption question.
