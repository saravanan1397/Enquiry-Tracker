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

const current = istParts();
const currentMonth = `${current.year}-${current.month}`;
const cutoff = Timestamp.fromDate(new Date(Date.now() - 48 * 60 * 60 * 1000));
const recentlyChanged = await documents(
  db.collection('salesEntries').where('updatedAt', '>=', cutoff),
);
const monthKeys = new Set([
  currentMonth,
  ...recentlyChanged.map((entry) => entry.monthKey).filter(Boolean),
]);
const people = await documents(db.collection('salesPersons'));

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

const releaseForMonth = async (monthKey) => {
  const tag = `sales-${monthKey}`;
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
        name: `Sales backup ${monthKey}`,
        body: 'Encrypted Enquiry Tracker Sales Tracker backups. Delete this release manually only when the corresponding month may be permanently removed from GitHub.',
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

for (const monthKey of [...monthKeys].sort()) {
  const [entries, audit, monthState] = await Promise.all([
    documents(db.collection('salesEntries').where('monthKey', '==', monthKey)),
    documents(db.collection('salesEntryAudit').where('monthKey', '==', monthKey)),
    documents(db.collection('salesMonths').where('monthKey', '==', monthKey)),
  ]);
  const generated = istParts();
  const generatedAtIst = `${generated.year}-${generated.month}-${generated.day}T${generated.hour}:${generated.minute}:${generated.second}+05:30`;
  const encrypted = encrypt({
    format: 'ENQUIRY_TRACKER_SALES_DATA_V1',
    projectId: serviceAccount.project_id,
    monthKey,
    generatedAtIst,
    sourceCommit: process.env.GITHUB_SHA ?? null,
    people,
    entries,
    audit,
    monthState,
  });
  const release = await releaseForMonth(monthKey);
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
  console.log(`Uploaded ${assetName} (${encrypted.length} bytes)`);
}
