# App Review Notes — Doktorumveben (com.doktorumveben.app)

> Paste the English block below into **App Store Connect → App Review Information → Notes**.
> Fill the demo credentials before submitting (see "Demo account").

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
1. Browsing works **without login** — open the app, tap "Doktor Bul" (Find a Doctor), filter by
   city/specialty, open a doctor profile, and start a booking to see the appointment calendar.
2. To see patient features (My Appointments, messaging, video), sign in with the demo account below.

**Demo account**
- Login: open the menu → "Giriş" (Sign in).
- Phone / Email: `__________`  ·  Password / One-time code: `__________`
  *(A working test login is provided; if you cannot receive the SMS code, use the credentials above.)*

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
