import { gzipSync } from 'node:zlib';
import {
  createCipheriv,
  randomBytes,
  scryptSync,
} from 'node:crypto';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

const required = (name) => {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing required secret: ${name}`);
  return value;
};

const serviceAccount = JSON.parse(required('FIREBASE_SERVICE_ACCOUNT_JSON'));
const password = required('SALES_BACKUP_PASSWORD');
const backupRepository = required('SALES_BACKUP_REPOSITORY');
const githubToken = required('SALES_BACKUP_TOKEN');
const githubApi = 'https://api.github.com';
const githubHeaders = {
  Accept: 'application/vnd.github+json',
  Authorization: `Bearer ${githubToken}`,
  'User-Agent': 'enquiry-tracker-sales-backup',
  'X-GitHub-Api-Version': '2022-11-28',
};

initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();
const runMode = process.env.SALES_BACKUP_RUN_MODE?.trim() || 'daily';
const requestReference = db.collection('salesBackupRequests').doc('current');

const istParts = (date = new Date()) => {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Kolkata',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(date);
  return Object.fromEntries(parts.map(({ type, value }) => [type, value]));
};

const serialize = (value) => {
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (Array.isArray(value)) return value.map(serialize);
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [key, serialize(item)]),
    );
  }
  return value;
};

const documents = async (query) => {
  const snapshot = await query.get();
  return snapshot.docs.map((document) => ({
    id: document.id,
    ...serialize(document.data()),
  }));
};

const githubRequest = async (url, options = {}) => {
  const response = await fetch(url, {
    ...options,
    headers: { ...githubHeaders, ...(options.headers ?? {}) },
  });
  if (!response.ok) {
    throw new Error(
      `GitHub request failed (${response.status}): ${await response.text()}`,
    );
  }
  return response;
};

const fullBackupRelease = async () => {
  const tag = 'sales-tracker-full';
  const existing = await fetch(
    `${githubApi}/repos/${backupRepository}/releases/tags/${tag}`,
    { headers: githubHeaders },
  );
  if (existing.ok) return existing.json();
  if (existing.status !== 404) {
    throw new Error(`Could not read backup release: ${await existing.text()}`);
  }
  const created = await githubRequest(
    `${githubApi}/repos/${backupRepository}/releases`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        tag_name: tag,
        name: 'Sales Tracker full backup',
        body: 'Complete encrypted Sales Tracker snapshots containing every available month, salesperson, daily sale, audit record and month status.',
        draft: false,
        prerelease: false,
      }),
    },
  );
  return created.json();
};

const encrypt = (payload) => {
  const salt = randomBytes(16);
  const iv = randomBytes(12);
  const key = scryptSync(password, salt, 32);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const compressed = gzipSync(Buffer.from(JSON.stringify(payload)));
  const ciphertext = Buffer.concat([cipher.update(compressed), cipher.final()]);
  return Buffer.from(
    JSON.stringify({
      format: 'ENQUIRY_TRACKER_SALES_BACKUP_V1',
      cipher: 'AES-256-GCM',
      compression: 'gzip',
      salt: salt.toString('base64'),
      iv: iv.toString('base64'),
      authTag: cipher.getAuthTag().toString('base64'),
      data: ciphertext.toString('base64'),
    }),
  );
};

let requestedBackup = false;

const requestStatusUpdate = async (fields, phase) => {
  try {
    await requestReference.update(fields);
  } catch (error) {
    if (Number(error?.code) === 7 || error?.code === 'permission-denied') {
      throw new Error(
        `The backup service account cannot ${phase} in Firestore. ` +
          'Grant it the Cloud Datastore User role (roles/datastore.user) ' +
          'for the Firebase project, then rerun the backup.',
        { cause: error },
      );
    }
    throw error;
  }
};

try {
  if (runMode === 'requested') {
    const request = await requestReference.get();
    const requestData = request.data();
    if (!request.exists || requestData?.status !== 'pending') {
      console.log('No pending owner backup request.');
      process.exit(0);
    }
    requestedBackup = true;
    await requestStatusUpdate({
      status: 'processing',
      startedAt: Timestamp.now(),
      error: null,
    }, 'mark the owner backup request as processing');
  }

  const [
    people,
    personNames,
    entries,
    audit,
    monthState,
    personTotalSnapshots,
  ] = await Promise.all([
    documents(db.collection('salesPersons')),
    documents(db.collection('salesPersonNames')),
    documents(db.collection('salesEntries')),
    documents(db.collection('salesEntryAudit')),
    documents(db.collection('salesMonths')),
    documents(db.collection('salesPersonTotalSnapshots')),
  ]);
  const generated = istParts();
  const generatedAtIst = `${generated.year}-${generated.month}-${generated.day}T${generated.hour}:${generated.minute}:${generated.second}+05:30`;
  const encrypted = encrypt({
    format: 'ENQUIRY_TRACKER_SALES_DATA_V3',
    scope: 'all-sales-tracker-data',
    projectId: serviceAccount.project_id,
    generatedAtIst,
    sourceCommit: process.env.GITHUB_SHA ?? null,
    people,
    personNames,
    entries,
    audit,
    monthState,
    personTotalSnapshots,
  });
  const release = await fullBackupRelease();
  const assetName =
    `sales-backup-${generated.year}${generated.month}${generated.day}-${generated.hour}${generated.minute}${generated.second}-IST.etbackup`;
  const uploadUrl = release.upload_url.replace('{?name,label}', '');
  await githubRequest(`${uploadUrl}?name=${encodeURIComponent(assetName)}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/octet-stream',
      'Content-Length': String(encrypted.length),
    },
    body: encrypted,
  });
  const assetNames = [assetName];
  console.log(
    `Uploaded complete Sales Tracker backup ${assetName} ` +
      `(${encrypted.length} bytes; ${entries.length} sales entries)`,
  );

  if (requestedBackup) {
    await requestStatusUpdate({
      status: 'completed',
      completedAt: Timestamp.now(),
      assetNames,
      error: null,
    }, 'mark the owner backup request as completed');
  }
} catch (error) {
  if (requestedBackup) {
    try {
      await requestStatusUpdate({
        status: 'failed',
        completedAt: Timestamp.now(),
        error: String(error?.message ?? error).slice(0, 500),
      }, 'record the failed owner backup request');
    } catch (statusError) {
      console.error(
        'Could not record the backup failure in Firestore:',
        statusError,
      );
    }
  }
  throw error;
}
