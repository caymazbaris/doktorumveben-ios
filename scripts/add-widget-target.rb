# frozen_string_literal: true

# DVB-000111 — WIDGET UZANTISI HEDEFİNİ PROJEYE EKLER (WidgetKit).
#
# NEDEN RUBY / xcodeproj GEM:
# Widget ayrı bir Xcode HEDEFİ ister: PBXNativeTarget (app-extension), kendi build
# fazları, kendi XCBuildConfiguration listesi, ana hedefe "Embed App Extensions"
# kopyalama fazı, ayrı Info.plist ve entitlements. Bunu project.pbxproj metnini
# elle keserek yapmak, doğrulanamayan ve derlemeyi topyekûn kıran bir iş olurdu
# (Mac yok, her deneme bulut CI'da ~15 dk). `xcodeproj` gem'i tam bu iş için var
# ve zaten macOS runner'ında mevcut.
#
# ⚠ HATA DURUMUNDA DERLEME DURMAZ — BİLİNÇLİ:
# Bu betik başarısız olursa uygulama widget OLMADAN derlenip mağazaya gider.
# Widget güzel bir ek; ama onun yüzünden 4.2 düzeltmelerini taşıyan sürümün
# hiç çıkamaması kabul edilemez. Bu yüzden her hata yakalanır, sebebi yazılır,
# proje dosyası ORİJİNALİNE geri alınır ve çıkış kodu 0 olur.
#
# Kullanım (Codemagic, `cap add ios` ve prepare-native-ios.mjs SONRASI):
#   ruby scripts/add-widget-target.rb

require 'fileutils'

PROJ_PATH   = 'ios/App/App.xcodeproj'
APP_TARGET  = 'App'
WIDGET_NAME = 'DVBWidgetExtension'
BUNDLE_ID   = 'com.doktorumveben.app'
APP_GROUP   = 'group.com.doktorumveben.app'
WIDGET_SRC  = 'widget/DVBWidget.swift'

# Widget'ın uygulamayla PAYLAŞTIĞI dosyalar. Widget bunlar olmadan derlenmez:
# önbelleği DVBOfflineStore okur, çözdüğü tip DVBAgenda'dır.
SHARED = ['ios/App/App/Native/DVBOfflineStore.swift', 'ios/App/App/Native/DVBModels.swift'].freeze

def say(m)  = puts("[widget] #{m}")
def warn!(m) = warn("\n[UYARI] widget hedefi eklenmedi: #{m}\n" \
                    "Uygulama widget OLMADAN derlenmeye devam edecek.\n")

yedek = "#{PROJ_PATH}/project.pbxproj.yedek"

begin
  require 'xcodeproj'
rescue LoadError
  warn!('`xcodeproj` gem bulunamadı (gem install xcodeproj).')
  exit 0
end

unless File.exist?("#{PROJ_PATH}/project.pbxproj")
  warn!("#{PROJ_PATH} yok — cap add ios koşmamış olabilir.")
  exit 0
end

unless File.exist?(WIDGET_SRC)
  warn!("#{WIDGET_SRC} yok.")
  exit 0
end

eksik = SHARED.reject { |f| File.exist?(f) }
unless eksik.empty?
  warn!("paylaşılan kaynaklar yok: #{eksik.join(', ')} (inject-native-swift.mjs önce koşmalı).")
  exit 0
end

FileUtils.cp("#{PROJ_PATH}/project.pbxproj", yedek)

