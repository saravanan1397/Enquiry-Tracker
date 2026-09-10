# Owner-approved promoter PIN reset

Only PIN recovery is added. No inactive-profile deletion or reactivation automation is included.

## Enable in Firebase

The three callable functions require the Firebase project to support Cloud Functions deployment (Blaze billing plan). The owner must approve billing in the Firebase console; the code does not change billing. Email/Password Authentication must remain enabled because promoter phone numbers map to existing internal Auth email accounts.

From the project folder:

```powershell
firebase deploy --only functions:requestPromoterPinReset,functions:generatePromoterPinResetCode,functions:completePromoterPinReset,firestore:rules --project sshtrackingapp
```

No collection needs manual creation. The server creates `pinResetRequests` (owner-readable), `pinResetSecrets` and `pinResetLimits` (server-only). Never make these collections publicly writable. Do not manually store PINs or raw codes. Deploy rules and functions before distributing the new app build.

## Use

1. Promoter: Sign in screen > Forgot PIN? > registered mobile > Request owner approval.
2. Owner: Promoters > PIN reset requests > verify the person's identity using a trusted existing contact or in person > Verify & generate code.
3. Owner: share the displayed 8-digit code privately. It is displayed once, expires in 15 minutes, and locks after five incorrect attempts. Regeneration invalidates the earlier code.
4. Promoter: Forgot PIN? > I already have a reset code > mobile, code, new PIN and confirmation > Set new PIN. Sign in normally afterward.

Only the password changes. The Auth UID, disabled/approved status, assignments, enquiries and history remain unchanged. Refresh tokens are revoked; already-issued ID tokens may remain usable until expiry (typically up to an hour). This is not an immediate remote-wipe mechanism and does not erase offline cached records.

Requests expire for owner issuance after 24 hours; submit a fresh request then. Public request and redemption endpoints limit attempts per mobile and IP. Anonymous repeat requests cannot cancel a live code. A reset that fails after claiming its code is not retried with the same code; ask the owner for a replacement. A request stuck in `processing` after a server interruption needs operator investigation before clearing/reissuing; never release it while the old operation may still be running.

For high-volume production, configure App Check for Android/web before enforcing it on these public recovery endpoints, and configure billing alerts. Rate limiting does not replace abuse monitoring. Do not log request payloads (they contain PINs/codes).

## Verification

```powershell
node --test functions/pin_reset.test.js functions/reminder_logic.test.js
flutter analyze
flutter test
flutter build web --release --base-href /Enquiry-Tracker/
```

After deployment, test with a dedicated promoter account: pending request visible only to owners, wrong/expired/reused code rejected, new PIN works, old PIN fails, same enquiries remain, and disabled accounts remain disabled. Automated backend tests use an in-memory Firestore/Auth adapter; live Firebase permissions/deployment must also be checked.

Firebase reference: https://firebase.google.com/docs/auth/admin/manage-users and https://firebase.google.com/docs/auth/admin/manage-sessions
