import { isIP } from 'node:net';
import { readFileSync } from 'node:fs';

export function validateConfig(value, { requirePublicKey = true } = {}) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('Yapılandırma bir JSON nesnesi olmalıdır.');
  }
  const allowed = new Set(['environment', 'serverHost', 'publicKey', 'accessMode']);
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) throw new Error(`Desteklenmeyen yapılandırma alanı: ${key}`);
  }
  const { environment, serverHost, publicKey } = value;
  const accessMode = value.accessMode === undefined ? 'quick-support' : value.accessMode;
  if (!['quick-support', 'unattended'].includes(accessMode)) {
    throw new Error('accessMode alanı quick-support veya unattended olmalıdır.');
  }
  if (!['local', 'pilot'].includes(environment)) {
    throw new Error('environment alanı local veya pilot olmalıdır.');
  }
  if (typeof serverHost !== 'string' || !serverHost || serverHost !== serverHost.trim()) {
    throw new Error('serverHost alanına bağlantı sunucusunun adresi girilmelidir.');
  }
  const dns = /^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?$/i;
  if (isIP(serverHost) !== 4 && !dns.test(serverHost)) {
    throw new Error('serverHost bir IPv4 adresi veya alan adı olmalıdır; URL ve port içeremez.');
  }
  const host = serverHost.toLowerCase();
  const loopback = isIP(host) === 4 && host.split('.')[0] === '127';
  const reserved = /(?:^|\.)(?:localhost|invalid|test|example)$|(?:^|\.)example\.(?:com|net|org)$/i.test(host);
  if (environment === 'local' && host !== '127.0.0.1') {
    throw new Error('local ortamında yalnızca 127.0.0.1 adresi kullanılabilir.');
  }
  if (environment === 'pilot' && (loopback || reserved || ['0.0.0.0', '255.255.255.255'].includes(host))) {
    throw new Error('Pilot için gerçek bağlantı sunucusunun adresi gereklidir.');
  }
  if (requirePublicKey || publicKey) {
    if (typeof publicKey !== 'string' || !/^[A-Za-z0-9+/]{43}=$/.test(publicKey)) {
      throw new Error('publicKey, sunucunun id_ed25519.pub dosyasındaki 32 baytlık Base64 açık anahtar olmalıdır.');
    }
    const bytes = Buffer.from(publicKey, 'base64');
    if (bytes.length !== 32 || bytes.toString('base64') !== publicKey || bytes.every(b => b === 0)) {
      throw new Error('Sunucunun açık anahtarı geçersiz.');
    }
  }
  return Object.freeze({ environment, serverHost: host, publicKey: publicKey || '', accessMode });
}

export function readConfig(file, options) {
  try {
    return validateConfig(JSON.parse(readFileSync(file, 'utf8').replace(/^\uFEFF/, '')), options);
  } catch (error) {
    throw new Error(`${file}: ${error.message}`, { cause: error });
  }
}

export function argumentsFor(argv, allowed) {
  const result = {};
  for (let i = 0; i < argv.length; i++) {
    const name = argv[i];
    if (!allowed.includes(name) || Object.hasOwn(result, name)) {
      throw new Error(`Geçersiz veya tekrarlanan argüman: ${name}`);
    }
    if (name === '--check' || name === '--runtime-config') result[name] = true;
    else {
      const next = argv[++i];
      if (!next || next.startsWith('--')) throw new Error(`${name} için bir değer gereklidir.`);
      result[name] = next;
    }
  }
  return result;
}
