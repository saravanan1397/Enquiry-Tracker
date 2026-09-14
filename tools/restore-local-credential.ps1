param(
    [Parameter(Mandatory = $true)]
    [string]$EncryptedFile,
    [Parameter(Mandatory = $true)]
    [string]$OutputFile
)

$ErrorActionPreference = 'Stop'
$SecurePassword = Read-Host 'Credential backup password' -AsSecureString
$PasswordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
try {
    $env:ENQUIRY_TRACKER_CREDENTIAL_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($PasswordPointer)
    node (Join-Path $PSScriptRoot 'credential-crypto.mjs') decrypt $EncryptedFile $OutputFile
    if ($LASTEXITCODE -ne 0) { throw 'Credential restoration failed.' }
}
finally {
    $env:ENQUIRY_TRACKER_CREDENTIAL_PASSWORD = $null
    if ($PasswordPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($PasswordPointer)
    }
}

Write-Host "Credential restored to $OutputFile"
