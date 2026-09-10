const test = require('node:test');
const assert = require('node:assert/strict');
const { handlers } = require('./pin_reset');
const { hash, validMobile, validPin, newCode, checkCode } = require('./pin_reset_logic');

function fixture() {
  let clock = 10000000;
  const records = new Map([
    ['users/owner', { role: 'admin', active: true }],
    ['promoters/promoter', { role: 'promoter', name: 'Test', mobile: '9000000001', active: false }],
  ]);
  const doc = path => ({ path, get: async () => ({ data: () => records.get(path) }) });
  function batch() {
    const writes = [];
    return {
      get: ref => ref.get(),
      set: (ref, value) => writes.push(() => records.set(ref.path, { ...value })),
      update: (ref, value) => writes.push(() => records.set(ref.path, { ...records.get(ref.path), ...value })),
      commit: async () => writes.forEach(write => write()),
    };
  }
  // Serialize transactions, like Firestore's conflict retries; discard writes on throws.
  let queue = Promise.resolve();
  const db = { doc, batch, runTransaction: fn => {
    const operation = queue.then(async () => {
      const tx = batch(); const result = await fn(tx); await tx.commit(); return result;
    });
    queue = operation.catch(() => {}); return operation;
  } };
  const updates = [];
  const revoked = [];
  const auth = {
    getUserByEmail: async email => {
      if (email !== '9000000001@auth.leadloop.app') throw { code: 'auth/user-not-found' };
      return { uid: 'promoter' };
    },
    updateUser: async (uid, changes) => updates.push({ uid, ...changes }),
    revokeRefreshTokens: async uid => revoked.push(uid),
  };
  const api = handlers(db, auth, () => clock);
  const request = { data: { mobile: '9000000001' }, rawRequest: { ip: 'test-ip' } };
  const owner = { auth: { uid: 'owner' }, data: { uid: 'promoter', identityVerified: true } };
  return { api, records, updates, revoked, auth, request, owner,
    advance: ms => { clock += ms; },
    issue: async () => { await api.requestPromoterPinReset(request); return api.generatePromoterPinResetCode(owner); },
    redeem: code => api.completePromoterPinReset({ ...request, data: { ...request.data, code, pin: '654321' } }),
  };
}

test('phone and PIN validators accept digits only and enforce lengths', () => {
  assert.equal(validMobile('9000000001'), true);
  for (const value of ['900000001', '90000000011', '+919000000001', '90000a0001', 9000000001]) assert.equal(validMobile(value), false);
  assert.equal(validPin('123456'), true);
  for (const value of ['12345', '123abc', '1'.repeat(129), null]) assert.equal(validPin(value), false);
});
test('generated code is eight digits; secrets contain no plaintext code', () => {
  const { code, secret } = newCode(1000);
  assert.match(code, /^\d{8}$/); assert.equal(secret.code, undefined);
  assert.equal(checkCode(secret, code, 1001), true);
  assert.equal(checkCode(secret, code, secret.expiresAtMs), false);
});
test('existing and unknown numbers receive identical responses', async () => {
  const f = fixture();
  const known = await f.api.requestPromoterPinReset(f.request);
  const unknown = await f.api.requestPromoterPinReset({ ...f.request, data: { mobile: '9000000002' } });
  assert.deepEqual(known, unknown);
  assert.equal(f.records.get('pinResetRequests/promoter').status, 'pending');
});
test('unauthenticated, promoter and inactive owner cannot generate codes', async () => {
  const f = fixture(); await f.api.requestPromoterPinReset(f.request);
  await assert.rejects(f.api.generatePromoterPinResetCode({ data: f.owner.data }), { code: 'unauthenticated' });
  await assert.rejects(f.api.generatePromoterPinResetCode({ ...f.owner, auth: { uid: 'promoter' } }), { code: 'permission-denied' });
  f.records.set('users/owner', { role: 'admin', active: false });
  await assert.rejects(f.api.generatePromoterPinResetCode(f.owner), { code: 'permission-denied' });
});
test('owner must confirm identity', async () => {
  const f = fixture();
  await assert.rejects(f.api.generatePromoterPinResetCode({ ...f.owner, data: { uid: 'promoter' } }), { code: 'failed-precondition' });
});
test('successful reset keeps same UID, disabled state and records; consumes code', async () => {
  const f = fixture(); const profile = { ...f.records.get('promoters/promoter') };
  const { code } = await f.issue(); await f.redeem(code);
  assert.deepEqual(f.updates, [{ uid: 'promoter', password: '654321' }]);
  assert.deepEqual(f.revoked, ['promoter']);
  assert.deepEqual(f.records.get('promoters/promoter'), profile);
  assert.equal(f.records.get('pinResetRequests/promoter').status, 'used');
  await assert.rejects(f.redeem(code), { code: 'invalid-argument' });
  assert.equal(f.updates.length, 1);
});
test('expired code cannot change PIN', async () => {
  const f = fixture(); const { code } = await f.issue(); f.advance(15 * 60000);
  await assert.rejects(f.redeem(code), { code: 'invalid-argument' });
  assert.equal(f.updates.length, 0);
});
test('five wrong attempts lock code, including the correct code afterward', async () => {
  const f = fixture(); const { code } = await f.issue();
  for (let i = 0; i < 5; i++) await assert.rejects(f.redeem('wrong'), { code: 'invalid-argument' });
  await assert.rejects(f.redeem(code), { code: 'invalid-argument' });
  assert.equal(f.records.get('pinResetRequests/promoter').status, 'locked');
});
test('concurrent redemption performs only one password change', async () => {
  const f = fixture(); const { code } = await f.issue();
  const results = await Promise.allSettled([f.redeem(code), f.redeem(code)]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(f.updates.length, 1);
});
test('anonymous repeat requests do not invalidate an issued code', async () => {
  const f = fixture(); const { code } = await f.issue(); f.advance(6 * 60000);
  await f.api.requestPromoterPinReset(f.request); await f.redeem(code);
  assert.equal(f.updates.length, 1);
});
test('owner regeneration replaces old secret and invalidates old code', async () => {
  const f = fixture(); await f.issue();
  const old = f.records.get(`pinResetSecrets/${hash('9000000001')}`);
  f.advance(31000); const fresh = await f.api.generatePromoterPinResetCode(f.owner);
  assert.notEqual(f.records.get(`pinResetSecrets/${hash('9000000001')}`).salt, old.salt);
  await f.redeem(fresh.code);
});
test('Auth failure consumes code; owner can issue replacement', async () => {
  const f = fixture(); const { code } = await f.issue();
  f.auth.updateUser = async () => { throw new Error('backend failure'); };
  await assert.rejects(f.redeem(code), { code: 'internal' });
  await assert.rejects(f.redeem(code), { code: 'invalid-argument' });
  assert.equal(f.records.get('pinResetRequests/promoter').status, 'failed');
  f.advance(31000); await f.api.generatePromoterPinResetCode(f.owner);
});
test('request flooding is rate limited', async () => {
  const f = fixture();
  for (let i = 0; i < 20; i++) await f.api.requestPromoterPinReset(f.request);
  await assert.rejects(f.api.requestPromoterPinReset(f.request), { code: 'resource-exhausted' });
});
