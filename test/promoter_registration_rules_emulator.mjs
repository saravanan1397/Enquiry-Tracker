import assert from 'node:assert/strict';

function endpoint(env) {
  const host = process.env[env];
  assert.match(host ?? '', /^(127\.0\.0\.1|localhost):\d+$/);
  return 'http://' + host;
}

const project = 'demo-inventory';
const path = 'projects/' + project + '/databases/(default)/documents';
const documents = endpoint('FIRESTORE_EMULATOR_HOST') + '/v1/' + path;
const signUp = endpoint('FIREBASE_AUTH_EMULATOR_HOST') +
  '/identitytoolkit.googleapis.com/v1/accounts:signUp?key=local';

async function call(url, {method = 'GET', token, body}, expected = 200) {
  const response = await fetch(url, {
    method,
    headers: {
      ...(token ? {Authorization: 'Bearer ' + token} : {}),
      ...(body ? {'Content-Type': 'application/json'} : {}),
    },
    ...(body ? {body: JSON.stringify(body)} : {}),
  });
  const result = await response.json();
  assert.equal(response.status, expected, JSON.stringify(result).slice(0, 700));
  return result;
}

const signup = email => call(signUp, {
  method: 'POST',
  body: {email, password: 'test-password', returnSecureToken: true},
});
const promoter = await signup('promoter@example.test');
const admin = await signup('owner@example.test');
const mobile = '9876543210';
const record = fields => ({name: path + '/promoters/' + promoter.localId, fields});
const string = stringValue => ({stringValue});
const state = {role: string('promoter'), active: {booleanValue: false}, status: string('pending')};
const commit = (writes, token, expected) =>
  call(documents + ':commit', {method: 'POST', token, body: {writes}}, expected);

for (const name of [undefined, {integerValue: '42'}, string(''), string('   '), string('\t\n ')]) {
  await commit([{update: record({...state, ...(name ? {name} : {})})}], promoter.idToken, 403);
}
await commit([
  {update: record({...state, name: string('புதிய Promoter'), mobile: string(mobile),
    emailVerificationOptional: {booleanValue: true}})},
  {update: {name: path + '/promoterMobiles/' + mobile, fields: {uid: string(promoter.localId)}}},
], promoter.idToken);

// A legacy profile with an empty name remains readable and can still be approved.
await commit([
  {update: {name: path + '/users/' + admin.localId,
    fields: {role: string('admin'), active: {booleanValue: true}}}},
  {update: record({...state, name: string('')})},
], 'owner');
await call(documents + '/promoters/' + promoter.localId, {token: promoter.idToken});
await commit([{
  update: record({active: {booleanValue: true}, status: string('approved')}),
  updateMask: {fieldPaths: ['active', 'status']},
}], admin.idToken);
console.log('Verified required registration names, optional recovery email, and unchanged legacy approval.');
