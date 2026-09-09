const { test } = require('node:test');
const assert = require('node:assert/strict');
const { nextDueAt, recipientsFor, inBusinessHours } = require('./reminder_logic');
test('15 hours spans Friday, Saturday and Sunday in India', () => {
  assert.equal(nextDueAt({followUp1: 'Call', followUp1At: '2026-09-11T21:00:00+05:30'}).toISOString(),
    '2026-09-13T04:30:00.000Z');
});
test('F4 starts a fresh deadline regardless of comment wording', () => {
  assert.equal(nextDueAt({additionalFollowUps: [{comment: 'Call next month', enteredAt: '2026-09-11T21:00:00+05:30'}]}).toISOString(),
    '2026-09-13T04:30:00.000Z');
});
test('completed and deleted records never need reminders', () => {
  for (const outcome of ['purchased', 'closedWithoutPurchase']) {
    assert.equal(nextDueAt({outcome, followUp1: 'Call', followUp1At: '2026-09-11T21:00:00+05:30'}), null);
  }
  assert.equal(nextDueAt({deletedAt: '2026-09-12', followUp1: 'Call', followUp1At: '2026-09-11T21:00:00+05:30'}), null);
});
test('only the respective promoter and owners are recipients', () => {
  assert.deepEqual(recipientsFor('promoter-a', ['owner']), ['promoter-a', 'owner']);
  assert.equal(recipientsFor('promoter-a', ['owner']).includes('promoter-b'), false);
});
test('outside business hours notifications are withheld', () => {
  assert.equal(inBusinessHours(new Date('2026-09-12T22:00:00+05:30')), false);
  assert.equal(inBusinessHours(new Date('2026-09-12T09:00:00+05:30')), true);
});
