import { readFileSync, writeFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';
import { createDecipheriv, scryptSync } from 'node:crypto';

const [input, output = 'sales-backup.json'] = process.argv.slice(2);
const password = process.env.SALES_BACKUP_PASSWORD;
if (!input || !password) {
  throw new Error(
    'Usage: set SALES_BACKUP_PASSWORD, then run node functions/scripts/decrypt-sales-backup.mjs <backup.etbackup> [output.json]',
  );
}
const envelope = JSON.parse(readFileSync(input, 'utf8'));
if (envelope.format !== 'ENQUIRY_TRACKER_SALES_BACKUP_V1') {
  throw new Error('Unsupported backup format.');
}
const salt = Buffer.from(envelope.salt, 'base64');
const iv = Buffer.from(envelope.iv, 'base64');
const key = scryptSync(password, salt, 32);
const decipher = createDecipheriv('aes-256-gcm', key, iv);
decipher.setAuthTag(Buffer.from(envelope.authTag, 'base64'));
const compressed = Buffer.concat([
  decipher.update(Buffer.from(envelope.data, 'base64')),
  decipher.final(),
]);
writeFileSync(output, gunzipSync(compressed));
console.log(`Decrypted backup written to ${output}`);
