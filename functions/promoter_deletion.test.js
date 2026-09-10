const test = require('node:test');
const assert = require('node:assert/strict');
const { deletionHandler } = require('./promoter_deletion');
const { hash } = require('./pin_reset_logic');

function setup() {
  const data = new Map([
    ['users/owner', { role: 'admin', active: true }],
    ['promoters/p1', { role: 'promoter', active: true, status: 'approved', mobile: '9000000001' }],
    ['promoters/p2', { role: 'promoter', active: true }],
    ['leads/one', { promoterId: 'p1', followUp1: 'Call later' }],
    ['leads/two', { promoterId: 'p1', outcome: 'purchased' }],
    ['pinResetRequests/p1', { status: 'issued' }],
    [`pinResetSecrets/${hash('9000000001')}`, { uid: 'p1', status: 'issued' }],
    ['pinResetSecrets/other', { uid: 'p2' }],
    ['reminderDevices/one', { uid: 'p1', token: 'first' }],
    ['reminderDevices/other', { uid: 'p2', token: 'other' }],
    ['promoters/p1/preferences/one', { value: 'private' }],
  ]);
  const doc = path => ({ path, get: async () => ({ data: () => data.get(path) }),
    listCollections: async () => [...new Set([...data.keys()].filter(key => key.startsWith(path + '/')).map(key => key.split('/').slice(0, 3).join('/')))].map(path => ({ path })),
  });
  const batch = () => {
    const changes = [];
    return {
      get: ref => ref.get(),
      set: (ref, value) => changes.push(() => data.set(ref.path, value)),
      update: (ref, value) => changes.push(() => data.set(ref.path, { ...data.get(ref.path), ...value })),
      delete: ref => changes.push(() => data.delete(ref.path)),
      commit: async () => { changes.forEach(change => change()); },
    };
  };
  let queue = Promise.resolve();
  const db = { doc, batch,
    runTransaction: fn => {
      const result = queue.then(async () => { const tx = batch(); const value = await fn(tx); await tx.commit(); return value; });
      queue = result.catch(() => {}); return result;
    },
    collection: name => ({ where: (field, operator, value) => ({ limit: count => ({ get: async () => ({
      docs: [...data.entries()].filter(([key, d]) => key.startsWith(name + '/') && d[field] === value)
        .slice(0, count).map(([key]) => ({ ref: doc(key) })),
    }) }) }) }),
    recursiveDelete: async ref => {
      for (const key of data.keys()) if (key === ref.path || key.startsWith(ref.path + '/')) data.delete(key);
    },
  };
  const deleted = [];
  const auth = { deleteUser: async uid => { deleted.push(uid); } };
  const invoke = deletionHandler(db, auth);
  const request = { auth: { uid: 'owner' }, data: { uid: 'p1', confirmation: 'DELETE' } };
  return { data, db, auth, deleted, invoke, request };
}

test('removes Auth, full profile, requests, secrets and own tokens; keeps enquiries and other promoters', async () => {
  const f = setup(); const enquiries = [...f.data.entries()].filter(([key]) => key.startsWith('leads/'));
  await f.invoke(f.request);
  assert.deepEqual(f.deleted, ['p1']);
  for (const path of ['promoters/p1', 'promoters/p1/preferences/one', 'pinResetRequests/p1', `pinResetSecrets/${hash('9000000001')}`, 'reminderDevices/one']) assert.equal(f.data.has(path), false);
  for (const path of ['promoters/p2', 'reminderDevices/other', 'pinResetSecrets/other']) assert.equal(f.data.has(path), true);
  assert.deepEqual([...f.data.entries()].filter(([key]) => key.startsWith('leads/')), enquiries);
  assert.deepEqual(f.data.get('promoterDeletions/p1'), { status: 'complete' });
});
test('rejects unauthenticated callers and promoters without deleting anything', async () => {
  const f = setup();
  await assert.rejects(f.invoke({ data: f.request.data }), { code: 'unauthenticated' });
  await assert.rejects(f.invoke({ ...f.request, auth: { uid: 'p2' } }), { code: 'permission-denied' });
  assert.equal(f.deleted.length, 0); assert.equal(f.data.get('promoters/p1').active, true);
});
test('requires exact confirmation and a valid UID', async () => {
  const f = setup();
  for (const data of [{ uid: 'p1' }, { uid: '../owner', confirmation: 'DELETE' }]) {
    await assert.rejects(f.invoke({ ...f.request, data }), { code: 'invalid-argument' });
  }
});
test('refuses owner/self and unknown targets', async () => {
  const f = setup();
  await assert.rejects(f.invoke({ ...f.request, data: { uid: 'owner', confirmation: 'DELETE' } }), { code: 'permission-denied' });
  f.data.set('users/p1', { role: 'admin', active: false });
  await assert.rejects(f.invoke(f.request), { code: 'permission-denied' });
  await assert.rejects(f.invoke({ ...f.request, data: { uid: 'unknown', confirmation: 'DELETE' } }), { code: 'not-found' });
  assert.equal(f.deleted.length, 0);
});
test('deletion does not interrupt a PIN reset already processing', async () => {
  const f = setup();
  f.data.set(`pinResetSecrets/${hash('9000000001')}`, { uid: 'p1', status: 'processing' });
  await assert.rejects(f.invoke(f.request), { code: 'failed-precondition' });
  assert.equal(f.deleted.length, 0);
});
test('Auth failure locks profile and preserves retryable state', async () => {
  const f = setup(); const original = f.auth.deleteUser;
  f.auth.deleteUser = async () => { throw new Error('Auth unavailable'); };
  await assert.rejects(f.invoke(f.request), { code: 'internal' });
  assert.equal(f.data.get('promoters/p1').status, 'deleting');
  assert.equal(f.data.get('promoters/p1').active, false);
  f.auth.deleteUser = original; await f.invoke(f.request);
  assert.equal(f.data.has('promoters/p1'), false);
});
test('Firestore cleanup failure remains retryable even if Auth was deleted', async () => {
  const f = setup(); const original = f.db.recursiveDelete;
  f.db.recursiveDelete = async () => { throw new Error('Firestore unavailable'); };
  await assert.rejects(f.invoke(f.request), { code: 'internal' });
  assert.equal(f.data.get('promoters/p1').status, 'deleting');
  f.db.recursiveDelete = original;
  f.auth.deleteUser = async () => { throw { code: 'auth/user-not-found' }; };
  await f.invoke(f.request);
  assert.equal(f.data.has('promoters/p1'), false);
});
test('successful deletion is idempotent', async () => {
  const f = setup(); await f.invoke(f.request); await f.invoke(f.request);
  assert.equal(f.deleted.length, 1);
});
test('cleans more than one page of notification registrations', async () => {
  const f = setup();
  for (let i = 0; i < 650; i++) f.data.set(`reminderDevices/t${i}`, { uid: 'p1' });
  await f.invoke(f.request);
  assert.equal([...f.data.entries()].filter(([key, value]) => key.startsWith('reminderDevices/') && value.uid === 'p1').length, 0);
  assert.equal(f.data.has('reminderDevices/other'), true);
});
