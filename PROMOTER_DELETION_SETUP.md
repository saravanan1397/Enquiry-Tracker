# Disable versus permanently delete a promoter

Owner > Promoters > three-dot menu:

- Disable: block app/database access but retain the Auth account, profile, assignments and history. Reactivate restores the same account. Existing connected app sessions now watch profile status and return to sign-in when disabled or deleted.
- Delete permanently: confirm the person's name/mobile, type DELETE and confirm. Removes the Firebase Auth account, promoter profile (including any nested profile data), reset request, private reset secrets and reminder-device registrations for that UID. Customer enquiries, original attribution and history are preserved, not transferred or deleted. Transfer open enquiries before deletion so someone continues follow-ups. Re-registration creates a new UID and does not inherit the deleted account's enquiries.

No real promoter is deleted during deployment/testing. Deletion only occurs when an owner explicitly confirms the action in the app.

## Deployment

Cloud Functions requires Blaze. Billing must be enabled by the project owner; this implementation does not upgrade billing. Deploy the deletion function and the updated reset/device functions together to prevent concurrent resets/device registrations racing with cleanup:

```powershell
firebase deploy --only functions:deletePromoterPermanently,functions:requestPromoterPinReset,functions:generatePromoterPinResetCode,functions:completePromoterPinReset,functions:registerReminderDevice,firestore:rules --project sshtrackingapp
```

No new manual collection is necessary. The server creates `promoterDeletions/{uid}`, containing only a deletion-state marker, not a profile, mobile number, PIN or token. This server-only marker prevents an old cached Auth token recreating the profile and makes interrupted operations safely retryable. Existing hashed abuse-rate limits remain for their security purpose. Historical enquiry records remain unchanged.

The operation first blocks the profile, deletes Auth, removes associated account data in bounded batches, and removes the profile last. On failure it reports incomplete cleanup and keeps the profile blocked. Use Retry permanent deletion to finish; do not reactivate a half-deleted account. A PIN reset already processing must finish before deletion is permitted. Never delete owner accounts through this action.

Disconnected devices cannot receive a remote disable/delete until reconnecting. This is not remote device wiping; already downloaded offline customer data cannot be remotely erased while a device has no connection. Firestore rejects subsequent server access based on the inactive/missing profile.

Tests use in-memory Auth/Firestore adapters; verify end-to-end with a dedicated test promoter after deployment. Run `node --test functions/promoter_deletion.test.js functions/pin_reset.test.js functions/reminder_logic.test.js`, `flutter analyze` and `flutter test`.

Firebase Admin API reference: https://firebase.google.com/docs/auth/admin/manage-users#delete_a_user
