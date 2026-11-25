# StudyPro Auto-Update One-Time Setup
# Run this file on the Windows PC that owns the StudyPro GitHub repositories.
# It creates/reuses the Tauri signing key locally and writes only the required
# public key / encrypted GitHub Actions secrets through GitHub CLI.
# Never upload the private key to chat or commit it to a repository.

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$SourceRepo = "sasinduboy88-ctrl/StudyPro"
$ReleaseRepo = "sasinduboy88-ctrl/StudyPro-Releases"
$ExpectedGitHubUser = "sasinduboy88-ctrl"
$TauriCliVersion = "2.12.6"
$KeyDirectory = Join-Path $HOME ".tauri\StudyPro"
$PrivateKeyPath = Join-Path $KeyDirectory "studypro.key"
$PublicKeyPath = "$PrivateKeyPath.pub"

function Write-Section([string]$Message) {
    Write-Host ""
    Write-Host "=== $Message ===" -ForegroundColor Cyan
}
function Invoke-Checked([string]$File, [string[]]$Arguments, [string]$FailureMessage) {
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) { throw $FailureMessage }
}
function Refresh-ProcessPath {
    $candidates = @(
        "$env:ProgramFiles\GitHub CLI",
        "$env:ProgramFiles\GitHub CLI\bin",
        "$env:LOCALAPPDATA\Programs\GitHub CLI",
        "$env:LOCALAPPDATA\Programs\GitHub CLI\bin",
        "$env:ProgramFiles\nodejs"
    )
    foreach ($candidate in $candidates) {
        if ((Test-Path -LiteralPath $candidate) -and ($env:Path -notlike "*$candidate*")) {
            $env:Path = "$candidate;$env:Path"
        }
    }
}
function Ensure-WingetPackage([string]$CommandName, [string]$PackageId, [string]$DisplayName) {
    Refresh-ProcessPath
    if (Get-Command $CommandName -ErrorAction SilentlyContinue) { return }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "Windows Package Manager (winget) is not available. Install/update 'App Installer' from Microsoft Store, then run this setup again."
    }
    Write-Host "Installing $DisplayName..."
    & winget install --id $PackageId --exact --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Refresh-ProcessPath
        if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
            throw "Could not install $DisplayName with winget. Run Windows Update / App Installer, then retry."
        }
    }
    Refresh-ProcessPath
    if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
        throw "$DisplayName was installed but is not available in this PowerShell session. Close PowerShell, open it again, and rerun this setup."
    }
}

