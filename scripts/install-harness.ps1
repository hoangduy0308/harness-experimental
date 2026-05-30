param(
  [Alias('d')]
  [string]$Directory = $PWD.Path,
  [Alias('y')]
  [switch]$Yes,
  [switch]$Merge,
  [switch]$Override,
  [switch]$Force,
  [switch]$DryRun,
  [switch]$RefreshAgentShim
)

$ErrorActionPreference = 'Stop'

function Fail($Message) {
  Write-Error $Message
  exit 1
}

function Log($Message) {
  Write-Output $Message
}

function Resolve-TargetPath($Path) {
  $expanded = [Environment]::ExpandEnvironmentVariables($Path)
  if ($expanded.StartsWith('~')) {
    $expanded = Join-Path $HOME $expanded.Substring(1).TrimStart('\', '/')
  }
  if ([System.IO.Path]::IsPathRooted($expanded)) {
    return [System.IO.Path]::GetFullPath($expanded)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $PWD.Path $expanded))
}

function Get-SourceFile($Relative) {
  Join-Path $SourceRoot $Relative
}

function Copy-HarnessFile($Relative) {
  $target = Join-Path $TargetDir $Relative

  if ($Relative -eq '.gitignore' -and (Test-Path -LiteralPath $target) -and -not $Force) {
    Merge-Gitignore $target
    return
  }

  if (Test-Path -LiteralPath $target) {
    if ($ConflictAction -eq 'merge') {
      if ($Relative -in @('scripts/harness', 'scripts/harness.cmd')) {
        if ($DryRun) {
          Log "update   $Relative (refresh launcher)"
        } else {
          $backup = Join-Path $BackupDir $Relative
          New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
          Copy-Item -LiteralPath $target -Destination $backup -Force
          Write-SourceFile $Relative $target
          Log "updated $Relative (backup: $($backup.Substring($TargetDir.Length + 1)))"
        }
        $script:Updated++
      } else {
        Log "skip     $Relative (merge keeps existing file)"
        $script:Skipped++
      }
      return
    }

    if ($Force) {
      if ($DryRun) {
        Log "overwrite $Relative (backup first)"
      } else {
        $backup = Join-Path $BackupDir $Relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
        Copy-Item -LiteralPath $target -Destination $backup -Force
        Write-SourceFile $Relative $target
        Log "updated $Relative (backup: $($backup.Substring($TargetDir.Length + 1)))"
      }
      $script:Updated++
    } else {
      Log "skip     $Relative (already exists)"
      $script:Skipped++
    }
    return
  }

  if ($DryRun) {
    Log "create   $Relative"
  } else {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Write-SourceFile $Relative $target
    Log "created  $Relative"
  }
  $script:Created++
}

function Write-SourceFile($Relative, $Target) {
  $source = Get-SourceFile $Relative
  if (Test-Path -LiteralPath $source) {
    Copy-Item -LiteralPath $source -Destination $Target -Force
    return
  }

  $uriRelative = ($Relative -replace '\\', '/')
  $url = "$SourceBaseUrl/$uriRelative"
  Invoke-WebRequest -Uri $url -OutFile $Target -UseBasicParsing
}

function Merge-Gitignore($Target) {
  $rules = @('harness.db', 'harness.db-wal', 'harness.db-shm', 'scripts/bin/harness-cli', 'scripts/bin/harness-cli.exe')
  $existing = if (Test-Path -LiteralPath $Target) { Get-Content -LiteralPath $Target } else { @() }
  $missing = $rules | Where-Object { $existing -notcontains $_ }
  if (-not $missing) {
    Log 'skip     .gitignore (harness rules already present)'
    $script:Skipped++
    return
  }

  if ($DryRun) {
    Log 'update   .gitignore (append harness rules)'
  } else {
    Add-Content -LiteralPath $Target -Value ''
    Add-Content -LiteralPath $Target -Value '# Harness durable layer'
    Add-Content -LiteralPath $Target -Value $missing
    Log 'updated  .gitignore (appended harness rules)'
  }
  $script:Updated++
}

