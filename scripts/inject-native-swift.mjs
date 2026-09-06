/**
 * Tur 235 — `native/*.swift` dosyalarını Capacitor'ın ÜRETTİĞİ Xcode projesine enjekte eder.
 *
 * NEDEN GEREKLİ: `ios/` sürüm kontrolünde yok; her CI derlemesinde `npx cap add ios`
 * şablondan sıfırdan üretiliyor. Dolayısıyla Swift kaynaklarımız da her derlemede
 * yeniden kopyalanıp Xcode hedefine yeniden eklenmeli. Xcode'da elle dosya eklemek
 * bir sonraki derlemede KAYBOLUR.
 *
 * Yaptıkları:
 *  1) native/AppDelegate.swift → App/AppDelegate.swift (kök görünüm SwiftUI olur)
 *  2) native/DVB*.swift        → App/Native/
 *  3) Info.plist'ten UIMainStoryboardFile kaldırılır (aksi hâlde storyboard ikinci
 *     bir pencere kökü kurar ve native kökle çakışır)
 *  4) project.pbxproj: fileRef + buildFile + "Native" grubu + Sources fazı üyeliği
 *
 * GÜVENLİK AĞI: pbxproj'a yazmadan ÖNCE beklenen çapa dizgileri aranır ve yazdıktan
 * sonra sonuç doğrulanır. Tek bir tutarsızlıkta hata verip çıkar — bozuk bir pbxproj
 * Xcode'un projeyi hiç açamamasına yol açar ve her deneme ~15 dakikadır.
 *
 * Kullanım: node scripts/inject-native-swift.mjs
 */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const root = process.cwd();
const say = (m) => console.log(`[native-enjekte] ${m}`);
const die = (m) => { console.error(`\n[HATA] ${m}\n`); process.exit(1); };

const nativeDir = path.join(root, 'native');
const appDir = path.join(root, 'ios/App/App');
const targetDir = path.join(appDir, 'Native');
const pbxPath = path.join(root, 'ios/App/App.xcodeproj/project.pbxproj');

if (!fs.existsSync(nativeDir)) die('native/ klasörü yok.');
if (!fs.existsSync(appDir)) die('ios/App/App yok — önce npx cap add ios && npx cap sync ios.');
if (!fs.existsSync(pbxPath)) die('project.pbxproj yok.');

/* ── 1) AppDelegate ────────────────────────────────────────────────────────── */
const appDelegateSrc = path.join(nativeDir, 'AppDelegate.swift');
if (!fs.existsSync(appDelegateSrc)) die('native/AppDelegate.swift yok.');
fs.copyFileSync(appDelegateSrc, path.join(appDir, 'AppDelegate.swift'));
say('AppDelegate.swift değiştirildi (kök görünüm: DVBRootView).');

/* ── 1b) SceneDelegate (DVB-000124) ────────────────────────────────────────────
 * Capacitor 8.5 iOS şablonu SAHNE (UIScene) yaşam döngüsüne geçti: Info.plist'e
 * UIApplicationSceneManifest eklendi ve şablon kendi SceneDelegate'ini getiriyor;
 * o da kökü doğrudan CAPBridgeViewController() yapıyor — yani siteyi açan WebView.
 *
 * Sahne manifesti varken UIKit AppDelegate.window'u YOK SAYAR. Yani yukarıdaki
 * AppDelegate değişimi tek başına HİÇBİR İŞE YARAMIYORDU: native ekranlar derleniyor,
 * ikiliye giriyor, ama uygulama açılışta doktorumveben.com'u gösteriyordu. App Store
 * 4.2'nin ("paketlenmiş web sitesi") çözüldüğü sanılan durum sessizce geri gelmişti.
 *
 * ⚠ KOD TARAFINDA HİÇBİR ŞEY DEĞİŞMEDEN OLDU. Değişen, depoda package-lock.json
 * OLMADIĞI için CI'nın çektiği Capacitor sürümüydü (8.4.x → 8.5.1).
 */
