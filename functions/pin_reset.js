const admin = require('firebase-admin');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { hash, validMobile, validPin, newCode, checkCode } = require('./pin_reset_logic');
const options = { region: 'asia-south1', maxInstances: 5 };
const generic = { message: 'If this number is registered, the owner will see your request. Contact the owner to verify your identity and obtain a code.' };

// Dependency injection keeps the entire callable workflow testable without live accounts.
function handlers(db, auth, now = Date.now) {
  async function throttle(request, action, mobile) {
    const time = now();
    const keys = [`${action}:ip:${request.rawRequest?.ip || 'unknown'}`,
      `${action}:mobile:${mobile}`];
    await db.runTransaction(async tx => {
      const refs = keys.map(key => db.doc(`pinResetLimits/${hash(key)}`));
      const docs = await Promise.all(refs.map(ref => tx.get(ref)));
      const values = docs.map(doc => {
        const old = doc.data();
        return !old || time - old.start >= 3600000
          ? { start: time, count: 1 } : { start: old.start, count: old.count + 1 };
      });
      if (values.some(value => value.count > 20)) {
        throw new HttpsError('resource-exhausted', 'Too many attempts. Try again in an hour.');
      }
      refs.forEach((ref, i) => tx.set(ref, values[i]));
    });
  }
  async function requireOwner(request) {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Owner sign-in required.');
    const owner = (await db.doc(`users/${request.auth.uid}`).get()).data();
    if (owner?.role !== 'admin' || owner.active !== true) {
      throw new HttpsError('permission-denied', 'Only active owners can generate reset codes.');
    }
  }
  return {
    async requestPromoterPinReset(request) {
      const mobile = request.data?.mobile;
      if (!validMobile(mobile)) throw new HttpsError('invalid-argument', 'Enter exactly 10 digits.');
      await throttle(request, 'request', mobile);
      let user;
      try { user = await auth.getUserByEmail(`${mobile}@auth.leadloop.app`); }
      catch (error) { if (error.code === 'auth/user-not-found') return generic; throw error; }
      const profile = (await db.doc(`promoters/${user.uid}`).get()).data();
      if (profile?.role !== 'promoter' || profile.mobile !== mobile) return generic;
      const ref = db.doc(`pinResetRequests/${user.uid}`);
      const secretRef = db.doc(`pinResetSecrets/${hash(mobile)}`);
      await db.runTransaction(async tx => {
        const currentProfile = (await tx.get(db.doc(`promoters/${user.uid}`))).data();
        if (!currentProfile || currentProfile.status === 'deleting') return;
        const previous = (await tx.get(ref)).data();
        const secret = (await tx.get(secretRef)).data();
        const time = now();
        // Anonymous requests must never invalidate a code the owner already issued.
        if (secret?.status === 'processing' ||
            (secret?.status === 'issued' && secret.expiresAtMs > time) ||
            (previous && time - previous.requestedAtMs < 300000)) return;
        tx.set(ref, { uid: user.uid, name: profile.name || 'Promoter', mobile,
          shopName: profile.shopName || '', status: 'pending', requestedAtMs: time });
      });
      return generic;
    },
    async generatePromoterPinResetCode(request) {
      await requireOwner(request);
      const uid = request.data?.uid;
      if (typeof uid !== 'string' || !/^[a-zA-Z0-9_-]{1,128}$/.test(uid)) {
        throw new HttpsError('invalid-argument', 'Invalid promoter.');
      }
      if (request.data?.identityVerified !== true) {
        throw new HttpsError('failed-precondition', 'Verify the promoter identity first.');
      }
      const ref = db.doc(`pinResetRequests/${uid}`);
      const result = await db.runTransaction(async tx => {
        const pending = (await tx.get(ref)).data();
        const profile = (await tx.get(db.doc(`promoters/${uid}`))).data();
        if (!pending || profile?.role !== 'promoter' || profile.status === 'deleting' || profile.mobile !== pending.mobile) {
          throw new HttpsError('not-found', 'No matching reset request.');
        }
        const secretRef = db.doc(`pinResetSecrets/${hash(pending.mobile)}`);
        const old = (await tx.get(secretRef)).data();
        const time = now();
        if (old?.status === 'processing' || pending.status === 'processing') {
          throw new HttpsError('failed-precondition', 'Reset is processing. Contact support if it does not finish.');
        }
        if (pending.status === 'used' || time - pending.requestedAtMs > 86400000) {
          throw new HttpsError('failed-precondition', 'Ask the promoter to submit a new request.');
        }
        if (pending.issuedAtMs && time - pending.issuedAtMs < 30000) {
          throw new HttpsError('resource-exhausted', 'Wait 30 seconds before generating another code.');
        }
        const generated = newCode(time);
        tx.set(secretRef, { ...generated.secret, uid });
        tx.update(ref, { status: 'issued', issuedAtMs: time,
          expiresAtMs: generated.secret.expiresAtMs, issuedBy: request.auth.uid });
        return { code: generated.code, expiresAtMs: generated.secret.expiresAtMs };
      });
      return result;
    },
    async completePromoterPinReset(request) {
      const { mobile, code, pin } = request.data || {};
      if (!validMobile(mobile) || !validPin(pin)) {
        throw new HttpsError('invalid-argument', 'Use a 10-digit mobile number and a PIN of 6–128 digits.');
      }
      await throttle(request, 'redeem', mobile);
      const secretRef = db.doc(`pinResetSecrets/${hash(mobile)}`);
      const uid = await db.runTransaction(async tx => {
        const secret = (await tx.get(secretRef)).data();
        if (secret) {
          const profile = (await tx.get(db.doc(`promoters/${secret.uid}`))).data();
          if (!profile || profile.status === 'deleting') return null;
        }
        if (!checkCode(secret, code, now())) {
          if (secret?.status === 'issued') {
            const attempts = secret.attempts + 1;
            const status = secret.expiresAtMs <= now() ? 'expired' : attempts >= 5 ? 'locked' : 'issued';
            tx.update(secretRef, { attempts, status });
            tx.update(db.doc(`pinResetRequests/${secret.uid}`), { status });
          }
          return null; // Commit attempt counters before returning an error to the caller.
        }
        tx.update(secretRef, { status: 'processing' });
        tx.update(db.doc(`pinResetRequests/${secret.uid}`), { status: 'processing' });
        return secret.uid;
      });
      if (!uid) throw new HttpsError('invalid-argument', 'Code invalid, expired or already used. Contact the owner for a new code.');
      try {
        // Only the credential changes: the UID, approval, assignments and history stay intact.
        await auth.updateUser(uid, { password: pin });
        await auth.revokeRefreshTokens(uid);
        const batch = db.batch();
        batch.update(secretRef, { status: 'used', digest: '', salt: '' });
        batch.update(db.doc(`pinResetRequests/${uid}`), { status: 'used', completedAtMs: now() });
        await batch.commit();
      } catch (_) {
        // Never make a claimed code reusable after a partial/uncertain Auth failure.
        const batch = db.batch();
        batch.update(secretRef, { status: 'failed', digest: '', salt: '' });
        batch.update(db.doc(`pinResetRequests/${uid}`), { status: 'failed' });
        await batch.commit();
        throw new HttpsError('internal', 'Reset could not finish. Ask the owner for a new code.');
      }
      return { message: 'PIN updated. Sign in with your new PIN.' };
    },
  };
}
exports.handlers = handlers;
for (const name of ['requestPromoterPinReset', 'generatePromoterPinResetCode', 'completePromoterPinReset']) {
  exports[name] = onCall(options, request => handlers(admin.firestore(), admin.auth())[name](request));
}
