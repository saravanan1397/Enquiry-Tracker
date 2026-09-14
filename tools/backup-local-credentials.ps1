param(
    [Parameter(Mandatory = $true)]
    [string]$BackupRepositoryPath
)

$ErrorActionPreference = 'Stop'
$ProjectPath = Split-Path -Parent $PSScriptRoot
$BackupPath = (Resolve-Path -LiteralPath $BackupRepositoryPath).Path
$GitFolder = Join-Path $BackupPath '.git'

if (-not (Test-Path -LiteralPath $GitFolder -PathType Container)) {
    throw "BackupRepositoryPath must be a cloned Git repository."
}

$Remote = git -C $BackupPath remote get-url origin
if ($LASTEXITCODE -ne 0 -or $Remote -notmatch 'Enquiry-Tracker-Backup(?:\.git)?$') {
    throw "The selected repository must be Enquiry-Tracker-Backup."
}

$Sources = @(
    @{ Input = (Join-Path $ProjectPath 'Git secrets.txt'); Output = 'Git-secrets.txt.etcred' },
    @{ Input = (Join-Path $ProjectPath 'sshtrackingapp-2db5c46c703b.json'); Output = 'sshtrackingapp-service-account.json.etcred' }
)

foreach ($Item in $Sources) {
    if (-not (Test-Path -LiteralPath $Item.Input -PathType Leaf)) {
        throw "Required credential file is missing: $($Item.Input)"
    }
}

$SecurePassword = Read-Host 'Credential backup password (minimum 12 characters)' -AsSecureString
$PasswordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
try {
    $env:ENQUIRY_TRACKER_CREDENTIAL_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($PasswordPointer)
    $OutputFolder = Join-Path $BackupPath 'credentials'
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null

    foreach ($Item in $Sources) {
        $OutputFile = Join-Path $OutputFolder $Item.Output
        node (Join-Path $PSScriptRoot 'credential-crypto.mjs') encrypt $Item.Input $OutputFile
        if ($LASTEXITCODE -ne 0) { throw 'Credential encryption failed.' }
    }
}
finally {
    $env:ENQUIRY_TRACKER_CREDENTIAL_PASSWORD = $null
    if ($PasswordPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($PasswordPointer)
    }
}

git -C $BackupPath add -- 'credentials/Git-secrets.txt.etcred' 'credentials/sshtrackingapp-service-account.json.etcred'
git -C $BackupPath commit -m 'Back up encrypted local credentials'
if ($LASTEXITCODE -ne 0) {
    Write-Host 'No credential changes needed a new commit.'
    exit 0
}
git -C $BackupPath push origin main
if ($LASTEXITCODE -ne 0) { throw 'Encrypted credential backup push failed.' }

Write-Host 'Encrypted credential copies were pushed to the private backup repository.'
