import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { validateConfig, argumentsFor } from '../scripts/config.mjs';
import { serverCompose } from '../scripts/server.mjs';
import { clientModule } from '../scripts/prepare.mjs';

const { publicKey } = generateKeyPairSync('ed25519');
const rawKey = publicKey.export({ type: 'spki', format: 'der' }).subarray(-32).toString('base64');
const local = { environment: 'local', serverHost: '127.0.0.1', publicKey: rawKey };

test('istemci gerçek açık anahtar ister, ilk sunucu hazırlığı anahtar olmadan yapılabilir', () => {
  assert.throws(() => validateConfig({ ...local, publicKey: '' }), /açık anahtar/);
  assert.throws(() => validateConfig({ ...local, publicKey: Buffer.alloc(32).toString('base64') }), /geçersiz/);
  assert.equal(validateConfig(local).publicKey, rawKey);
  assert.equal(serverCompose({ ...local, publicKey: '' }).services.hbbs.command[0], 'hbbs');
});

test('pilot örnek adresleri ve komut/URL girdilerini reddeder', () => {
  for (const serverHost of ['127.0.0.1', '0.0.0.0', 'demo.example.com', 'demo.test', 'https://remote.domain.com', 'remote.domain.com:21116', 'remote.domain.com;whoami', 'remote.domain.com\n']) {
    assert.throws(() => validateConfig({ ...local, environment: 'pilot', serverHost }));
  }
  assert.equal(validateConfig({ ...local, environment: 'pilot', serverHost: 'DESTEK.KEYPLUS.COM.TR' }).serverHost, 'destek.keyplus.com.tr');
  assert.throws(() => validateConfig({ ...local, serverHost: '192.168.1.2' }), /127/);
});

test('ERP yapılandırması ve özel anahtar alanları kabul edilmez', () => {
  for (const extra of [{ erpUrl: 'https://erp.domain.com' }, { privateKey: 'secret' }, { permanentPassword: 'shared-secret' }]) {
    assert.throws(() => validateConfig({ ...local, ...extra }), /Desteklenmeyen/);
  }
});

test('yerel sunucu yalnızca loopback ve masaüstü portlarını yayımlar', () => {
  const compose = serverCompose(local);
  const ports = Object.values(compose.services).flatMap(service => service.ports);
  assert.deepEqual(ports, ['127.0.0.1:21115:21115/tcp', '127.0.0.1:21116:21116/tcp', '127.0.0.1:21116:21116/udp', '127.0.0.1:21117:21117/tcp']);
  assert.ok(Object.values(compose.services).every(service => service.command.includes('-k')));
  assert.deepEqual(compose.services.hbbs.volumes, compose.services.hbbr.volumes);
  assert.ok(Object.values(compose.services).every(service => !service.image.endsWith(':latest')));
});

test('üretilen istemci müşteri kabulünü ve sabit sunucuyu kullanır; parola içermez', () => {
  const module = clientModule(local);
  assert.match(module, /defaults\.insert\("approve-mode"\.into\(\), "click"\.into\(\)/);
  assert.match(module, /"custom-rendezvous-server"\.into\(\), "127\.0\.0\.1:21116"/);
  assert.match(module, /"disable-installation"\.into\(\), "N"/);
  assert.doesNotMatch(module, /set_permanent_password|DB_PASSWORD|erpUrl|sign::verify|5Qbwsde3/);
});

test('kalıcı erişim müşteri tıklaması ve açık pencere zorunluluğu olmadan kalıcı parola kullanır', () => {
  const module = clientModule({ ...local, accessMode: 'unattended' });
  assert.match(module, /defaults\.insert\("approve-mode"\.into\(\), "password"\.into\(\)/);
  assert.match(module, /defaults\.insert\("verification-method"\.into\(\), "use-permanent-password"\.into\(\)/);
  assert.match(module, /defaults\.insert\("allow-only-conn-window-open"\.into\(\), "N"\.into\(\)/);
  assert.match(module, /hard\.insert\("disable-installation"\.into\(\), "N"\.into\(\)/);
  assert.doesNotMatch(module, /set_permanent_password|preset-password|default-connect-password|password=.*/);
});

test('erişim modu cihazın güvenlik ekranından değiştirilebilir; ağ ayarları sabit kalır', () => {
  for (const accessMode of ['quick-support', 'unattended']) {
    const module = clientModule({ ...local, accessMode });
    assert.doesNotMatch(module, /settings\.insert\("(?:approve-mode|verification-method|allow-only-conn-window-open)"/);
    assert.match(module, /settings\.insert\("key"/);
  }
  assert.equal(validateConfig(local).accessMode, 'quick-support');
  assert.throws(() => validateConfig({ ...local, accessMode: 'password-click' }), /accessMode/);
  assert.throws(() => validateConfig({ ...local, accessMode: null }), /accessMode/);
});

test('komut satırı eksik, tekrarlanan ve bilinmeyen argümanları reddeder', () => {
  assert.deepEqual(argumentsFor(['--source', 'C:\\kaynak', '--check'], ['--source', '--check']), { '--source': 'C:\\kaynak', '--check': true });
  assert.throws(() => argumentsFor(['--source'], ['--source']), /değer/);
  assert.throws(() => argumentsFor(['--check', '--check'], ['--check']), /tekrarlanan/);
  assert.throws(() => argumentsFor(['--deploy'], ['--check']), /Geçersiz/);
});