function Test-HarnessCliSupportsCurrentSchema($BinaryPath) {
  $probeDb = Join-Path ([System.IO.Path]::GetTempPath()) ("harness-cli-probe-" + [guid]::NewGuid().ToString('N') + ".db")
  $oldHarnessDb = $env:HARNESS_DB
  $oldHarnessRoot = $env:HARNESS_REPO_ROOT
  try {
    $env:HARNESS_DB = $probeDb
    $env:HARNESS_REPO_ROOT = $TargetDir
    $storyHelp = & $BinaryPath story --help 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (($storyHelp -join "`n") -match '(^|\s)list(\s|$)')) {
      return $false
    }

    & $BinaryPath init *> $null
    if ($LASTEXITCODE -ne 0) { return $false }

    $traceOutput = & $BinaryPath trace --summary "__harness_probe__" --outcome review 2>&1
    if ($LASTEXITCODE -ne 0) { return $false }
    return (($traceOutput -join "`n") -match 'Trace #')
  } finally {
    if ($null -eq $oldHarnessDb) {
      Remove-Item Env:HARNESS_DB -ErrorAction SilentlyContinue
    } else {
      $env:HARNESS_DB = $oldHarnessDb
    }
    if ($null -eq $oldHarnessRoot) {
      Remove-Item Env:HARNESS_REPO_ROOT -ErrorAction SilentlyContinue
    } else {
      $env:HARNESS_REPO_ROOT = $oldHarnessRoot
    }
    Remove-Item -LiteralPath $probeDb, "$probeDb-wal", "$probeDb-shm" -Force -ErrorAction SilentlyContinue
  }
}

