param(
    [Parameter(Mandatory)] [string]$Root,
    [Parameter(Mandatory)]
    # `select-frontier` is what moves work forward after a cell closes. Without it the tool
    # could close a cell and never open the next one: `Get-WorkResume` reported
    # `frontier_transition` as the next action and nothing here could perform it, so a project
    # that finished a cell had no supported way to start another. Initialize-WorkScopeProject
    # is not the escape hatch -- it throws on existing state.
    # `amend-discovery` is the correcting entry. Capture and disposition were the only two
    # writers, so a finding whose facts decayed could only be closed and recaptured under a new
    # id, and a *closed* item could not be touched at all -- disposition refuses the status it
    # already holds. A wrong fact in a closure reason was therefore permanent, and the correction
    # ended up recorded outside the state file. It never changes status, so retirement keeps one
    # owner.
    [ValidateSet('add-task', 'complete-task', 'retire-task', 'close-cell', 'block-cell', 'select-frontier', 'set-ownership', 'transfer-ownership', 'retire-discovery', 'amend-discovery')]
    [string]$Action,
    [string]$TaskId,
    [string]$DiscoveryId,
    [ValidateSet('ready', 'blocked', 'closed', 'rejected')] [string]$DiscoveryStatus,
    # retire-discovery -DiscoveryStatus blocked: what the item waits on. A prerequisite id,
    # or an open decision id from the owning project's Open Decisions document. Required
    # when blocking, because Reason reaches only the event log and Test-TaskStateFormat.ps1
    # grades the item.
    [string[]]$Blockers = @(),
    [string]$Reason,
    [string]$Title,
    # amend-discovery only. Named apart from the discovery's own vocabulary because -Value and
    # -Risk would read as generic on a tool that also writes tasks, checks and ownership.
    [ValidateSet('low', 'medium', 'high')] [string]$DiscoveryValue,
    [ValidateSet('low', 'medium', 'high')] [string]$DiscoveryRisk,
    [string]$Acceptance,
    [string[]]$Dependencies = @(),
    [string]$CheckId,
    [ValidateSet('test', 'command')] [string]$CheckVerifier,
    [string]$CheckExecutable,
    [string[]]$CheckArguments = @(),
    [string[]]$CheckInputs = @(),
    [string[]]$CheckArtifacts = @(),
    # 4 hours; see the note on the matching parameter in WorkScope.psm1. Change both together.
    [ValidateRange(1, 14400)] [int]$CheckTimeoutSeconds = 300,
    [ValidateRange(64, 10485760)] [int64]$CheckMaxOutputBytes = 1048576,
    [string[]]$Evidence = @(),
    [string]$SessionId,
    [string[]]$Artifacts = @(),
    [string]$Artifact,
    [string]$FromSession,
    [string]$ToSession,
    [switch]$Confirmed
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'WorkScope.psm1') -Force

# See Expand-WorkScopePackedArgument in WorkScope.psm1 for why this is needed.
$Dependencies   = Expand-WorkScopePackedArgument $Dependencies
$CheckArguments = Expand-WorkScopePackedArgument $CheckArguments
$CheckInputs    = Expand-WorkScopePackedArgument $CheckInputs
$CheckArtifacts = Expand-WorkScopePackedArgument $CheckArtifacts
$Evidence       = Expand-WorkScopePackedArgument $Evidence
$Artifacts      = Expand-WorkScopePackedArgument $Artifacts

$result = switch ($Action) {
    'add-task' {
        if (-not $TaskId -or -not $Title -or -not $Acceptance -or
            -not $CheckId -or -not $CheckVerifier -or -not $CheckExecutable) {
            throw 'add-task requires TaskId, Title, Acceptance, CheckId, CheckVerifier, and CheckExecutable.'
        }
        Add-WorkScopeTask -Root $Root -TaskId $TaskId -Title $Title -Acceptance $Acceptance `
            -Dependencies $Dependencies -CheckId $CheckId -CheckVerifier $CheckVerifier `
            -CheckExecutable $CheckExecutable -CheckArguments $CheckArguments `
            -CheckInputs $CheckInputs -CheckArtifacts $CheckArtifacts `
            -CheckTimeoutSeconds $CheckTimeoutSeconds `
            -CheckMaxOutputBytes $CheckMaxOutputBytes
    }
    'complete-task' {
        if (-not $TaskId) {
            throw 'complete-task requires TaskId.'
        }
        Complete-WorkScopeTask -Root $Root -TaskId $TaskId -Evidence $Evidence
    }
    'retire-task' {
        if (-not $TaskId) {
            throw 'retire-task requires TaskId.'
        }
        if (-not $Reason) {
            throw 'retire-task requires Reason.'
        }
        Set-WorkScopeTaskRetired -Root $Root -TaskId $TaskId -Reason $Reason
    }
    'close-cell' {
        Close-WorkScopeCell -Root $Root -Evidence $Evidence
    }
    'block-cell' {
        if (-not $Reason -or -not $Blockers) {
            throw 'block-cell requires Reason and Blockers.'
        }
        Block-WorkScopeCell -Root $Root -Reason $Reason -Blockers $Blockers
    }
    'select-frontier' {
        Select-WorkScopeFrontier -Root $Root
    }
    'retire-discovery' {
        if (-not $DiscoveryId -or -not $DiscoveryStatus -or -not $Reason) {
            throw 'retire-discovery requires DiscoveryId, DiscoveryStatus, and Reason.'
        }
        Set-WorkScopeDiscoveryStatus -Root $Root -Id $DiscoveryId -Status $DiscoveryStatus -Reason $Reason -Evidence $Evidence -Blockers $Blockers
    }
    'amend-discovery' {
        # Evidence is checked here rather than only downstream: it is Mandatory on
        # Add-WorkScopeDiscoveryCorrection, so omitting it produced a parameter-binding error
        # naming a function the caller never invoked, under a guard whose message listed the two
        # arguments that were already present.
        if (-not $DiscoveryId -or -not $Reason -or -not $Evidence) {
            throw 'amend-discovery requires DiscoveryId, Reason and Evidence.'
        }
        $amendArguments = @{ Root = $Root; Id = $DiscoveryId; Reason = $Reason; Evidence = $Evidence }
        # Bound-parameter presence is the signal, not emptiness: passing -Title '' must be an
        # error rather than a silent no-op, and omitting it must leave the field alone.
        if ($PSBoundParameters.ContainsKey('Title')) { $amendArguments['Title'] = $Title }
        if ($PSBoundParameters.ContainsKey('DiscoveryValue')) { $amendArguments['Value'] = $DiscoveryValue }
        if ($PSBoundParameters.ContainsKey('DiscoveryRisk')) { $amendArguments['Risk'] = $DiscoveryRisk }
        Add-WorkScopeDiscoveryCorrection @amendArguments
    }
    'set-ownership' {
        if (-not $SessionId) {
            throw 'set-ownership requires SessionId.'
        }
        Set-WorkScopeOwnership -Root $Root -SessionId $SessionId -Artifacts $Artifacts
    }
    'transfer-ownership' {
        if (-not $Artifact -or -not $FromSession -or -not $ToSession) {
            throw 'transfer-ownership requires Artifact, FromSession, and ToSession.'
        }
        Move-WorkScopeOwnership -Root $Root -Artifact $Artifact -FromSession $FromSession -ToSession $ToSession -Confirmed:$Confirmed
    }
}
$result | ConvertTo-Json -Depth 30
