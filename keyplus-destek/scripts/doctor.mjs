import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join } from 'node:path';

const locate = process.platform === 'win32' ? 'where.exe' : 'which';
const tools = ['git', 'node', 'python', 'cargo', 'rustc', 'flutter', 'clang', 'cmake', 'cl'];
const results = tools.map(name => {
  const result = spawnSync(locate, [name], { encoding: 'utf8', windowsHide: true });
  return { name, available: result.status === 0 };
});
const vcpkg = process.env.VCPKG_ROOT;
results.push({ name: 'VCPKG_ROOT', available: !!vcpkg && existsSync(join(vcpkg, 'vcpkg.exe')) });
console.log(JSON.stringify({
  platform: process.platform,
  architecture: process.arch,
  windowsBuildReady: process.platform === 'win32' && results.every(result => result.available),
  checks: results,
  note: 'Bu kontrol araçları kurmaz. Native bridge dosyaları ve bağımlılıklar ayrıca doğrulanmalıdır.',
}, null, 2));
if (process.platform !== 'win32' || results.some(result => !result.available)) process.exitCode = 1;
