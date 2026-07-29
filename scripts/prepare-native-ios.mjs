/**
 * Doktorumveben iOS — `npx cap add ios` + `cap sync ios` SONRASI native projeyi
 * App Store'a uygun hale getirir. `ios/` her CI derlemesinde sıfırdan üretildiği için
 * bu ayarların HER derlemede yeniden yazılması gerekir.
 *
 * Yaptıkları:
 *  1) Info.plist — kamera/mikrofon/foto izin AÇIKLAMALARI (görüntülü muayene + belge yükleme).
 *     Yoksa hem getUserMedia çöker HEM Apple "eksik amaç dizesi" ile reddeder.
 *  2) App.entitlements — aps-environment=production (push). Yoksa iOS cihaz token'ı üretmez.
 *  3) project.pbxproj — CODE_SIGN_ENTITLEMENTS bağla + TARGETED_DEVICE_FAMILY=1 (iPhone-only).
 *  4) PrivacyInfo.xcprivacy — 2024'ten beri ZORUNLU privacy manifest (required-reason API'lar
 *     + NSPrivacyTracking=false → ATT gerekmez, "tracking yok").
 *  5) firebase/GoogleService-Info.plist varsa kopyala (FCM/push için). Yoksa UYARIR (durdurmaz).
 *
 * Eksik kritik dosyada SESSİZ geçmez; ama push henüz kurulmadıysa derlemeyi engellemez.
 * Kullanım: node scripts/prepare-native-ios.mjs
 */
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import crypto from 'node:crypto';

const root = process.cwd();
const say = (m) => console.log(`[ios-hazırlık] ${m}`);
const warn = (m) => console.warn(`\n[UYARI] ${m}\n`);
const die = (m) => { console.error(`\n[HATA] ${m}\n`); process.exit(1); };
const read = (p) => fs.readFileSync(p, 'utf8');
const write = (p, c) => fs.writeFileSync(p, c, 'utf8');

const appDir = path.join(root, 'ios/App/App');
const pbxPath = path.join(root, 'ios/App/App.xcodeproj/project.pbxproj');
if (!fs.existsSync(appDir)) die('ios/ klasörü yok. Önce: npx cap add ios && npx cap sync ios');

// ── 0) MARKA GÖRSELLERİ — App Store 2.3.8 (28 Tem 2026 reddinin sebebi) ──────
// `ios/` sürüm kontrolünde YOK; her CI derlemesinde `npx cap add ios` Capacitor'ın
// ŞABLONUNU açıyor ve AppIcon.appiconset içine kendi yer-tutucu logosunu koyuyor.
// 1.0 (8) bu yüzden Capacitor logosuyla mağazaya gitti → "app icons appear to be
// placeholder icons". capacitor-assets adımı CI'da eklendi, AMA tek dayanak o değil:
// burada ikon KOŞULSUZ marka dosyasıyla yazılır ve doğrulanmadan derleme İLERLEMEZ.
const iconSrcPath = path.join(root, 'assets/app-icon-1024.png');
const iconSetDir = path.join(appDir, 'Assets.xcassets/AppIcon.appiconset');
const splashSetDir = path.join(appDir, 'Assets.xcassets/Splash.imageset');
const assetsMarker = path.join(root, 'ios/.assets-generated'); // capacitor-assets başarıyla koştuysa CI yaratır
const BRAND_RGB = [0x08, 0x91, 0xB2]; // #0891B2 — marka teali (SplashScreen eklentisiyle aynı)

const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();
const crc32 = (buf) => {
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
};

/** PNG başlığını okur: boyut + renk tipi + tRNS (şeffaflık) var mı. */
function pngInfo(buf) {
  if (buf.length < 33 || buf.readUInt32BE(0) !== 0x89504e47) return null;
  const info = { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20), colorType: buf[25], hasTrns: false };
  let off = 8;
  while (off + 8 <= buf.length) {
    const len = buf.readUInt32BE(off);
    const type = buf.toString('ascii', off + 4, off + 8);
    if (type === 'tRNS') info.hasTrns = true;
    if (type === 'IEND') break;
    off += 12 + len;
  }
  return info;
}

