# Promoter email recovery (Spark-compatible)

Promoters continue signing in with their 10-digit mobile number and numeric PIN. Firebase Authentication stores the verified recovery email and password securely; neither the email nor PIN is stored in Firestore. This app remembers only the email-to-mobile mapping in secure storage on each device/browser.

## Promoter flow

- New promoter: enter a real email during registration, open the verification link, then wait for owner approval.
- Existing promoter who knows the PIN: tap **Set up / verify recovery email**, authenticate with mobile + current PIN, verify the email, then tap **I verified my email**.
- New device/browser: tap **New device / email changed?**, enter the verified email once, and sign in with mobile + PIN.
- Forgotten PIN: tap **Forgot PIN?**, enter the verified email, open the email link, and choose a new numeric PIN.
- Existing promoter with no linked email and no current PIN: identity must be handled outside the app; Firebase's secure email recovery cannot recover an account that never linked an email.

## One-time Firebase Console configuration

1. Authentication > Settings > Authorized domains: add `saravanan1397.github.io`.
2. Authentication > Templates > Password reset > Customize action URL: use `https://saravanan1397.github.io/Enquiry-Tracker/`.
3. Repeat the same custom action URL for Email address verification and Email address change templates.

The custom hosted handler is required so reset links enforce the app's numeric PIN rules. Email/Password sign-in must remain enabled; no Blaze upgrade, SMS provider, Cloud Function or manual Firestore collection is required for email recovery.
