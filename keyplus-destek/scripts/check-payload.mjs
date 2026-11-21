import { readFileSync, readdirSync, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve, relative, join, isAbsolute, sep } from 'node:path';
import { argumentsFor, readConfig } from './config.mjs';

const args = argumentsFor(process.argv.slice(2), ['--payload', '--manifest', '--config']);
if (!args['--payload'] || !args['--manifest'] || !args['--config']) throw new Error('Payload, manifest and config are required');
const base = resolve(args['--payload']);
const entries = JSON.parse(readFileSync(args['--manifest'], 'utf8').replace(/^\uFEFF/, ''));
if (!Array.isArray(entries) || !entries.length) throw new Error('Empty payload manifest');
const expected = new Set();
for (const entry of entries) {
  const file = resolve(base, entry.path.replaceAll('\\', '/'));
  const rel = relative(base, file);
  if (!rel || isAbsolute(rel) || rel === '..' || rel.startsWith(`..${sep}`)) throw new Error('Payload path escapes directory');
  const data = readFileSync(file);
  if (data.length !== entry.size || createHash('sha256').update(data).digest('hex') !== entry.sha256) throw new Error(`Payload integrity failure: ${entry.path}`);
  expected.add(file.toLowerCase());
}
function visit(dir) {
  for (const name of readdirSync(dir)) {
    const file = join(dir, name);
    if (statSync(file).isDirectory()) visit(file);
    else if (!expected.has(file.toLowerCase())) throw new Error(`Unlisted payload file: ${relative(base, file)}`);
  }
}
visit(base);
readConfig(args['--config']);
console.log(`Verified ${entries.length} compiled files and the pinned server configuration.`);