/** Bağımlılıksız (zlib) düz renk PNG — capacitor-assets çalışmazsa açılış ekranı yedeği. */
function solidPng(w, h, [r, g, b]) {
  const row = Buffer.alloc(1 + w * 3); // filtre baytı 0 (None) + RGB
  for (let x = 0; x < w; x++) { row[1 + x * 3] = r; row[2 + x * 3] = g; row[3 + x * 3] = b; }
  const idat = zlib.deflateSync(Buffer.concat(Array.from({ length: h }, () => row)), { level: 9 });
  const chunk = (type, data) => {
    const out = Buffer.alloc(12 + data.length);
    out.writeUInt32BE(data.length, 0);
    out.write(type, 4, 'ascii');
    data.copy(out, 8);
    out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length);
    return out;
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 2; // 8 bit, truecolor (alfa YOK)
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr), chunk('IDAT', idat), chunk('IEND', Buffer.alloc(0)),
  ]);
}

if (!fs.existsSync(iconSrcPath)) die('assets/app-icon-1024.png YOK — App Store ikonu olmadan derleme yapılmaz.');
const iconBuf = fs.readFileSync(iconSrcPath);
const iconMeta = pngInfo(iconBuf);
if (!iconMeta) die('assets/app-icon-1024.png geçerli bir PNG değil.');
if (iconMeta.width !== 1024 || iconMeta.height !== 1024) {
  die(`App Store ikonu 1024x1024 olmalı (bulunan: ${iconMeta.width}x${iconMeta.height}).`);
}
// Apple App Store ikonunda ŞEFFAFLIK KABUL ETMEZ (colorType 4/6 = alfa kanalı, tRNS = renk anahtarı).
if (iconMeta.colorType === 4 || iconMeta.colorType === 6 || iconMeta.hasTrns) {
  die('App Store ikonunda alfa/şeffaflık var — Apple reddeder. Düz zeminli PNG üretin.');
}
if (!fs.existsSync(iconSetDir)) die(`AppIcon.appiconset yok: ${iconSetDir} — cap add ios düzgün çalışmamış.`);

const iconSha = crypto.createHash('sha256').update(iconBuf).digest('hex');
let iconsWritten = 0;
for (const f of fs.readdirSync(iconSetDir).filter((f) => f.toLowerCase().endsWith('.png'))) {
  const p = path.join(iconSetDir, f);
  const meta = pngInfo(fs.readFileSync(p));
  // Capacitor 8 appiconset'i tek yuvalıdır (1024). capacitor-assets koştuysa da aynı
  // dosyayı marka ikonuyla üzerine yazmak zararsız; koşmadıysa yer tutucuyu siler.
  if (meta && meta.width === 1024 && meta.height === 1024) {
    fs.writeFileSync(p, iconBuf);
    iconsWritten++;
  }
}
const iconOk = fs.readdirSync(iconSetDir)
  .filter((f) => f.toLowerCase().endsWith('.png'))
  .some((f) => crypto.createHash('sha256').update(fs.readFileSync(path.join(iconSetDir, f))).digest('hex') === iconSha);
if (!iconOk) {
  die('AppIcon marka ikonuyla yazılamadı — 1024x1024 yuva bulunamadı. Bu hâliyle derleme yine 2.3.8 reddi alır.');
}
say(`AppIcon doğrulandı: 1024x1024, alfa yok, ${iconsWritten} dosya marka ikonuyla yazıldı (sha ${iconSha.slice(0, 12)}…).`);

// Açılış ekranı: capacitor-assets koştuysa (marker) logolu splash üretilmiştir; koşmadıysa
// şablonda Capacitor logosu kalır → onu da düz marka rengiyle değiştiriyoruz (yer tutucu kalmasın).
if (fs.existsSync(assetsMarker)) {
  say('Açılış ekranı capacitor-assets tarafından üretildi (marka logosu).');
} else if (fs.existsSync(splashSetDir)) {
  let n = 0;
  for (const f of fs.readdirSync(splashSetDir).filter((f) => f.toLowerCase().endsWith('.png'))) {
    const p = path.join(splashSetDir, f);
    const meta = pngInfo(fs.readFileSync(p));
    if (!meta) continue;
    fs.writeFileSync(p, solidPng(meta.width, meta.height, BRAND_RGB));
    n++;
  }
  warn(`capacitor-assets çalışmadı → açılış ekranı düz marka rengine (#0891B2) çevrildi (${n} dosya). Capacitor yer-tutucu logosu KALMADI, ama logolu splash için CI adımı onarılmalı.`);
}