function Install-HarnessCliBinary {
  $platform = $env:HARNESS_CLI_PLATFORM
  if (-not $platform) { $platform = 'windows-x64' }
  if ($platform -notlike 'windows-*') {
    Fail "PowerShell installer supports Windows CLI assets only; got $platform"
  }

  $binaryName = "harness-cli-$platform"
  $target = Join-Path $TargetDir 'scripts\bin\harness-cli.exe'

  if ((Test-Path -LiteralPath $target) -and $ConflictAction -eq 'merge' -and -not $Force -and (Test-HarnessCliSupportsCurrentSchema $target)) {
    Log 'skip     scripts/bin/harness-cli.exe (existing CLI supports current schema)'
    $script:Skipped++
    return
  }

  if ($DryRun) {
    Log "download $binaryName -> scripts/bin/harness-cli.exe"
    Log "verify   $binaryName.sha256"
    $script:Created++
    return
  }

  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("harness-cli-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  try {
    $binaryTmp = Join-Path $tmp $binaryName
    $checksumTmp = Join-Path $tmp "$binaryName.sha256"
    Invoke-WebRequest -Uri "$CliBaseUrl/$binaryName" -OutFile $binaryTmp -UseBasicParsing
    Invoke-WebRequest -Uri "$CliBaseUrl/$binaryName.sha256" -OutFile $checksumTmp -UseBasicParsing

    $expected = ((Get-Content -LiteralPath $checksumTmp -Raw).Trim() -split '\s+')[0].ToLowerInvariant()
    if (-not $expected) { Fail "Checksum file is empty: $CliBaseUrl/$binaryName.sha256" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $binaryTmp).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
      Fail "Checksum mismatch for ${binaryName}: expected $expected, got $actual"
    }
    if (-not (Test-HarnessCliSupportsCurrentSchema $binaryTmp)) {
      Fail "Downloaded Harness CLI does not support the current schema. Publish a compatible release or set HARNESS_CLI_BASE_URL to one before installing."
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    if (Test-Path -LiteralPath $target) {
      if ($Force -or $ConflictAction -eq 'merge') {
        $backup = Join-Path $BackupDir 'scripts\bin\harness-cli.exe'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
        Copy-Item -LiteralPath $target -Destination $backup -Force
      }
      $script:Updated++
      Log 'updated  scripts/bin/harness-cli.exe'
    } else {
      $script:Created++
      Log 'created  scripts/bin/harness-cli.exe'
    }
    Copy-Item -LiteralPath $binaryTmp -Destination $target -Force
    Log "verified scripts/bin/harness-cli.exe ($platform)"
  } finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Check-ProtectedTargetPaths {
  $conflicts = @('AGENTS.md', 'docs', 'scripts') | Where-Object { Test-Path -LiteralPath (Join-Path $TargetDir $_) }
  if (-not $conflicts) { return }

  if ($Merge) {
    $script:ConflictAction = 'merge'
    Log 'Continuing with merge. Existing files will be skipped.'
    return
  }
  if ($Override) {
    $script:ConflictAction = 'override'
    Override-ProtectedTargetPaths
    return
  }
  if ($Yes) {
    Fail "target already contains protected Harness paths: $($conflicts -join ', '). Use -Merge or -Override."
  }

  Fail "target already contains protected Harness paths: $($conflicts -join ', '). Re-run with -Merge or -Override."
}

function Override-ProtectedTargetPaths {
  foreach ($protected in @('AGENTS.md', 'docs', 'scripts')) {
    $target = Join-Path $TargetDir $protected
    if (-not (Test-Path -LiteralPath $target)) { continue }
    if ($DryRun) {
      Log "override $protected (backup first)"
      continue
    }
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    Move-Item -LiteralPath $target -Destination (Join-Path $BackupDir $protected)
    Log "removed  $protected (backup: $($BackupDir.Substring($TargetDir.Length + 1))\$protected)"
  }
}

$TargetDir = Resolve-TargetPath $Directory
$script:Created = 0
$script:Updated = 0
$script:Skipped = 0
$script:ConflictAction = 'install'
$BackupDir = Join-Path $TargetDir ('.harness-backup\' + (Get-Date -Format yyyyMMddHHmmss))
$SourceBaseUrl = $env:HARNESS_SOURCE_BASE_URL
if (-not $SourceBaseUrl) { $SourceBaseUrl = 'https://raw.githubusercontent.com/hoangduy0308/harness-experimental/main' }
$SourceBaseUrl = $SourceBaseUrl.TrimEnd('/')
$CliBaseUrl = $env:HARNESS_CLI_BASE_URL
if (-not $CliBaseUrl) { $CliBaseUrl = 'https://github.com/hoangduy0308/harness-experimental/releases/latest/download' }
$CliBaseUrl = $CliBaseUrl.TrimEnd('/')
$SourceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

if ($Merge -and $Override) { Fail 'Choose only one of -Merge or -Override.' }
if (-not (Test-Path -LiteralPath $TargetDir)) {
  if ($DryRun) { Log "Target directory would be created: $TargetDir" } else { New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null }
}

Check-ProtectedTargetPaths

Log "Harness source: $SourceRoot"
Log "Harness CLI source: $CliBaseUrl"
Log "Target project: $TargetDir"

@(
  'AGENTS.md',
  'README.md',
  'docs/ARCHITECTURE.md',
  'docs/CONTEXT_RULES.md',
  'docs/FEATURE_INTAKE.md',
  'docs/GLOSSARY.md',
  'docs/HARNESS.md',
  'docs/HARNESS_BACKLOG.md',
  'docs/HARNESS_COMPONENTS.md',
  'docs/HARNESS_MATURITY.md',
  'docs/README.md',
  'docs/TEST_MATRIX.md',
  'docs/TRACE_SPEC.md',
  'docs/decisions/0001-harness-first-development.md',
  'docs/decisions/0002-post-spec-product-lifecycle.md',
  'docs/decisions/0003-generic-spec-intake-harness.md',
  'docs/decisions/0004-sqlite-durable-layer.md',
  'docs/decisions/0005-prebuilt-rust-harness-cli.md',
  'docs/decisions/README.md',
  'docs/product/README.md',
  'docs/stories/README.md',
  'docs/stories/backlog.md',
  'docs/templates/decision.md',
  'docs/templates/spec-intake.md',
  'docs/templates/story.md',
  'docs/templates/validation-report.md',
  'docs/templates/high-risk-story/design.md',
  'docs/templates/high-risk-story/execplan.md',
  'docs/templates/high-risk-story/overview.md',
  'docs/templates/high-risk-story/validation.md',
  'scripts/README.md',
  'scripts/harness',
  'scripts/harness.cmd',
  'scripts/install-harness.ps1',
  'scripts/schema/001-init.sql',
  'scripts/schema/002-trace-review-outcome.sql',
  '.gitignore'
) | ForEach-Object { Copy-HarnessFile $_ }

Install-HarnessCliBinary

Log ''
Log "Done. Created: $Created, updated: $Updated, skipped: $Skipped."
if ($Skipped -gt 0 -and -not $Force) {
  Log 'Existing files were left untouched. Re-run with -Force to overwrite with backups.'
}