const sceneDelegateSrc = path.join(nativeDir, 'SceneDelegate.swift');
if (!fs.existsSync(sceneDelegateSrc)) die('native/SceneDelegate.swift yok — sahne kökü kurulamaz.');
fs.copyFileSync(sceneDelegateSrc, path.join(appDir, 'SceneDelegate.swift'));
say('SceneDelegate.swift değiştirildi (sahne kökü: DVBRootView).');

/* ── 2) Swift kaynakları ───────────────────────────────────────────────────────
 * AppDelegate ve SceneDelegate App/ kökünde ŞABLON DOSYASININ ÜZERİNE yazılır;
 * App/Native/ altına ikinci bir kopya konursa sınıf adı iki kez tanımlanır ve
 * derleme kırılır.
 */
const sources = fs.readdirSync(nativeDir)
  .filter((f) => f.endsWith('.swift') && f !== 'AppDelegate.swift' && f !== 'SceneDelegate.swift')
  .sort();

if (sources.length === 0) die('native/ içinde DVB*.swift yok.');

fs.rmSync(targetDir, { recursive: true, force: true });
fs.mkdirSync(targetDir, { recursive: true });
for (const f of sources) {
  fs.copyFileSync(path.join(nativeDir, f), path.join(targetDir, f));
}
say(`${sources.length} Swift dosyası App/Native/ altına kopyalandı.`);

/* ── 3) Info.plist — storyboard kökünü kaldır ──────────────────────────────── */
const plistPath = path.join(appDir, 'Info.plist');
let plist = fs.readFileSync(plistPath, 'utf8');
const storyboardKey = /\s*<key>UIMainStoryboardFile<\/key>\s*\n\s*<string>Main<\/string>/;
if (storyboardKey.test(plist)) {
  plist = plist.replace(storyboardKey, '');
  fs.writeFileSync(plistPath, plist, 'utf8');
  say('Info.plist: UIMainStoryboardFile kaldırıldı (native kök devrede).');
} else if (plist.includes('UIMainStoryboardFile')) {
  die('Info.plist içinde UIMainStoryboardFile var ama beklenen biçimde değil — elle bakılmalı.');
} else {
  say('Info.plist zaten storyboard köksüz.');
}

/* ── 3b) Sahne yapılandırmasından storyboard'u kaldır (DVB-000124) ────────────
 * Capacitor 8.5 şablonu sahneyi Main storyboard'una bağlıyor:
 *     <key>UISceneStoryboardFile</key><string>Main</string>
 * Kökü SceneDelegate'imiz kuruyor; bu anahtar kalırsa UIKit ayrıca storyboard'u
 * örnekler — gereksiz bir WebView örneği ve açılışta görünen bir kırpışma.
 */
const sceneStoryboard = /\s*<key>UISceneStoryboardFile<\/key>\s*\n\s*<string>Main<\/string>/;
if (sceneStoryboard.test(plist)) {
  plist = plist.replace(sceneStoryboard, '');
  fs.writeFileSync(plistPath, plist, 'utf8');
  say('Info.plist: UISceneStoryboardFile kaldırıldı (sahne kökü SceneDelegate\'te).');
}

/* ── 3c) SERT KAPI: native kök gerçekten devrede mi? ──────────────────────────
 * ⚠ BU KAPI, DVB-000124'ÜN TEKRARINI ÖNLEMEK İÇİN VAR.
 *
 * Önceki hâlde betik "AppDelegate değiştirildi" deyip başarıyla bitiyordu ve
 * hiçbir şey yanlış görünmüyordu — oysa sahne yaşam döngüsü yüzünden o AppDelegate
 * hiç ekrana gelmiyordu. Hata, üç derleme boyunca (12, 13, 14) fark edilmeden
 * mağazaya gitti. Kusur kodda değil, "yaptım" demenin kanıtlanmamış olmasındaydı.
 *
 * Bundan sonra: sahne manifesti varsa, o sahnenin delegesi BİZİM kökümüzü kurmuyorsa
 * derleme DURUR.
 */