// ── 1) Info.plist izin açıklamaları ─────────────────────────────────────────
const plistPath = path.join(appDir, 'Info.plist');
let plist = read(plistPath);
const usageKeys = {
  NSCameraUsageDescription:
    'Görüntülü muayene ve belge/fotoğraf yüklemek için kameraya erişim gerekir.',
  NSMicrophoneUsageDescription:
    'Doktorunuzla görüntülü görüşme yapabilmek için mikrofona erişim gerekir.',
  NSPhotoLibraryUsageDescription:
    'Randevu ve sağlık belgelerinizi yükleyebilmek için fotoğraflara erişim gerekir.',
  NSPhotoLibraryAddUsageDescription:
    'Belge ve raporları cihazınıza kaydedebilmek için galeriye erişim gerekir.',
  // Tur 230 — "Yakınımdakiler": WKWebView'daki geolocation çağrısı bu anahtar OLMADAN
  // iOS'ta sessizce reddedilir (uygulama içinde buton hiç çalışmaz).
  NSLocationWhenInUseUsageDescription:
    'Size en yakın hekimleri sıralayabilmek için konumunuza erişim gerekir. Konumunuz kaydedilmez.',
  // Tur 238 — Randevuyu telefonun KENDİ takvimine yazma (DVBCalendarKit).
  // iOS 17 takvim iznini ikiye böldü: yalnız-yazma anahtarı olmadan iOS 17+'ta
  // izin diyaloğu HİÇ açılmaz; eski anahtar da iOS 16 ve altı için gerekli.
  NSCalendarsWriteOnlyAccessUsageDescription:
    'Randevunuzu telefonunuzun takvimine ekleyebilmek için izin gerekir. Takviminiz okunmaz.',
  NSCalendarsUsageDescription:
    'Randevunuzu telefonunuzun takvimine ekleyebilmek için izin gerekir.',
};
let addedUsage = [];
for (const [key, val] of Object.entries(usageKeys)) {
  if (!plist.includes(`<key>${key}</key>`)) {
    // İlk <dict>'ten hemen sonra ekle.
    plist = plist.replace(/<dict>/, `<dict>\n\t<key>${key}</key>\n\t<string>${val}</string>`);
    addedUsage.push(key);
  }
}
// ITSAppUsesNonExemptEncryption = NO → Export Compliance sorusunu otomatik geçer.
if (!plist.includes('<key>ITSAppUsesNonExemptEncryption</key>')) {
  plist = plist.replace(/<dict>/, '<dict>\n\t<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>');
}
write(plistPath, plist);
say(`Info.plist izin/uyum anahtarları yazıldı${addedUsage.length ? ' (' + addedUsage.join(', ') + ')' : ' (zaten vardı)'}.`);

// ── 2) App.entitlements (push) ──────────────────────────────────────────────
// KRİTİK: aps-environment SADECE Firebase gerçekten yapılandırıldığında (firebase/
// GoogleService-Info.plist mevcutken) yazılır. Aksi halde profilde Push capability
// olmadığı için Xcode arşivi "requires a provisioning profile with the Push
// Notifications feature" ile REDDEDER. Push kurulunca (o .plist eklenince) hem bu
// entitlement hem de Apple Developer'da App ID'ye Push capability gerekir.
const entPath = path.join(appDir, 'App.entitlements');
const pushReady = fs.existsSync(path.join(root, 'firebase/GoogleService-Info.plist'));
const entInner = pushReady
  ? '\t<key>aps-environment</key>\n\t<string>production</string>\n'
  : '';
write(entPath, `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
${entInner}</dict>
</plist>
`);
say(pushReady
  ? 'App.entitlements yazıldı (aps-environment: production — push aktif).'
  : 'App.entitlements yazıldı (push YOK — firebase/GoogleService-Info.plist eklenince otomatik açılır).');

