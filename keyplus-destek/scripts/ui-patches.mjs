// Keep upstream lifecycle, consent, access policy and transport code intact.
// Every source anchor must match exactly once; preparation remains transactional.
export function uiPatches(patch, replaceOnce) {
  const edit = (text, from, to, file) => replaceOnce(text, from, to, file);
  patch('src/core_main.rs', original => edit(edit(original,
    '    #[cfg(any(target_os = "linux", target_os = "windows"))]\n    if args.is_empty() {',
    '    #[cfg(windows)]\n    if crate::keyplus_startup::handle_startup(&args) {\n        return None;\n    }\n    #[cfg(any(target_os = "linux", target_os = "windows"))]\n    if args.is_empty() {', 'core_main.rs installed startup'),
    '    if args.len() > 0 {\n        if args[0] == "--version" {',
    '    #[cfg(windows)]\n    if args.first().map(String::as_str) == Some("--keyplus-service-status") {\n        println!("{}", crate::keyplus_health::status());\n        return None;\n    }\n    if args.len() > 0 {\n        if args[0] == "--version" {', 'core_main.rs safe diagnostics'));
  patch('src/flutter_ffi.rs', original => edit(original,
    'pub fn main_get_common(key: String) -> String {',
    'pub fn main_get_common(key: String) -> String {\n    #[cfg(windows)]\n    match key.as_str() {\n        "keyplus-service-health" => return crate::keyplus_health::status(),\n        "keyplus-update-service" => return crate::keyplus_health::request_update(),\n        _ => {}\n    }', 'flutter_ffi.rs'));
  patch('flutter/lib/desktop/pages/desktop_home_page.dart', original => {
    let text = "import 'keyplus_home.dart';\n" + original;
    return edit(text, '    super.build(context);\n    final isIncomingOnly = bind.isIncomingOnly();',
      '    super.build(context);\n    if (isWindows) {\n      return _buildBlock(child: KeyplusHome(warning: buildPresetPasswordWarning(), systemError: systemError));\n    }\n    final isIncomingOnly = bind.isIncomingOnly();', 'desktop_home_page.dart');
  });
  patch('flutter/lib/desktop/pages/connection_page.dart', original => {
    let text = edit("import 'keyplus_access.dart';\n" + original, '  const ConnectionPage({Key? key}) : super(key: key);',
      '  final bool keyplusOperator;\n  const ConnectionPage({Key? key, this.keyplusOperator = false}) : super(key: key);', 'connection_page.dart constructor');
    text = edit(text, "  bool isWindowMinimized = false;", "  bool isWindowMinimized = false;\n  String? _keyplusError;", 'connection_page.dart state');
    text = edit(text, '    var id = _idController.id;\n    connect(context, id,',
      `    var id = _idController.id;
    if (isWindows) {
      final error = keyplusIdError(id, gFFI.serverModel.serverId.text);
      setState(() => _keyplusError = error);
      if (error != null) { _idFocusNode.requestFocus(); return; }
    }
    connect(context, id,`, 'connection_page.dart connect');
    text = edit(text, '    final isOutgoingOnly = bind.isOutgoingOnly();\n    return Column(',
      `    final isOutgoingOnly = bind.isOutgoingOnly();
    if (isWindows) {
      return Padding(padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.keyplusOperator ? 'Hızlı bağlantı' : 'Bilgisayara bağlanın', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('Karşı cihazın kimliğini yazın. Parola veya izin adımı bağlantı sırasında açılır.', style: TextStyle(fontSize: 14, height: 1.5)),
        const SizedBox(height: 18),
        _buildRemoteIDTextField(context),
        const SizedBox(height: 12), const Divider(),
        const SizedBox(height: 8),
        Text(widget.keyplusOperator ? 'Son bağlantılar ve favoriler' : 'Son bağlantılar', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 6),
        const Expanded(child: PeerTabPage(keyplusLabels: true)),
      ]));
    }
    return Column(`, 'connection_page.dart layout');
    text = edit(text, '      width: 320 + 20 * 2,\n      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),',
      '      width: isWindows ? double.infinity : 320 + 20 * 2,\n      padding: isWindows ? EdgeInsets.zero : const EdgeInsets.fromLTRB(20, 24, 20, 22),', 'connection_page.dart form');
    text = edit(text, '            getConnectionPageTitle(context, false).marginOnly(bottom: 15),',
      `            if (!isWindows) getConnectionPageTitle(context, false).marginOnly(bottom: 15),
            if (isWindows) const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Karşı bilgisayarın kimliği'))),`, 'connection_page.dart label');
    text = edit(text, "                              counterText: '',", "                              counterText: '',\n                              errorText: isWindows ? _keyplusError : null,\n                              errorMaxLines: 3,", 'connection_page.dart error');
    text = edit(text, "                            fontFamily: 'WorkSans',", "                            fontFamily: 'Segoe UI',", 'connection_page.dart font');
    text = edit(text, '                          onChanged: (v) {\n                            _idController.id = v;',
      '                          onChanged: (v) {\n                            if (_keyplusError != null) setState(() => _keyplusError = null);\n                            _idController.id = v;', 'connection_page.dart input');
    text = edit(text, '                  height: 28.0,\n                  child: ElevatedButton(',
      '                  height: isWindows ? 44.0 : 28.0,\n                  child: ElevatedButton(', 'connection_page.dart button');
    text = edit(text, '                    child: Text(translate("Connect")),',
      '                    child: Text(isWindows ? "Bağlan" : translate("Connect")),', 'connection_page.dart button label');
    text = text.replaceAll('Icon(IconFont.more, size: 14)', "Icon(Icons.more_horiz, semanticLabel: 'Diğer bağlantı seçenekleri', size: 20)");
    text = edit(text, '                  height: 28.0,\n                  width: 28.0,',
      '                  height: isWindows ? 44.0 : 28.0,\n                  width: isWindows ? 44.0 : 28.0,', 'connection_page.dart actions size');
    return text;
  });
  patch('flutter/lib/common/widgets/peer_tab_page.dart', original => {
    let text = edit(original, '  const PeerTabPage({Key? key}) : super(key: key);',
      '  final bool keyplusLabels;\n  const PeerTabPage({Key? key, this.keyplusLabels = false}) : super(key: key);', 'peer_tab_page.dart constructor');
    text = edit(text, '              height: 32,', '              height: widget.keyplusLabels ? 44 : 32,', 'peer_tab_page.dart targets');
    return edit(text, '                        child: Icon(model.tabIcon(t), color: color)\n                            .paddingSymmetric(horizontal: 4),',
      `                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(model.tabIcon(t), color: color).paddingSymmetric(horizontal: 4),
                          if (widget.keyplusLabels && (selected || MediaQuery.of(context).size.width >= 1100))
                            Padding(padding: const EdgeInsets.only(right: 8), child: Text(model.tabTooltip(t), style: TextStyle(color: color))),
                        ]),`, 'peer_tab_page.dart labels');
  });
  patch('flutter/lib/desktop/pages/server_page.dart', original => {
    let text = edit(original, '            Color(0xff00bfe1),\n            Color(0xff0071ff),',
      '            Color(0xff102b3b),\n            Color(0xff183f53),', 'server_page.dart identity');
    text = edit(text, '                if (client.type_() == ClientType.terminal)\n                  FittedBox(',
      `                if (!client.authorized) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Cihaz adı karşı taraftan bildirilir. Tanıdığınız kişiden gelen isteğe izin verin.', style: TextStyle(color: Colors.white, fontSize: 12, height: 1.4))),
                if (client.type_() == ClientType.terminal)
                  FittedBox(`, 'server_page.dart identity note');
    text = edit(text, '    final btn = Container(\n      height: 28,',
      '    final btn = Container(\n      height: isWindows ? 44 : 28,', 'server_page.dart consent buttons');
    text = edit(text, "                text: 'Cancel',", "                text: 'Reddet',", 'server_page.dart reject');
    // Preserve checkClickTime and all permission/elevation callbacks.
    return text;
  });
  patch('flutter/lib/desktop/widgets/remote_toolbar.dart', original => {
    const anchor = `    return _IconMenuButton(
      assetName: 'assets/close.svg',
      tooltip: 'Close',`;
    return edit(original, anchor,
      `    if (isWindows) {
      return Semantics(label: 'Bağlantıyı bitir: $id', button: true, child: TextButton.icon(
        onPressed: () async {
          if (await showConnEndAuditDialogCloseCanceled(ffi: ffi)) return;
          closeConnection(id: id);
        },
        style: TextButton.styleFrom(foregroundColor: _ToolbarTheme.redColor, minimumSize: const Size(44, 40)),
        icon: const Icon(Icons.call_end_outlined, size: 18), label: const Text('Bitir'),
      ));
    }
${anchor}`, 'remote_toolbar.dart end session');
  });
  patch('flutter/lib/desktop/pages/desktop_setting_page.dart', original => {
    let text = edit(original, "            _lock(locked, 'Unlock Security Settings', () {",
      `            const Padding(padding: EdgeInsets.fromLTRB(24, 20, 24, 4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Parola, onay ve pencere koşulu', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              Text('Kalıcı parola tanımlamak, tıklama onayını veya pencerenin açık kalması koşulunu değiştirmez. Her seçeneği ayrı kontrol edin. Kurulu cihazda değişiklik için mevcut güvenlik kilidini açmanız gerekir.', style: TextStyle(height: 1.5)),
            ])),
            _lock(locked, 'Unlock Security Settings', () {`, 'desktop_setting_page.dart access guide');
    text = edit(text, "          return _Card(title: 'Password', children: [",
      "          return _Card(title: 'Parola ve bağlantı onayı', children: [", 'desktop_setting_page.dart password group');
    text = edit(text, "        child: _Card(title: translate('About RustDesk'), children: [",
      String.raw`        child: _Card(title: 'Keyplus Destek', children: [
          loadLogo(),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12), child: Text('Keyplus Destek 2026.11.20.4 · RustDesk $version\nAGPL-3.0 lisanslı RustDesk tabanı. Bağlantı ve erişim denetimleri korunur.')),
          TextButton.icon(onPressed: () => launchUrlString('https://portal.keyplus.com.tr/downloads/keyplus-destek/KeyplusDestek-source.tar.gz'), icon: const Icon(Icons.code), label: const Text('Bu dağıtımın kaynak kodu')),
          TextButton(onPressed: () => launchUrlString('https://www.gnu.org/licenses/agpl-3.0.html'), child: const Text('AGPL-3.0 lisans metni')),`, 'desktop_setting_page.dart about');
    // $version is runtime data, so the containing widget cannot be const.
    text = text.replace("const Padding(padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12), child: Text('Keyplus Destek 2026.11.20.4", "Padding(padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12), child: Text('Keyplus Destek 2026.11.20.4");
    return text;
  });
}
