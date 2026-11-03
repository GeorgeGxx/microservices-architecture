import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const packagePath = fileURLToPath(new URL('../node_modules/kafkajs/package.json', import.meta.url));
const requestQueuePath = fileURLToPath(
  new URL('../node_modules/kafkajs/src/network/requestQueue/index.js', import.meta.url),
);
const kafkaPackage = JSON.parse(await readFile(packagePath, 'utf8'));

if (kafkaPackage.version !== '2.2.4') {
  throw new Error(`KafkaJS timer guard expects version 2.2.4; found ${kafkaPackage.version}`);
}

const source = await readFile(requestQueuePath, 'utf8');
const original = [
  '    let scheduleAt = this.throttledUntil - Date.now()',
  '    if (!this.throttleCheckTimeoutId) {',
].join('\n');
const patched = [
  '    const now = Date.now()',
  '    if (this.pending.length === 0 && this.throttledUntil <= now) {',
  '      return',
  '    }',
  '    let scheduleAt = this.throttledUntil - now',
  '    if (!this.throttleCheckTimeoutId) {',
].join('\n');

if (source.includes(patched)) {
  process.exit(0);
}

if (source.split(original).length !== 2) {
  throw new Error('KafkaJS request queue no longer matches the expected timer implementation');
}

await writeFile(requestQueuePath, source.replace(original, patched));
