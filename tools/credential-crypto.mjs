import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const [, , operation, inputPath, outputPath] = process.argv;
const password = process.env.ENQUIRY_TRACKER_CREDENTIAL_PASSWORD;

if (!['encrypt', 'decrypt'].includes(operation) || !inputPath || !outputPath) {
  throw new Error(
    'Usage: node tools/credential-crypto.mjs <encrypt|decrypt> <input> <output>',
  );
}
if (!password || password.length < 12) {
  throw new Error('The encryption password must contain at least 12 characters.');
}

const magic = Buffer.from('ETCRED01', 'ascii');

function encrypt() {
  const salt = crypto.randomBytes(16);
  const iv = crypto.randomBytes(12);
  const key = crypto.scryptSync(password, salt, 32);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const encrypted = Buffer.concat([
    cipher.update(fs.readFileSync(inputPath)),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  writeAtomically(Buffer.concat([magic, salt, iv, tag, encrypted]));
}

function decrypt() {
  const payload = fs.readFileSync(inputPath);
  if (payload.length < 52 || !payload.subarray(0, 8).equals(magic)) {
    throw new Error('This is not an Enquiry Tracker credential backup.');
  }
  const salt = payload.subarray(8, 24);
  const iv = payload.subarray(24, 36);
  const tag = payload.subarray(36, 52);
  const encrypted = payload.subarray(52);
  const key = crypto.scryptSync(password, salt, 32);
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  writeAtomically(Buffer.concat([decipher.update(encrypted), decipher.final()]));
}

function writeAtomically(contents) {
  fs.mkdirSync(path.dirname(path.resolve(outputPath)), { recursive: true });
  const temporaryPath = `${outputPath}.tmp`;
  fs.writeFileSync(temporaryPath, contents, { mode: 0o600 });
  fs.renameSync(temporaryPath, outputPath);
}

operation === 'encrypt' ? encrypt() : decrypt();
