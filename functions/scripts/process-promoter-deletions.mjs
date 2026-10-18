import { createRequire } from 'node:module';
import { initializeApp, cert } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

const accountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
if (!accountJson) throw new Error('Missing FIREBASE_SERVICE_ACCOUNT_JSON secret.');
const account = JSON.parse(accountJson);
initializeApp({ credential: cert(account) });

const db = getFirestore();
const auth = getAuth();
const requests = db.collection('promoterDeletionRequests');
const retryFailed = process.env.PROMOTER_DELETION_RETRY_FAILED === 'true';
const eligibleStatuses = retryFailed
  ? ['pending', 'processing', 'failed']
  : ['pending', 'processing'];
const require = createRequire(import.meta.url);
const { deletionHandler } = require('../promoter_deletion.js');
const permanentlyDelete = deletionHandler(db, auth);

const queued = await requests
  .where('status', 'in', eligibleStatuses)
  .limit(50)
  .get();

if (queued.empty) {
  console.log('No eligible promoter permanent-deletion requests.');
  process.exit(0);
}

for (const candidate of queued.docs) {
  const reference = candidate.ref;
  const claimed = await db.runTransaction(async transaction => {
    const latest = await transaction.get(reference);
    const data = latest.data();
    const claimableStatuses = retryFailed
      ? ['pending', 'processing', 'failed']
      : ['pending', 'processing'];
    if (!latest.exists || !claimableStatuses.includes(data?.status)) {
      return null;
    }
    transaction.update(reference, {
      status: 'processing',
      startedAt: Timestamp.now(),
      error: null,
    });
    return data;
  });
  if (!claimed) continue;

  try {
    if (typeof claimed.promoterId !== 'string' ||
        typeof claimed.requestedBy !== 'string') {
      throw new Error('Deletion request is missing its promoter or admin ID.');
    }
    await permanentlyDelete({
      auth: { uid: claimed.requestedBy },
      data: { uid: claimed.promoterId, confirmation: 'DELETE' },
    });
    await reference.delete();
    console.log(`Permanently deleted promoter account ${claimed.promoterId}.`);
  } catch (error) {
    const causeCode = error?.details?.causeCode;
    const causeMessage = error?.details?.causeMessage;
    const message = causeMessage
      ? `${String(error?.message ?? error)} Cause (${causeCode ?? 'unknown'}): ${String(causeMessage).slice(0, 400)}`
      : String(error?.message ?? error).slice(0, 500);
    console.error(`Promoter deletion ${candidate.id} failed: ${message}`);
    await reference.update({
      status: 'failed',
      completedAt: Timestamp.now(),
      error: message.slice(0, 900),
    });
  }
}
