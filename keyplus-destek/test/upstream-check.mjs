import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, existsSync, unlinkSync, realpathSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { generateKeyPairSync } from 'node:crypto';
import { prepare } from '../scripts/prepare.mjs';

if (!process.argv[2]) throw new Error('Kullanım: node test/upstream-check.mjs <pristine-rustdesk-kökü>');
const source = realpathSync(resolve(process.argv[2]));
const files = ['src/lib.rs', 'src/common.rs', 'src/platform/mod.rs', 'src/server/connection.rs', 'src/ipc/auth.rs', 'libs/hbb_common/src/config.rs', 'flutter/lib/common.dart', 'flutter/windows/runner/Runner.rc',
  'src/flutter_ffi.rs', 'src/core_main.rs', 'flutter/lib/desktop/pages/desktop_home_page.dart', 'flutter/lib/desktop/pages/connection_page.dart', 'flutter/lib/desktop/pages/server_page.dart',
  'flutter/lib/desktop/widgets/remote_toolbar.dart', 'flutter/lib/desktop/pages/desktop_setting_page.dart', 'flutter/lib/common/widgets/peer_tab_page.dart'];
const snapshots = new Map(files.map(file => [join(source, file), readFileSync(join(source, file))]));
const generated = join(source, 'src', 'keyplus.rs');
const windowModule = join(source, 'src', 'keyplus_window.rs');
const created = [generated, windowModule, ...['src/keyplus_health.rs', 'src/keyplus_startup.rs', 'flutter/lib/desktop/pages/keyplus_home.dart', 'flutter/lib/desktop/pages/keyplus_text.dart',
  'flutter/lib/desktop/pages/keyplus_layout.dart', 'flutter/lib/desktop/pages/keyplus_access.dart', 'flutter/test/keyplus_ui_test.dart'].map(file => join(source, file))];
if (created.some(existsSync)) throw new Error('Bu doğrulama değiştirilmemiş ayrı bir kaynak kopyası gerektirir.');
const { publicKey } = generateKeyPairSync('ed25519');
const config = { environment: 'local', serverHost: '127.0.0.1', publicKey: publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64') };

function restore() {
  for (const [file, content] of snapshots) writeFileSync(file, content);
  for (const file of created) {
    if (existsSync(file)) {
      if (realpathSync(file) !== file) throw new Error('Üretilen test dosyasının yolu değişti; silinmedi.');
      unlinkSync(file);
    }
  }
}

try {
  const plan = prepare(source, config, { check: true });
  assert.equal(plan.filter(file => file.changed).length, files.length + created.length);
  for (const [file, content] of snapshots) assert.deepEqual(readFileSync(file), content);
  assert.equal(existsSync(generated), false);

  // A late-file conflict must stop preparation before any earlier file is written.
  const conflict = join(source, 'flutter/windows/runner/Runner.rc');
  writeFileSync(conflict, Buffer.concat([snapshots.get(conflict), Buffer.from('\n// preserved local edit\n')]));
  assert.throws(() => prepare(source, config), /yerel değişiklik/);
  for (const [file, content] of snapshots) {
    if (file !== conflict) assert.deepEqual(readFileSync(file), content);
  }
  writeFileSync(conflict, snapshots.get(conflict));

  for (const accessMode of ['quick-support', 'unattended']) {
    const selected = { ...config, accessMode };
    prepare(source, selected);
    assert.ok(prepare(source, selected).every(file => !file.changed));
    const common = readFileSync(join(source, 'src/common.rs'), 'utf8');
    assert.match(common, /crate::keyplus::init\(\)/);
    assert.match(common, /sign::verify\(&data, &pk\)/);
    const generatedModule = readFileSync(generated, 'utf8');
    assert.match(generatedModule, /config::DEFAULT_SETTINGS\.write\(\)/);
    assert.match(generatedModule, new RegExp(`defaults\\.insert\\("approve-mode"\\.into\\(\\), "${accessMode === 'unattended' ? 'password' : 'click'}"`));
    assert.match(generatedModule, /"disable-installation"\.into\(\), "N"/);
    const nativeConfig = readFileSync(join(source, 'libs/hbb_common/src/config.rs'), 'utf8');
    assert.match(nativeConfig, /RwLock::new\("KeyplusDestek"/);
    assert.match(nativeConfig, /config_name = if cfg!\(windows\) && app_name == "KeyplusDestek" \{ "Keyplus Destek"/);
    assert.match(readFileSync(join(source, 'flutter/lib/common.dart'), 'utf8'), /static const Color accent = Color\(0xFFDF192A\)/);
    assert.match(readFileSync(join(source, 'src/server/connection.rs'), 'utf8'), /spawn_blocking\(crate::keyplus_window::is_open\)/);
    const ipcAuth = readFileSync(join(source, 'src/ipc/auth.rs'), 'utf8');
    assert.match(ipcAuth, /crate::keyplus_window::same_application\(peer_pid, &peer_exe\)\?/);
    assert.match(ipcAuth, /if !authorized/);
    assert.match(ipcAuth, /is_allowed_windows_session_scoped_peer/);
    assert.doesNotMatch(readFileSync(windowModule, 'utf8'), /Runtime::|new_current_thread|new_listener|\.block_on\(/);
    restore();
  }
  prepare(source, null, { runtimeConfig: true });
  assert.ok(prepare(source, null, { runtimeConfig: true }).every(file => !file.changed));
  const runtime = readFileSync(generated, 'utf8');
  assert.match(runtime, /directory\.join\("data"\)\.join\("keyplus-server\.json"\)/);
  assert.match(runtime, /pub fn init\(\) -> bool/);
  assert.match(readFileSync(join(source, 'src/common.rs'), 'utf8'), /if !crate::keyplus::init\(\)/);
  assert.match(readFileSync(join(source, 'libs/hbb_common/src/config.rs'), 'utf8'), /pub const RS_PUB_KEY: &str = "";/);
  assert.doesNotMatch(runtime, /set_permanent_password|default-connect-password/);
  restore();
  console.log('Geçti: iki erişim modu gerçek sabit kaynağa uygulandı; yerel değişiklik koruması, tekrar uygulanabilirlik ve özgün imza kontrolü doğrulandı.');
  console.log('Bu kontrol Windows derlemesi veya iki bilgisayar arasında bağlantı testi değildir.');
} finally {
  restore();
}
