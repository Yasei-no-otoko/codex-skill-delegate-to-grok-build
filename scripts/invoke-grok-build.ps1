#Requires -Version 7.0

[CmdletBinding(DefaultParameterSetName = 'Inline')]
param(
    [Parameter(Mandatory, Position = 0, ParameterSetName = 'Inline')]
    [ValidateNotNullOrEmpty()]
    [string]$Prompt,

    [Parameter(Mandatory, ParameterSetName = 'File')]
    [ValidateNotNullOrEmpty()]
    [string]$PromptFile,

    [ValidateNotNullOrEmpty()]
    [string]$WorkingDirectory = (Get-Location).Path,

    [ValidateSet('Review', 'Edit')]
    [string]$Mode = 'Review',

    [string]$Model,

    [ValidateSet('low', 'medium', 'high', 'xhigh')]
    [string]$ReasoningEffort,

    [ValidateRange(1, 100)]
    [int]$MaxTurns = 12,

    [ValidateRange(5, 3600)]
    [int]$TimeoutSeconds = 300,

    [string[]]$DenyRule = @(),

    [switch]$EnableWebSearch,

    [string]$GrokExecutable,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-GrokExecutable {
    param([string]$RequestedPath)

    if ($RequestedPath) {
        if (Test-Path -LiteralPath $RequestedPath -PathType Leaf) {
            return (Resolve-Path -LiteralPath $RequestedPath).Path
        }

        $requestedCommand = Get-Command $RequestedPath -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($requestedCommand) {
            return $requestedCommand.Source
        }

        throw "Grok executable was not found: $RequestedPath"
    }

    $grokCommand = Get-Command grok -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($grokCommand) {
        return $grokCommand.Source
    }

    $installedPath = Join-Path $env:USERPROFILE '.grok\bin\grok.exe'
    if (Test-Path -LiteralPath $installedPath -PathType Leaf) {
        return $installedPath
    }

    throw 'Grok Build CLI was not found. Install it or pass -GrokExecutable.'
}

function Add-ArgumentPair {
    param(
        [System.Collections.Generic.List[string]]$Target,
        [string]$Name,
        [string]$Value
    )

    $Target.Add($Name)
    $Target.Add($Value)
}

$resolvedWorkingDirectory = (Resolve-Path -LiteralPath $WorkingDirectory).Path
if (-not (Test-Path -LiteralPath $resolvedWorkingDirectory -PathType Container)) {
    throw "Working directory is not a directory: $WorkingDirectory"
}

$resolvedPromptFile = $null
if ($PSCmdlet.ParameterSetName -eq 'File') {
    $resolvedPromptFile = (Resolve-Path -LiteralPath $PromptFile).Path
    if (-not (Test-Path -LiteralPath $resolvedPromptFile -PathType Leaf)) {
        throw "Prompt file is not a file: $PromptFile"
    }
}

$executable = Resolve-GrokExecutable -RequestedPath $GrokExecutable
$arguments = [System.Collections.Generic.List[string]]::new()

$arguments.Add('--no-auto-update')
Add-ArgumentPair -Target $arguments -Name '--cwd' -Value $resolvedWorkingDirectory
Add-ArgumentPair -Target $arguments -Name '--max-turns' -Value $MaxTurns.ToString()
Add-ArgumentPair -Target $arguments -Name '--output-format' -Value 'json'
$arguments.Add('--no-memory')
$arguments.Add('--no-subagents')
$arguments.Add('--no-plan')
Add-ArgumentPair -Target $arguments -Name '--permission-mode' -Value 'dontAsk'

if ($Model) {
    Add-ArgumentPair -Target $arguments -Name '--model' -Value $Model
}

$fixedRules = @'
Act only as a bounded delegated worker in the selected working directory. Respect every repository instruction. Preserve pre-existing user changes. Never access credentials, modify Git metadata, commit, push, tag, create or edit remote resources, install software, change machine configuration, or perform destructive cleanup. Do not ask interactive questions. If a required action is unavailable, report the blocker. Finish with a concise report containing SUMMARY, EVIDENCE OR CHANGES, VERIFICATION, and BLOCKERS.
'@

if ($Mode -eq 'Review') {
    Add-ArgumentPair -Target $arguments -Name '--sandbox' -Value 'read-only'
    Add-ArgumentPair -Target $arguments -Name '--allow' -Value 'Read'
    Add-ArgumentPair -Target $arguments -Name '--allow' -Value 'Grep'
    Add-ArgumentPair -Target $arguments -Name '--deny' -Value 'Edit'
    Add-ArgumentPair -Target $arguments -Name '--deny' -Value 'Bash'
    $fixedRules += "`nThis is a read-only delegation. Use only file listing, read, and grep tools. Do not create, edit, move, or delete files, and do not run shell commands."
}
else {
    Add-ArgumentPair -Target $arguments -Name '--sandbox' -Value 'workspace'
    Add-ArgumentPair -Target $arguments -Name '--allow' -Value 'Read'
    Add-ArgumentPair -Target $arguments -Name '--allow' -Value 'Grep'
    Add-ArgumentPair -Target $arguments -Name '--allow' -Value 'Edit'
    Add-ArgumentPair -Target $arguments -Name '--deny' -Value 'Bash'
    $fixedRules += "`nEdits are allowed only inside the selected working directory and only when required by the delegated task. Do not run shell commands; the parent agent performs verification."
}

Add-ArgumentPair -Target $arguments -Name '--deny' -Value 'MCPTool'

if ($EnableWebSearch) {
    Add-ArgumentPair -Target $arguments -Name '--allow' -Value 'WebSearch'
    Add-ArgumentPair -Target $arguments -Name '--allow' -Value 'WebFetch'
}
else {
    $arguments.Add('--disable-web-search')
    Add-ArgumentPair -Target $arguments -Name '--deny' -Value 'WebSearch'
    Add-ArgumentPair -Target $arguments -Name '--deny' -Value 'WebFetch'
}

$defaultDenyRules = @(
    'Bash(git commit*)',
    'Bash(git push*)',
    'Bash(git tag*)',
    'Bash(git reset*)',
    'Bash(git clean*)',
    'Bash(git checkout*)',
    'Bash(git restore*)',
    'Bash(git rebase*)',
    'Bash(git merge*)',
    'Bash(git cherry-pick*)',
    'Bash(git config*)',
    'Bash(git remote*)',
    'Bash(gh *)',
    'Bash(Remove-Item*)',
    'Bash(ri *)',
    'Bash(rm *)',
    'Bash(del *)',
    'Bash(erase *)',
    'Bash(rmdir *)',
    'Bash(rd *)',
    'Bash(*&&*)',
    'Bash(*||*)',
    'Bash(*;*)',
    'Bash(*|*)',
    'Bash(*&*)',
    'Bash(*>*)',
    'Bash(*<*)',
    'Bash(format *)',
    'Bash(shutdown *)',
    'Bash(winget *)',
    'Bash(choco *)',
    'Bash(scoop *)',
    'Bash(Set-ExecutionPolicy*)'
)

$profilePath = (Resolve-Path -LiteralPath $env:USERPROFILE).Path.TrimEnd('\')
$workingPath = $resolvedWorkingDirectory.TrimEnd('\')
$sensitivePathDenyRules = @(
    "Read($profilePath\.grok\**)",
    "Edit($profilePath\.grok\**)",
    "Read($profilePath\.ssh\**)",
    "Edit($profilePath\.ssh\**)",
    "Read($profilePath\.aws\**)",
    "Edit($profilePath\.aws\**)",
    "Read($profilePath\.azure\**)",
    "Edit($profilePath\.azure\**)",
    "Read($profilePath\.kube\**)",
    "Edit($profilePath\.kube\**)",
    "Read($profilePath\.git-credentials)",
    "Edit($profilePath\.git-credentials)",
    "Read($profilePath\.npmrc)",
    "Edit($profilePath\.npmrc)",
    "Read($workingPath\.env*)",
    "Edit($workingPath\.env*)",
    "Read($workingPath\**\.env*)",
    "Edit($workingPath\**\.env*)",
    "Read($workingPath\**\*.pem)",
    "Edit($workingPath\**\*.pem)",
    "Read($workingPath\**\*.key)",
    "Edit($workingPath\**\*.key)",
    "Edit($workingPath\.git\**)",
    "Edit($workingPath\**\.git\**)"
)

foreach ($rule in ($defaultDenyRules + $sensitivePathDenyRules + $DenyRule)) {
    Add-ArgumentPair -Target $arguments -Name '--deny' -Value $rule
}

Add-ArgumentPair -Target $arguments -Name '--rules' -Value $fixedRules

if ($ReasoningEffort) {
    Add-ArgumentPair -Target $arguments -Name '--reasoning-effort' -Value $ReasoningEffort
}

$temporaryPromptFile = $null
if ($resolvedPromptFile) {
    Add-ArgumentPair -Target $arguments -Name '--prompt-file' -Value $resolvedPromptFile
}
elseif ($DryRun) {
    Add-ArgumentPair -Target $arguments -Name '--prompt-file' -Value '<temporary prompt file>'
}
else {
    $temporaryPromptFile = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-grok-prompt-{0}.txt" -f [guid]::NewGuid().ToString('N'))
    [System.IO.File]::WriteAllText($temporaryPromptFile, $Prompt, [System.Text.UTF8Encoding]::new($false))
    Add-ArgumentPair -Target $arguments -Name '--prompt-file' -Value $temporaryPromptFile
}

if ($DryRun) {
    $displayArguments = [System.Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $arguments.Count; $index++) {
        $value = $arguments[$index]
        $displayArguments.Add($value)
    }

    [pscustomobject]@{
        executable = $executable
        workingDirectory = $resolvedWorkingDirectory
        mode = $Mode
        arguments = $displayArguments
    } | ConvertTo-Json -Depth 4
    return
}

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $executable
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
foreach ($argument in $arguments) {
    $startInfo.ArgumentList.Add($argument)
}

if (-not $startInfo.Environment['GROK_HOME']) {
    $startInfo.Environment['GROK_HOME'] = Join-Path $env:USERPROFILE '.grok'
}

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo

try {
    if (-not $process.Start()) {
        throw 'Failed to start Grok Build.'
    }

    $standardOutputTask = $process.StandardOutput.ReadToEndAsync()
    $standardErrorTask = $process.StandardError.ReadToEndAsync()

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try {
            $process.Kill($true)
            $process.WaitForExit()
        }
        catch {
            [Console]::Error.WriteLine("Failed to terminate the timed-out Grok Build process tree: $($_.Exception.Message)")
        }

        $timedOutOutput = $standardOutputTask.GetAwaiter().GetResult()
        $timedOutError = $standardErrorTask.GetAwaiter().GetResult()
        if ($timedOutOutput) { Write-Output $timedOutOutput.TrimEnd() }
        if ($timedOutError) { [Console]::Error.Write($timedOutError) }
        [Console]::Error.WriteLine("Grok Build timed out after $TimeoutSeconds seconds and was terminated.")
        exit 124
    }

    $grokOutput = $standardOutputTask.GetAwaiter().GetResult()
    $grokError = $standardErrorTask.GetAwaiter().GetResult()
    $grokExitCode = $process.ExitCode
}
finally {
    $process.Dispose()
    if ($temporaryPromptFile -and (Test-Path -LiteralPath $temporaryPromptFile)) {
        Remove-Item -LiteralPath $temporaryPromptFile -Force -ErrorAction SilentlyContinue
    }
}

if ($grokOutput) { Write-Output $grokOutput.TrimEnd() }
if ($grokError) { [Console]::Error.Write($grokError) }

if ($grokExitCode -ne 0) {
    [Console]::Error.WriteLine("Grok Build exited with code $grokExitCode. Check authentication with 'grok models' and sign in with 'grok login' if needed.")
    exit $grokExitCode
}

try {
    $grokResult = $grokOutput | ConvertFrom-Json -ErrorAction Stop
}
catch {
    [Console]::Error.WriteLine("Grok Build returned malformed JSON: $($_.Exception.Message)")
    exit 65
}

if ($grokResult.stopReason -ne 'end_turn') {
    [Console]::Error.WriteLine("Grok Build did not complete normally (stopReason=$($grokResult.stopReason)).")
    exit 2
}