try {
    Write-Section "1/6 — Install required tools"
    Ensure-WingetPackage "gh" "GitHub.cli" "GitHub CLI"
    Ensure-WingetPackage "node" "OpenJS.NodeJS.LTS" "Node.js LTS"
    Ensure-WingetPackage "npm" "OpenJS.NodeJS.LTS" "Node.js npm"

    Write-Host "Installing pinned Tauri CLI $TauriCliVersion..."
    Invoke-Checked "npm" @("install", "--global", "@tauri-apps/cli@$TauriCliVersion") "Tauri CLI installation failed."
    Refresh-ProcessPath
    Invoke-Checked "tauri" @("--version") "Tauri CLI could not be started."

    Write-Section "2/6 — Sign in to GitHub"
    Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
    Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
    & gh auth status --hostname github.com 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "A browser sign-in will open. Sign in to the GitHub account that owns StudyPro."
        Invoke-Checked "gh" @("auth", "login", "--hostname", "github.com", "--git-protocol", "https", "--web", "--scopes", "repo,workflow") "GitHub sign-in did not complete."
    } else {
        Write-Host "Refreshing GitHub CLI scopes for private repository automation..."
        Invoke-Checked "gh" @("auth", "refresh", "--hostname", "github.com", "--scopes", "repo,workflow") "GitHub permission refresh failed."
    }

    $githubUser = (& gh api user --jq ".login").Trim()
    if ($LASTEXITCODE -ne 0 -or $githubUser -ne $ExpectedGitHubUser) {
        throw "GitHub is signed in as '$githubUser'. Sign in as $ExpectedGitHubUser and run this setup again."
    }

    $isAdmin = (& gh api "repos/$SourceRepo" --jq ".permissions.admin").Trim()
    if ($LASTEXITCODE -ne 0 -or $isAdmin -ne "true") {
        throw "The signed-in GitHub account does not have repository admin access to $SourceRepo."
    }
    $releaseVisibility = (& gh api "repos/$ReleaseRepo" --jq ".visibility").Trim()
    if ($LASTEXITCODE -ne 0 -or $releaseVisibility -ne "public") {
        throw "$ReleaseRepo must exist and remain public."
    }

    Write-Section "3/6 — Check existing signing keys"
    New-Item -ItemType Directory -Force -Path $KeyDirectory | Out-Null
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls $KeyDirectory /inheritance:r /grant:r "$($identity):(OI)(CI)F" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not tighten the local key-folder ACL. The key folder remains under your Windows user profile; check its permissions."
    }

    $secretNames = @(& gh secret list --repo $SourceRepo --json name --jq ".[].name" 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Could not list GitHub Actions secrets. Check GitHub repository permissions." }
    $variableNames = @(& gh variable list --repo $SourceRepo --json name --jq ".[].name" 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Could not list GitHub Actions variables. Check GitHub repository permissions." }

    $hasPrivateSecret = $secretNames -contains "TAURI_SIGNING_PRIVATE_KEY"
    $hasPublicVariable = $variableNames -contains "STUDYPRO_UPDATER_PUBLIC_KEY"
    $hasReleaseToken = $secretNames -contains "STUDYPRO_RELEASE_TOKEN"
    $localPrivateExists = Test-Path -LiteralPath $PrivateKeyPath
    $localPublicExists = Test-Path -LiteralPath $PublicKeyPath

    if ($localPrivateExists -xor $localPublicExists) {
        throw "Only one local signing key file exists. To avoid breaking existing installations, no key will be regenerated automatically. Keep the existing key pair together."
    }
    if ($hasPrivateSecret -and -not $hasPublicVariable) {
        throw "GitHub already has a private signing secret but its public key variable is missing. The secret cannot be read back, so this setup refuses to guess or replace the matching public key."
    }
    if ($hasPublicVariable -and -not $hasPrivateSecret -and -not ($localPrivateExists -and $localPublicExists)) {
        throw "GitHub has a public signing key but no matching local private key or Actions secret. Refusing to generate a new key that would break installed apps."
    }

    $publicKey = $null
    $privateKey = $null
    $newKeyGenerated = $false

    if ($localPrivateExists -and $localPublicExists) {
        $privateKey = Get-Content -LiteralPath $PrivateKeyPath -Raw
        $publicKey = (Get-Content -LiteralPath $PublicKeyPath -Raw).Trim()
        if ([string]::IsNullOrWhiteSpace($privateKey) -or [string]::IsNullOrWhiteSpace($publicKey)) {
            throw "The existing local signing key pair is empty or unreadable."
        }
        if ($hasPublicVariable) {
            $remotePublicKey = (& gh variable get STUDYPRO_UPDATER_PUBLIC_KEY --repo $SourceRepo).Trim()
            if ($LASTEXITCODE -ne 0 -or $remotePublicKey -ne $publicKey) {
                throw "The local public key does not match the key already configured in GitHub. Refusing to change a key used by installed apps."
            }
        }
        Write-Host "Reusing the existing local StudyPro signing key pair. No new key will be created."
    } elseif ($hasPrivateSecret -and $hasPublicVariable) {
        Write-Host "GitHub already has both signing settings. They will be preserved; no new key will be generated."
    } else {
        Write-Host "Generating the first StudyPro updater signing key pair."
        Write-Host "The private key stays on this PC and is sent only to GitHub Actions Secrets."
        $oldCI = $env:CI
        $env:CI = "true"
        try {
            Invoke-Checked "tauri" @("signer", "generate", "-w", $PrivateKeyPath, "--ci") "Tauri signing key generation failed."
        } finally {
            if ($null -eq $oldCI) { Remove-Item Env:CI -ErrorAction SilentlyContinue } else { $env:CI = $oldCI }
        }
        if (-not (Test-Path -LiteralPath $PrivateKeyPath) -or -not (Test-Path -LiteralPath $PublicKeyPath)) {
            throw "Tauri did not create both signing key files."
        }
        $privateKey = Get-Content -LiteralPath $PrivateKeyPath -Raw
        $publicKey = (Get-Content -LiteralPath $PublicKeyPath -Raw).Trim()
        $newKeyGenerated = $true
    }

    if ($localPrivateExists -or $newKeyGenerated) {
        if (-not $hasPublicVariable) {
            $publicKey | & gh variable set STUDYPRO_UPDATER_PUBLIC_KEY --repo $SourceRepo
            if ($LASTEXITCODE -ne 0) { throw "Could not save STUDYPRO_UPDATER_PUBLIC_KEY to GitHub." }
            $hasPublicVariable = $true
        }
        if (-not $hasPrivateSecret) {
            $privateKey | & gh secret set TAURI_SIGNING_PRIVATE_KEY --repo $SourceRepo
            if ($LASTEXITCODE -ne 0) { throw "Could not save TAURI_SIGNING_PRIVATE_KEY to GitHub Actions Secrets." }
            $hasPrivateSecret = $true
        }
        if ($newKeyGenerated -and ($secretNames -contains "TAURI_SIGNING_PRIVATE_KEY_PASSWORD")) {
            & gh secret delete TAURI_SIGNING_PRIVATE_KEY_PASSWORD --repo $SourceRepo
            if ($LASTEXITCODE -ne 0) { throw "Could not remove a stale signing-password secret for the newly generated passwordless key." }
        }
    }

    if (-not ($hasPrivateSecret -and $hasPublicVariable)) {
        throw "Signing key configuration is incomplete. No release will be started."
    }

    Write-Section "4/6 — Configure release upload access"
    $releaseToken = $null
    $providedToken = Read-Host "Paste a fine-grained GitHub token limited to $ReleaseRepo (Contents: Read and write). Press Enter to keep an existing token or use your signed-in GitHub CLI account token" -AsSecureString
    $tokenPointer = [IntPtr]::Zero
    try {
        if ($providedToken.Length -gt 0) {
            $tokenPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($providedToken)
            $releaseToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPointer)
        }
    } finally {
        if ($tokenPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPointer) }
    }

    if ([string]::IsNullOrWhiteSpace($releaseToken) -and -not $hasReleaseToken) {
        Write-Warning "The fallback GitHub CLI token can have broader account-level repository access than a fine-grained token."
        $allowBroadToken = Read-Host "Use the signed-in GitHub CLI token as the release secret? Type YES to approve"
        if ($allowBroadToken -cne "YES") {
            throw "No release upload token was supplied. Create a fine-grained token for StudyPro-Releases and run setup again."
        }
        $releaseToken = (& gh auth token --hostname github.com).Trim()
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($releaseToken)) {
            throw "Could not read the authenticated GitHub CLI token."
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($releaseToken)) {
        $oldGhToken = $env:GH_TOKEN
        $env:GH_TOKEN = $releaseToken
        try {
            $canPushRelease = (& gh api "repos/$ReleaseRepo" --jq ".permissions.push").Trim()
            if ($LASTEXITCODE -ne 0 -or $canPushRelease -ne "true") {
                throw "The supplied release token cannot write to $ReleaseRepo. Use a fine-grained token with Contents: Read and write."
            }
        } finally {
            if ($null -eq $oldGhToken) { Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue } else { $env:GH_TOKEN = $oldGhToken }
        }

        if (-not $hasReleaseToken -or $providedToken.Length -gt 0) {
            $releaseToken | & gh secret set STUDYPRO_RELEASE_TOKEN --repo $SourceRepo
            if ($LASTEXITCODE -ne 0) { throw "Could not save STUDYPRO_RELEASE_TOKEN to GitHub Actions Secrets." }
            $hasReleaseToken = $true
        }
    } else {
        Write-Host "An existing STUDYPRO_RELEASE_TOKEN secret will be preserved."
    }
    $releaseToken = $null
    $providedToken = $null

    Write-Section "5/6 — Verify GitHub configuration"
    $secretNames = @(& gh secret list --repo $SourceRepo --json name --jq ".[].name")
    $variableNames = @(& gh variable list --repo $SourceRepo --json name --jq ".[].name")
    foreach ($required in @("TAURI_SIGNING_PRIVATE_KEY", "STUDYPRO_RELEASE_TOKEN")) {
        if ($secretNames -notcontains $required) { throw "GitHub Actions secret missing after setup: $required" }
    }
    if ($variableNames -notcontains "STUDYPRO_UPDATER_PUBLIC_KEY") {
        throw "GitHub Actions variable missing after setup: STUDYPRO_UPDATER_PUBLIC_KEY"
    }
    Write-Host "GitHub Actions now has the required updater variable and secrets."
    Write-Host "The private signing key was not added to any Git repository."

    Write-Section "6/6 — Optional first signed release"
    Write-Host "Your currently installed StudyPro 1.0.0 was built before the updater public key was configured."
    Write-Host "The first signed release (1.0.1) must be installed once manually. Later versions can update inside StudyPro."
    $startRelease = Read-Host "Start the first signed StudyPro release (v1.0.1) now? Type YES to start"
    if ($startRelease -ceq "YES") {
        Invoke-Checked "gh" @("workflow", "run", "publish-release.yml", "--repo", $SourceRepo, "--ref", "main", "-f", "version=1.0.1") "Could not start the signed release workflow."
        Write-Host "Signed release workflow started." -ForegroundColor Green
        Start-Process "https://github.com/$SourceRepo/actions/workflows/publish-release.yml"
    } else {
        Write-Host "Setup completed. The signed release was not started; no public release was created."
    }

    Write-Host ""
    Write-Host "IMPORTANT: Back up this private key file to a secure offline location:" -ForegroundColor Yellow
    Write-Host $PrivateKeyPath -ForegroundColor Yellow
    Write-Host "Never share it, upload it to chat, or commit it to GitHub."
    Write-Host "Setup finished." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "StudyPro Auto-Update setup stopped safely:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "No signing key is automatically overwritten by this script."
    exit 1
}
