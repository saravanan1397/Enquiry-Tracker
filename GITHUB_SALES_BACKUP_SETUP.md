# GitHub Sales Tracker backup setup

The web app writes owner-only Sales Tracker records to Firestore. The scheduled
workflow reads those collections at 11:00 PM Asia/Kolkata, compresses and
encrypts them with AES-256-GCM, then uploads a dated asset to a monthly release
in a separate private GitHub repository.

The browser never receives the Firebase service-account key, GitHub token, or
backup password. Deleting data in the app deletes it from Firestore only. It
does not call GitHub or delete an existing backup.

## One-time manual setup

1. Create a new **private** GitHub repository, for example
   `Enquiry-Tracker-Backups`, and select **Add a README file** so the repository
   has a default branch. Do not add application source code to it.
2. Create a fine-grained GitHub personal access token restricted to that one
   repository with **Contents: Read and write** permission.
3. In Google Cloud IAM for Firebase project `sshtrackingapp`, create a dedicated
   service account with the **Cloud Datastore User** role
   (`roles/datastore.user`), then create one JSON key for it. This role is
   required because the backup runner reads Sales Tracker data and writes the
   manual request's `processing`, `completed`, or `failed` status. Do not grant
   broad Owner or Editor access.
4. Open the application repository on GitHub, then go to
   **Settings → Secrets and variables → Actions → New repository secret**.
5. Add these four repository secrets:
   - `FIREBASE_SERVICE_ACCOUNT_JSON`: the complete contents of the JSON key.
   - `SALES_BACKUP_PASSWORD`: a long unique password kept in your password
     manager. Losing it makes backups impossible to decrypt.
   - `SALES_BACKUP_REPOSITORY`: `saravanan1397/Enquiry-Tracker-Backups` (or the
     private repository name you chose).
   - `SALES_BACKUP_TOKEN`: the fine-grained token from step 2.
6. Deploy the updated Firestore rules and push this workflow to `main`.
7. Open **Actions → Encrypted Sales Tracker backup → Run workflow** once.
8. Confirm that the private backup repository contains a release named
   `Sales backup YYYY-MM` with an `.etbackup` asset.

## How the daily backup is organised

The 11:00 PM Asia/Kolkata workflow always backs up the current sales month. It
also backs up any earlier month containing a sales entry changed during the
previous 48 hours. GitHub therefore has one release per sales month, such as
`Sales backup 2026-09` and `Sales backup 2026-08`. Each daily run adds a new
dated encrypted `.etbackup` asset inside every month selected by that rule.

GitHub Actions scheduled workflows can start later than their configured time
during platform congestion. The computer running the web app does not need to
be switched on.

## Manual backup troubleshooting

The web app's **Back up now** button creates
`salesBackupRequests/current` with status `pending`. A scheduled GitHub Actions
poll reads the request, marks it `processing`, uploads the encrypted backup,
and then marks it `completed`. GitHub scheduling is not real-time, so the poll
can take longer than five minutes.

If a run reports `PERMISSION_DENIED: Missing or insufficient permissions`,
verify that the service account email contained in
`FIREBASE_SERVICE_ACCOUNT_JSON` has **Cloud Datastore User** on project
`sshtrackingapp`. Firestore client security rules do not grant permissions to
the Admin SDK service account; Google Cloud IAM does.

## Manual GitHub deletion

To remove a month from GitHub, open the private backup repository's Releases
page and delete the corresponding `Sales backup YYYY-MM` release. This is never
triggered by the Enquiry Tracker application.

## Recovery check

Download an `.etbackup` file and run the included decrypt script locally with
the same `SALES_BACKUP_PASSWORD`. The result is inspectable JSON containing
salespeople, daily sales, timestamps, edit history and month status.