const sonPlist = fs.readFileSync(plistPath, 'utf8');
if (sonPlist.includes('UIApplicationSceneManifest')) {
  const sceneDelegateOut = path.join(appDir, 'SceneDelegate.swift');
  const icerik = fs.existsSync(sceneDelegateOut) ? fs.readFileSync(sceneDelegateOut, 'utf8') : '';

  // ⚠ ATAMAYA bakılır, kelimeye DEĞİL. İlk sürüm `includes('CAPBridgeViewController')`
  // diyordu ve kendi dosyamızın YORUMUNDA geçen sözcüğe takılıp derlemeyi durdurdu.
  // Yanlış pozitif veren bir kapı, kapalı bir kapı kadar zararlıdır: insan onu
  // devre dışı bırakmayı öğrenir.
  const kokAtamasi = /rootViewController\s*=\s*([A-Za-z0-9_]+)/g;
  const kokler = [...icerik.matchAll(kokAtamasi)].map((m) => m[1]);

  if (!/rootView:\s*DVBRootView\(\)/.test(icerik)) {
    die('Sahne yaşam döngüsü açık ama SceneDelegate DVBRootView kurmuyor — '
      + 'uygulama açılışta WEB SİTESİNİ gösterir (DVB-000124). Derleme durduruldu.');
  }
  if (kokler.includes('CAPBridgeViewController')) {
    die('SceneDelegate kökü CAPBridgeViewController olarak ATANIYOR (Capacitor şablonu) — '
      + 'native katman ekrana gelmez (DVB-000124). Derleme durduruldu.');
  }
  say('Sahne kökü doğrulandı: SceneDelegate → DVBRootView (CAPBridgeViewController yok).');
} else {
  say('Sahne manifesti yok — kök AppDelegate üzerinden kuruluyor (eski şablon).');
}

/* ── 4) project.pbxproj ────────────────────────────────────────────────────── */
let pbx = fs.readFileSync(pbxPath, 'utf8');

if (pbx.includes('/* DVB-NATIVE-BASLANGIC */')) {
  say('pbxproj zaten enjekte edilmiş (idempotent) — atlanıyor.');
  process.exit(0);
}

// Çapalar. Biri bile yoksa Capacitor şablonu değişmiş demektir → DUR.
const anchors = {
  buildFileBegin: '/* Begin PBXBuildFile section */',
  fileRefBegin: '/* Begin PBXFileReference section */',
  groupEnd: '/* End PBXGroup section */',
};
for (const [name, needle] of Object.entries(anchors)) {
  if (!pbx.includes(needle)) die(`pbxproj çapası bulunamadı: ${name} (${needle})`);
}

// App grubu ve Sources fazı — kimlikler şablonda sabit ama yine de dizgiyle bulunur.
const appGroupMatch = pbx.match(/([0-9A-F]{24}) \/\* App \*\/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n/);
if (!appGroupMatch) die('pbxproj: "App" PBXGroup bloğu bulunamadı.');

