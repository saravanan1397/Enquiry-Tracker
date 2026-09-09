const INDIA_OFFSET = 330 * 60 * 1000;
const HOUR = 60 * 60 * 1000;

function asDate(value) {
  if (!value) return null;
  if (typeof value.toDate === 'function') return value.toDate();
  if (value instanceof Date) return value;
  // Legacy dates without an offset were captured on India-local devices.
  const text = String(value);
  const date = new Date(/(?:Z|[+-]\d\d:\d\d)$/.test(text) ? text : `${text}+05:30`);
  return Number.isNaN(date.getTime()) ? null : date;
}

function nextDueAt(lead) {
  if (lead.deletedAt || ['purchased', 'closedWithoutPurchase'].includes(lead.outcome)) return null;
  const extra = lead.additionalFollowUps || [];
  const last = extra.length ? asDate(extra[extra.length - 1].enteredAt)
    : (lead.followUp3 || '').trim() ? asDate(lead.followUp3At)
    : (lead.followUp2 || '').trim() ? asDate(lead.followUp2At)
    : (lead.followUp1 || '').trim() ? asDate(lead.followUp1At) : null;
  if (!last) return null;
  let cursor = last.getTime() + INDIA_OFFSET;
  let remaining = 15 * HOUR;
  while (remaining > 0) {
    const day = new Date(cursor);
    const start = Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate(), 9);
    const end = start + 13 * HOUR;
    if (cursor >= end) { cursor = start + 24 * HOUR; continue; }
    cursor = Math.max(cursor, start);
    const available = end - cursor;
    if (remaining <= available) return new Date(cursor + remaining - INDIA_OFFSET);
    remaining -= available;
    cursor = start + 24 * HOUR;
  }
  return new Date(cursor - INDIA_OFFSET);
}

function indiaDay(now) { return new Date(now.getTime() + INDIA_OFFSET).toISOString().slice(0, 10); }
function inBusinessHours(now) {
  const hour = new Date(now.getTime() + INDIA_OFFSET).getUTCHours();
  return hour >= 9 && hour < 22;
}
function recipientsFor(promoterId, ownerIds) { return [...new Set([promoterId, ...ownerIds])]; }
module.exports = { nextDueAt, indiaDay, inBusinessHours, recipientsFor };
