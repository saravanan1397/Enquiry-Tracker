const { createHash, randomInt, randomBytes, timingSafeEqual } = require('node:crypto');
const hash = value => createHash('sha256').update(value).digest('hex');
const validMobile = value => typeof value === 'string' && /^\d{10}$/.test(value);
const validPin = value => typeof value === 'string' && /^\d{6,128}$/.test(value);
function newCode(now) {
  const code = String(randomInt(0, 100000000)).padStart(8, '0');
  const salt = randomBytes(32).toString('hex');
  return { code, secret: { salt, digest: hash(salt + code), attempts: 0,
    expiresAtMs: now + 15 * 60 * 1000, status: 'issued' } };
}
function checkCode(secret, code, now) {
  if (!secret || secret.status !== 'issued' || secret.expiresAtMs <= now ||
      secret.attempts >= 5) return false;
  if (typeof code !== 'string' || !/^\d{8}$/.test(code)) return false;
  return timingSafeEqual(Buffer.from(hash(secret.salt + code), 'hex'),
    Buffer.from(secret.digest, 'hex'));
}
module.exports = { hash, validMobile, validPin, newCode, checkCode };