// ── 3) PrivacyInfo.xcprivacy (ZORUNLU privacy manifest, YOL B = tracking yok) ─
const privPath = path.join(appDir, 'PrivacyInfo.xcprivacy');
write(privPath, `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<key>NSPrivacyCollectedDataTypes</key>
	<array/>
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array><string>CA92.1</string></array>
		</dict>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array><string>C617.1</string></array>
		</dict>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategorySystemBootTime</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array><string>35F9.1</string></array>
		</dict>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryDiskSpace</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array><string>E174.1</string></array>
		</dict>
	</array>
</dict>
</plist>
`);
say('PrivacyInfo.xcprivacy yazıldı (tracking=false + required-reason API gerekçeleri).');

// ── 4) project.pbxproj — entitlements + iPhone-only + kaynak dosya üyelikleri ─
if (!fs.existsSync(pbxPath)) die('project.pbxproj yok — cap add/sync başarısız olmuş olabilir.');
let pbx = read(pbxPath);

// 4a) CODE_SIGN_ENTITLEMENTS
if (!pbx.includes('CODE_SIGN_ENTITLEMENTS')) {
  pbx = pbx.replace(
    /(PRODUCT_BUNDLE_IDENTIFIER = [^;]+;)/g,
    '$1\n\t\t\t\tCODE_SIGN_ENTITLEMENTS = App/App.entitlements;',
  );
  say('CODE_SIGN_ENTITLEMENTS build ayarı eklendi.');
}
// 4b) iPhone-only (iPad görseli zorunluluğunu ve bozuk iPad görünümü reddini önler)
if (/TARGETED_DEVICE_FAMILY = "1,2";/.test(pbx)) {
  pbx = pbx.replace(/TARGETED_DEVICE_FAMILY = "1,2";/g, 'TARGETED_DEVICE_FAMILY = 1;');
  say('TARGETED_DEVICE_FAMILY = 1 (iPhone-only) ayarlandı.');
} else if (!/TARGETED_DEVICE_FAMILY/.test(pbx)) {
  pbx = pbx.replace(
    /(PRODUCT_BUNDLE_IDENTIFIER = [^;]+;)/g,
    '$1\n\t\t\t\tTARGETED_DEVICE_FAMILY = 1;',
  );
  say('TARGETED_DEVICE_FAMILY = 1 eklendi.');
}
write(pbxPath, pbx);

// NOT: PrivacyInfo.xcprivacy ve (varsa) GoogleService-Info.plist'in Xcode "Copy Bundle
// Resources" fazına üyeliği pbxproj'da elle referans ister. Capacitor 8 App klasörünü grup
// olarak referanslar; yeni dosyanın hedefe eklenmesi ilk gerçek derlemede DOĞRULANMALI
// (App Store Connect "PrivacyInfo eksik/ITMS-91053" verirse bu dosyanın bundle'a
// eklenmesi Xcode/pbxproj tarafında tamamlanacak).
warn('PrivacyInfo.xcprivacy + GoogleService-Info.plist bundle üyeliği ilk Codemagic derlemesinde doğrulanmalı (pbxproj resource fazı).');

// ── 5) Firebase (push) — opsiyonel, yoksa uyar ──────────────────────────────
const gsSrc = path.join(root, 'firebase/GoogleService-Info.plist');
if (fs.existsSync(gsSrc)) {
  fs.copyFileSync(gsSrc, path.join(appDir, 'GoogleService-Info.plist'));
  say('GoogleService-Info.plist kopyalandı (iOS push aktif).');
} else {
  warn(
    'firebase/GoogleService-Info.plist YOK → iOS push henüz kurulmadı.\n' +
    'Firebase Console → iOS uygulaması (com.doktorumveben.app) ekle → .plist indir → firebase/ içine koy.\n' +
    'Ayrıca APNs Auth Key (.p8) Firebase Cloud Messaging ayarlarına yüklenmeli. (4.2 için push önerilir.)',
  );
}

say('iOS hazırlık tamamlandı.');