const sourcesMatch = pbx.match(/([0-9A-F]{24}) \/\* Sources \*\/ = \{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = \d+;\n\t\t\tfiles = \(\n/);
if (!sourcesMatch) die('pbxproj: PBXSourcesBuildPhase bloğu bulunamadı.');

/** Dosya adından türetilen kararlı 24 haneli kimlik (idempotent + çakışmasız). */
const uuid = (seed) =>
  ('DB' + crypto.createHash('md5').update(seed).digest('hex').toUpperCase()).slice(0, 24);

const groupId = uuid('group:Native');
const entries = sources.map((f) => ({
  name: f,
  fileRef: uuid('ref:' + f),
  buildFile: uuid('bf:' + f),
}));

// Kimlik çakışması olmadığını doğrula (md5 çakışması pratikte imkânsız ama ucuz kontrol).
for (const id of [groupId, ...entries.flatMap((e) => [e.fileRef, e.buildFile])]) {
  if (pbx.includes(id)) die(`pbxproj: üretilen kimlik zaten kullanılıyor (${id}).`);
}

// 4a) PBXBuildFile
const buildFileLines = entries
  .map((e) => `\t\t${e.buildFile} /* ${e.name} in Sources */ = {isa = PBXBuildFile; fileRef = ${e.fileRef} /* ${e.name} */; };`)
  .join('\n');
pbx = pbx.replace(
  anchors.buildFileBegin,
  `${anchors.buildFileBegin}\n/* DVB-NATIVE-BASLANGIC */\n${buildFileLines}\n/* DVB-NATIVE-BITIS */`,
);

// 4b) PBXFileReference
const fileRefLines = entries
  .map((e) => `\t\t${e.fileRef} /* ${e.name} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ${e.name}; sourceTree = "<group>"; };`)
  .join('\n');
pbx = pbx.replace(anchors.fileRefBegin, `${anchors.fileRefBegin}\n${fileRefLines}`);

// 4c) "Native" grubu + App grubuna üyelik
const groupBlock =
  `\t\t${groupId} /* Native */ = {\n` +
  `\t\t\tisa = PBXGroup;\n` +
  `\t\t\tchildren = (\n` +
  entries.map((e) => `\t\t\t\t${e.fileRef} /* ${e.name} */,`).join('\n') + '\n' +
  `\t\t\t);\n` +
  `\t\t\tpath = Native;\n` +
  `\t\t\tsourceTree = "<group>";\n` +
  `\t\t};\n`;
pbx = pbx.replace(anchors.groupEnd, `${groupBlock}${anchors.groupEnd}`);
pbx = pbx.replace(appGroupMatch[0], `${appGroupMatch[0]}\t\t\t\t${groupId} /* Native */,\n`);

// 4d) Sources fazı üyeliği
const sourceMemberships = entries
  .map((e) => `\t\t\t\t${e.buildFile} /* ${e.name} in Sources */,`)
  .join('\n');
pbx = pbx.replace(sourcesMatch[0], `${sourcesMatch[0]}${sourceMemberships}\n`);

/* ── 5) Yazmadan ÖNCE doğrula ──────────────────────────────────────────────── */
const problems = [];

// Her kimlik hem tanımlanmış hem de kullanılmış olmalı.
for (const e of entries) {
  const refDef = pbx.includes(`${e.fileRef} /* ${e.name} */ = {isa = PBXFileReference`);
  const bfDef = pbx.includes(`${e.buildFile} /* ${e.name} in Sources */ = {isa = PBXBuildFile`);
  const inSources = pbx.includes(`\t\t\t\t${e.buildFile} /* ${e.name} in Sources */,`);
  const inGroup = pbx.includes(`\t\t\t\t${e.fileRef} /* ${e.name} */,`);
  if (!refDef) problems.push(`${e.name}: fileRef tanımı yok`);
  if (!bfDef) problems.push(`${e.name}: buildFile tanımı yok`);
  if (!inSources) problems.push(`${e.name}: Sources fazında değil`);
  if (!inGroup) problems.push(`${e.name}: Native grubunda değil`);
}
if (!pbx.includes(`${groupId} /* Native */,`)) problems.push('Native grubu App grubuna eklenmemiş');

// Kaba yapı kontrolü: süslü parantezler dengeli mi?
const opens = (pbx.match(/\{/g) || []).length;
const closes = (pbx.match(/\}/g) || []).length;
if (opens !== closes) problems.push(`süslü parantez dengesiz (${opens} açık / ${closes} kapalı)`);

if (problems.length) die('pbxproj enjeksiyonu doğrulanamadı:\n  - ' + problems.join('\n  - '));

fs.writeFileSync(pbxPath, pbx, 'utf8');
say(`pbxproj güncellendi: ${entries.length} Swift dosyası "Native" grubuyla App hedefine eklendi.`);
say('Native enjeksiyon tamamlandı.');
