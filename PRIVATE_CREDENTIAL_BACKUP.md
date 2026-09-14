# Private credential backup

The original credential files remain excluded from the public `Enquiry-Tracker`
repository. Only AES-256-GCM encrypted copies are stored in the private
`Enquiry-Tracker-Backup` repository.

## Back up both credential files

Clone the private backup repository once, then run this command from the app
project in PowerShell:

```powershell
.\tools\backup-local-credentials.ps1 -BackupRepositoryPath "D:\Projects\Enquiry-Tracker-Backup"
```

Enter a new password of at least 12 characters when prompted. Keep this password
in a password manager and never put it in either credential file, Git, or GitHub
Secrets. The command encrypts only `Git secrets.txt` and
`sshtrackingapp-2db5c46c703b.json`, commits the encrypted copies, and pushes them
to the private repository.

## Restore one credential file

```powershell
.\tools\restore-local-credential.ps1 -EncryptedFile "D:\Projects\Enquiry-Tracker-Backup\credentials\Git-secrets.txt.etcred" -OutputFile "D:\Restore\Git secrets.txt"
```

Use the same password entered during backup. A wrong password or modified file
will fail authentication and will not produce usable plaintext.
