# Doktorumveben — App Store (iOS) Yayınlama Kılavuzu (Capacitor)

Bu klasör, mevcut web uygulamasını **Capacitor** ile iOS (ve istenirse Android) native kabuğa
saran hazır proje iskeletidir. Native WebView canlı `doktorumveben.com`'u açar; üstüne native
push/durum çubuğu/splash eklenir.

> ⚠️ **iOS derleme yalnızca Mac + Xcode'da (veya bulut Mac CI'da) yapılır.** Bu Windows ortamından
> `.ipa` üretilemez — bu yüzden proje **kaynağı** hazırlandı; derleme/imzalama sende (Mac/CI).

---

## 0) Ön koşullar (senin)
- **Apple Developer Program** — $99/yıl. Kuruluş (İksero Ltd.) için **DUNS** şart (bekliyor).
- **Mac + Xcode** *veya* bulut CI: **Codemagic** (önerilen, hazır `codemagic.yaml` bu klasörde) / Ionic Appflow / EAS Build.
- Apple ID + App Store Connect erişimi.

## 0.5) MAC'SİZ YOL — Codemagic bulut CI (ÖNERİLEN, hazır)
Bu klasördeki **`codemagic.yaml`** ile `.ipa` derlemesi tamamen bulutta (kiralık Mac'te) yapılır;
sende Mac/Xcode gerekmez, süreci telefondan/PC tarayıcısından yönetirsin:
1. Bu klasörü **özel bir GitHub reposuna** push et.
2. **codemagic.io**'ya GitHub ile üye ol (kişisel plan: ayda **500 dk macOS ücretsiz** — bu build ~15-25 dk, ayda ~20 build bedava).
3. Apple Developer hesabı açılınca: App Store Connect → Users and Access → Integrations →
   **App Store Connect API anahtarı** oluştur (.p8 indir) → Codemagic → Teams → Integrations →
   **"DoktorumvebenASC"** adıyla ekle (isim `codemagic.yaml` ile birebir aynı olmalı).
4. App Store Connect'te uygulama kaydını oluştur (Bundle ID `com.doktorumveben.app`).
5. Codemagic'te **Start new build** → `ios-release` → sertifika/profil otomatik üretilir,
   `.ipa` derlenir ve **TestFlight'a otomatik yüklenir**. Sonrası: aşağıdaki listeleme metinleriyle incelemeye gönder.
> Güvenlik notu: API anahtarını yalnızca Codemagic panelindeki şifreli alana yükle; repoya asla koyma.

## 1) Projeyi kur (Mac veya herhangi bir makinede)
```bash
cd doktorumveben-ios
npm install
npx cap add ios          # iOS platformunu ekler (Mac gerekir: CocoaPods)
# (opsiyonel Android da:) npx cap add android
npx cap sync
```
- App ikonu/splash: `App/App/Assets.xcassets` içine 1024×1024 ikon (kaynak: doktorumveben.com/img/pwa/icon-512.png'nin 1024 sürümü — istenirse üretirim).

## 2) Xcode'da aç + imzala + push
```bash
npx cap open ios
```
- **Signing & Capabilities:** Team = İksero (Apple hesabın), Bundle ID = `com.doktorumveben.app`.
- **Push Notifications** capability ekle (native APNs). Ayrıca **Background Modes → Remote notifications**.
- APNs anahtarı (App Store Connect → Keys → +APNs) oluştur; sunucudan APNs'e bildirim göndermek için
  backend eklentisi gerekir. **MVP için opsiyonel** — uygulama önce push'suz da yayınlanabilir
  (giriş + randevu + mesajlaşma gerçek işlev olduğu için "asgari işlevsellik" karşılanır).

## 3) Arşivle + App Store Connect'e yükle
- Xcode → **Product → Archive** → **Distribute App → App Store Connect → Upload**.
- App Store Connect'te uygulama kaydı oluştur (aşağıdaki metinlerle), TestFlight → sonra **İncelemeye gönder**.

---

## APP STORE LİSTELEME (kopyala-yapıştır)

**Uygulama adı (≤30):**  `Doktorumveben`
**Alt başlık (≤30):**  `Doktor bul, randevu al`
**Kategori:**  Tıp (Medical)  ·  İkincil: Sağlık ve Fitness

**Tanıtım metni / Promotional (≤170):**
```
Türkiye'nin dört bir yanındaki uzman doktorları bul, incele ve online ya da yüz yüze randevunu
saniyeler içinde al.
```

**Açıklama (Description):**
```
Doktorumveben ile Türkiye genelinde 90'dan fazla branşta uzman doktorları bul ve randevunu kolayca al.

• Doktor Bul: İl, ilçe ve branşa göre filtrele; ilgi alanları, adres, harita ve yorumlarla doğru doktoru seç.
• Kolay Randevu: Doktorun takviminden uygun saati seç, online (görüntülü) veya yüz yüze randevu oluştur.
• Randevularım: Geçmiş ve gelecek randevularını takip et, hatırlatma al.
• Online Görüşme: Uygun doktorlarla güvenli görüntülü muayene.
• WhatsApp Desteği: Randevu talebini veya ücret bilgisini tek dokunuşla ilet.
• Güvenli & KVKK Uyumlu: Sağlık verilerin şifreli saklanır.

Doktorumveben yalnızca doktor ile hastayı buluşturan bir aracı platformdur; tıbbi teşhis ve tedavi
sorumluluğu ilgili hekime/sağlık kuruluşuna aittir.

Doktorumveben, İksero Bilişim Ltd. Şti. ürünüdür.
```

**Anahtar kelimeler (≤100, virgülle):**
```
doktor,randevu,sağlık,online doktor,diş,dermatoloji,psikolog,diyetisyen,muayene,hastane
```

**Destek URL:**  https://doktorumveben.com/iletisim  (yoksa https://doktorumveben.com)
**Pazarlama URL:**  https://doktorumveben.com
**Gizlilik Politikası:**  https://doktorumveben.com/sozlesmeler/gizlilik

**App Privacy (gizlilik etiketi):** Toplanan: Ad, E-posta, Telefon, Sağlık bilgisi, Yaklaşık konum;
amaç: uygulama işlevi + hesap; üçüncü tarafa satış: **Hayır**; şifreli aktarım: **Evet**; silme: **Evet**.

**Yaş sınırı:** 4+ (tıbbi/tedavi bilgisi içerdiğinden Apple 17+ isteyebilir — ankette "Sık/Yoğun
tıbbi bilgi" sorusuna göre belirlenir).

---

## EKRAN GÖRÜNTÜLERİ — ✅ HAZIR (`assets/` klasöründe)
- **`assets/app-icon-1024.png`** — 1024×1024 App Store ikonu (opak, tam kanama; Apple köşeleri kendi yuvarlar).
- **`assets/screenshots/6.7-inch-1290x2796/`** — 4 adet marka çerçeveli kare (zorunlu min. 3 ✓).
- **`assets/screenshots/6.5-inch-1242x2688/`** — aynı 4 kare 6.5" boyutunda.
- Kareler: 01 Ana sayfa (hero) · 02 Doktor Bul listesi · 03 Doktor profili · 04 Randevu (takvim sihirbazı).
- (Opsiyonel iPad 12.9" 2048×2732 istenirse aynı hattan üretilebilir.)

## Not — Apple reddini önlemek
Apple "sadece web" sarmalayıcıları reddedebilir (Kural 4.2). Elde giriş, randevu oluşturma,
mesajlaşma, görüntülü görüşme gibi **gerçek işlevler var** → geçme şansı yüksek. Güçlendirmek için
native push (APNs) eklemek en etkili adımdır (yukarıda).
