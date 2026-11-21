import { readFileSync, mkdirSync, writeFileSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { argumentsFor, readConfig, validateConfig } from './config.mjs';

const project = JSON.parse(readFileSync(new URL('../project.json', import.meta.url), 'utf8'));

export function serverCompose(input) {
  const config = validateConfig(input, { requirePublicKey: false });
  const bind = config.environment === 'local' ? '127.0.0.1' : '0.0.0.0';
  const service = command => ({
    image: project.server.image,
    command,
    volumes: ['./data:/root'],
    restart: 'unless-stopped',
    logging: { driver: 'json-file', options: { 'max-size': '10m', 'max-file': '3' } },
  });
  return {
    name: 'keyplus-destek',
    services: {
      hbbs: {
        ...service(['hbbs', '-r', `${config.serverHost}:21117`, '-k', '_']),
        ports: [`${bind}:21115:21115/tcp`, `${bind}:21116:21116/tcp`, `${bind}:21116:21116/udp`],
      },
      hbbr: {
        ...service(['hbbr', '-k', '_']),
        ports: [`${bind}:21117:21117/tcp`],
      },
    },
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const args = argumentsFor(process.argv.slice(2), ['--config', '--out']);
    if (!args['--config'] || !args['--out']) {
      throw new Error('Kullanım: node scripts/server.mjs --config <json> --out <yeni-klasör>');
    }
    const compose = serverCompose(readConfig(args['--config'], { requirePublicKey: false }));
    const directory = resolve(args['--out']);
    if (existsSync(directory)) throw new Error('Çıktı klasörü zaten var; mevcut sunucu dosyaları korunuyor.');
    mkdirSync(directory, { recursive: true });
    writeFileSync(join(directory, 'compose.json'), JSON.stringify(compose, null, 2) + '\n');
    writeFileSync(join(directory, '.gitignore'), 'data/\n');
    console.log(`Sunucu taslağı hazır: ${directory}. Herhangi bir servis başlatılmadı.`);
  } catch (error) {
    console.error(`Keyplus Destek sunucu hazırlığı başarısız: ${error.message}`);
    process.exitCode = 1;
  }
}