begin
  proje = Xcodeproj::Project.open(PROJ_PATH)

  if proje.targets.any? { |t| t.name == WIDGET_NAME }
    say("#{WIDGET_NAME} zaten var — atlandı (betik idempotent).")
    FileUtils.rm_f(yedek)
    exit 0
  end

  app = proje.targets.find { |t| t.name == APP_TARGET }
  raise "ana hedef '#{APP_TARGET}' bulunamadı" if app.nil?

  # ── Kaynak klasörü ────────────────────────────────────────────────────────
  hedef_dir = "ios/App/#{WIDGET_NAME}"
  FileUtils.mkdir_p(hedef_dir)
  FileUtils.cp(WIDGET_SRC, "#{hedef_dir}/DVBWidget.swift")

  # Uzantının kendi Info.plist'i. NSExtension anahtarı olmadan Xcode bunu
  # widget saymaz; App Store da "geçersiz uzantı" ile reddeder.
  File.write("#{hedef_dir}/Info.plist", <<~PLIST)
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    \t<key>CFBundleDisplayName</key>
    \t<string>Randevularım</string>
    \t<key>NSExtension</key>
    \t<dict>
    \t\t<key>NSExtensionPointIdentifier</key>
    \t\t<string>com.apple.widgetkit-extension</string>
    \t</dict>
    </dict>
    </plist>
  PLIST

  # Uzantının entitlements'ı — App Group ANA UYGULAMAYLA AYNI olmalı,
  # yoksa widget ortak kabı göremez ve hep boş görünür.
  File.write("#{hedef_dir}/#{WIDGET_NAME}.entitlements", <<~ENT)
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    \t<key>com.apple.security.application-groups</key>
    \t<array>
    \t\t<string>#{APP_GROUP}</string>
    \t</array>
    </dict>
    </plist>
  ENT

  # ── Hedef ─────────────────────────────────────────────────────────────────
  widget = proje.new_target(
    :app_extension, WIDGET_NAME, :ios,
    app.deployment_target || '17.0'
  )

  # ⚠ GRUP YOLU PROJEYE GÖRE, DEPO KÖKÜNE GÖRE DEĞİL.
  # İlk yazışımda `new_group(WIDGET_NAME, hedef_dir)` demiştim; hedef_dir depo
  # kökünden "ios/App/DVBWidgetExtension" idi. Ama .xcodeproj dosyası zaten
  # ios/App altında olduğu için Xcode bunu "ios/App/ios/App/..." diye çözerdi:
  # kaynak dosya BULUNAMAZ, hedef boş derlenir. Proje kökü ios/App olduğundan
  # yol yalnızca klasör adı olmalı. (INFOPLIST_FILE ve CODE_SIGN_ENTITLEMENTS
  # ayarları da aynı köke göre yazılıyor — üçü tutarlı.)
  grup = proje.main_group.new_group(WIDGET_NAME, WIDGET_NAME)
  widget.add_file_references([grup.new_reference('DVBWidget.swift')])

  # Paylaşılan dosyalar İKİ hedefe birden üye olur. Kopyalamak yerine üyelik
  # veriyoruz: kopya olsaydı iki tanım zamanla ayrışır ve widget yanlış veri gösterirdi.
  SHARED.each do |yol|
    ref = proje.files.find { |f| f.real_path.to_s.end_with?(File.basename(yol)) }
    widget.add_file_references([ref]) if ref
  end

  widget.build_configurations.each do |c|
    c.build_settings.merge!(
      'PRODUCT_BUNDLE_IDENTIFIER'          => "#{BUNDLE_ID}.widget",
      'INFOPLIST_FILE'                     => "#{WIDGET_NAME}/Info.plist",
      'CODE_SIGN_ENTITLEMENTS'             => "#{WIDGET_NAME}/#{WIDGET_NAME}.entitlements",
      'TARGETED_DEVICE_FAMILY'             => '1',
      'SWIFT_VERSION'                      => '5.0',
      'SKIP_INSTALL'                       => 'YES',
      'ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES' => 'NO',
      'MARKETING_VERSION'                  => '1.0',
      'CURRENT_PROJECT_VERSION'            => '1',
    )
  end

  # ── Ana uygulamaya göm ────────────────────────────────────────────────────
  # Bu faz olmadan .appex ipa'ya girmez: widget "eklendi" görünür ama cihazda YOKTUR.
  faz = app.copy_files_build_phases.find { |p| p.symbol_dst_subfolder_spec == :plug_ins }
  faz ||= begin
    f = app.new_copy_files_build_phase('Embed App Extensions')
    f.symbol_dst_subfolder_spec = :plug_ins
    f
  end
  faz.add_file_reference(widget.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  app.add_dependency(widget)

  proje.save
  FileUtils.rm_f(yedek)
  say("#{WIDGET_NAME} eklendi (bundle #{BUNDLE_ID}.widget, App Group #{APP_GROUP}).")
rescue StandardError => e
  # Projeyi bozulmuş bırakma: yedeği geri koy.
  FileUtils.cp(yedek, "#{PROJ_PATH}/project.pbxproj") if File.exist?(yedek)
  FileUtils.rm_f(yedek)
  warn!("#{e.class}: #{e.message}")
  exit 0
end
