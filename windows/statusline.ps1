$statusJson = ''
if ([Console]::IsInputRedirected) {
    try {
        $statusJson = [Console]::In.ReadToEnd()
    } catch {
        $statusJson = ''
    }
}

$handyHint = 'space hold to record'
$localAppData = [Environment]::GetFolderPath('LocalApplicationData')
if ([string]::IsNullOrWhiteSpace($localAppData)) {
    $localAppData = Join-Path $HOME '.cache'
}
$cacheDir = Join-Path $localAppData 'copilot-statusline'
$esc = [char]27
$reset = "$esc[0m"
$dim = "$esc[2m"
$separator = " $dim·$reset "
$colors = @{
    Refresh = $dim
    Handy = "$esc[38;5;196m"
    Azure = "$esc[38;5;208m"
    GitHub = "$esc[38;5;226m"
    Tokens = "$esc[38;5;201m"
    Agents = "$esc[38;5;46m"
    Squad = "$esc[38;5;33m"
    OpenSpec = "$esc[38;5;99m"
    SpecKit = "$esc[38;5;129m"
    Colima = "$esc[38;5;201m"
}

function Get-PropertyValue {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Short-Text {
    param(
        [string]$Text,
        [int]$Max = 36
    )

    if ($Text.Length -gt $Max) {
        return "$($Text.Substring(0, $Max - 3))..."
    }

    return $Text
}

function Paint {
    param(
        [string]$Color,
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    return "$Color$Text$reset"
}

function Join-Segments {
    param([string[]]$Segments)

    $visible = @($Segments | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    return ($visible -join $separator)
}

function Find-Up {
    param(
        [string]$StartDirectory,
        [string]$Marker
    )

    $directory = $StartDirectory
    while (-not [string]::IsNullOrWhiteSpace($directory)) {
        if (Test-Path (Join-Path $directory $Marker)) {
            return $directory
        }

        $parent = Split-Path -Parent $directory
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $directory) {
            break
        }
        $directory = $parent
    }

    return $null
}

function Get-CacheKey {
    param(
        [string]$Prefix,
        [string]$Value
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes("$Prefix`:$Value")
    $hash = [Security.Cryptography.SHA1]::Create().ComputeHash($bytes)
    $hex = -join ($hash | ForEach-Object { $_.ToString('x2') })
    return $hex
}

function Invoke-CachedCommand {
    param(
        [string]$Key,
        [int]$TtlSeconds,
        [string]$Directory,
        [scriptblock]$Command
    )

    New-Item -ItemType Directory -Force $cacheDir | Out-Null
    $file = Join-Path $cacheDir $Key

    if (Test-Path $file) {
        $age = (Get-Date) - (Get-Item $file).LastWriteTime
        if ($age.TotalSeconds -lt $TtlSeconds) {
            return Get-Content -Raw $file
        }
    }

    $previousDirectory = (Get-Location).Path
    try {
        Set-Location $Directory
        # Drop ai-engineering-fluency progress lines ("Processing: N/M files")
        # so the truncation that follows keeps the actual report.
        $output = (& $Command 2>&1 |
            Where-Object { $_ -notmatch '^Processing: \d+/\d+ files' } |
            Select-Object -First 200 |
            Out-String).Trim()
    } catch {
        $output = ''
    } finally {
        Set-Location $previousDirectory
    }

    Set-Content -Path $file -Value $output -NoNewline
    return $output
}

function Count-Tasks {
    param(
        [string]$TasksFile,
        [string]$Label
    )

    if (-not (Test-Path $TasksFile)) {
        return $null
    }

    $lines = Get-Content $TasksFile
    $total = @($lines | Where-Object { $_ -match '^\s*- \[[ xX]\]' }).Count
    $done = @($lines | Where-Object { $_ -match '^\s*- \[[xX]\]' }).Count

    if ($total -gt 0) {
        return "$Label`: $done/$total tasks"
    }

    return $null
}

function Get-LatestChildDirectory {
    param([string]$Parent)

    if (-not (Test-Path $Parent)) {
        return $null
    }

    $directory = Get-ChildItem -Path $Parent -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if ($null -eq $directory) {
        return $null
    }

    return $directory.FullName
}

function Get-ProjectDirectory {
    param([object]$Status)

    $projectDirectory = (Get-Location).Path
    if ($null -eq $Status) {
        return $projectDirectory
    }

    foreach ($name in @('cwd', 'currentWorkingDirectory', 'workingDirectory', 'workspaceRoot')) {
        $candidate = Get-PropertyValue $Status $name
        if ($candidate -is [string] -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    foreach ($name in @('workspaceFolder', 'workspaceFolders', 'workspace_folders')) {
        $candidate = Get-PropertyValue $Status $name
        if ($candidate -is [array]) {
            $candidate = $candidate[0]
        }
        if ($candidate -is [string] -and (Test-Path $candidate)) {
            return $candidate
        }
        $path = Get-PropertyValue $candidate 'path'
        if ($path -is [string] -and (Test-Path $path)) {
            return $path
        }
        $uri = Get-PropertyValue $candidate 'uri'
        if ($uri -is [string] -and (Test-Path $uri)) {
            return $uri
        }
    }

    return $projectDirectory
}

function Get-RefreshStatus {
    return "↻ $(Get-Date -Format 'HH:mm:ss')"
}

function Get-AzureStatus {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        return $null
    }

    $output = Invoke-CachedCommand 'azure-account-v3' 60 $HOME {
        az account show --query 'user.name' -o tsv
    }
    $user = ($output -split "`r?`n" | Select-Object -First 1).Trim()

    if ([string]::IsNullOrWhiteSpace($user)) {
        return $null
    }

    if ($user -match '@') {
        $user = '@' + ($user -split '@', 2)[1]
    }

    return "az: $(Short-Text $user 32)"
}

function Get-GitHubStatus {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        return $null
    }

    $output = Invoke-CachedCommand 'github-auth' 60 $HOME {
        gh auth status
    }

    $account = $null
    foreach ($line in ($output -split "`r?`n")) {
        if ($line -match 'Logged in to github\.com account ([^\s]+)') {
            $account = $Matches[1]
        }
        if ($line -match 'Active account: true' -and -not [string]::IsNullOrWhiteSpace($account)) {
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($account)) {
        return $null
    }

    return "gh: $account"
}

function Get-TokenUsageStatus {
    if (-not (Get-Command ai-engineering-fluency -ErrorAction SilentlyContinue)) {
        return $null
    }

    $output = Invoke-CachedCommand 'ai-fluency-usage-v1' 1800 $HOME {
        ai-engineering-fluency usage
    }

    $inLast30Days = $false
    foreach ($line in ($output -split "`r?`n")) {
        if ($line -match 'Last 30 Days') {
            $inLast30Days = $true
            continue
        }
        if ($inLast30Days -and $line -match 'Total tokens:\s+(\S+)') {
            return "tokens<30d: $($Matches[1])"
        }
    }

    return $null
}

function Get-AgentIdentifier {
    param([object]$Object)

    foreach ($name in @('agent_id', 'agentId', 'id', 'name', 'title', 'description', 'agent_type', 'agentType')) {
        $value = Get-PropertyValue $Object $name
        if ($value -is [string] -and -not [string]::IsNullOrWhiteSpace($value)) {
            return Short-Text $value 40
        }
    }

    return 'agent'
}

function Find-AgentObjects {
    param(
        [object]$Node,
        [string]$Path = ''
    )

    $results = @()
    if ($null -eq $Node) {
        return $results
    }

    if ($Node -is [array]) {
        for ($index = 0; $index -lt $Node.Count; $index++) {
            $results += Find-AgentObjects $Node[$index] "$Path.$index"
        }
        return $results
    }

    if ($Node -is [pscustomobject]) {
        $propertyNames = @($Node.PSObject.Properties.Name)
        $typeValue = @(@('type', 'kind', 'category') | ForEach-Object { Get-PropertyValue $Node $_ }) -join ' '
        $agentProperties = @(@('agent_id', 'agentId', 'agent_type', 'agentType') | Where-Object { $propertyNames -contains $_ })
        $looksLikeAgent = $agentProperties.Count -gt 0 -or
            $typeValue -match 'agent|subagent|sidekick' -or
            $Path -match 'agent|subagent|sidekick'

        $state = Get-PropertyValue $Node 'status'
        if ($null -eq $state) {
            $state = Get-PropertyValue $Node 'state'
        }
        if ($null -eq $state) {
            $state = Get-PropertyValue $Node 'phase'
        }
        if ($null -eq $state) {
            $state = 'active'
        }

        if ($looksLikeAgent -and "$state".ToLowerInvariant() -match 'running|starting|pending|queued|in[_ -]?progress|spawning|active') {
            $results += Get-AgentIdentifier $Node
        }

        foreach ($property in $Node.PSObject.Properties) {
            $childPath = if ([string]::IsNullOrWhiteSpace($Path)) { $property.Name } else { "$Path.$($property.Name)" }
            $results += Find-AgentObjects $property.Value $childPath
        }
    }

    return $results
}

function Get-SubtaskStatus {
    param([object]$Status)

    if ($null -eq $Status) {
        return $null
    }

    $agents = @(Find-AgentObjects $Status | Sort-Object -Unique)
    if ($agents.Count -eq 0) {
        return $null
    }
    if ($agents.Count -eq 1) {
        return 'subtasks: 1 running'
    }

    return "subtasks: $($agents.Count) running"
}

function Get-SquadStatus {
    param([string]$ProjectDirectory)

    $root = Find-Up $ProjectDirectory '.squad'
    if ([string]::IsNullOrWhiteSpace($root)) {
        $root = Find-Up $ProjectDirectory '.ai-team'
    }
    if ([string]::IsNullOrWhiteSpace($root)) {
        return $null
    }

    return 'squad'
}

function Get-OpenSpecStatus {
    param([string]$ProjectDirectory)

    $root = Find-Up $ProjectDirectory 'openspec'
    if ([string]::IsNullOrWhiteSpace($root)) {
        $root = Find-Up $ProjectDirectory '.openspec'
    }
    if ([string]::IsNullOrWhiteSpace($root)) {
        return $null
    }

    if (-not (Get-Command openspec -ErrorAction SilentlyContinue)) {
        return 'openspec: enabled'
    }

    try {
        Push-Location $root
        $json = openspec list --json 2>$null
    } catch {
        $json = $null
    } finally {
        Pop-Location
    }

    if ([string]::IsNullOrWhiteSpace($json)) {
        return 'openspec: enabled'
    }

    try {
        $data = $json | ConvertFrom-Json -Depth 32
        $changes = @($data.changes | Where-Object { $_.status -ne 'archived' })
        if ($changes.Count -eq 0) {
            return 'openspec: 0 changes'
        }

        $summaries = @()
        foreach ($change in ($changes | Select-Object -First 3)) {
            $name = $change.name
            if ([string]::IsNullOrWhiteSpace($name)) {
                $name = $change.id
            }
            if ([string]::IsNullOrWhiteSpace($name)) {
                $name = 'change'
            }
            $total = 0
            if ($null -ne $change.totalTasks) {
                $total = [int]$change.totalTasks
            }
            $done = 0
            if ($null -ne $change.completedTasks) {
                $done = [int]$change.completedTasks
            }
            $percent = if ($total -le 0) { 0 } else { [math]::Floor($done * 100 / $total) }
            $summaries += "$(Short-Text $name 16) $percent%"
        }

        $extra = if ($changes.Count -gt 3) { " +$($changes.Count - 3)" } else { '' }
        return "openspec: $($summaries -join ', ')$extra"
    } catch {
        return 'openspec: enabled'
    }
}

function Get-SpecKitStatus {
    param([string]$ProjectDirectory)

    $root = $null
    $directory = $ProjectDirectory

    while (-not [string]::IsNullOrWhiteSpace($directory)) {
        $specsDirectory = Join-Path $directory 'specs'
        $hasSpecFiles = $false
        if (Test-Path $specsDirectory) {
            $hasSpecFiles = $null -ne (Get-ChildItem -Path $specsDirectory -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -in @('spec.md', 'plan.md', 'tasks.md') } |
                Select-Object -First 1)
        }

        if ((Test-Path (Join-Path $directory '.specify')) -or $hasSpecFiles) {
            $root = $directory
            break
        }

        $parent = Split-Path -Parent $directory
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $directory) {
            break
        }
        $directory = $parent
    }

    if ([string]::IsNullOrWhiteSpace($root)) {
        return $null
    }

    $featureDirectory = Get-LatestChildDirectory (Join-Path $root 'specs')
    if (-not [string]::IsNullOrWhiteSpace($featureDirectory)) {
        $taskStatus = Count-Tasks (Join-Path $featureDirectory 'tasks.md') 'spec-kit'
        if (-not [string]::IsNullOrWhiteSpace($taskStatus)) {
            return $taskStatus
        }

        if (Test-Path (Join-Path $featureDirectory 'plan.md')) {
            return 'spec-kit: plan'
        }

        if (Test-Path (Join-Path $featureDirectory 'spec.md')) {
            return 'spec-kit: spec'
        }
    }

    return 'spec-kit: active'
}

function Get-ColimaStatus {
    if (-not (Get-Command colima -ErrorAction SilentlyContinue)) {
        return $null
    }

    $output = Invoke-CachedCommand 'colima-list-v1' 30 $HOME {
        colima list -j
    }

    $lines = @($output -split "`r?`n" | Where-Object { $_ -match '^\{' })
    $total = $lines.Count
    if ($total -le 0) {
        return $null
    }

    $running = @($lines | Where-Object { $_ -match '"status":"Running"' }).Count
    return "colima: $running/$total"
}

$statusObject = $null
if (-not [string]::IsNullOrWhiteSpace($statusJson)) {
    try {
        $statusObject = $statusJson | ConvertFrom-Json -Depth 32
    } catch {
        $statusObject = $null
    }
}

$projectDirectory = Get-ProjectDirectory $statusObject

Join-Segments @(
    Paint $colors.Handy $handyHint
    Paint $colors.Refresh (Get-RefreshStatus)
    Paint $colors.Azure (Get-AzureStatus)
    Paint $colors.GitHub (Get-GitHubStatus)
    Paint $colors.Tokens (Get-TokenUsageStatus)
    Paint $colors.Agents (Get-SubtaskStatus $statusObject)
    Paint $colors.Squad (Get-SquadStatus $projectDirectory)
    Paint $colors.OpenSpec (Get-OpenSpecStatus $projectDirectory)
    Paint $colors.SpecKit (Get-SpecKitStatus $projectDirectory)
    Paint $colors.Colima (Get-ColimaStatus)
)
