import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../common.dart';
import '../../models/platform_model.dart';
import '../../models/server_model.dart';
import 'connection_page.dart';
import 'desktop_setting_page.dart';
import 'desktop_tab_page.dart';
import 'keyplus_access.dart';
import 'keyplus_layout.dart';

const keyplusRed = Color(0xFFDF192A);
const keyplusNavy = Color(0xFF102B3B);

// Visual preferences only. Access policy continues to come from ServerModel.
class KeyplusHome extends StatefulWidget {
  final Widget warning;
  final String systemError;
  const KeyplusHome(
      {super.key, required this.warning, required this.systemError});
  @override
  State<KeyplusHome> createState() => _KeyplusHomeState();
}

class _KeyplusHomeState extends State<KeyplusHome> with WidgetsBindingObserver {
  late bool operatorView;
  String health = 'checking';
  bool canUpdate = false;
  bool checking = false;
  String? updateResult;

  @override
  void initState() {
    super.initState();
    operatorView =
        bind.mainGetLocalOption(key: 'keyplus-home-view') == 'operator';
    WidgetsBinding.instance.addObserver(this);
    refreshHealth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refreshHealth();
  }

  Future<void> refreshHealth() async {
    if (checking) return;
    setState(() {
      checking = true;
      health = 'checking';
      canUpdate = false;
    });
    var result = <String, dynamic>{'state': 'unknown'};
    try {
      result = Map<String, dynamic>.from(
          jsonDecode(await bind.mainGetCommon(key: 'keyplus-service-health')));
    } catch (_) {/* Unknown is an explicit state, never inferred as ready. */}
    if (!mounted) return;
    setState(() {
      health = keyplusKnownServiceState(result['state']);
      canUpdate = health == 'mismatch' && result['canUpdate'] == true;
      checking = false;
    });
  }

  void openSettings(SettingsTabKey tab) {
    DesktopTabPage.onAddSetting(initialPage: tab);
  }

