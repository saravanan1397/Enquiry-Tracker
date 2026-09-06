# Enquiry Tracker — Promoter Enquiry Capture

VS Code-ready Flutter project foundation for the offline-first promoter app and owner admin panel.

## Current slice

- Promoter capture screen with name, mobile number, and first comment.
- PIN entry with separate promoter and admin demo roles.
- Three follow-up comment fields with a dedicated follow-up screen.
- Admin filters for shop, promoter, and any follow-up stage.
- Owner soft-delete, restore, and permanent-delete actions.
- Local encrypted Hive storage for leads on the Android device.
- Firebase Cloud Firestore sync when connectivity returns.
- Owner dashboard foundation with shop, promoter, and follow-up filters.
- Owner Promoter Accounts screen for approving and disabling registrations.
- Recycle bin foundation for soft-deleted records.
- Material 3 theme matching the approved UI direction.

## Run in VS Code

1. Install Flutter and the Android SDK.
2. Open this folder in VS Code.
3. Run `flutter pub get`.
4. Confirm an Android emulator is running with `flutter devices`.
5. Run `flutter analyze`.
6. Run `flutter test`.
7. Start the app with `flutter run -d <android-device-id>`.

For the Pixel emulator used during setup:

```powershell
flutter emulators --launch Pixel_5
flutter devices
flutter run -d emulator-5554
```

The bottom-right device picker in VS Code can also be used after the emulator boots.

## Firebase setup

The app keeps saving to encrypted Hive when offline and uploads pending leads
to Firestore when online. An admin device downloads the central `leads`
collection using the sync button. Promoters register with their own mobile
number and PIN; owners sign in with the Firebase email/password account.
Follow [docs/firebase-setup.md](docs/firebase-setup.md) to connect the app to
your Firebase project.

## Important implementation note

The local encrypted database, Firebase Authentication flow, Firestore
transport, and production rules are implemented. Promoter registration is
pending until an owner approves the account. Owners should disable a promoter
by setting their `promoters/{uid}` document to `active: false`.

The Android Gradle configuration disables Kotlin incremental compilation and runs the Kotlin compiler in-process to avoid the Windows cache-lock failure seen during the first `url_launcher_android` build.
