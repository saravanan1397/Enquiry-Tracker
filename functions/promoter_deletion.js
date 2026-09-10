const admin = require('firebase-admin');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { hash } = require('./pin_reset_logic');

function deletionHandler(db, auth) {
  return async request => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Owner sign-in required.');
    const uid = request.data?.uid;
    if (typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid) || request.data?.confirmation !== 'DELETE') {
      throw new HttpsError('invalid-argument', 'Confirm the selected promoter by typing DELETE.');
    }
    if (uid === request.auth.uid) throw new HttpsError('permission-denied', 'You cannot delete your own account here.');
    const profileRef = db.doc(`promoters/${uid}`);
    // Minimal server-only UID marker prevents an old ID token recreating a deleted
    // profile and permits retry after partial failure. No name/mobile/credentials.
    const jobRef = db.doc(`promoterDeletions/${uid}`);
    const finished = await db.runTransaction(async tx => {
      const [ownerDoc, targetUser, profileDoc, jobDoc] = await Promise.all([
        tx.get(db.doc(`users/${request.auth.uid}`)), tx.get(db.doc(`users/${uid}`)),
        tx.get(profileRef), tx.get(jobRef),
      ]);
      const owner = ownerDoc.data();
      if (owner?.role !== 'admin' || owner.active !== true) {
        throw new HttpsError('permission-denied', 'Only active owners can delete promoters.');
      }
      if (targetUser.data()) throw new HttpsError('permission-denied', 'Owner/user accounts cannot be deleted through promoter management.');
      const profile = profileDoc.data();
      if (jobDoc.data()?.status === 'complete') return true;
      if ((!profile || profile.role !== 'promoter') && !jobDoc.data()) {
        throw new HttpsError('not-found', 'Promoter profile not found. No account was deleted.');
      }
      if (profile?.mobile) {
        const secret = (await tx.get(db.doc(`pinResetSecrets/${hash(profile.mobile)}`))).data();
        if (secret?.uid === uid && secret.status === 'processing') {
          throw new HttpsError('failed-precondition', 'A PIN reset is processing. Wait until it finishes before deleting.');
        }
      }
      if (profile) tx.update(profileRef, { active: false, status: 'deleting' });
      tx.set(jobRef, { status: 'pending' });
      return false;
    });
    if (finished) return { deleted: true };

    try {
      try { await auth.deleteUser(uid); }
      catch (error) { if (error.code !== 'auth/user-not-found') throw error; }

      // Paginate cleanup. Recheck ownership transactionally because a device token
      // may be reassigned to a different account between query and deletion.
      for (const collection of ['reminderDevices', 'pinResetSecrets']) {
        while (true) {
          const page = await db.collection(collection).where('uid', '==', uid).limit(300).get();
          if (page.docs.length === 0) break;
          await db.runTransaction(async tx => {
            const fresh = await Promise.all(page.docs.map(doc => tx.get(doc.ref)));
            fresh.forEach((doc, i) => {
              if (doc.data()?.uid === uid) tx.delete(page.docs[i].ref);
            });
          });
        }
      }
      await db.recursiveDelete(db.doc(`pinResetRequests/${uid}`));
      for (const child of await profileRef.listCollections()) {
        await db.recursiveDelete(child);
      }
      const finalBatch = db.batch();
      finalBatch.delete(profileRef);
      finalBatch.set(jobRef, { status: 'complete' });
      await finalBatch.commit();
      return { deleted: true };
    } catch (_) {
      // Keep the deletion marker/profile locked. Retrying is safe even when Auth
      // was already deleted. Never report success while cleanup is incomplete.
      throw new HttpsError('internal', 'Deletion is incomplete. The account is blocked. Retry Delete permanently to finish cleanup.');
    }
  };
}
exports.deletionHandler = deletionHandler;
exports.deletePromoterPermanently = onCall(
  { region: 'asia-south1', timeoutSeconds: 540, maxInstances: 5 },
  request => deletionHandler(admin.firestore(), admin.auth())(request),
);
