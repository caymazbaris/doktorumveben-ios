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

const root = process.cwd();
const say = (m) => console.log(`[ios-hazırlık] ${m}`);
const warn = (m) => console.warn(`\n[UYARI] ${m}\n`);
const die = (m) => { console.error(`\n[HATA] ${m}\n`); process.exit(1); };
const read = (p) => fs.readFileSync(p, 'utf8');
const write = (p, c) => fs.writeFileSync(p, c, 'utf8');

const appDir = path.join(root, 'ios/App/App');
const pbxPath = path.join(root, 'ios/App/App.xcodeproj/project.pbxproj');
if (!fs.existsSync(appDir)) die('ios/ klasörü yok. Önce: npx cap add ios && npx cap sync ios');

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
const entPath = path.join(appDir, 'App.entitlements');
if (!fs.existsSync(entPath)) {
  write(entPath, `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>aps-environment</key>
	<string>production</string>
</dict>
</plist>
`);
  say('App.entitlements oluşturuldu (aps-environment: production).');
}

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