  Future<void> updateService() async {
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Kurulu hizmeti güncelle'),
              content: const SizedBox(
                  width: 440,
                  child: Text(
                      'Açık uzak bağlantılar kesilebilir. Windows yönetici izni isteyecek ve uygulama yeniden açılabilir. '
                      'Cihaz kimliğiniz, parolanız ve erişim tercihleriniz korunur. Devam etmeden önce karşı taraftaki çalışmayı kaydedin.')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Vazgeç')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Hizmeti güncelle')),
              ],
            ));
    if (accepted != true || !mounted) return;
    setState(() {
      canUpdate = false;
      updateResult = 'Windows onayı bekleniyor…';
    });
    String result = 'failed';
    try {
      result =
          jsonDecode(await bind.mainGetCommon(key: 'keyplus-update-service'))[
                  'result'] ??
              'failed';
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      updateResult = switch (result) {
        'launched' =>
          'Güncelleme başlatıldı. Uygulama yeniden açıldığında hizmeti tekrar denetleyin.',
        'cancelled' => 'Windows izni verilmedi. Güncelleme başlatılmadı.',
        'unavailable' =>
          'Hizmet durumu değişti. Yeniden denetleyin; gerekirse güncel paketi açın.',
        _ =>
          'Güncelleme başlatılamadı. Windows yönetici iznini kontrol edip yeniden deneyin.',
      };
    });
    await refreshHealth();
  }

  @override
  Widget build(BuildContext context) {
    final original = Theme.of(context);
    final dark = original.brightness == Brightness.dark;
    final theme = original.copyWith(
      textTheme: original.textTheme.apply(
          fontFamily: 'Segoe UI',
          bodyColor: dark ? const Color(0xFFEDF3F5) : keyplusNavy,
          displayColor: dark ? const Color(0xFFEDF3F5) : keyplusNavy),
      scaffoldBackgroundColor:
          dark ? const Color(0xFF0C202C) : const Color(0xFFF2F5F5),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
              backgroundColor: keyplusRed,
              foregroundColor: Colors.white,
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              elevation: 0)),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(44, 44),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12))),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(minimumSize: const Size(44, 44))),
      inputDecorationTheme: original.inputDecorationTheme.copyWith(
          focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: keyplusRed, width: 2),
              borderRadius: BorderRadius.all(Radius.circular(8))),
          enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                  color:
                      dark ? const Color(0xFF607784) : const Color(0xFF879BA5)),
              borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 15)),
    );
    return Theme(
        data: theme,
        child: Builder(
            builder: (context) => Material(
                  color: theme.scaffoldBackgroundColor,
                  child: ChangeNotifierProvider.value(
                      value: gFFI.serverModel,
                      child: Consumer<ServerModel>(
                          builder: (context, model, _) =>
                              LayoutBuilder(builder: (context, constraints) {
                                final narrow = constraints.maxWidth < 780;
                                final receive = _receive(context, model);
                                final connection = _surface(context,
                                    child: ConnectionPage(
                                        keyplusOperator: operatorView));
                                return KeyplusTaskLayout(
                                  header: _header(context, narrow),
                                  receive:
                                      bind.isOutgoingOnly() ? null : receive,
                                  connection:
                                      bind.isIncomingOnly() ? null : connection,
                                  navigation: operatorView
                                      ? _navigation(context)
                                      : null,
                                );
                              }))),
                )));
  }

  Widget _surface(BuildContext context, {required Widget child}) =>
      DecoratedBox(
        decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF142D3C)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: Theme.of(context).dividerColor.withOpacity(0.15))),
        child: child,
      );

  Widget _header(BuildContext context, bool narrow) => Padding(
        padding:
            EdgeInsets.fromLTRB(narrow ? 16 : 24, 20, narrow ? 16 : 24, 20),
        child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 20,
            runSpacing: 12,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Semantics(
                    label: 'Keyplus Destek',
                    image: true,
                    child:
                        Image.asset('assets/icon.png', width: 40, height: 40)),
                const SizedBox(width: 12),
                const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Keyplus Destek',
                          style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                              height: 1.2)),
                      SizedBox(height: 4),
                      Text('Yanınızda, uzaktan.',
                          style: TextStyle(fontSize: 13)),
                    ]),
              ]),
              Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Tooltip(
                        message: 'Bu seçim yalnızca ekran düzenini değiştirir.',
                        child: DropdownButton<bool>(
                            value: operatorView,
                            underline: const SizedBox.shrink(),
                            items: const [
                              DropdownMenuItem(
                                  value: false, child: Text('Sade destek')),
                              DropdownMenuItem(
                                  value: true, child: Text('Operatör görünümü'))
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              bind.mainSetLocalOption(
                                  key: 'keyplus-home-view',
                                  value: value ? 'operator' : 'simple');
                              setState(() => operatorView = value);
                            })),
                    TextButton.icon(
                        onPressed: () => _help(context),
                        icon: const Icon(Icons.help_outline, size: 19),
                        label: const Text('Yardım')),
                    if (!bind.isDisableSettings())
                      TextButton.icon(
                          onPressed: () => openSettings(SettingsTabKey.general),
                          icon: const Icon(Icons.settings_outlined, size: 19),
                          label: const Text('Ayarlar')),
                  ]),
            ]),
      );

  Widget _navigation(BuildContext context) => SizedBox(
      width: 150,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.computer_outlined),
            title: Text('Bağlantılar',
                style: TextStyle(fontWeight: FontWeight.w600))),
        if (!bind.isDisableSettings())
          TextButton.icon(
              onPressed: () => openSettings(SettingsTabKey.safety),
              icon: const Icon(Icons.shield_outlined),
              label: const Text('Erişim izinleri')),
        TextButton.icon(
            onPressed: () => _help(context),
            icon: const Icon(Icons.help_outline),
            label: const Text('Bağlantı yardımı')),
        const Spacer(),
        TextButton(
            onPressed: () => openSettings(SettingsTabKey.about),
            child: const Text('Hakkında ve lisans')),
      ]));

  Widget _receive(BuildContext context, ServerModel model) => _surface(context,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.support_agent_outlined, size: 30, color: keyplusRed),
          const SizedBox(height: 16),
          const Text('Destek alın',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          const Text('Bağlanacak kişiye bu bilgisayarın kimliğini iletin.',
              style: TextStyle(fontSize: 14, height: 1.5)),
          const SizedBox(height: 25),
          const Text('Bu bilgisayarın kimliği', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          ValueListenableBuilder<TextEditingValue>(
              valueListenable: model.serverId,
              builder: (context, value, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SelectableText(
                            value.text.isEmpty
                                ? 'Kimlik alınıyor…'
                                : value.text,
                            semanticsLabel:
                                'Bu bilgisayarın kimliği ${value.text}',
                            style: const TextStyle(
                                fontSize: 29,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5)),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                            onPressed: value.text.isEmpty || value.text == '-'
                                ? null
                                : () async {
                                    await Clipboard.setData(
                                        ClipboardData(text: value.text));
                                    if (mounted) showToast('Kimlik kopyalandı');
                                  },
                            icon: const Icon(Icons.copy_outlined, size: 18),
                            label: const Text('Kimliği kopyala')),
                      ])),
          const SizedBox(height: 22),
          const Divider(),
          const SizedBox(height: 12),
          const Text('Bağlantıya nasıl izin verilir?',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 10),
          Text(keyplusApprovalText(model.approveMode, model.verificationMethod),
              style: const TextStyle(fontSize: 14, height: 1.5)),
          if (model.approveMode != 'click' &&
              model.verificationMethod != kUsePermanentPassword) ...[
            const SizedBox(height: 12),
            ValueListenableBuilder<TextEditingValue>(
                valueListenable: model.serverPasswd,
                builder: (context, value, _) => Row(children: [
                      Expanded(
                          child: SelectableText(
                              'Tek kullanımlık parola: ${value.text.isEmpty ? 'hazırlanıyor' : value.text}',
                              style: const TextStyle(fontSize: 14))),
                      IconButton(
                          tooltip: 'Tek kullanımlık parolayı yenile',
                          onPressed: () => bind.mainUpdateTemporaryPassword(),
                          icon: const Icon(Icons.refresh)),
                    ])),
          ],
          if (bind.mainGetOptionSync(key: 'allow-only-conn-window-open') ==
              'Y') ...[
            const SizedBox(height: 10),
            const Text('Bağlantı alabilmek için bu pencere açık kalmalı.',
                style: TextStyle(fontSize: 13, height: 1.4)),
          ],
          if (!bind.isDisableSettings())
            TextButton.icon(
                onPressed: () => openSettings(SettingsTabKey.safety),
                icon: const Icon(Icons.shield_outlined, size: 18),
                label: const Text('Parola ve erişim izinleri')),
          widget.warning,
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          _healthCard(context, model),
          if (widget.systemError.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(widget.systemError)),
        ]),
      ));

  Widget _healthCard(BuildContext context, ServerModel model) {
    final verified = health == 'compatible' || health == 'portable';
    final stopped = bind.mainGetOptionSync(key: 'stop-service') == 'Y';
    final title = switch (health) {
      'checking' => 'Hizmet denetleniyor…',
      'mismatch' => 'Arayüz ile kurulu hizmet farklı',
      'unknown' => 'Hizmet uyumu doğrulanamadı',
      'stopped' => 'Kurulu hizmet çalışmıyor',
      _ => stopped
          ? 'Bağlantı hizmeti durdurulmuş'
          : model.connectStatus == 1
              ? 'Bağlantı almaya hazır'
              : 'Bağlantı sunucusu bekleniyor',
    };
    return Semantics(
        liveRegion: true,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(
                verified && !stopped && model.connectStatus == 1
                    ? Icons.check_circle_outline
                    : Icons.info_outline,
                size: 19,
                color: verified && !stopped && model.connectStatus == 1
                    ? (Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF6DE0BB)
                        : const Color(0xFF16704F))
                    : null),
            const SizedBox(width: 8),
            Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, height: 1.4))),
          ]),
          const SizedBox(height: 9),
          Text(
              switch (health) {
                'mismatch' =>
                  'Kurulu hizmet bu arayüzle aynı dosyaları kullanmıyor. Bu durum parola ekranına ulaşmadan bağlantıyı engelleyebilir.',
                'unknown' =>
                  'Bu kontrol başarılı olmadı. Hazır olduğunu varsaymadan yeniden denetleyin.',
                'portable' =>
                  'Taşınabilir kullanım. Kalıcı erişim ve oturum açma ekranı için cihaz kurulumu gerekir.',
                'compatible' =>
                  'Arayüz ile çalışan kurulu hizmetin dosyaları eşleşiyor.',
                'stopped' =>
                  'Ayarlar bölümünden hizmeti başlatıp yeniden denetleyin.',
                _ =>
                  'Kurulu hizmet ile arayüzün aynı sürüm olduğu kontrol ediliyor.',
              },
              style: const TextStyle(fontSize: 13, height: 1.5)),
          if (canUpdate)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ElevatedButton(
                    onPressed: updateService,
                    child: const Text('Kurulu hizmeti güncelle'))),
          if (health == 'mismatch' && !canUpdate)
            const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                    'Bu arayüzün daha yeni olduğu doğrulanamadı. Güncel Keyplus Destek paketini açın veya destek alın.',
                    style: TextStyle(fontSize: 13, height: 1.5))),
          if (updateResult != null)
            Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(updateResult!,
                    style: const TextStyle(fontSize: 13, height: 1.5))),
          Wrap(spacing: 4, children: [
            TextButton(
                onPressed: checking ? null : refreshHealth,
                child: const Text('Yeniden denetle')),
            if (!bind.isDisableSettings())
              TextButton(
                  onPressed: () => openSettings(SettingsTabKey.general),
                  child: const Text('Hizmet ayarları')),
            if (health == 'portable' && !bind.isDisableInstallation())
              TextButton(
                  onPressed: () => bind.mainGotoInstall(),
                  child: const Text('Bu cihaza kur')),
          ]),
        ]));
  }

  Future<void> _help(BuildContext context) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
            title: const Text('Bağlantı yardımı'),
            content: SizedBox(
                width: 510,
                child: SingleChildScrollView(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('Destek almak için',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const Text(
                          'Kimliğinizi paylaşın. Seçili erişim yönteminize göre isteğe izin verin veya parolanızı yalnızca güvendiğiniz destek görevlisine iletin.'),
                      const SizedBox(height: 18),
                      const Text('Parola ekranı açılmıyorsa',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const Text(
                          'Parola denetimine henüz ulaşılmamış olabilir. İki cihazın da açık ve bağlantı sunucusuna bağlı olduğunu kontrol edin. Ardından kurulu hizmet uyumunu denetleyin. Her bağlantı hatası sürüm farkından kaynaklanmaz.'),
                      const SizedBox(height: 18),
                      const Text('Kalıcı erişim',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const Text(
                          'Kalıcı parola, tıklama onayı ve pencerenin açık kalması ayrı ayarlardır. Birini değiştirmek diğerini otomatik olarak değiştirmez. Mevcut güvenlik ayarlarından her birini kontrol edin.'),
                      const SizedBox(height: 18),
                      const Text('Tanı özeti',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const Text(
                          'Aşağıdaki özet yalnızca sürüm ve hizmet durumunu içerir; parola, kimlik, bağlantı geçmişi ve token içermez.'),
                      TextButton.icon(
                          onPressed: () async {
                            final version = await bind.mainGetVersion();
                            final buildDate = await bind.mainGetBuildDate();
                            await Clipboard.setData(ClipboardData(
                                text:
                                    'Keyplus Destek\nSürüm: $version\nDerleme: $buildDate\nHizmet: $health\nGüncelleme sunulabilir: $canUpdate'));
                            if (mounted) showToast('Tanı özeti kopyalandı');
                          },
                          icon: const Icon(Icons.copy_outlined),
                          label: const Text('Güvenli tanı özetini kopyala')),
                    ]))),
            actions: [
              TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    openSettings(SettingsTabKey.about);
                  },
                  child: const Text('Hakkında ve kaynak kodu')),
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Kapat')),
            ],
          ));
}
