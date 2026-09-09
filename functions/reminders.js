const admin = require('firebase-admin');
const { createHash } = require('node:crypto');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { nextDueAt, indiaDay, inBusinessHours, recipientsFor } = require('./reminder_logic');
const db = () => admin.firestore();
const hash = value => createHash('sha256').update(value).digest('hex');

exports.registerReminderDevice = onCall({ region: 'asia-south1' }, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const uid = request.auth.uid;
  const [owner, promoter] = await Promise.all([
    db().doc(`users/${uid}`).get(), db().doc(`promoters/${uid}`).get(),
  ]);
  if (!((owner.data()?.role === 'admin' && owner.data()?.active === true) ||
        (promoter.data()?.role === 'promoter' && promoter.data()?.active === true))) {
    throw new HttpsError('permission-denied', 'An approved account is required.');
  }
  const token = request.data?.token;
  if (typeof token !== 'string' || token.length < 20 || token.length > 4096) {
    throw new HttpsError('invalid-argument', 'Invalid notification registration.');
  }
  // A token can belong to only one authenticated UID, even on shared devices.
  await db().collection('reminderDevices').doc(hash(token)).set({
    uid, token, updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { registered: true };
});

exports.sendFollowUpReminders = onSchedule({
  region: 'asia-south1', schedule: 'every 5 minutes', timeZone: 'Asia/Kolkata',
  timeoutSeconds: 540, maxInstances: 1,
}, async () => {
  const now = new Date();
  if (!inBusinessHours(now)) return;
  const [owners, promoters] = await Promise.all([
    db().collection('users').where('active', '==', true).get(),
    db().collection('promoters').where('active', '==', true).get(),
  ]);
  const ownerIds = owners.docs.filter(d => d.data().role === 'admin').map(d => d.id);
  for (const promoter of promoters.docs) {
    if (promoter.data().role !== 'promoter') continue;
    const overdue = [];
    let cursor;
    // Page by document ID so older records also participate without migration.
    while (true) {
      let query = db().collection('leads').where('promoterId', '==', promoter.id)
        .orderBy(admin.firestore.FieldPath.documentId()).limit(400);
      if (cursor) query = query.startAfter(cursor);
      const page = await query.get();
      for (const lead of page.docs) {
        const due = nextDueAt(lead.data());
        if (due && due <= now) overdue.push(`${lead.id}:${due.toISOString()}`);
      }
      if (page.size < 400) break;
      cursor = page.docs[page.docs.length - 1];
    }
    if (!overdue.length) continue;
    const signature = hash(`${indiaDay(now)}:${overdue.sort().join('|')}`);
    const body = `${promoter.data().name || 'Promoter'} has ${overdue.length} pending followups.`;
    for (const uid of recipientsFor(promoter.id, ownerIds)) {
      const devices = await db().collection('reminderDevices').where('uid', '==', uid).get();
      for (const device of devices.docs) {
        const data = device.data();
        if (!data.updatedAt || now - data.updatedAt.toDate() > 35 * 86400000) continue;
        const state = db().collection('reminderDelivery').doc(hash(`${device.id}:${promoter.id}`));
        const claimed = await db().runTransaction(async tx => {
          const previous = (await tx.get(state)).data();
          if (previous?.signature === signature || previous?.leaseUntil?.toMillis() > now.getTime()) return false;
          tx.set(state, { leaseUntil: admin.firestore.Timestamp.fromMillis(now.getTime() + 600000) }, { merge: true });
          return true;
        });
        if (!claimed) continue;
        try {
          // Recheck device ownership immediately before dispatch.
          if ((await device.ref.get()).data()?.uid !== uid) continue;
          await admin.messaging().send({
            token: data.token,
            notification: { title: 'Pending follow-ups', body },
            data: { promoterId: promoter.id, recipientUid: uid, count: String(overdue.length) },
            android: { priority: 'high', ttl: 5 * 60 * 1000,
              notification: { tag: `followups-${promoter.id}` } },
          });
          await state.set({ signature, sentAt: admin.firestore.FieldValue.serverTimestamp(),
            leaseUntil: admin.firestore.Timestamp.fromMillis(0) });
        } catch (error) {
          await state.set({ leaseUntil: admin.firestore.Timestamp.fromMillis(0) }, { merge: true });
          if (['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(error.code)) {
            await device.ref.delete();
          } else { throw error; }
        }
      }
    }
  }
});
