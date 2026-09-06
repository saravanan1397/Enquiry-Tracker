# Firebase setup

The app now uses Cloud Firestore as its central lead store while retaining
Hive as the offline device store.

## Connect this Flutter project

From PowerShell:

```powershell
cd "D:\Projects\Mobile App"
flutter pub get
firebase login
dart pub global activate flutterfire_cli
flutterfire configure
```

In the FlutterFire prompts, select the Firebase project and the Android
platform. This creates `lib/firebase_options.dart` with the real project
configuration. The checked-in placeholder file is replaced automatically.

In the Firebase console, create a Cloud Firestore database. For the first
use, choose production mode. Then enable **Authentication → Sign-in method →
Email/Password**.

Create the first owner in **Authentication → Users → Add user**. Copy that
user's UID and create a Firestore document at `users/{uid}` with:

```text
name: Owner
role: admin
active: true
```

Deploy the production rules from the project folder:

```powershell
firebase use sshtrackingapp
firebase deploy --only firestore:rules
```

## Test the sync flow

1. Run the app and choose **New promoter? Create an account**.
2. Register with a mobile number and a PIN of at least six digits.
3. On the owner device, open **Promoters**. Approve the new registration and
   confirm or change the assigned shop. The app updates `active` to `true` and
   `status` to `approved`.
4. Sign in with the promoter's mobile number and PIN.
5. Save a customer. It is written to encrypted Hive first, so it works
   without internet.
6. Restore internet connectivity. The promoter device uploads pending leads.
7. Run the app on the owner's device using the owner email and password, then
   tap the sync icon. The owner dashboard downloads the central `leads`
   collection.

Each lead uses its local stable ID as the Firestore document ID, so retrying a
sync updates the same record instead of creating a duplicate. Recycle-bin
records are uploaded as soft-delete tombstones.

## Production security still required

Promoter PINs are used as Firebase Authentication passwords behind the scenes;
the PIN is never stored in Firestore. The app creates a pending promoter
profile, and the owner must approve it before access is granted. The owner
account is created manually in Firebase Authentication and linked to a
`users/{uid}` admin document. The owner can later disable or re-enable the
promoter from the app's **Promoters** section.
