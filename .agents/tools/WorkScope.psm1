Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Depths = @('D0', 'D1', 'D2', 'D3', 'D4', 'D5')
$script:DepthNames = @{
    D0 = 'Explore'
    D1 = 'Direct'
    D2 = 'Complete'
    D3 = 'Hardened'
    D4 = 'Reusable'
    D5 = 'Rollout'
}
$script:EvidencePattern = '^verifier=(?<verifier>test|command|inspection|artifact|source); subject=(?<subject>[^;]+); result=(?<result>pass|verified); reference=(?<reference>.+)$'
$script:HeldWorkScopeLocks = @{}

function Expand-WorkScopePackedArgument {
    <#
        `pwsh -File` passes every argument as a literal string, so an array
        parameter written the natural way -- -Evidence 'a','b' -- either arrives
        as ONE element still carrying its quotes and commas, or splits and dies
        as a stray positional argument. Observed 2026-08-06 in two tools: an
        ownership claim recorded "'tools/x.ps1','docs/y.md'" into state.json as a
        single junk artifact path that no guarded action can remove, and a
        discovery capture failed with "A positional parameter cannot be found".

        Only the unambiguous mangled shape is unpacked: one element that is a
        comma-separated list of QUOTED items. A real path is never quoted, so a
        genuine path containing a comma is left untouched.
    #>
    param([string[]]$Value)

    if ($null -eq $Value -or $Value.Count -ne 1) { return $Value }
    $only = $Value[0]
    if ($only -notmatch "^\s*['`"][^'`"]*['`"]\s*(,\s*['`"][^'`"]*['`"]\s*)+$") { return $Value }

    return @($only -split ',' | ForEach-Object { $_.Trim().Trim("'").Trim('"') } | Where-Object { $_ })
}

function ConvertTo-WorkScopeCanonicalValue {
    param($Value)
    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
            $ordered[$key] = ConvertTo-WorkScopeCanonicalValue -Value $Value[$key]
        }
        return $ordered
    }
    if ($Value -is [pscustomobject]) {
        $ordered = [ordered]@{}
        foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) {
            $ordered[$property.Name] = ConvertTo-WorkScopeCanonicalValue -Value $property.Value
        }
        return $ordered
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = @($Value | ForEach-Object { ConvertTo-WorkScopeCanonicalValue -Value $_ })
        return ,$items
    }
    return $Value
}

function Get-WorkScopeEventHash {
    param([Parameter(Mandatory)] [System.Collections.IDictionary]$Event)
    $Event = $Event |
        ConvertTo-Json -Depth 30 -Compress |
        ConvertFrom-Json -AsHashtable
    $canonical = [ordered]@{
        event_id = $Event.event_id
        previous_event_id = $Event.previous_event_id
        previous_event_hash = $Event.previous_event_hash
        state_revision = [int64]$Event.state_revision
        occurred_at = $Event.occurred_at
        type = $Event.type
        project_id = $Event.project_id
        track_id = $Event.track_id
        capability_id = $Event.capability_id
        cell_id = $Event.cell_id
        evidence = @($Event.evidence)
        data = $Event.data
    }
    $canonical = ConvertTo-WorkScopeCanonicalValue -Value $canonical
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($canonical | ConvertTo-Json -Depth 30 -Compress))
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Assert-SafeWorkScopeId {
    param(
        [Parameter(Mandatory)] [string]$Id,
        [string]$Label = 'Identifier'
    )
    if ($Id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' -or $Id -in @('.', '..')) {
        throw "$Label '$Id' is not a safe identifier. Use 1-128 letters, digits, dots, underscores, or hyphens with no path separators."
    }
}

function Get-WorkScopeStringArrayHash {
    param([string[]]$Values = @())
    $json = ConvertTo-Json -InputObject @($Values) -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

# Verification must run a native program image, never an interpreted wrapper whose
# meaning depends on a shell. On Windows that is exactly a `.exe`: `.cmd` and `.bat`
# are re-parsed by cmd.exe and would let argument metacharacters execute. POSIX has
# no such extension convention, so the same guarantee is expressed structurally --
# no interpreted-script extension, and no `#!` shebang in the program image itself.
$script:WorkScopeInterpretedExtensions = @(
    '.cmd', '.bat', '.com', '.ps1', '.psm1', '.sh', '.bash', '.zsh', '.ksh',
    '.py', '.rb', '.pl', '.php', '.js', '.mjs', '.cjs', '.vbs', '.jse', '.wsf', '.wsh'
)

function Test-WorkScopeWindowsShapedPath {
    param([Parameter(Mandatory)] [string]$Path)
    return ($Path -match '^[A-Za-z]:[\\/]' -or $Path -match '^\\\\')
}

function Assert-WorkScopeNativeExecutableShape {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [string]$Context = 'Verification executable'
    )
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if (Test-WorkScopeWindowsShapedPath -Path $Path) {
        if ($extension -ne '.exe') {
            throw "$Context '$Path' is not a native .exe. Batch files and shell scripts are rejected; invoke a fixed script through an explicitly declared native interpreter such as pwsh.exe."
        }
        return
    }
    if ($extension -in $script:WorkScopeInterpretedExtensions) {
        throw "$Context '$Path' is an interpreted script, not a native program image. Invoke a fixed script through an explicitly declared native interpreter such as pwsh."
    }
}

function Resolve-WorkScopeNativeExecutable {
    param([Parameter(Mandatory)] [string]$Executable)
    $command = Get-Command $Executable -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $source = [System.IO.Path]::GetFullPath([string]$command.Source)
    Assert-WorkScopeNativeExecutableShape -Path $source
    # The shape rule is a string test that also holds for state authored elsewhere.
    # When the image is present we additionally prove it is not a shebang wrapper.
    # The declaration-time SHA-256 binding makes this durable: the runner rehashes
    # the image before every execution, so a later swap to a script cannot pass.
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        $prefix = [byte[]]::new(2)
        $stream = [System.IO.File]::OpenRead($source)
        try { $read = $stream.Read($prefix, 0, 2) } finally { $stream.Dispose() }
        if ($read -eq 2 -and $prefix[0] -eq 0x23 -and $prefix[1] -eq 0x21) {
            throw "Verification executable '$source' begins with a '#!' shebang and is an interpreter script, not a native program image."
        }
    }
    return $source
}

function Test-WorkScopeDeclaredInterpreter {
    param([Parameter(Mandatory)] [string]$Path)
    $name = [System.IO.Path]::GetFileName($Path)
    if (Test-WorkScopeWindowsShapedPath -Path $Path) {
        return ($name -in @('pwsh.exe', 'powershell.exe'))
    }
    return ($name -in @('pwsh', 'powershell', 'pwsh.exe', 'powershell.exe'))
}

if ($null -eq ('WorkScope.NativeProcessRunner' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace WorkScope
{
    public sealed class NativeProcessResult
    {
        public int ExitCode { get; set; }
        public bool TimedOut { get; set; }
        public bool OutputLimitExceeded { get; set; }
        public long OutputSizeBytes { get; set; }
        public string OutputSha256 { get; set; }
    }

    internal sealed class OutputCounter
    {
        public long Total;
        public long Limit;
        public int Exceeded;
    }

    internal sealed class StreamDigest
    {
        public long Size;
        public string Hash;
    }

    public static class NativeProcessRunner
    {
        private static void KillTree(Process process)
        {
            try
            {
                if (!process.HasExited)
                    process.Kill(true);
            }
            catch { }
        }

        private static async Task<StreamDigest> DigestStream(
            Stream stream,
            Process process,
            OutputCounter counter)
        {
            using (var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256))
            {
                var buffer = new byte[8192];
                long size = 0;
                try
                {
                    while (true)
                    {
                        int count = await stream.ReadAsync(buffer, 0, buffer.Length).ConfigureAwait(false);
                        if (count <= 0)
                            break;
                        size += count;
                        hash.AppendData(buffer, 0, count);
                        long total = Interlocked.Add(ref counter.Total, count);
                        if (total > counter.Limit &&
                            Interlocked.Exchange(ref counter.Exceeded, 1) == 0)
                        {
                            KillTree(process);
                        }
                    }
                }
                catch (IOException) { }
                catch (ObjectDisposedException) { }

                return new StreamDigest
                {
                    Size = size,
                    Hash = Convert.ToHexString(hash.GetHashAndReset()).ToLowerInvariant()
                };
            }
        }

        public static NativeProcessResult Run(
            string executable,
            IEnumerable<string> arguments,
            string workingDirectory,
            int timeoutMilliseconds,
            long maxOutputBytes)
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = executable,
                WorkingDirectory = workingDirectory,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            foreach (string argument in arguments)
                startInfo.ArgumentList.Add(argument);

            using (var process = new Process { StartInfo = startInfo })
            {
                if (!process.Start())
                    throw new InvalidOperationException("The verification process did not start.");

                var counter = new OutputCounter { Limit = maxOutputBytes };
                Task<StreamDigest> stdout = DigestStream(process.StandardOutput.BaseStream, process, counter);
                Task<StreamDigest> stderr = DigestStream(process.StandardError.BaseStream, process, counter);
                bool completed = process.WaitForExit(timeoutMilliseconds);
                if (!completed)
                    KillTree(process);
                process.WaitForExit();
                Task.WaitAll(stdout, stderr);

                StreamDigest outDigest = stdout.Result;
                StreamDigest errDigest = stderr.Result;
                string combined = outDigest.Hash + ":" + outDigest.Size + "\n" +
                                  errDigest.Hash + ":" + errDigest.Size;
                byte[] combinedBytes = Encoding.UTF8.GetBytes(combined);
                string combinedHash = Convert.ToHexString(
                    SHA256.HashData(combinedBytes)).ToLowerInvariant();

                return new NativeProcessResult
                {
                    ExitCode = completed && counter.Exceeded == 0 ? process.ExitCode : -1,
                    TimedOut = !completed,
                    OutputLimitExceeded = counter.Exceeded != 0,
                    OutputSizeBytes = counter.Total,
                    OutputSha256 = combinedHash
                };
            }
        }
    }
}
'@
}

function Test-StructuredEvidence {
    param(
        $Evidence,
        [string]$Root,
        [switch]$RequireProvenance,
        # Set when re-reading a receipt that belongs to something already terminal -- a closed
        # cell, a closed task -- rather than when accepting one at closure time. It skips the
        # re-hash of the files the stored execution record NAMES, and nothing else: the record's
        # own hash, the provenance event, and every field cross-check still hold, so a tampered
        # or mismatched receipt is caught exactly as before. See the note at that re-hash for why
        # the distinction is the whole fix.
        [switch]$Historical,
        # Used only by the explicit retire-task recovery path after Douglas approves
        # superseding a closed result artifact. Receipt bytes, provenance, event binding,
        # schema, and every unrelated error remain mandatory; only live result-artifact
        # snapshots are omitted from this one classification pass.
        [switch]$RetirementArtifactDrift
    )
    if ($RetirementArtifactDrift -and -not $Historical) {
        return $false
    }
    $items = @(ConvertTo-NormalizedArray $Evidence)
    if ($items.Count -eq 0) {
        return $false
    }
    foreach ($item in $items) {
        if ($item -isnot [System.Collections.IDictionary]) {
            return $false
        }
        $requiredFields = @('receipt_id', 'verifier', 'subject', 'result', 'reference', 'sha256', 'size_bytes', 'captured_at')
        if ($RequireProvenance) {
            $requiredFields += @(
                'check_id',
                'exit_code',
                'provenance_event_id',
                'project_id',
                'track_id',
                'capability_id',
                'cell_id',
                'task_id'
            )
        }
        foreach ($required in $requiredFields) {
            if (-not $item.Contains($required)) {
                return $false
            }
        }
        if ($item.receipt_id -notmatch '^[A-Fa-f0-9-]{36}$' -or
            $item.verifier -notin @('test', 'command', 'inspection', 'artifact', 'source') -or
            [string]::IsNullOrWhiteSpace([string]$item.subject) -or
            $item.result -notin @('pass', 'verified') -or
            $item.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
            [int64]$item.size_bytes -lt 0 -or
            [string]::IsNullOrWhiteSpace([string]$item.captured_at)) {
            return $false
        }
        if (-not [string]::IsNullOrWhiteSpace($Root)) {
            try {
                $relativeReference = Resolve-WorkScopeArtifact -Root $Root -Artifact ([string]$item.reference)
            }
            catch {
                return $false
            }
            $referencePath = Join-Path $Root $relativeReference
            # Closure evidence is a proof, so it is pinned to the exact bytes it was
            # taken against and drift invalidates it. Discovery evidence is only
            # provenance -- where the item was noticed -- and pinning it to a hash
            # meant that editing any living document a discovery had cited turned the
            # whole state invalid, which in turn blocked every unrelated closure in
            # the project.
            #
            # Requiring the file to still EXIST was the same bug's other half, and it
            # bit on 2026-08-08 in exactly the way the paragraph above predicts. An
            # authorized consolidation deleted `commands/permcheck.md`, which one
            # discovery receipt cited as where it was noticed. That single deletion
            # made the whole state invalid, and because every mutation validates
            # first, it blocked EVERY write to the queue from every platform at once
            # -- the queue could not even record the defect that was blocking it.
            # A discovery is a claim about the past. Deleting the file it was noticed
            # in does not make it false, and the deletion is usually the correct act.
            # So existence is now required only where the receipt is load-bearing:
            # closure proof. `Resolve-WorkScopeArtifact` above still rejects a
            # traversal or non-project-local path for both kinds, so a malformed
            # reference is still caught here rather than being written.
            if ($RequireProvenance) {
                if (-not (Test-Path -LiteralPath $referencePath -PathType Leaf)) {
                    return $false
                }
                $referenceItem = Get-Item -LiteralPath $referencePath -Force
                $actualHash = (Get-FileHash -LiteralPath $referencePath -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($actualHash -ne ([string]$item.sha256).ToLowerInvariant() -or
                    [int64]$referenceItem.Length -ne [int64]$item.size_bytes) {
                    return $false
                }
            }
            if ($RequireProvenance) {
                if ([int64]$item.exit_code -ne 0 -or
                    [string]::IsNullOrWhiteSpace([string]$item.check_id) -or
                    [string]::IsNullOrWhiteSpace([string]$item.provenance_event_id)) {
                    return $false
                }
                try {
                    $record = Get-Content -LiteralPath $referencePath -Raw | ConvertFrom-Json -AsHashtable
                    $eventsPath = Join-Path $Root '.agents\work\events.jsonl'
                    $provenanceEvent = Get-Content -LiteralPath $eventsPath |
                        Where-Object { $_ } |
                        ForEach-Object { $_ | ConvertFrom-Json -AsHashtable } |
                        Where-Object { $_.event_id -eq $item.provenance_event_id -and $_.type -eq 'verification_executed' } |
                        Select-Object -First 1
                }
                catch {
                    return $false
                }
                if ($null -eq $provenanceEvent -or
                    $record.receipt_id -ne $item.receipt_id -or
                    $record.check_id -ne $item.check_id -or
                    $record.verifier -ne $item.verifier -or
                    $record.subject -ne $item.subject -or
                    $record.project_id -ne $item.project_id -or
                    $record.track_id -ne $item.track_id -or
                    $record.capability_id -ne $item.capability_id -or
                    $record.cell_id -ne $item.cell_id -or
                    $record.task_id -ne $item.task_id -or
                    $record.result -ne $item.result -or
                    [int64]$record.exit_code -ne 0 -or
                    $provenanceEvent.data.receipt_id -ne $item.receipt_id -or
                    $provenanceEvent.data.check_id -ne $item.check_id -or
                    $provenanceEvent.data.task_id -ne $item.task_id -or
                    $provenanceEvent.track_id -ne $item.track_id -or
                    $provenanceEvent.capability_id -ne $item.capability_id -or
                    $provenanceEvent.cell_id -ne $item.cell_id -or
                    $provenanceEvent.data.reference -ne $item.reference -or
                    $provenanceEvent.data.sha256 -ne $item.sha256 -or
                    [int64]$provenanceEvent.data.exit_code -ne 0) {
                    return $false
                }
                # A stored record names two different kinds of file and they do not deserve the
                # same treatment once the task is terminal.
                #
                # An ARTIFACT is the proof itself -- the output the check produced. If it changes
                # after closure the evidence no longer shows what it claims to show, so drift
                # there stays an error forever. That is a deliberate, tested contract and this
                # does not touch it.
                #
                # A VERIFIER INPUT is the tooling the check RAN: the script, its manifest. Editing
                # it later does not falsify that the check passed when it ran; it only means the
                # result would need re-taking. Enforcing it against the live tree made every file
                # ever named by any closed check permanently uneditable, because state validation
                # fails closed and every mutation validates first -- so the edit invalidated the
                # whole state and blocked even the retire that would have released the binding.
                # Hit on 2026-08-10 by two ordinary edits to Run-ToolTests.ps1 and its policy
                # manifest, both of which were FIXING a defect, with no repair available from
                # Reconcile-WorkState in either direction. The recorded hash is kept either way,
                # so what the check ran against is still readable off the receipt.
                # A file may be declared in both lists, and on a terminal task that pair is
                # decisive rather than ambiguous: whatever else it is, it is the tooling this
                # check ran, and naming it an artifact as well does not turn an input into an
                # output. The live case was .agents/manifests/tool-test-policy.json, declared
                # both ways by the task that gated the overnight run -- so releasing inputs
                # alone left the state wedged on the same file through its other name, and the
                # only unwedge would have been reverting the fix the edit was making.
                $snapshotsToVerify = if ($Historical -and $RetirementArtifactDrift) {
                    @()
                } elseif ($Historical) {
                    $inputReferences = @(@($record.verifier_inputs) | ForEach-Object { [string]$_.reference })
                    @(@($record.artifacts) | Where-Object { $inputReferences -notcontains [string]$_.reference })
                } else {
                    @($record.verifier_inputs) + @($record.artifacts)
                }
                foreach ($artifactSnapshot in $snapshotsToVerify) {
                    try {
                        $artifactReference = Resolve-WorkScopeArtifact -Root $Root -Artifact ([string]$artifactSnapshot.reference)
                        $artifactPath = Join-Path $Root $artifactReference
                    }
                    catch {
                        return $false
                    }
                    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
                        return $false
                    }
                    $artifactItem = Get-Item -LiteralPath $artifactPath -Force
                    $artifactHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
                    if ($artifactHash -ne ([string]$artifactSnapshot.sha256).ToLowerInvariant() -or
                        [int64]$artifactItem.Length -ne [int64]$artifactSnapshot.size_bytes) {
                        return $false
                    }
                }
            }
        }
    }
    return $true
}

function ConvertTo-WorkScopeEvidenceReceipts {
    param(
        [Parameter(Mandatory)] $Evidence,
        [Parameter(Mandatory)] [string]$Root,
        [string]$Context = 'Transition'
    )
    $receipts = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @(ConvertTo-NormalizedArray $Evidence)) {
        if ($item -isnot [string]) {
            throw "$Context accepts evidence declarations as strings and stores verified typed receipts."
        }
        $match = [regex]::Match($item, $script:EvidencePattern)
        if (-not $match.Success) {
            throw "$Context requires structured evidence with an existing project-local reference: verifier=<test|command|inspection|artifact|source>; subject=<what>; result=<pass|verified>; reference=<relative artifact path>."
        }
        $relativeReference = Resolve-WorkScopeArtifact -Root $Root -Artifact $match.Groups['reference'].Value
        $referencePath = Join-Path $Root $relativeReference
        if (-not (Test-Path -LiteralPath $referencePath -PathType Leaf)) {
            throw "$Context evidence reference '$relativeReference' must be an existing project-local file."
        }
        $referenceItem = Get-Item -LiteralPath $referencePath -Force
        $receipts.Add([ordered]@{
            receipt_id = [guid]::NewGuid().ToString()
            verifier = $match.Groups['verifier'].Value
            subject = $match.Groups['subject'].Value
            result = $match.Groups['result'].Value
            reference = $relativeReference
            sha256 = (Get-FileHash -LiteralPath $referencePath -Algorithm SHA256).Hash.ToLowerInvariant()
            size_bytes = [int64]$referenceItem.Length
            captured_at = Get-UtcTimestamp
        })
    }
    if ($receipts.Count -eq 0) {
        throw "$Context requires at least one evidence receipt."
    }
    return @($receipts)
}

function Invoke-WorkScopeVerification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [string]$CheckId,
        [Parameter(Mandatory)] [ValidateSet('test', 'command')] [string]$Verifier,
        [Parameter(Mandatory)] [string]$Subject,
        [Parameter(Mandatory)] [string]$Executable,
        [string[]]$Arguments = @(),
        [string[]]$Artifacts = @()
    )
    Assert-SafeWorkScopeId -Id $CheckId -Label 'Verification check id'
    $rootFull = [System.IO.Path]::GetFullPath($Root)
    $executablePath = Resolve-WorkScopeNativeExecutable -Executable $Executable
    $executableHash = (Get-FileHash -LiteralPath $executablePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $argumentsHash = Get-WorkScopeStringArrayHash -Values $Arguments
    $normalizedArtifacts = @(
        @(ConvertTo-NormalizedArray $Artifacts) |
            ForEach-Object { Resolve-WorkScopeArtifact -Root $rootFull -Artifact $_ } |
            Sort-Object -Unique
    )

    $snapshot = Invoke-WithWorkScopeLock -Root $rootFull -Action {
        $validation = Test-WorkScopeState -Root $rootFull
        if (-not $validation.valid) {
            throw "Cannot execute verification against invalid authoritative state: $($validation.errors -join '; ')"
        }
        $state = Read-WorkScopeState -Root $rootFull
        $matches = @(
            foreach ($task in @($state.active.tasks)) {
                foreach ($check in @($task.acceptance_checks)) {
                    if ($check.id -eq $CheckId) {
                        [pscustomobject]@{ task = $task; check = $check }
                    }
                }
            }
        )
        if ($matches.Count -ne 1) {
            throw "Verification check '$CheckId' must identify exactly one declared task acceptance check in the active scope cell."
        }
        $match = $matches[0]
        if ($Subject -ne $match.task.id) {
            throw "Verification subject '$Subject' does not match the declared task '$($match.task.id)'."
        }
        if ($Verifier -ne $match.check.verifier -or
            -not $executablePath.Equals([string]$match.check.executable, [System.StringComparison]::OrdinalIgnoreCase) -or
            $executableHash -ne $match.check.executable_sha256 -or
            ((@($Arguments) | ConvertTo-Json -Compress) -ne (@($match.check.arguments) | ConvertTo-Json -Compress)) -or
            $argumentsHash -ne $match.check.arguments_sha256 -or
            (($normalizedArtifacts | ConvertTo-Json -Compress) -ne (@($match.check.artifacts) | ConvertTo-Json -Compress))) {
            throw "Verification invocation does not match declared acceptance check '$CheckId'."
        }
        return [pscustomobject]@{
            revision = [int64]$state.revision
            last_event_id = $state.last_event_id
            last_event_hash = $state.last_event_hash
            project_id = $state.project.id
            track_id = $state.active.track_id
            capability_id = $state.active.capability_id
            cell_id = $state.active.cell_id
            task_id = $match.task.id
            timeout_seconds = [int]$match.check.timeout_seconds
            max_output_bytes = [int64]$match.check.max_output_bytes
            verifier_inputs = @($match.check.verifier_inputs)
        }
    }

    foreach ($inputSnapshot in @($snapshot.verifier_inputs)) {
        $inputReference = Resolve-WorkScopeArtifact -Root $rootFull -Artifact ([string]$inputSnapshot.reference)
        $inputPath = Join-Path $rootFull $inputReference
        if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
            throw "Declared verification input '$inputReference' is missing."
        }
        $inputItem = Get-Item -LiteralPath $inputPath -Force
        $inputHash = (Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($inputHash -ne $inputSnapshot.sha256 -or
            [int64]$inputItem.Length -ne [int64]$inputSnapshot.size_bytes) {
            throw "Declared verification input '$inputReference' changed after task declaration."
        }
    }

    $startedAt = Get-UtcTimestamp
    try {
        $processResult = [WorkScope.NativeProcessRunner]::Run(
            $executablePath,
            [string[]]$Arguments,
            $rootFull,
            [int]($snapshot.timeout_seconds * 1000),
            [int64]$snapshot.max_output_bytes
        )
    }
    catch {
        $processResult = [pscustomobject]@{
            ExitCode = -1
            TimedOut = $false
            OutputLimitExceeded = $false
            OutputSizeBytes = 0
            OutputSha256 = [Convert]::ToHexString(
                [System.Security.Cryptography.SHA256]::HashData([byte[]]@())
            ).ToLowerInvariant()
        }
    }
    $finishedAt = Get-UtcTimestamp
    $exitCode = [int]$processResult.ExitCode
    $receiptId = [guid]::NewGuid().ToString()
    $artifactSnapshots = @(
        foreach ($relativeArtifact in $normalizedArtifacts) {
            $artifactPath = Join-Path $rootFull $relativeArtifact
            if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
                throw "Verification artifact '$relativeArtifact' must be an existing project-local file."
            }
            $artifactItem = Get-Item -LiteralPath $artifactPath -Force
            [ordered]@{
                reference = $relativeArtifact
                sha256 = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
                size_bytes = [int64]$artifactItem.Length
            }
        }
    )
    $evidenceRoot = Join-Path $rootFull '.agents\work\evidence'
    New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
    $recordPath = Join-Path $evidenceRoot "$receiptId.json"
    $temporaryRecordPath = "$recordPath.$([guid]::NewGuid().ToString('N')).tmp"
    $record = [ordered]@{
        receipt_id = $receiptId
        check_id = $CheckId
        verifier = $Verifier
        subject = $snapshot.task_id
        project_id = $snapshot.project_id
        track_id = $snapshot.track_id
        capability_id = $snapshot.capability_id
        cell_id = $snapshot.cell_id
        task_id = $snapshot.task_id
        result = if ($exitCode -eq 0 -and -not $processResult.TimedOut -and -not $processResult.OutputLimitExceeded) { 'pass' } else { 'fail' }
        executable = [System.IO.Path]::GetFileName($executablePath)
        executable_sha256 = $executableHash
        arguments_sha256 = $argumentsHash
        output_sha256 = [string]$processResult.OutputSha256
        output_size_bytes = [int64]$processResult.OutputSizeBytes
        timed_out = [bool]$processResult.TimedOut
        output_limit_exceeded = [bool]$processResult.OutputLimitExceeded
        timeout_seconds = [int]$snapshot.timeout_seconds
        max_output_bytes = [int64]$snapshot.max_output_bytes
        verifier_inputs = @($snapshot.verifier_inputs)
        artifacts = $artifactSnapshots
        exit_code = $exitCode
        started_at = $startedAt
        finished_at = $finishedAt
    }
    Set-Content -LiteralPath $temporaryRecordPath -Value ($record | ConvertTo-Json -Depth 20) -Encoding utf8NoBOM
    $relativeReference = Resolve-WorkScopeArtifact -Root $rootFull -Artifact ([System.IO.Path]::GetRelativePath($rootFull, $recordPath))
    $recordItem = Get-Item -LiteralPath $temporaryRecordPath -Force
    $recordHash = (Get-FileHash -LiteralPath $temporaryRecordPath -Algorithm SHA256).Hash.ToLowerInvariant()
    try {
        $event = Invoke-WithWorkScopeLock -Root $rootFull -Action {
            $validation = Test-WorkScopeState -Root $rootFull
            if (-not $validation.valid) {
                throw "Verification finished, but authoritative state became invalid before its receipt could be committed: $($validation.errors -join '; ')"
            }
            $state = Read-WorkScopeState -Root $rootFull
            if ([int64]$state.revision -ne $snapshot.revision -or
                $state.last_event_id -ne $snapshot.last_event_id -or
                $state.last_event_hash -ne $snapshot.last_event_hash -or
                $state.active.cell_id -ne $snapshot.cell_id) {
                throw "Verification finished, but work-scope state changed during execution. Run the declared check again."
            }
            return Add-WorkScopeEvent -Root $rootFull -State $state -Type 'verification_executed' -Data @{
                receipt_id = $receiptId
                check_id = $CheckId
                verifier = $Verifier
                result = $record.result
                task_id = $snapshot.task_id
                reference = $relativeReference
                sha256 = $recordHash
                size_bytes = [int64]$recordItem.Length
                exit_code = $exitCode
            } -FileCommit @{
                temporary_path = $temporaryRecordPath
                final_path = $recordPath
                overwrite = $false
            }
        }
    }
    finally {
        $transactionPath = Join-Path $rootFull '.agents\work\transaction.json'
        if ((Test-Path -LiteralPath $temporaryRecordPath) -and
            -not (Test-Path -LiteralPath $transactionPath)) {
            Remove-Item -LiteralPath $temporaryRecordPath -Force
        }
    }
    Sync-WorkScopeViews -Root $rootFull | Out-Null
    return [pscustomobject]@{
        receipt_id = $receiptId
        check_id = $CheckId
        result = $record.result
        exit_code = $exitCode
        reference = $relativeReference
        provenance_event_id = $event.event_id
    }
}

function Resolve-WorkScopeClosureEvidence {
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] $Evidence,
        [string]$Context = 'Closure',
        [switch]$Historical
    )
    $receipts = [System.Collections.Generic.List[object]]::new()
    $seenReceiptIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $eventsPath = Join-Path ([System.IO.Path]::GetFullPath($Root)) '.agents\work\events.jsonl'
    $events = @(
        Get-Content -LiteralPath $eventsPath |
            Where-Object { $_ } |
            ForEach-Object { $_ | ConvertFrom-Json -AsHashtable }
    )
    foreach ($declaration in @(ConvertTo-NormalizedArray $Evidence)) {
        if ($declaration -isnot [string] -or $declaration -notmatch '^receipt=(?<id>[A-Fa-f0-9-]{36})$') {
            throw "$Context accepts only executed verification receipts in the form receipt=<receipt-id>. Run Invoke-WorkScopeEvidence.ps1 first."
        }
        $receiptId = $Matches.id
        if (-not $seenReceiptIds.Add($receiptId)) {
            throw "$Context verification receipt '$receiptId' was supplied more than once."
        }
        $event = $events |
            Where-Object { $_.type -eq 'verification_executed' -and $_.data.receipt_id -eq $receiptId } |
            Select-Object -Last 1
        if ($null -eq $event) {
            throw "$Context verification receipt '$receiptId' has no hashed execution event."
        }
        $reference = Resolve-WorkScopeArtifact -Root $Root -Artifact ([string]$event.data.reference)
        $recordPath = Join-Path $Root $reference
        if (-not (Test-Path -LiteralPath $recordPath -PathType Leaf)) {
            throw "$Context verification receipt '$receiptId' is missing its execution record."
        }
        $recordItem = Get-Item -LiteralPath $recordPath -Force
        $recordHash = (Get-FileHash -LiteralPath $recordPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json -AsHashtable
        if ($recordHash -ne $event.data.sha256 -or
            [int64]$recordItem.Length -ne [int64]$event.data.size_bytes -or
            $record.receipt_id -ne $receiptId -or
            $record.result -ne 'pass' -or
            [int64]$record.exit_code -ne 0 -or
            [int64]$event.data.exit_code -ne 0) {
            throw "$Context verification receipt '$receiptId' is failed, altered, or inconsistent."
        }
        $receipts.Add([ordered]@{
            receipt_id = $receiptId
            check_id = $record.check_id
            verifier = $record.verifier
            subject = $record.subject
            result = $record.result
            reference = $reference
            sha256 = $recordHash
            size_bytes = [int64]$recordItem.Length
            captured_at = $record.finished_at
            exit_code = [int64]$record.exit_code
            provenance_event_id = $event.event_id
            project_id = $record.project_id
            track_id = $record.track_id
            capability_id = $record.capability_id
            cell_id = $record.cell_id
            task_id = $record.task_id
        })
    }
    if ($receipts.Count -eq 0 -or -not (Test-StructuredEvidence -Evidence $receipts -Root $Root -RequireProvenance -Historical:$Historical)) {
        throw "$Context requires at least one valid executed verification receipt."
    }
    return @($receipts)
}

function Assert-WorkScopeTaskReceiptCoverage {
    param(
        [Parameter(Mandatory)] $Task,
        [Parameter(Mandatory)] $Receipts,
        [Parameter(Mandatory)] [hashtable]$State,
        [string]$Context = 'Task completion'
    )
    $declaredCheckIds = @($Task.acceptance_checks | ForEach-Object { $_.id } | Sort-Object)
    $receiptCheckIds = @($Receipts | ForEach-Object { $_.check_id } | Sort-Object)
    if (($declaredCheckIds | ConvertTo-Json -Compress) -ne ($receiptCheckIds | ConvertTo-Json -Compress)) {
        throw "$Context evidence must cover exactly the declared acceptance checks for task '$($Task.id)': $($declaredCheckIds -join ', ')."
    }
    foreach ($receipt in @($Receipts)) {
        if ($receipt.project_id -ne $State.project.id -or
            $receipt.track_id -ne $State.active.track_id -or
            $receipt.capability_id -ne $State.active.capability_id -or
            $receipt.cell_id -ne $State.active.cell_id -or
            $receipt.task_id -ne $Task.id -or
            $receipt.subject -ne $Task.id) {
            throw "$Context receipt '$($receipt.receipt_id)' belongs to a different task or scope cell."
        }
    }
}

function Get-WorkScopePhysicalPath {
    param([Parameter(Mandatory)] [string]$Path)
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
    $current = $pathRoot
    $remainder = $fullPath.Substring($pathRoot.Length)
    foreach ($segment in @($remainder -split '[\\/]' | Where-Object { $_ })) {
        $candidate = Join-Path $current $segment
        if (Test-Path -LiteralPath $candidate) {
            $item = Get-Item -LiteralPath $candidate -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                $target = $item.ResolveLinkTarget($true)
                if ($null -eq $target) {
                    throw "Reparse point '$candidate' cannot be resolved safely."
                }
                $current = [System.IO.Path]::GetFullPath($target.FullName)
                continue
            }
        }
        $current = $candidate
    }
    return [System.IO.Path]::GetFullPath($current).TrimEnd('\', '/')
}

function Resolve-WorkScopeArtifact {
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [string]$Artifact
    )
    if ([string]::IsNullOrWhiteSpace($Artifact) -or [System.IO.Path]::IsPathRooted($Artifact)) {
        throw "Artifact '$Artifact' is outside the project boundary because it is empty or rooted."
    }
    $projectRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $projectPrefix = $projectRoot + [System.IO.Path]::DirectorySeparatorChar
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $Artifact))
    if (-not $candidate.StartsWith($projectPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Artifact '$Artifact' resolves outside the project boundary."
    }
    $relative = [System.IO.Path]::GetRelativePath($projectRoot, $candidate).Replace('\', '/')
    if ($relative -in @('.', '..') -or $relative.StartsWith('../')) {
        throw "Artifact '$Artifact' resolves outside the project boundary."
    }
    $physicalRoot = Get-WorkScopePhysicalPath -Path $projectRoot
    $physicalCandidate = Get-WorkScopePhysicalPath -Path $candidate
    $physicalPrefix = $physicalRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $physicalCandidate.StartsWith($physicalPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Artifact '$Artifact' resolves outside the project boundary through a reparse point."
    }
    return $relative
}

function Test-WorkScopeArtifactOverlap {
    param(
        [Parameter(Mandatory)] [string]$Left,
        [Parameter(Mandatory)] [string]$Right
    )
    $leftNormalized = $Left.TrimEnd('/')
    $rightNormalized = $Right.TrimEnd('/')
    return (
        $leftNormalized.Equals($rightNormalized, [System.StringComparison]::OrdinalIgnoreCase) -or
        $leftNormalized.StartsWith($rightNormalized + '/', [System.StringComparison]::OrdinalIgnoreCase) -or
        $rightNormalized.StartsWith($leftNormalized + '/', [System.StringComparison]::OrdinalIgnoreCase)
    )
}

function Get-WorkScopeLockKey {
    param([Parameter(Mandatory)] [string]$Root)
    return [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/').ToLowerInvariant()
}

function Test-WorkScopeLockHeld {
    param([Parameter(Mandatory)] [string]$Root)
    return $script:HeldWorkScopeLocks.ContainsKey((Get-WorkScopeLockKey -Root $Root))
}

function Copy-WorkScopeBoundParameters {
    param([Parameter(Mandatory)] $BoundParameters)
    $copy = @{}
    foreach ($entry in $BoundParameters.GetEnumerator()) {
        $copy[$entry.Key] = $entry.Value
    }
    return $copy
}

function Invoke-WithWorkScopeLock {
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [scriptblock]$Action,
        [int]$TimeoutMilliseconds = 1000
    )
    $key = Get-WorkScopeLockKey -Root $Root
    if ($script:HeldWorkScopeLocks.ContainsKey($key)) {
        return & $Action
    }
    $paths = Get-WorkScopePaths -Root $Root
    New-Item -ItemType Directory -Path $paths.WorkRoot -Force | Out-Null
    $lockPath = Join-Path $paths.WorkRoot 'state.lock'
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $handle = $null
    while ($null -eq $handle -and $stopwatch.ElapsedMilliseconds -lt $TimeoutMilliseconds) {
        try {
            $handle = [System.IO.File]::Open(
                $lockPath,
                [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None
            )
        }
        catch [System.IO.IOException] {
            Start-Sleep -Milliseconds 50
        }
    }
    if ($null -eq $handle) {
        throw "Project state is locked by another mutation at '$lockPath'."
    }
    $script:HeldWorkScopeLocks[$key] = $handle
    try {
        return & $Action
    }
    finally {
        $script:HeldWorkScopeLocks.Remove($key)
        $handle.Dispose()
    }
}

function Get-WorkScopePaths {
    param([Parameter(Mandatory)] [string]$Root)
    $resolved = [System.IO.Path]::GetFullPath($Root)
    return @{
        Root           = $resolved
        AgentRoot      = Join-Path $resolved '.agents'
        WorkRoot       = Join-Path $resolved '.agents\work'
        HandoffRoot    = Join-Path $resolved '.agents\handoffs'
        State          = Join-Path $resolved '.agents\work\state.json'
        Schema         = Join-Path $resolved '.agents\work\schema.json'
        Events         = Join-Path $resolved '.agents\work\events.jsonl'
        SelectionRules = Join-Path $resolved '.agents\work\selection-rules.json'
    }
}

function Get-WorkScopeCanonicalRoot {
    param([Parameter(Mandatory)] [string]$Root)
    $fullPath = [System.IO.Path]::GetFullPath($Root)
    $pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
    while ($fullPath.Length -gt $pathRoot.Length -and
        $fullPath[-1] -in @([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)) {
        $fullPath = $fullPath.Substring(0, $fullPath.Length - 1)
    }
    return $fullPath
}

function ConvertTo-WorkScopeRemoteIdentity {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
    $value = $Url.Trim()
    # scp-style ssh (git@host:owner/repo) has no scheme and a colon where a slash belongs.
    if ($value -match '^[^/]+@([^:/]+):(.+)$') {
        $value = "$($Matches[1])/$($Matches[2])"
    }
    else {
        $value = [regex]::Replace($value, '^[A-Za-z][A-Za-z0-9+.-]*://', '')
        $value = [regex]::Replace($value, '^[^/@]+@', '')
    }
    $value = $value.TrimEnd('/')
    if ($value.EndsWith('.git', [System.StringComparison]::OrdinalIgnoreCase)) {
        $value = $value.Substring(0, $value.Length - 4)
    }
    $value = $value.TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    return $value.ToLowerInvariant()
}

function Get-WorkScopeRepositoryIdentity {
    <#
        The identity of a project is its repository, not the folder one device happens to
        keep it in. `AGENTS.md` states that outright -- "A project's truth is its remote,
        not a folder on one device" -- and every cloud agent checks the same repository out
        at a path no Windows session will ever have. Returns $null whenever the answer is
        not knowable (no git, no repository, no origin), which is what keeps the caller's
        fallback to the location bind honest rather than optimistic.
    #>
    param([Parameter(Mandatory)] [string]$Root)
    try {
        if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) { return $null }
        $url = & git -C $Root remote get-url origin 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return ConvertTo-WorkScopeRemoteIdentity -Url ([string]($url | Select-Object -First 1))
    }
    catch {
        return $null
    }
}

function Get-UtcTimestamp {
    return [DateTime]::UtcNow.ToString('o')
}

function ConvertTo-NormalizedArray {
    param($Value)
    if ($null -eq $Value) {
        return @()
    }
    return @($Value)
}

function ConvertTo-DepthIndex {
    param([Parameter(Mandatory)] [string]$Depth)
    $index = [array]::IndexOf($script:Depths, $Depth)
    if ($index -lt 0) {
        throw "Invalid depth '$Depth'. Expected D0 through D5."
    }
    return $index
}

function Get-StateTrack {
    param(
        [Parameter(Mandatory)] [hashtable]$State,
        [Parameter(Mandatory)] [string]$TrackId
    )
    return ($State.tracks | Where-Object { $_.id -eq $TrackId } | Select-Object -First 1)
}

function Get-StateCapability {
    param(
        [Parameter(Mandatory)] [hashtable]$State,
        [Parameter(Mandatory)] [string]$TrackId,
        [Parameter(Mandatory)] [string]$CapabilityId
    )
    $track = Get-StateTrack -State $State -TrackId $TrackId
    if ($null -eq $track) {
        return $null
    }
    return ($track.capabilities | Where-Object { $_.id -eq $CapabilityId } | Select-Object -First 1)
}

function Read-WorkScopeState {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Root)
    $paths = Get-WorkScopePaths -Root $Root
    if (-not (Test-Path -LiteralPath $paths.State)) {
        throw "Work-scope state not found at '$($paths.State)'."
    }
    return (Get-Content -LiteralPath $paths.State -Raw | ConvertFrom-Json -AsHashtable)
}

function Write-WorkScopeState {
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [hashtable]$State
    )
    $paths = Get-WorkScopePaths -Root $Root
    if (-not $State.ContainsKey('revision') -or $null -eq $State.revision) {
        $State.revision = 0
    }
    $State.revision = [int64]$State.revision + 1
    $State.updated_at = Get-UtcTimestamp
    $json = $State | ConvertTo-Json -Depth 30
    $temporary = "$($paths.State).$([guid]::NewGuid().ToString('N')).tmp"
    Set-Content -LiteralPath $temporary -Value $json -Encoding utf8NoBOM
    Move-Item -LiteralPath $temporary -Destination $paths.State -Force
}

function Add-WorkScopeEvent {
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [hashtable]$State,
        [Parameter(Mandatory)] [string]$Type,
        $Evidence = @(),
        [hashtable]$Data = @{},
        [hashtable]$FileCommit
    )
    $paths = Get-WorkScopePaths -Root $Root
    $authoritativeValidation = Test-WorkScopeState -Root $Root
    if (-not $authoritativeValidation.valid) {
        # Retirement is the supported recovery for a mis-declared live check, including one
        # whose immutable input has already drifted or disappeared. In that case the disk
        # state is invalid precisely because the binding retirement is about to release.
        # Admit only those errors for this event's target task; candidate validation below
        # still has to pass, and every schema, event-chain, or unrelated-task error stays
        # fail-closed.
        $unrelatedAuthoritativeErrors = @($authoritativeValidation.errors)
        if ($Type -eq 'task_retired' -and -not [string]::IsNullOrWhiteSpace([string]$Data.task_id)) {
            $retirementTaskIds = @(
                @([string]$Data.task_id) + @($Data.related_task_ids) |
                    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                    ForEach-Object { [string]$_ } |
                    Sort-Object -Unique
            )
            $closedArtifactDriftTaskIds = @($Data.closed_artifact_drift_task_ids)
            if ($closedArtifactDriftTaskIds.Count -eq 0 -and $Data.closed_artifact_drift -eq $true) {
                $closedArtifactDriftTaskIds = @([string]$Data.task_id)
            }
            foreach ($retirementTaskId in $retirementTaskIds) {
                $escapedTaskId = [regex]::Escape($retirementTaskId)
                $recoverableInputError = "^Task '$escapedTaskId' verification input '.+' (?:is missing|changed after declaration)\.$"
                $unrelatedAuthoritativeErrors = @($unrelatedAuthoritativeErrors | Where-Object { $_ -notmatch $recoverableInputError })
                $targetTask = $State.active.tasks | Where-Object { $_.id -eq $retirementTaskId } | Select-Object -First 1
                $closedArtifactRecoveryIsValid = (
                    $closedArtifactDriftTaskIds -contains $retirementTaskId -and
                    $null -ne $targetTask -and
                    (Test-StructuredEvidence -Evidence $targetTask.evidence -Root $Root -RequireProvenance -Historical -RetirementArtifactDrift)
                )
                if ($closedArtifactRecoveryIsValid) {
                    $recoverableClosedEvidenceError = "^Closed task '$escapedTaskId' has missing or invalid structured evidence\.$"
                    $unrelatedAuthoritativeErrors = @($unrelatedAuthoritativeErrors | Where-Object { $_ -notmatch $recoverableClosedEvidenceError })
                }
            }
        }
        if ($Type -eq 'scope_cell_closed' -and $Data.target_depth_recovery -eq $true) {
            # A pre-2026-08-11 expand selection could reuse an existing capability at a deeper
            # entry depth without raising its target. That left an active selector-produced cell
            # that can complete correctly, yet fails only when closure writes its deeper current
            # depth. Admit that one historical shape here so the valid candidate below can repair
            # it. Every other authoritative error remains fail-closed.
            $storedState = Read-WorkScopeState -Root $Root
            $storedCapability = Get-StateCapability -State $storedState -TrackId $storedState.active.track_id -CapabilityId $storedState.active.capability_id
            $storedSelection = Get-WorkScopeActiveSelection -Root $Root -State $storedState
            $matchesSelectorRecovery = (
                $null -ne $storedCapability -and
                $null -ne $storedSelection -and
                $storedState.active.status -eq 'active' -and
                $storedState.active.track_id -eq $State.active.track_id -and
                $storedState.active.capability_id -eq $State.active.capability_id -and
                $storedState.active.cell_id -eq $State.active.cell_id -and
                $storedState.active.depth -eq $State.active.depth -and
                $storedSelection.suggested_track -eq $storedState.active.track_id -and
                $storedSelection.suggested_capability -eq $storedState.active.capability_id -and
                $storedSelection.entry_depth -eq $storedState.active.depth -and
                $Data.recovered_capability_id -eq $storedState.active.capability_id -and
                $Data.previous_target_depth -eq $storedCapability.target_depth -and
                $Data.recovered_target_depth -eq $storedState.active.depth -and
                (ConvertTo-DepthIndex $storedState.active.depth) -gt (ConvertTo-DepthIndex $storedCapability.target_depth) -and
                ($null -eq $storedCapability.current_depth -or
                    (ConvertTo-DepthIndex $storedCapability.current_depth) -le (ConvertTo-DepthIndex $storedState.active.depth))
            )
            if ($matchesSelectorRecovery) {
                $escapedCapabilityId = [regex]::Escape([string]$storedCapability.id)
                $recoverableDepthError = "^Capability '$escapedCapabilityId' current depth exceeds target depth\\.$"
                $unrelatedAuthoritativeErrors = @($unrelatedAuthoritativeErrors | Where-Object { $_ -notmatch $recoverableDepthError })
            }
        }
        if ($unrelatedAuthoritativeErrors.Count -gt 0) {
            throw "Authoritative state or event chain is invalid before mutation: $($authoritativeValidation.errors -join '; ')"
        }
    }
    $previousEventId = $State.last_event_id
    $previousEventHash = $State.last_event_hash
    $event = [ordered]@{
        event_id     = [guid]::NewGuid().ToString()
        previous_event_id = $previousEventId
        previous_event_hash = $previousEventHash
        state_revision = [int64]$State.revision + 1
        occurred_at  = Get-UtcTimestamp
        type         = $Type
        project_id   = $State.project.id
        track_id     = $State.active.track_id
        capability_id = $State.active.capability_id
        cell_id      = $State.active.cell_id
        evidence     = @(ConvertTo-NormalizedArray $Evidence)
        data         = $Data
    }
    $event.event_hash = Get-WorkScopeEventHash -Event $event
    $State.last_event_id = $event.event_id
    $State.last_event_hash = $event.event_hash
    $candidateValidation = Test-WorkScopeState -State $State -ArtifactRoot $paths.Root
    if (-not $candidateValidation.valid) {
        throw "Candidate state validation failed before commit: $($candidateValidation.errors -join '; ')"
    }
    $transactionPath = Join-Path $paths.WorkRoot 'transaction.json'
    if (Test-Path -LiteralPath $transactionPath) {
        throw "A pending transaction already exists at '$transactionPath'. Run transaction repair before another mutation."
    }
    $transaction = [ordered]@{
        version = '1.0.0'
        prepared_at = Get-UtcTimestamp
        state = $State
        event = $event
        file_commit = $FileCommit
    }
    if ($null -ne $FileCommit) {
        foreach ($requiredFileField in @('temporary_path', 'final_path', 'overwrite')) {
            if (-not $FileCommit.ContainsKey($requiredFileField)) {
                throw "File commit is missing '$requiredFileField'."
            }
        }
        if (-not (Test-Path -LiteralPath $FileCommit.temporary_path)) {
            throw "File commit temporary path '$($FileCommit.temporary_path)' does not exist."
        }
        if ((Test-Path -LiteralPath $FileCommit.final_path) -and -not [bool]$FileCommit.overwrite) {
            throw "File commit target '$($FileCommit.final_path)' already exists."
        }
    }
    Set-Content -LiteralPath $transactionPath -Value ($transaction | ConvertTo-Json -Depth 30) -Encoding utf8NoBOM
    try {
        Write-WorkScopeState -Root $Root -State $State
        Add-Content -LiteralPath $paths.Events -Value ($event | ConvertTo-Json -Depth 20 -Compress) -Encoding utf8NoBOM
        if ($null -ne $FileCommit) {
            Move-Item -LiteralPath $FileCommit.temporary_path -Destination $FileCommit.final_path -Force
        }
        Remove-Item -LiteralPath $transactionPath -Force
    }
    catch {
        throw "State-event commit was interrupted. The recovery journal remains at '$transactionPath'. $($_.Exception.Message)"
    }
    return $event
}

function Repair-WorkScopeTransaction {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Root)
    if (-not (Test-WorkScopeLockHeld -Root $Root)) {
        $arguments = Copy-WorkScopeBoundParameters -BoundParameters $PSBoundParameters
        return Invoke-WithWorkScopeLock -Root $Root -Action { Repair-WorkScopeTransaction @arguments }
    }
    $paths = Get-WorkScopePaths -Root $Root
    $transactionPath = Join-Path $paths.WorkRoot 'transaction.json'
    if (-not (Test-Path -LiteralPath $transactionPath)) {
        return [pscustomobject]@{ repaired = $false; reason = 'no_pending_transaction' }
    }
    $transaction = Get-Content -LiteralPath $transactionPath -Raw | ConvertFrom-Json -AsHashtable
    if (-not $transaction.ContainsKey('state') -or -not $transaction.ContainsKey('event') -or
        [string]::IsNullOrWhiteSpace([string]$transaction.event.event_id)) {
        throw "Transaction journal '$transactionPath' is invalid and cannot be repaired automatically."
    }
    $state = Read-WorkScopeState -Root $Root
    $rootFull = [System.IO.Path]::GetFullPath($paths.Root).TrimEnd('\', '/')
    # Same reasoning as the location bind in Test-WorkScopeState: the journal belongs to this
    # project, and on a checkout at a different absolute path the recorded project.root can
    # never match. Fall back to project identity so a container can repair its own interrupted
    # write instead of being wedged by one.
    $transactionRootMatches = ([System.IO.Path]::GetFullPath([string]$transaction.state.project.root).TrimEnd('\', '/') -eq $rootFull)
    if (-not $transactionRootMatches) {
        $stateRemote = if ($state.project.Contains('remote')) { ConvertTo-WorkScopeRemoteIdentity -Url ([string]$state.project.remote) } else { $null }
        $journalRemote = if ($transaction.state.project.Contains('remote')) { ConvertTo-WorkScopeRemoteIdentity -Url ([string]$transaction.state.project.remote) } else { $null }
        $transactionRootMatches = (
            [string]$transaction.state.project.id -eq [string]$state.project.id -and
            $null -ne $stateRemote -and $stateRemote -eq $journalRemote
        )
    }
    if ($transaction.version -ne '1.0.0' -or -not $transactionRootMatches) {
        throw "Transaction journal '$transactionPath' does not match this project."
    }
    $transactionValidation = Test-WorkScopeState -State ([hashtable]$transaction.state) -ArtifactRoot $paths.Root
    if (-not $transactionValidation.valid) {
        throw "Transaction journal contains invalid candidate state: $($transactionValidation.errors -join '; ')"
    }
    $expectedTransactionEventHash = Get-WorkScopeEventHash -Event $transaction.event
    if ($transaction.event.event_hash -ne $expectedTransactionEventHash -or
        $transaction.state.last_event_id -ne $transaction.event.event_id -or
        $transaction.state.last_event_hash -ne $transaction.event.event_hash -or
        [int64]$transaction.event.state_revision -ne ([int64]$transaction.state.revision + 1) -or
        $transaction.event.project_id -ne $transaction.state.project.id -or
        $transaction.event.track_id -ne $transaction.state.active.track_id -or
        $transaction.event.capability_id -ne $transaction.state.active.capability_id -or
        $transaction.event.cell_id -ne $transaction.state.active.cell_id) {
        throw "Transaction journal state and event are not internally consistent. hash=$($transaction.event.event_hash -eq $expectedTransactionEventHash); state_id=$($transaction.state.last_event_id -eq $transaction.event.event_id); state_hash=$($transaction.state.last_event_hash -eq $transaction.event.event_hash); revision=$([int64]$transaction.event.state_revision -eq ([int64]$transaction.state.revision + 1)); identity=$($transaction.event.project_id -eq $transaction.state.project.id -and $transaction.event.track_id -eq $transaction.state.active.track_id -and $transaction.event.capability_id -eq $transaction.state.active.capability_id -and $transaction.event.cell_id -eq $transaction.state.active.cell_id)."
    }
    $isBeforeStateCommit = (
        $state.last_event_id -eq $transaction.event.previous_event_id -and
        $state.last_event_hash -eq $transaction.event.previous_event_hash -and
        [int64]$state.revision + 1 -eq [int64]$transaction.event.state_revision
    )
    $isAfterStateCommit = (
        $state.last_event_id -eq $transaction.event.event_id -and
        $state.last_event_hash -eq $transaction.event.event_hash -and
        [int64]$state.revision -eq [int64]$transaction.event.state_revision
    )
    if (-not $isBeforeStateCommit -and -not $isAfterStateCommit) {
        throw 'Transaction journal does not continue from the authoritative state.'
    }
    if ($transaction.ContainsKey('file_commit') -and $null -ne $transaction.file_commit) {
        $fileCommit = $transaction.file_commit
        foreach ($requiredFileField in @('temporary_path', 'final_path', 'overwrite')) {
            if (-not $fileCommit.ContainsKey($requiredFileField)) {
                throw "Transaction file commit is missing '$requiredFileField'."
            }
        }
        $normalizedFilePaths = @{}
        foreach ($field in @('temporary_path', 'final_path')) {
            $absolute = [System.IO.Path]::GetFullPath([string]$fileCommit[$field])
            $relative = [System.IO.Path]::GetRelativePath($rootFull, $absolute).Replace('\', '/')
            $normalized = Resolve-WorkScopeArtifact -Root $paths.Root -Artifact $relative
            $normalizedFilePaths[$field] = $normalized
        }
        $temporaryName = [System.IO.Path]::GetFileName([string]$fileCommit.temporary_path)
        $finalName = [System.IO.Path]::GetFileName([string]$fileCommit.final_path)
        switch ($transaction.event.type) {
            'handoff_generated' {
                foreach ($field in @('temporary_path', 'final_path')) {
                    if (-not $normalizedFilePaths[$field].StartsWith('.agents/handoffs/', [System.StringComparison]::OrdinalIgnoreCase)) {
                        throw "Transaction handoff file commit '$field' must remain inside the project handoff directory."
                    }
                }
                $backburnerId = [string]$transaction.event.data.backburner_id
                Assert-SafeWorkScopeId -Id $backburnerId -Label 'Transaction backburner id'
                if (-not $temporaryName.StartsWith(".$backburnerId.", [System.StringComparison]::OrdinalIgnoreCase) -or
                    -not $temporaryName.EndsWith('.tmp', [System.StringComparison]::OrdinalIgnoreCase) -or
                    $finalName -ne "$backburnerId.md" -or
                    [System.IO.Path]::GetFullPath([string]$transaction.event.data.path) -ne
                        [System.IO.Path]::GetFullPath([string]$fileCommit.final_path) -or
                    [bool]$transaction.event.data.overwrite -ne [bool]$fileCommit.overwrite) {
                    throw 'Transaction file commit is not bound to its handoff event.'
                }
            }
            'verification_executed' {
                foreach ($field in @('temporary_path', 'final_path')) {
                    if (-not $normalizedFilePaths[$field].StartsWith('.agents/work/evidence/', [System.StringComparison]::OrdinalIgnoreCase)) {
                        throw "Transaction evidence file commit '$field' must remain inside the project evidence directory."
                    }
                }
                $receiptId = [string]$transaction.event.data.receipt_id
                $parsedReceiptId = [guid]::Empty
                if (-not [guid]::TryParse($receiptId, [ref]$parsedReceiptId) -or
                    -not $temporaryName.StartsWith("$receiptId.json.", [System.StringComparison]::OrdinalIgnoreCase) -or
                    -not $temporaryName.EndsWith('.tmp', [System.StringComparison]::OrdinalIgnoreCase) -or
                    $finalName -ne "$receiptId.json" -or
                    $normalizedFilePaths.final_path -ne [string]$transaction.event.data.reference -or
                    [bool]$fileCommit.overwrite) {
                    throw 'Transaction file commit is not bound to its verification event.'
                }
                $recordCandidate = if (Test-Path -LiteralPath $fileCommit.temporary_path) {
                    $fileCommit.temporary_path
                }
                else {
                    $fileCommit.final_path
                }
                if (-not (Test-Path -LiteralPath $recordCandidate -PathType Leaf)) {
                    throw 'Transaction verification record is missing.'
                }
                $recordItem = Get-Item -LiteralPath $recordCandidate -Force
                $recordHash = (Get-FileHash -LiteralPath $recordCandidate -Algorithm SHA256).Hash.ToLowerInvariant()
                $record = Get-Content -LiteralPath $recordCandidate -Raw | ConvertFrom-Json -AsHashtable
                if ($recordHash -ne $transaction.event.data.sha256 -or
                    [int64]$recordItem.Length -ne [int64]$transaction.event.data.size_bytes -or
                    $record.receipt_id -ne $receiptId -or
                    $record.check_id -ne $transaction.event.data.check_id -or
                    $record.task_id -ne $transaction.event.data.task_id -or
                    [int64]$record.exit_code -ne [int64]$transaction.event.data.exit_code) {
                    throw 'Transaction verification record is not bound to its event.'
                }
            }
            default {
                throw "Transaction event type '$($transaction.event.type)' cannot commit a file."
            }
        }
    }
    if ($state.last_event_id -ne $transaction.event.event_id) {
        $recoveryState = [hashtable]$transaction.state
        $recoveryState.last_event_id = $transaction.event.event_id
        $recoveryState.last_event_hash = $transaction.event.event_hash
        Write-WorkScopeState -Root $Root -State $recoveryState
    }
    $existingEventIds = @(
        Get-Content -LiteralPath $paths.Events |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { ($_ | ConvertFrom-Json).event_id }
    )
    if ($existingEventIds -notcontains $transaction.event.event_id) {
        Add-Content -LiteralPath $paths.Events -Value ($transaction.event | ConvertTo-Json -Depth 20 -Compress) -Encoding utf8NoBOM
    }
    if ($transaction.ContainsKey('file_commit') -and $null -ne $transaction.file_commit) {
        $fileCommit = $transaction.file_commit
        if (Test-Path -LiteralPath $fileCommit.temporary_path) {
            if ((Test-Path -LiteralPath $fileCommit.final_path) -and -not [bool]$fileCommit.overwrite) {
                throw "Transaction file target '$($fileCommit.final_path)' exists and overwrite was not authorized."
            }
            Move-Item -LiteralPath $fileCommit.temporary_path -Destination $fileCommit.final_path -Force
        }
        elseif (-not (Test-Path -LiteralPath $fileCommit.final_path)) {
            throw "Transaction file commit cannot find its temporary or final artifact."
        }
    }
    Remove-Item -LiteralPath $transactionPath -Force
    Sync-WorkScopeViews -Root $Root | Out-Null
    return [pscustomobject]@{ repaired = $true; event_id = $transaction.event.event_id }
}

function Get-DefaultSchemaPath {
    return (Join-Path $PSScriptRoot '..\assets\schema.json')
}

function Get-DefaultSelectionRulesPath {
    return (Join-Path $PSScriptRoot '..\assets\selection-rules.json')
}

function Initialize-WorkScopeProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [string]$ProjectId,
        [Parameter(Mandatory)] [ValidateSet('application', 'operations', 'agent-harness', 'coordination', 'client')] [string]$ProjectKind,
        [Parameter(Mandatory)] [string]$InitiativeId,
        [Parameter(Mandatory)] [string]$TrackId,
        [Parameter(Mandatory)] [string]$CapabilityId,
        [Parameter(Mandatory)] [string]$CapabilityName,
        [Parameter(Mandatory)] [ValidateSet('D0', 'D1', 'D2', 'D3', 'D4', 'D5')] [string]$TargetDepth,
        [ValidateSet('drilldown', 'expand')] [string]$FrontierMode = 'drilldown',
        [ValidateSet('D0', 'D1', 'D2', 'D3', 'D4', 'D5')] [string]$DepthCeiling = 'D4',
        [ValidateSet('capability', 'track', 'project', 'portfolio', 'system')] [string]$BreadthBoundary = 'track',
        [ValidateSet('dependency-first', 'highest-value', 'highest-risk', 'shortest-ready', 'balanced')] [string]$SelectionStrategy = 'dependency-first',
        [Parameter(Mandatory)] [string]$OwnerSession
    )
    if (-not (Test-WorkScopeLockHeld -Root $Root)) {
        $arguments = Copy-WorkScopeBoundParameters -BoundParameters $PSBoundParameters
        return Invoke-WithWorkScopeLock -Root $Root -Action { Initialize-WorkScopeProject @arguments }
    }
    ConvertTo-DepthIndex $TargetDepth | Out-Null
    ConvertTo-DepthIndex $DepthCeiling | Out-Null
    $paths = Get-WorkScopePaths -Root $Root
    if (Test-Path -LiteralPath $paths.State) {
        throw "Work-scope state already exists at '$($paths.State)'."
    }

    New-Item -ItemType Directory -Path $paths.WorkRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $paths.HandoffRoot -Force | Out-Null
    Copy-Item -LiteralPath (Get-DefaultSchemaPath) -Destination $paths.Schema
    Copy-Item -LiteralPath (Get-DefaultSelectionRulesPath) -Destination $paths.SelectionRules
    New-Item -ItemType File -Path $paths.Events -Force | Out-Null

    $now = Get-UtcTimestamp
    $state = [ordered]@{
        schema_version = '1.0.0'
        revision = 0
        created_at = $now
        updated_at = $now
        project = [ordered]@{
            id = $ProjectId
            kind = $ProjectKind
            initiative_id = $InitiativeId
            root = $paths.Root
            definition_of_done = @(
                'All active-cell tasks are closed with evidence.'
                'Generated views reconcile with canonical state.'
            )
        }
        tracks = @(
            [ordered]@{
                id = $TrackId
                status = 'active'
                capabilities = @(
                    [ordered]@{
                        id = $CapabilityId
                        name = $CapabilityName
                        current_depth = $null
                        target_depth = $TargetDepth
                        status = 'active'
                        dependencies = @()
                        blockers = @()
                        owner_session = $OwnerSession
                    }
                )
            }
        )
        active = [ordered]@{
            track_id = $TrackId
            capability_id = $CapabilityId
            depth = 'D0'
            cell_id = "$CapabilityId@D0"
            status = 'active'
            opened_at = $now
            closed_at = $null
            goal = "Complete and verify $CapabilityName at D0."
            in_scope = @($CapabilityId)
            out_of_scope = @()
            tasks = @()
            evidence = @()
            discoveries = @()
        }
        frontier = [ordered]@{
            mode = $FrontierMode
            automatic = $true
            depth_ceiling = $DepthCeiling
            breadth_boundary = $BreadthBoundary
            selection_strategy = $SelectionStrategy
            handoff_independent_tracks = $true
            stop_on = @(
                'destructive_action'
                'external_publish'
                'unresolved_collision'
                'missing_credential'
                'boundary_change'
            )
        }
        ownership = [ordered]@{
            sessions = @(
                [ordered]@{
                    session_id = $OwnerSession
                    track_id = $TrackId
                    capability_id = $CapabilityId
                    artifacts = @()
                }
            )
        }
        backburner = @()
        last_event_id = $null
        last_event_hash = $null
    }
    Write-WorkScopeState -Root $Root -State $state
    # Enrollment overwrites TASK.md, BACKBURNER.md and LOG.md with generated views. Line 1326
    # guarantees no state file existed a moment ago, so anything sitting at those names is
    # authored legacy content by definition -- and the first Sync-WorkScopeViews destroyed it,
    # silently, with no copy anywhere. Migrate-TaskState.ps1 -ToWorkScope is the route that
    # carries the content across, but nothing made it run first. Archive by default, per the
    # shared contract: enrollment still proceeds, and the event names what was set aside.
    $legacyArchived = @()
    $legacyNames = @('TASK.md', 'BACKBURNER.md', 'LOG.md', 'PROJECT.md', 'TRACKS.md')
    $legacyPresent = @($legacyNames | Where-Object { Test-Path -LiteralPath (Join-Path $Root $_) -PathType Leaf })
    if ($legacyPresent.Count -gt 0) {
        $archiveRoot = Join-Path $paths.WorkRoot ('legacy-task-state-' + (Get-UtcTimestamp).Replace(':', '-'))
        New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null
        foreach ($legacyName in $legacyPresent) {
            Copy-Item -LiteralPath (Join-Path $Root $legacyName) -Destination (Join-Path $archiveRoot $legacyName) -Force
            $legacyArchived += $legacyName
        }
    }
    Add-WorkScopeEvent -Root $Root -State $state -Type 'project_initialized' -Data @{
        owner_session = $OwnerSession
        frontier_mode = $FrontierMode
        breadth_boundary = $BreadthBoundary
        legacy_task_state_archived = $legacyArchived
    } | Out-Null
    Sync-WorkScopeViews -Root $Root | Out-Null
    return $state
}

function Test-WorkScopeState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Root')] [string]$Root,
        [Parameter(Mandatory, ParameterSetName = 'State')] [hashtable]$State,
        # Where this checkout actually lives. Callers in the State set know it; the stored
        # project.root does not, once the same repository is checked out on another machine.
        [Parameter(ParameterSetName = 'State')] [string]$ArtifactRoot
    )
    $schemaFailure = $null
    $resolvedArtifactRoot = $null
    if ($PSCmdlet.ParameterSetName -eq 'Root') {
        try {
            $paths = Get-WorkScopePaths -Root $Root
            $State = Read-WorkScopeState -Root $Root
            $resolvedArtifactRoot = $paths.Root
            $expectedRoot = Get-WorkScopeCanonicalRoot -Root $paths.Root
            $declaredRoot = if ($State.ContainsKey('project') -and
                $State.project -is [System.Collections.IDictionary] -and
                $State.project.Contains('root') -and
                -not [string]::IsNullOrWhiteSpace([string]$State.project.root)) {
                Get-WorkScopeCanonicalRoot -Root ([string]$State.project.root)
            }
            else {
                $null
            }
            $pathComparison = if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
                [System.StringComparison]::OrdinalIgnoreCase
            }
            else {
                [System.StringComparison]::Ordinal
            }
            if ($null -eq $declaredRoot -or
                -not $declaredRoot.Equals($expectedRoot, $pathComparison)) {
                # The bind exists so a copied or relocated state file cannot be written as if
                # it were canonical, and that purpose is real. But binding it to an absolute
                # path binds it to one device: a container checkout of the same repository at
                # /workspace/<name> failed every write, so a cloud session could do the work
                # and then had no legal way to record that it had. `project.remote` re-binds
                # the same guarantee to the thing that actually identifies the project -- its
                # repository -- so the same repo passes anywhere and a different repo still
                # fails. It is optional and never inferred: a project with no remote by
                # design (build-log, operating-dashboard) keeps the location bind verbatim,
                # and so does any state file enrolled before this existed.
                $declaredRemote = if ($State.project -is [System.Collections.IDictionary] -and
                    $State.project.Contains('remote')) {
                    ConvertTo-WorkScopeRemoteIdentity -Url ([string]$State.project.remote)
                }
                else { $null }
                $checkoutRemote = if ($declaredRemote) { Get-WorkScopeRepositoryIdentity -Root $paths.Root } else { $null }
                if ($null -eq $declaredRemote -or $null -eq $checkoutRemote -or
                    -not $declaredRemote.Equals($checkoutRemote, [System.StringComparison]::Ordinal)) {
                    return [pscustomobject]@{
                        valid = $false
                        errors = @('Work Scope state is location-bound to its canonical project.root and does not match -Root, and no matching project.remote re-binds it to this checkout. A relocated project requires deliberate reviewed re-enrollment; project.root is never repaired automatically.')
                    }
                }
            }
            if (-not (Test-Path -LiteralPath $paths.Schema)) {
                $schemaFailure = "JSON schema file is missing at '$($paths.Schema)'."
            }
            elseif (-not (Test-Json -LiteralPath $paths.State -SchemaFile $paths.Schema -ErrorAction SilentlyContinue)) {
                $schemaFailure = 'JSON schema validation failed.'
            }
        }
        catch {
            return [pscustomobject]@{ valid = $false; errors = @($_.Exception.Message) }
        }
    }
    else {
        try {
            $resolvedArtifactRoot = if (-not [string]::IsNullOrWhiteSpace($ArtifactRoot)) { $ArtifactRoot }
                elseif ($State.ContainsKey('project') -and $State.project -is [System.Collections.IDictionary] -and
                    $State.project.Contains('root')) { [string]$State.project.root }
                else { $null }
            $schemaPath = Get-DefaultSchemaPath
            if ($resolvedArtifactRoot) {
                $candidateSchema = Join-Path $resolvedArtifactRoot '.agents/work/schema.json'
                if (Test-Path -LiteralPath $candidateSchema) {
                    $schemaPath = $candidateSchema
                }
            }
            $stateJson = $State | ConvertTo-Json -Depth 30
            if (-not ($stateJson | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue)) {
                $schemaFailure = 'JSON schema validation failed for candidate state.'
            }
        }
        catch {
            $schemaFailure = "JSON schema validation failed for candidate state: $($_.Exception.Message)"
        }
    }
    $errors = [System.Collections.Generic.List[string]]::new()
    if ($schemaFailure) {
        $errors.Add($schemaFailure)
    }
    $missingTopLevel = [System.Collections.Generic.List[string]]::new()
    foreach ($required in @('schema_version', 'revision', 'project', 'tracks', 'active', 'frontier', 'ownership', 'backburner')) {
        if (-not $State.ContainsKey($required)) {
            $message = "Missing required property '$required'."
            $errors.Add($message)
            $missingTopLevel.Add($message)
        }
    }
    if ($missingTopLevel.Count -gt 0) {
        return [pscustomobject]@{ valid = $false; errors = @($errors) }
    }
    if ($script:Depths -notcontains $State.active.depth) {
        $errors.Add("Active depth '$($State.active.depth)' is invalid.")
    }
    if (@('active', 'closed', 'blocked') -notcontains $State.active.status) {
        $errors.Add("Active cell status '$($State.active.status)' is invalid.")
    }
    if (@('drilldown', 'expand') -notcontains $State.frontier.mode) {
        $errors.Add("Frontier mode '$($State.frontier.mode)' is invalid.")
    }
    if (@('capability', 'track', 'project', 'portfolio', 'system') -notcontains $State.frontier.breadth_boundary) {
        $errors.Add("Breadth boundary '$($State.frontier.breadth_boundary)' is invalid.")
    }
    if ($State.frontier.automatic -isnot [bool]) {
        $errors.Add('Frontier automatic must be a boolean.')
    }
    $track = Get-StateTrack -State $State -TrackId $State.active.track_id
    if ($null -eq $track) {
        $errors.Add("Active track '$($State.active.track_id)' does not exist.")
    }
    elseif ($null -eq (Get-StateCapability -State $State -TrackId $State.active.track_id -CapabilityId $State.active.capability_id)) {
        $errors.Add("Active capability '$($State.active.capability_id)' does not exist.")
    }
    if ($State.active.cell_id -ne "$($State.active.capability_id)@$($State.active.depth)") {
        $errors.Add('Active cell_id does not match capability and depth.')
    }
    if ($State.active.status -eq 'closed') {
        if (@(ConvertTo-NormalizedArray $State.active.tasks).Count -eq 0) {
            $errors.Add('Closed scope cell has no materialized task.')
        }
        if (-not (Test-StructuredEvidence -Evidence $State.active.evidence -Root $resolvedArtifactRoot -RequireProvenance -Historical)) {
            $errors.Add('Closed scope cell has missing or invalid structured evidence.')
        }
        else {
            $expectedCellReceiptIds = @(
                $State.active.tasks |
                    Where-Object { $_.status -eq 'closed' } |
                    ForEach-Object { @($_.evidence) } |
                    ForEach-Object { $_.receipt_id } |
                    Sort-Object
            )
            $actualCellReceiptIds = @($State.active.evidence | ForEach-Object { $_.receipt_id } | Sort-Object)
            if (($expectedCellReceiptIds | ConvertTo-Json -Compress) -ne
                ($actualCellReceiptIds | ConvertTo-Json -Compress)) {
                $errors.Add('Closed scope cell evidence must match its task-bound receipts exactly.')
            }
        }
        if ([string]::IsNullOrWhiteSpace([string]$State.active.closed_at)) {
            $errors.Add('Closed scope cell has no closed_at timestamp.')
        }
    }
    $taskIds = @($State.active.tasks | ForEach-Object { $_.id })
    if (@($taskIds | Sort-Object -Unique).Count -ne $taskIds.Count) {
        $errors.Add('Active task ids must be unique.')
    }
    $backburnerIds = @($State.backburner | ForEach-Object { $_.id })
    if (@($backburnerIds | Sort-Object -Unique).Count -ne $backburnerIds.Count) {
        $errors.Add('Backburner ids must be unique.')
    }
    $allAcceptanceCheckIds = [System.Collections.Generic.List[string]]::new()
    foreach ($task in @($State.active.tasks)) {
        if ([string]::IsNullOrWhiteSpace([string]$task.id) -or [string]::IsNullOrWhiteSpace([string]$task.acceptance)) {
            $errors.Add('Every task requires an id and explicit acceptance criteria.')
        }
        $acceptanceChecks = @($task.acceptance_checks)
        if ($acceptanceChecks.Count -eq 0) {
            $errors.Add("Task '$($task.id)' requires at least one declared acceptance check.")
        }
        $taskCheckIds = @($acceptanceChecks | ForEach-Object { $_.id })
        if (@($taskCheckIds | Sort-Object -Unique).Count -ne $taskCheckIds.Count) {
            $errors.Add("Task '$($task.id)' acceptance check ids must be unique.")
        }
        foreach ($check in $acceptanceChecks) {
            $allAcceptanceCheckIds.Add([string]$check.id)
            try {
                Assert-SafeWorkScopeId -Id ([string]$check.id) -Label 'Verification check id'
                if ($check.verifier -notin @('test', 'command') -or
                    $check.executable_sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
                    $check.arguments_sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
                    $check.arguments_sha256 -ne (Get-WorkScopeStringArrayHash -Values @($check.arguments)) -or
                    [int]$check.timeout_seconds -lt 1 -or [int]$check.timeout_seconds -gt 14400 -or
                    [int64]$check.max_output_bytes -lt 64 -or [int64]$check.max_output_bytes -gt 10485760) {
                    $errors.Add("Task '$($task.id)' acceptance check '$($check.id)' is invalid.")
                }
                try {
                    Assert-WorkScopeNativeExecutableShape -Path ([string]$check.executable) `
                        -Context "Task '$($task.id)' acceptance check '$($check.id)' executable"
                }
                catch {
                    $errors.Add($_.Exception.Message)
                }
                foreach ($artifact in @($check.artifacts)) {
                    Resolve-WorkScopeArtifact -Root $resolvedArtifactRoot -Artifact ([string]$artifact) | Out-Null
                }
                foreach ($inputSnapshot in @($check.verifier_inputs)) {
                    $inputReference = Resolve-WorkScopeArtifact -Root $resolvedArtifactRoot -Artifact ([string]$inputSnapshot.reference)
                    # A terminal task's check will never run again, so its binding to the current
                    # working tree is dead weight -- but it was still enforced, and validation fails
                    # closed, so editing or deleting a file an ABANDONED check named invalidated the
                    # whole state and blocked every guarded mutation, including adding the
                    # replacement task. Found on kelly-uniforms-business REC-002, where recovery was
                    # the thing the lock prevented. The path is still resolved above, so a terminal
                    # task cannot smuggle in a traversal reference; only the filesystem binding goes.
                    #
                    # `closed` was deliberately left enforcing on 2026-08-09, tracked as
                    # closed-task-input-drift-blocks-state, on the reading that a closed task's proof
                    # genuinely no longer covers an edited file. That reading is right about the
                    # evidence and wrong about where to act on it, and this repository hit the
                    # consequence on 2026-08-10: two ordinary edits to files a closed task's check had
                    # named -- Run-ToolTests.ps1 and its policy manifest, edited to FIX a defect --
                    # invalidated the entire state and blocked every guarded write, including the
                    # retire that would have released the binding. Reconcile-WorkState had no repair
                    # for it either way. That is a ratchet: every file ever named by any closed check
                    # becomes permanently uneditable, and the failure lands on whoever edits it next
                    # rather than on the task whose proof went stale.
                    #
                    # A receipt is a historical record of what was true when the check ran. It keeps
                    # its recorded hash, so nothing is lost and the drift is still visible to anyone
                    # reading the evidence; what stops is re-hashing live files against a past
                    # receipt and calling today's tree a defect in yesterday's proof.
                    if ([string]$task.status -eq 'retired' -or [string]$task.status -eq 'closed') { continue }
                    $inputPath = Join-Path $resolvedArtifactRoot $inputReference
                    if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
                        $errors.Add("Task '$($task.id)' verification input '$inputReference' is missing.")
                        continue
                    }
                    $inputItem = Get-Item -LiteralPath $inputPath -Force
                    $inputHash = (Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash.ToLowerInvariant()
                    if ($inputHash -ne $inputSnapshot.sha256 -or
                        [int64]$inputItem.Length -ne [int64]$inputSnapshot.size_bytes) {
                        $errors.Add("Task '$($task.id)' verification input '$inputReference' changed after declaration.")
                    }
                }
                if (Test-WorkScopeDeclaredInterpreter -Path ([string]$check.executable)) {
                    $declaredArguments = @($check.arguments)
                    $fileArgumentIndex = -1
                    for ($argumentIndex = 0; $argumentIndex -lt $declaredArguments.Count; $argumentIndex++) {
                        if ($declaredArguments[$argumentIndex] -in @('-File', '-f')) {
                            $fileArgumentIndex = $argumentIndex
                            break
                        }
                    }
                    if ($fileArgumentIndex -ge 0) {
                        if ($fileArgumentIndex + 1 -ge $declaredArguments.Count) {
                            $errors.Add("Task '$($task.id)' PowerShell check has no -File script.")
                        }
                        else {
                            $scriptReference = Resolve-WorkScopeArtifact -Root $resolvedArtifactRoot -Artifact $declaredArguments[$fileArgumentIndex + 1]
                            if (@($check.verifier_inputs | Where-Object { $_.reference -eq $scriptReference }).Count -ne 1) {
                                $errors.Add("Task '$($task.id)' PowerShell -File script '$scriptReference' is not hash-bound as a verifier input.")
                            }
                        }
                    }
                }
            }
            catch {
                $errors.Add($_.Exception.Message)
            }
        }
        if (@('ready', 'blocked', 'closed', 'retired') -notcontains $task.status) {
            $errors.Add("Task '$($task.id)' has invalid status '$($task.status)'.")
        }
        $missingDependencies = @($task.dependencies | Where-Object { $taskIds -notcontains $_ })
        if ($missingDependencies.Count -gt 0) {
            $errors.Add("Task '$($task.id)' references missing dependencies: $($missingDependencies -join ', ').")
        }
        if ($task.status -eq 'closed') {
            if (-not (Test-StructuredEvidence -Evidence $task.evidence -Root $resolvedArtifactRoot -RequireProvenance -Historical)) {
                $errors.Add("Closed task '$($task.id)' has missing or invalid structured evidence.")
            }
            else {
                try {
                    Assert-WorkScopeTaskReceiptCoverage -Task $task -Receipts @($task.evidence) -State $State -Context 'State validation'
                }
                catch {
                    $errors.Add($_.Exception.Message)
                }
            }
            if ([string]::IsNullOrWhiteSpace([string]$task.closed_at)) {
                $errors.Add("Closed task '$($task.id)' has no closed_at timestamp.")
            }
        }
    }
    if (@($allAcceptanceCheckIds | Sort-Object -Unique).Count -ne $allAcceptanceCheckIds.Count) {
        $errors.Add('Acceptance check ids must be unique across the active scope cell.')
    }
    $taskInDegree = @{}
    $taskDependents = @{}
    foreach ($taskId in $taskIds) {
        $taskInDegree[$taskId] = 0
        $taskDependents[$taskId] = [System.Collections.Generic.List[string]]::new()
    }
    foreach ($task in @($State.active.tasks)) {
        foreach ($dependency in @($task.dependencies)) {
            if ($taskInDegree.ContainsKey($dependency)) {
                $taskInDegree[$task.id]++
                $taskDependents[$dependency].Add($task.id)
            }
        }
    }
    $taskQueue = [System.Collections.Generic.Queue[string]]::new()
    foreach ($taskId in @($taskInDegree.Keys)) {
        if ($taskInDegree[$taskId] -eq 0) {
            $taskQueue.Enqueue($taskId)
        }
    }
    $processedTasks = 0
    while ($taskQueue.Count -gt 0) {
        $taskId = $taskQueue.Dequeue()
        $processedTasks++
        foreach ($dependent in $taskDependents[$taskId]) {
            $taskInDegree[$dependent]--
            if ($taskInDegree[$dependent] -eq 0) {
                $taskQueue.Enqueue($dependent)
            }
        }
    }
    if ($processedTasks -ne $taskIds.Count) {
        $errors.Add('Active task dependencies contain a cycle.')
    }
    foreach ($stateTrack in @($State.tracks)) {
        foreach ($capability in @($stateTrack.capabilities)) {
            if ($script:Depths -notcontains $capability.target_depth) {
                $errors.Add("Capability '$($capability.id)' has invalid target depth.")
            }
            if ($null -ne $capability.current_depth -and $script:Depths -contains $capability.current_depth -and
                (ConvertTo-DepthIndex $capability.current_depth) -gt (ConvertTo-DepthIndex $capability.target_depth)) {
                $errors.Add("Capability '$($capability.id)' current depth exceeds target depth.")
            }
        }
    }
    $artifactOwners = [System.Collections.Generic.List[object]]::new()
    foreach ($session in @($State.ownership.sessions)) {
        foreach ($artifact in @($session.artifacts)) {
            try {
                $normalizedArtifact = Resolve-WorkScopeArtifact -Root $resolvedArtifactRoot -Artifact $artifact
                foreach ($claim in $artifactOwners) {
                    if ($claim.session_id -ne $session.session_id -and
                        (Test-WorkScopeArtifactOverlap -Left $claim.artifact -Right $normalizedArtifact)) {
                        $errors.Add("Artifact ownership overlaps between '$($claim.artifact)' and '$normalizedArtifact'.")
                    }
                }
                $artifactOwners.Add([pscustomobject]@{ session_id = $session.session_id; artifact = $normalizedArtifact })
            }
            catch {
                $errors.Add($_.Exception.Message)
            }
        }
    }
    foreach ($item in @($State.backburner)) {
        try {
            Assert-SafeWorkScopeId -Id $item.id -Label 'Backburner id'
        }
        catch {
            $errors.Add($_.Exception.Message)
        }
        if (-not (Test-StructuredEvidence -Evidence $item.evidence -Root $resolvedArtifactRoot)) {
            $errors.Add("Backburner item '$($item.id)' has invalid structured evidence.")
        }
    }
    if ($PSCmdlet.ParameterSetName -eq 'Root') {
        $transactionPath = Join-Path $paths.WorkRoot 'transaction.json'
        if (Test-Path -LiteralPath $transactionPath) {
            $errors.Add('A pending transaction requires recovery before reconciliation.')
        }
        $events = @()
        try {
            $events = @(Get-Content -LiteralPath $paths.Events | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable })
        }
        catch {
            $errors.Add("Event log contains invalid JSON: $($_.Exception.Message)")
        }
        if ($State.last_event_id) {
            if ($events.Count -eq 0) {
                $errors.Add('State references an event, but the event log is empty.')
            }
            elseif ($events[-1].event_id -ne $State.last_event_id) {
                $errors.Add('State last_event_id does not match the event log tail.')
            }
        }
        $eventIds = @($events | ForEach-Object { $_.event_id })
        if (@($eventIds | Sort-Object -Unique).Count -ne $eventIds.Count) {
            $errors.Add('Event ids must be unique.')
        }
        for ($eventIndex = 0; $eventIndex -lt $events.Count; $eventIndex++) {
            $event = $events[$eventIndex]
            if ($event.event_hash -ne (Get-WorkScopeEventHash -Event $event)) {
                $errors.Add("Event payload hash is invalid for '$($event.event_id)'.")
            }
            if ($eventIndex -eq 0) {
                if ($event.previous_event_id -or $event.previous_event_hash) {
                    $errors.Add('First event must not reference a previous event or hash.')
                }
            }
            else {
                $previousEvent = $events[$eventIndex - 1]
                if ($event.previous_event_id -ne $previousEvent.event_id) {
                    $errors.Add("Event chain is broken before '$($event.event_id)'.")
                }
                if ($event.previous_event_hash -ne $previousEvent.event_hash) {
                    $errors.Add("Event hash chain is broken before '$($event.event_id)'.")
                }
                if ([int64]$event.state_revision -ne ([int64]$previousEvent.state_revision + 1)) {
                    $errors.Add("Event revision continuity is broken at '$($event.event_id)'.")
                }
            }
            if ($event.project_id -ne $State.project.id) {
                $errors.Add("Event '$($event.event_id)' belongs to the wrong project.")
            }
        }
        if ($events.Count -gt 0 -and [int64]$events[-1].state_revision -ne [int64]$State.revision) {
            $errors.Add('State revision does not match the event log tail revision.')
        }
        if ($events.Count -gt 0 -and $events[-1].event_hash -ne $State.last_event_hash) {
            $errors.Add('State last_event_hash does not match the event log tail hash.')
        }
        foreach ($task in @($State.active.tasks | Where-Object { $_.status -eq 'closed' })) {
            $taskEvents = @($events | Where-Object {
                $_.type -eq 'task_completed' -and
                $_.data.task_id -eq $task.id -and
                $_.track_id -eq $State.active.track_id -and
                $_.capability_id -eq $State.active.capability_id -and
                $_.cell_id -eq $State.active.cell_id
            })
            if ($taskEvents.Count -eq 0) {
                $errors.Add("Closed task '$($task.id)' has no matching completion event.")
            }
            elseif (($taskEvents[-1].evidence | ConvertTo-Json -Depth 10 -Compress) -ne ($task.evidence | ConvertTo-Json -Depth 10 -Compress)) {
                $errors.Add("Closed task '$($task.id)' evidence disagrees with its completion event.")
            }
        }
        if ($State.active.status -eq 'closed') {
            $closureEvents = @($events | Where-Object {
                $_.type -eq 'scope_cell_closed' -and
                $_.track_id -eq $State.active.track_id -and
                $_.capability_id -eq $State.active.capability_id -and
                $_.cell_id -eq $State.active.cell_id
            })
            if ($closureEvents.Count -eq 0) {
                $errors.Add("Closed scope cell '$($State.active.cell_id)' has no matching closure event.")
            }
            elseif (($closureEvents[-1].evidence | ConvertTo-Json -Depth 10 -Compress) -ne ($State.active.evidence | ConvertTo-Json -Depth 10 -Compress)) {
                $errors.Add("Closed scope cell '$($State.active.cell_id)' evidence disagrees with its closure event.")
            }
        }
    }
    return [pscustomobject]@{
        valid = ($errors.Count -eq 0)
        errors = @($errors)
    }
}

function Add-WorkScopeTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [string]$TaskId,
        [Parameter(Mandatory)] [string]$Title,
        [Parameter(Mandatory)] [string]$Acceptance,
        [string[]]$Dependencies = @(),
        [Parameter(Mandatory)] [string]$CheckId,
        [Parameter(Mandatory)] [ValidateSet('test', 'command')] [string]$CheckVerifier,
        [Parameter(Mandatory)] [string]$CheckExecutable,
        [string[]]$CheckArguments = @(),
        [string[]]$CheckInputs = @(),
        [string[]]$CheckArtifacts = @(),
        # 4 hours. The old ceiling was 1 hour, which put this harness's own full test gate --
        # Run-ToolTests.ps1 with the slow suites, measured at about 65 minutes -- outside what any
        # project could declare as an acceptance check. A bound that excludes the most thorough
        # verifier available is a bound that quietly pushes tasks onto weaker proof, which is the
        # opposite of what acceptance checks are for. It stays bounded because a check with no
        # ceiling is a way for a run to hang forever holding a task open.
        [ValidateRange(1, 14400)] [int]$CheckTimeoutSeconds = 300,
        [ValidateRange(64, 10485760)] [int64]$CheckMaxOutputBytes = 1048576
    )
    if (-not (Test-WorkScopeLockHeld -Root $Root)) {
        $arguments = Copy-WorkScopeBoundParameters -BoundParameters $PSBoundParameters
        return Invoke-WithWorkScopeLock -Root $Root -Action { Add-WorkScopeTask @arguments }
    }
    Assert-SafeWorkScopeId -Id $TaskId -Label 'Task id'
    Assert-SafeWorkScopeId -Id $CheckId -Label 'Verification check id'
    if ([string]::IsNullOrWhiteSpace($Acceptance)) {
        throw 'Task acceptance criteria cannot be empty.'
    }
    $state = Read-WorkScopeState -Root $Root
    if ($state.active.status -ne 'active') {
        throw 'Tasks can only be added to an active scope cell.'
    }
    if (@($state.active.tasks | Where-Object { $_.id -eq $TaskId }).Count -gt 0) {
        throw "Task '$TaskId' already exists."
    }
    if (@(
        $state.active.tasks |
            ForEach-Object { @($_.acceptance_checks) } |
            Where-Object { $_.id -eq $CheckId }
    ).Count -gt 0) {
        throw "Verification check '$CheckId' already exists in the active scope cell."
    }
    $checkExecutablePath = Resolve-WorkScopeNativeExecutable -Executable $CheckExecutable
    $checkInputsNormalized = @(
        @(ConvertTo-NormalizedArray $CheckInputs) |
            ForEach-Object { Resolve-WorkScopeArtifact -Root $Root -Artifact $_ } |
            Sort-Object -Unique
    )
    $checkInputSnapshots = @(
        foreach ($inputReference in $checkInputsNormalized) {
            $inputPath = Join-Path $Root $inputReference
            if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
                throw "Verification input '$inputReference' must exist when the task is declared."
            }
            $inputItem = Get-Item -LiteralPath $inputPath -Force
            [ordered]@{
                reference = $inputReference
                sha256 = (Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash.ToLowerInvariant()
                size_bytes = [int64]$inputItem.Length
            }
        }
    )
    if (Test-WorkScopeDeclaredInterpreter -Path $checkExecutablePath) {
        $fileArgumentIndex = -1
        for ($argumentIndex = 0; $argumentIndex -lt $CheckArguments.Count; $argumentIndex++) {
            if ($CheckArguments[$argumentIndex] -in @('-File', '-f')) {
                $fileArgumentIndex = $argumentIndex
                break
            }
        }
        if ($fileArgumentIndex -ge 0) {
            if ($fileArgumentIndex + 1 -ge $CheckArguments.Count) {
                throw 'PowerShell -File verification requires a script path argument.'
            }
            $scriptReference = Resolve-WorkScopeArtifact -Root $Root -Artifact $CheckArguments[$fileArgumentIndex + 1]
            if ($checkInputsNormalized -notcontains $scriptReference) {
                throw "PowerShell verification script '$scriptReference' must be declared in CheckInputs so its content is hash-bound."
            }
        }
    }
    $checkArtifactsNormalized = @(
        @(ConvertTo-NormalizedArray $CheckArtifacts) |
            ForEach-Object { Resolve-WorkScopeArtifact -Root $Root -Artifact $_ } |
            Sort-Object -Unique
    )
    # Work-scope's own state and event log change on every write, including the
    # write that completes this very task. A receipt snapshotting either one is
    # invalidated by its own completion, so the task could never close and would
    # wedge its cell permanently with no way back out. Refuse at declaration,
    # where the mistake is still cheap to correct.
    $selfMutatingArtifacts = @('.agents/work/state.json', '.agents/work/events.jsonl')
    foreach ($artifact in $checkArtifactsNormalized) {
        $normalized = ([string]$artifact).Replace('\', '/')
        if ($selfMutatingArtifacts -contains $normalized) {
            throw "Check artifact '$artifact' is work-scope's own mutating state; a receipt taken against it is invalidated by the completion that follows it. Declare the artifact the task actually produces."
        }
    }
    $acceptanceCheck = [ordered]@{
        id = $CheckId
        verifier = $CheckVerifier
        executable = $checkExecutablePath
        executable_sha256 = (Get-FileHash -LiteralPath $checkExecutablePath -Algorithm SHA256).Hash.ToLowerInvariant()
        arguments = @($CheckArguments)
        arguments_sha256 = Get-WorkScopeStringArrayHash -Values $CheckArguments
        verifier_inputs = $checkInputSnapshots
        artifacts = $checkArtifactsNormalized
        timeout_seconds = $CheckTimeoutSeconds
        max_output_bytes = $CheckMaxOutputBytes
    }
    $task = [ordered]@{
        id = $TaskId
        title = $Title
        acceptance = $Acceptance
        acceptance_checks = @($acceptanceCheck)
        dependencies = @(ConvertTo-NormalizedArray $Dependencies)
        status = if (@(ConvertTo-NormalizedArray $Dependencies).Count -gt 0) { 'blocked' } else { 'ready' }
        evidence = @()
        closed_at = $null
    }
    $state.active.tasks = @($state.active.tasks) + @($task)
    Add-WorkScopeEvent -Root $Root -State $state -Type 'task_added' -Data @{ task_id = $TaskId } | Out-Null
    Sync-WorkScopeViews -Root $Root | Out-Null
    return $task
}

function Resolve-TaskStatuses {
    param([Parameter(Mandatory)] [hashtable]$State)
    $closed = @($State.active.tasks | Where-Object { $_.status -eq 'closed' } | ForEach-Object { $_.id })
    foreach ($task in @($State.active.tasks)) {
        # `retired` belongs here as much as `closed` does, and its absence made retirement
        # temporary. This resolver runs twice inside task completion on state that is then
        # persisted, so a retired task was rewritten to `ready` the next time any other task
        # closed -- taking its abandoned check's working-tree binding with it, which is the
        # thing retirement exists to release. Both are terminal: neither can become ready
        # again, and dependency satisfaction still requires `closed`, so a task depending on a
        # retired one stays blocked rather than being quietly let through.
        if ($task.status -eq 'closed' -or $task.status -eq 'retired') {
            continue
        }
        $unmet = @($task.dependencies | Where-Object { $closed -notcontains $_ })
        $task.status = if ($unmet.Count -eq 0) { 'ready' } else { 'blocked' }
    }
}

function Set-WorkScopeTaskRetired {
    # A task whose acceptance check can never pass -- a mis-declared artifact, an
    # obsolete premise -- otherwise wedges its cell forever, because closure
    # requires every task closed and nothing could amend or remove one. Retiring
    # records why, on the hashed event chain, so the escape is auditable rather
    # than a hand edit. It is not a way to skip work: a cell still cannot close
    # unless at least one task closed on real executed evidence.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [string]$TaskId,
        [string[]]$RelatedTaskIds = @(),
        [Parameter(Mandatory)] [string]$Reason
    )
    if (-not (Test-WorkScopeLockHeld -Root $Root)) {
        $arguments = Copy-WorkScopeBoundParameters -BoundParameters $PSBoundParameters
        return Invoke-WithWorkScopeLock -Root $Root -Action { Set-WorkScopeTaskRetired @arguments }
    }
    if ([string]::IsNullOrWhiteSpace($Reason)) {
        throw 'Retiring a task requires a reason.'
    }
    $state = Read-WorkScopeState -Root $Root
    if ($state.active.status -ne 'active') {
        throw 'Tasks can only be retired inside an active scope cell.'
    }
    $taskIds = @(
        @($TaskId) + @(ConvertTo-NormalizedArray $RelatedTaskIds) |
            Sort-Object -Unique
    )
    $tasks = @()
    $closedArtifactDriftTaskIds = @()
    foreach ($retirementTaskId in $taskIds) {
        $task = $state.active.tasks | Where-Object { $_.id -eq $retirementTaskId } | Select-Object -First 1
        if ($null -eq $task) {
            throw "Task '$retirementTaskId' does not exist in the active scope cell."
        }
        if ($task.status -eq 'closed') {
            $strictEvidenceIsValid = Test-StructuredEvidence -Evidence $task.evidence -Root $Root -RequireProvenance -Historical
            $receiptAndProvenanceAreValid = Test-StructuredEvidence -Evidence $task.evidence -Root $Root -RequireProvenance -Historical -RetirementArtifactDrift
            if ($strictEvidenceIsValid -or -not $receiptAndProvenanceAreValid) {
                throw "Task '$retirementTaskId' already closed on evidence and cannot be retired."
            }
            $closedArtifactDriftTaskIds += $retirementTaskId
        }
        $tasks += $task
    }
    $retiredAt = Get-UtcTimestamp
    foreach ($task in $tasks) {
        $task.status = 'retired'
        $task['retired_reason'] = $Reason
        $task['retired_at'] = $retiredAt
    }
    Add-WorkScopeEvent -Root $Root -State $state -Type 'task_retired' -Data @{
        task_id = $TaskId
        related_task_ids = @($taskIds | Where-Object { $_ -ne $TaskId })
        reason = $Reason
        closed_artifact_drift = ($closedArtifactDriftTaskIds.Count -gt 0)
        closed_artifact_drift_task_ids = @($closedArtifactDriftTaskIds)
    } | Out-Null
    Sync-WorkScopeViews -Root $Root | Out-Null
    $results = @($taskIds | ForEach-Object { [pscustomobject]@{ task_id = $_; status = 'retired'; reason = $Reason } })
    if ($results.Count -eq 1) { return $results[0] }
    return $results
}

function Complete-WorkScopeTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [string]$TaskId,
        [Parameter(Mandatory)] [string[]]$Evidence
    )
    if (-not (Test-WorkScopeLockHeld -Root $Root)) {
        $arguments = Copy-WorkScopeBoundParameters -BoundParameters $PSBoundParameters
        return Invoke-WithWorkScopeLock -Root $Root -Action { Complete-WorkScopeTask @arguments }
    }
    $evidenceReceipts = @(Resolve-WorkScopeClosureEvidence -Evidence $Evidence -Root $Root -Context 'Task completion')
    $state = Read-WorkScopeState -Root $Root
    $task = $state.active.tasks | Where-Object { $_.id -eq $TaskId } | Select-Object -First 1
    if ($null -eq $task) {
        throw "Task '$TaskId' does not exist in the active cell."
    }
    Assert-WorkScopeTaskReceiptCoverage -Task $task -Receipts $evidenceReceipts -State $state -Context 'Task completion'
    Resolve-TaskStatuses -State $state
    if ($task.status -eq 'blocked') {
        throw "Task '$TaskId' is blocked by an open dependency."
    }
    $task.status = 'closed'
    $task.evidence = $evidenceReceipts
    $task.closed_at = Get-UtcTimestamp
    Resolve-TaskStatuses -State $state
    Add-WorkScopeEvent -Root $Root -State $state -Type 'task_completed' -Evidence $evidenceReceipts -Data @{ task_id = $TaskId } | Out-Null
    Sync-WorkScopeViews -Root $Root | Out-Null
    return $task
}

function Get-WorkScopeActiveSelection {
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [System.Collections.IDictionary]$State
    )
    $eventsPath = Join-Path ([System.IO.Path]::GetFullPath($Root)) '.agents\work\events.jsonl'
    $selection = @(
        Get-Content -LiteralPath $eventsPath |
            Where-Object { $_ } |
            ForEach-Object { $_ | ConvertFrom-Json -AsHashtable } |
            Where-Object {
                $_.type -eq 'frontier_item_selected' -and
                $_.track_id -eq $State.active.track_id -and
                $_.capability_id -eq $State.active.capability_id -and
                $_.cell_id -eq $State.active.cell_id
            }
    ) | Select-Object -Last 1
    if ($null -eq $selection -or [string]::IsNullOrWhiteSpace([string]$selection.data.backburner_id)) {
        return $null
    }
    $selected = $State.backburner |
        Where-Object { $_.id -eq [string]$selection.data.backburner_id } |
        Select-Object -First 1
    if ($null -eq $selected) {
        throw "Active selection '$($selection.data.backburner_id)' is missing from the discovery queue."
    }
    if ($selected.status -ne 'selected') {
        throw "Active selection '$($selected.id)' is '$($selected.status)' instead of selected."
    }
    return $selected
}

function Close-WorkScopeCell {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Root,
        [string[]]$Evidence = @()
    )
    if (-not (Test-WorkScopeLockHeld -Root $Root)) {
        $arguments = Copy-WorkScopeBoundParameters -BoundParameters $PSBoundParameters
        return Invoke-WithWorkScopeLock -Root $Root -Action { Close-WorkScopeCell @arguments }
    }
    $state = Read-WorkScopeState -Root $Root
    if (@($state.active.tasks).Count -eq 0) {
        throw 'Cannot close a scope cell without at least one materialized task.'
    }
    $open = @($state.active.tasks | Where-Object { $_.status -notin @('closed', 'retired') })
    if ($open.Count -gt 0) {
        throw "Cannot close scope cell while an open task remains: $($open.id -join ', ')."
    }
    $closedTasks = @($state.active.tasks | Where-Object { $_.status -eq 'closed' })
    if ($closedTasks.Count -eq 0) {
        throw 'Cannot close a scope cell whose every task was retired; at least one task must close on executed evidence.'
    }
    $evidenceReceipts = @(Resolve-WorkScopeClosureEvidence -Evidence $Evidence -Root $Root -Context 'Scope-cell completion' -Historical)
    $expectedReceiptIds = @(
        $closedTasks |
            ForEach-Object { @($_.evidence) } |
            ForEach-Object { $_.receipt_id } |
            Sort-Object
    )
    $providedReceiptIds = @($evidenceReceipts | ForEach-Object { $_.receipt_id } | Sort-Object)
    if (($expectedReceiptIds | ConvertTo-Json -Compress) -ne ($providedReceiptIds | ConvertTo-Json -Compress)) {
        throw 'Scope-cell completion evidence must be exactly the receipts already bound to its closed tasks.'
    }
    # Retirement preserves any historical task receipt and its event provenance, but that
    # receipt no longer proves the final artifact state. Active cell-completion evidence is
    # therefore exactly the still-closed tasks; demanding retired coverage would make an
    # authorized supersession impossible to finish.
    foreach ($task in $closedTasks) {
        $taskReceipts = @($evidenceReceipts | Where-Object { $_.task_id -eq $task.id })
        Assert-WorkScopeTaskReceiptCoverage -Task $task -Receipts $taskReceipts -State $state -Context 'Scope-cell completion'
    }
    $selectedDiscovery = Get-WorkScopeActiveSelection -Root $Root -State $state
    $capability = Get-StateCapability -State $state -TrackId $state.active.track_id -CapabilityId $state.active.capability_id
    $targetDepthRecovery = $null
    if ((ConvertTo-DepthIndex $state.active.depth) -gt (ConvertTo-DepthIndex $capability.target_depth) -and
        $null -ne $selectedDiscovery -and
        $selectedDiscovery.suggested_track -eq $state.active.track_id -and
        $selectedDiscovery.suggested_capability -eq $state.active.capability_id -and
        $selectedDiscovery.entry_depth -eq $state.active.depth -and
        ($null -eq $capability.current_depth -or
            (ConvertTo-DepthIndex $capability.current_depth) -le (ConvertTo-DepthIndex $state.active.depth))) {
        # A selector event ties this active cell to the discovery that opened it. Only that
        # provenance permits recovery: an arbitrary persisted current/target mismatch stays
        # invalid rather than being silently normalized at closure.
        $targetDepthRecovery = [ordered]@{
            previous_target_depth = $capability.target_depth
            recovered_target_depth = $state.active.depth
            recovered_capability_id = $capability.id
        }
        $capability.target_depth = $state.active.depth
    }
    if ($null -ne $selectedDiscovery) {
        $selectedDiscovery.status = 'closed'
        $selectedDiscovery.blockers = @()
    }
    $state.active.status = 'closed'
    $state.active.closed_at = Get-UtcTimestamp
    $state.active.evidence = $evidenceReceipts
    $capability.current_depth = $state.active.depth
    if ((ConvertTo-DepthIndex $state.active.depth) -ge (ConvertTo-DepthIndex $capability.target_depth)) {
        $capability.status = 'closed'
    }
    Add-WorkScopeEvent -Root $Root -State $state -Type 'scope_cell_closed' -Evidence $evidenceReceipts -Data @{
        backburner_ids = if ($null -eq $selectedDiscovery) { @() } else { @($selectedDiscovery.id) }
        target_depth_recovery = ($null -ne $targetDepthRecovery)
        previous_target_depth = if ($null -eq $targetDepthRecovery) { $null } else { $targetDepthRecovery.previous_target_depth }
        recovered_target_depth = if ($null -eq $targetDepthRecovery) { $null } else { $targetDepthRecovery.recovered_target_depth }
        recovered_capability_id = if ($null -eq $targetDepthRecovery) { $null } else { $targetDepthRecovery.recovered_capability_id }
    } | Out-Null
    Sync-WorkScopeViews -Root $Root | Out-Null
    return $state.active
}

function Block-WorkScopeCell {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [string]$Reason,
        [string[]]$Blockers = @()
    )
    if (-not (Test-WorkScopeLockHeld -Root $Root)) {
        $arguments = Copy-WorkScopeBoundParameters -BoundParameters $PSBoundParameters
        return Invoke-WithWorkScopeLock -Root $Root -Action { Block-WorkScopeCell @arguments }
    }
    $normalizedBlockers = @(
        ConvertTo-NormalizedArray $Blockers |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim() } |
            Sort-Object -Unique
    )
    if ([string]::IsNullOrWhiteSpace($Reason) -or $normalizedBlockers.Count -eq 0) {
        throw 'Blocking a scope cell requires a reason and at least one named blocker.'
    }
    $state = Read-WorkScopeState -Root $Root
    if ($state.active.status -ne 'active') {
        throw "Only an active scope cell can be blocked; '$($state.active.cell_id)' is '$($state.active.status)'."
    }
    $openTasks = @($state.active.tasks | Where-Object { $_.status -notin @('closed', 'retired') })
    if ($openTasks.Count -gt 0) {
        throw "Cannot block scope cell while an open task remains: $($openTasks.id -join ', ')."
    }

    $capability = Get-StateCapability -State $state -TrackId $state.active.track_id -CapabilityId $state.active.capability_id
    $capability.status = 'blocked'
    $capability.blockers = $normalizedBlockers
    $selectedDiscovery = Get-WorkScopeActiveSelection -Root $Root -State $state
    if ($null -ne $selectedDiscovery) {
        $selectedDiscovery.status = 'blocked'
        $selectedDiscovery.blockers = $normalizedBlockers
    }
    $state.active.status = 'blocked'
    Add-WorkScopeEvent -Root $Root -State $state -Type 'scope_cell_blocked' -Data @{
        reason = $Reason.Trim()
        blockers = $normalizedBlockers
        backburner_ids = if ($null -eq $selectedDiscovery) { @() } else { @($selectedDiscovery.id) }
    } | Out-Null
    Sync-WorkScopeViews -Root $Root | Out-Null
    return $state.active
}

function Set-WorkScopeOwnership {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [string]$SessionId,
        [Parameter(Mandatory)] [string[]]$Artifacts
    )
    if (-not (Test-WorkScopeLockHeld -Root $Root)) {
        $arguments = Copy-WorkScopeBoundParameters -BoundParameters $PSBoundParameters
        return Invoke-WithWorkScopeLock -Root $Root -Action { Set-WorkScopeOwnership @arguments }
    }
    $state = Read-WorkScopeState -Root $Root
    $session = $state.ownership.sessions | Where-Object { $_.session_id -eq $SessionId } | Select-Object -First 1
    $normalized = @($Artifacts | ForEach-Object { Resolve-WorkScopeArtifact -Root $Root -Artifact $_ })
    foreach ($artifact in $normalized) {
        foreach ($existingSession in @($state.ownership.sessions | Where-Object { $_.session_id -ne $SessionId })) {
            foreach ($existingArtifact in @($existingSession.artifacts)) {
                if (Test-WorkScopeArtifactOverlap -Left $existingArtifact -Right $artifact) {
                    throw "Artifact '$artifact' overlaps '$existingArtifact', owned by session '$($existingSession.session_id)'."
                }
            }
        }
    }
    if ($null -eq $session) {
        $session = [ordered]@{
            session_id = $SessionId
            track_id = $state.active.track_id
            capability_id = $state.active.capability_id
            artifacts = @()
        }
        $state.ownership.sessions = @($state.ownership.sessions) + @($session)
    }
    $session.track_id = $state.active.track_id
    $session.capability_id = $state.active.capability_id
    $session.artifacts = @(@($session.artifacts) + $normalized | Sort-Object -Unique)
    Add-WorkScopeEvent -Root $Root -State $state -Type 'ownership_updated' -Data @{
        session_id = $SessionId
        artifacts = $normalized
    } | Out-Null
    Sync-WorkScopeViews -Root $Root | Out-Null
    return $session
}

function Move-WorkScopeOwnership {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [string]$Artifact,
        [Parameter(Mandatory)] [string]$FromSession,
        [Parameter(Mandatory)] [string]$ToSession,
        [switch]$Confirmed
    )
    if (-not (Test-WorkScopeLockHeld -Root $Root)) {
        $arguments = Copy-WorkScopeBoundParameters -BoundParameters $PSBoundParameters
        return Invoke-WithWorkScopeLock -Root $Root -Action { Move-WorkScopeOwnership @arguments }
    }
    if (-not $Confirmed) {
        throw 'Ownership transfer is consequential; confirm it before applying.'
    }
    $state = Read-WorkScopeState -Root $Root
    $normalized = Resolve-WorkScopeArtifact -Root $Root -Artifact $Artifact
    $source = $state.ownership.sessions | Where-Object session_id -eq $FromSession | Select-Object -First 1
    if ($null -eq $source -or @($source.artifacts) -notcontains $normalized) {
        throw "Session '$FromSession' does not own '$normalized'."
    }
    foreach ($otherOwner in @($state.ownership.sessions | Where-Object { $_.session_id -notin @($FromSession, $ToSession) })) {
        foreach ($otherArtifact in @($otherOwner.artifacts)) {
            if (Test-WorkScopeArtifactOverlap -Left $otherArtifact -Right $normalized) {
                throw "Artifact '$normalized' overlaps '$otherArtifact', owned by session '$($otherOwner.session_id)'; resolve the collision first."
            }
        }
    }
    $target = $state.ownership.sessions | Where-Object session_id -eq $ToSession | Select-Object -First 1
    if ($null -eq $target) {
        $target = [ordered]@{
            session_id = $ToSession
            track_id = $source.track_id
            capability_id = $source.capability_id
            artifacts = @()
        }
        $state.ownership.sessions = @($state.ownership.sessions) + @($target)
    }
    $source.artifacts = @($source.artifacts | Where-Object { $_ -ne $normalized })
    $target.track_id = $source.track_id
    $target.capability_id = $source.capability_id
    $target.artifacts = @(@($target.artifacts) + $normalized | Sort-Object -Unique)
    Add-WorkScopeEvent -Root $Root -State $state -Type 'ownership_transferred' -Data @{
        artifact = $normalized
        from_session = $FromSession
        to_session = $ToSession
    } | Out-Null
    Sync-WorkScopeViews -Root $Root | Out-Null
    return [pscustomobject]@{ artifact = $normalized; from_session = $FromSession; to_session = $ToSession }
}

# The project's root INTENT.md is the one artifact the guard must not scope to a cell, because
# the contract defines it as the thing that outlives every cell: "a statement that would still
# govern after this project's current work ends is an intent clarification and goes to that
# project's INTENT.md". Scoping it to a cell inverted that. Once the active cell closed -- the
# ordinary state between two units, and the permanent state of a finished project -- every
# modify of INTENT.md returned cell_not_active, and citing no capability instead returned
# boundary_change, so the only sanctioned way to record a new binding intent was closed from
# both sides. Reproduced on a fixture 2026-08-08 with every capability closed: exit 2 either way.
# A finished project could never record another ruling.
#
# Deliberately exactly one path, matched at the project root only. A nested INTENT.md belongs to
# something else and is ordinary work product. Everything the exemption does not touch still
# applies: ownership collisions, artifacts outside the project, deletion, publication and
# credential access are all unchanged, so this widens what a cell may be, not what a session may do.
function Test-WorkScopeProjectIntentArtifact([string]$Normalized) {
    if ([string]::IsNullOrWhiteSpace($Normalized)) { return $false }
    return ($Normalized.Replace('\', '/') -ceq 'INTENT.md')
}

function Invoke-WorkScopeGuard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [string]$SessionId,
        [Parameter(Mandatory)] [ValidateSet('read', 'modify', 'create', 'delete', 'destructive_action', 'external_publish', 'credential_access')] [string]$ActionKind,
        [Parameter(Mandatory)] [string]$Artifact,
        [string]$ProjectId,
        [string]$TrackId,
        [Parameter(Mandatory)] [string]$CapabilityId
    )
    $state = Read-WorkScopeState -Root $Root
    $reasons = [System.Collections.Generic.List[string]]::new()
    $artifactOutsideProject = $false
    try {
        $normalized = Resolve-WorkScopeArtifact -Root $Root -Artifact $Artifact
    }
    catch {
        $artifactOutsideProject = $true
        $normalized = $Artifact
    }
    if ([string]::IsNullOrWhiteSpace($ProjectId)) {
        $ProjectId = $state.project.id
    }
    $matchingTracks = @($state.tracks | Where-Object {
        @($_.capabilities | Where-Object id -eq $CapabilityId).Count -gt 0
    })
    if ([string]::IsNullOrWhiteSpace($TrackId)) {
        if ($matchingTracks.Count -eq 1) {
            $TrackId = $matchingTracks[0].id
        }
        elseif ($CapabilityId -eq $state.active.capability_id) {
            $TrackId = $state.active.track_id
        }
    }
    $targetTrack = if ([string]::IsNullOrWhiteSpace($TrackId)) {
        $null
    }
    else {
        Get-StateTrack -State $state -TrackId $TrackId
    }
    $targetCapability = if ($null -ne $targetTrack) {
        Get-StateCapability -State $state -TrackId $TrackId -CapabilityId $CapabilityId
    } else { $null }
    if ($ActionKind -in @('delete', 'destructive_action')) {
        $reasons.Add('destructive_action')
    }
    if ($ActionKind -eq 'external_publish') {
        $reasons.Add('external_publish')
    }
    if ($ActionKind -eq 'credential_access') {
        $reasons.Add('missing_credential')
    }
    if ($artifactOutsideProject) {
        $reasons.Add('artifact_outside_project')
    }
    $projectIntentWrite = (-not $artifactOutsideProject) -and (Test-WorkScopeProjectIntentArtifact $normalized)
    if ($projectIntentWrite -and $ProjectId -eq $state.project.id) {
        # Project intent is not in a track, so there is no capability that would be the right one
        # to cite for it. Requiring one is what made "cite none" fail as boundary_change while
        # "cite the closed cell" failed as cell_not_active. Leaving the project is still a
        # boundary change, which is why this only holds inside it.
    }
    elseif ($ProjectId -ne $state.project.id -or $null -eq $targetTrack -or $null -eq $targetCapability) {
        $reasons.Add('boundary_change')
    }
    else {
        switch ($state.frontier.breadth_boundary) {
            'capability' {
                if ($TrackId -ne $state.active.track_id -or $CapabilityId -ne $state.active.capability_id) {
                    $reasons.Add('boundary_change')
                }
            }
            'track' {
                if ($TrackId -ne $state.active.track_id) {
                    $reasons.Add('boundary_change')
                }
            }
            'project' { }
            'portfolio' { }
            'system' { }
        }
    }
    if (-not $artifactOutsideProject) {
        foreach ($session in @($state.ownership.sessions)) {
            foreach ($ownedArtifact in @($session.artifacts)) {
                if (Test-WorkScopeArtifactOverlap -Left $ownedArtifact -Right $normalized) {
                    if ($session.session_id -ne $SessionId) {
                        $reasons.Add('ownership_collision')
                    }
                    # Not for project intent: the guard just declined to require a capability for
                    # it, so comparing the owner's against the caller's would refuse on a value it
                    # has already called meaningless. The collision check above still stands --
                    # two sessions writing INTENT.md at once is a real conflict.
                    if (-not $projectIntentWrite) {
                        if (($session.ContainsKey('track_id') -and $session.track_id -ne $TrackId) -or
                            ($session.ContainsKey('capability_id') -and $session.capability_id -ne $CapabilityId)) {
                            $reasons.Add('artifact_scope_mismatch')
                        }
                    }
                }
            }
        }
    }
    if ($state.active.status -ne 'active' -and $ActionKind -in @('modify', 'create') -and -not $projectIntentWrite) {
        $reasons.Add('cell_not_active')
    }
    return [pscustomobject]@{
        allowed = ($reasons.Count -eq 0)
        reasons = @($reasons | Sort-Object -Unique)
        active_cell = $state.active.cell_id
        action = $ActionKind
        artifact = $normalized
    }
}

function Set-WorkScopeProjectRemote {
    <#
        The deliberate, reviewed re-binding path. It is the only way `project.remote` is ever
        written, and it refuses every shortcut that would turn the location bind into a
        formality: it must run at a root where the state already validates on its own terms,
        so a relocated or copied state file cannot bind itself; the value is read from this
        checkout's own origin rather than accepted from an argument; and the change is
        committed through the same lock, event chain, and validation as any other mutation.
        `-Confirmed` is required because it widens where this state may legally be written.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Root,
        [switch]$Confirmed
    )
    if (-not (Test-WorkScopeLockHeld -Root $Root)) {
        $arguments = Copy-WorkScopeBoundParameters -BoundParameters $PSBoundParameters
        return Invoke-WithWorkScopeLock -Root $Root -Action { Set-WorkScopeProjectRemote @arguments }
    }
    if (-not $Confirmed) {
        throw 'Binding project.remote widens where this state may be written; confirm it deliberately.'
    }
    $validation = Test-WorkScopeState -Root $Root
    if (-not $validation.valid) {
        throw "Refusing to bind project.remote against invalid state: $($validation.errors -join '; ')"
    }
    $state = Read-WorkScopeState -Root $Root
    $paths = Get-WorkScopePaths -Root $Root
    $canonicalRoot = Get-WorkScopeCanonicalRoot -Root $paths.Root
    $declaredRoot = Get-WorkScopeCanonicalRoot -Root ([string]$state.project.root)
    $pathComparison = if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    if (-not $declaredRoot.Equals($canonicalRoot, $pathComparison)) {
        throw 'project.remote may only be bound from the canonical project.root, so a relocated copy cannot bind itself.'
    }
    $identity = Get-WorkScopeRepositoryIdentity -Root $paths.Root
    if ([string]::IsNullOrWhiteSpace($identity)) {
        throw "No git origin is readable at '$($paths.Root)', so there is no project identity to bind. A project with no remote by design keeps the location bind."
    }
    $before = if ($state.project.Contains('remote')) { [string]$state.project.remote } else { '' }
    if ($before -eq $identity) {
        return [pscustomobject]@{ changed = $false; remote = $identity }
    }
    $state.project['remote'] = $identity
    Add-WorkScopeEvent -Root $Root -State $state -Type 'project_remote_bound' -Data @{
        before = $before
        after = $identity
    } | Out-Null
    Sync-WorkScopeViews -Root $Root | Out-Null
    return [pscustomobject]@{ changed = $true; remote = $identity }
}

function Set-WorkScopeFrontier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [ValidateSet('drilldown', 'expand')] [string]$Mode,
        [Parameter(Mandatory)] [bool]$Automatic,
        [Parameter(Mandatory)] [ValidateSet('D0', 'D1', 'D2', 'D3', 'D4', 'D5')] [string]$DepthCeiling,
        [Parameter(Mandatory)] [ValidateSet('capability', 'track', 'project', 'portfolio', 'system')] [string]$BreadthBoundary,
        [Parameter(Mandatory)] [ValidateSet('dependency-first', 'highest-value', 'highest-risk', 'shortest-ready', 'balanced')] [string]$SelectionStrategy,
        # Read at frontier selection but written only at initialization, where it is hardcoded
        # true -- so a project could never turn independent-track handoff off, and the state
        # field advertised a setting nothing could set. Optional: omitted leaves it as it is.
        [Nullable[bool]]$HandoffIndependentTracks,
        [switch]$Confirmed
    )
    if (-not (Test-WorkScopeLockHeld -Root $Root)) {
        $arguments = Copy-WorkScopeBoundParameters -BoundParameters $PSBoundParameters
        return Invoke-WithWorkScopeLock -Root $Root -Action { Set-WorkScopeFrontier @arguments }
    }
    if (-not $Confirmed) {
        throw 'Frontier configuration is consequential; show the interpretation and confirm it before applying.'
    }
    $state = Read-WorkScopeState -Root $Root
    $before = [ordered]@{
        mode = $state.frontier.mode
        automatic = $state.frontier.automatic
        depth_ceiling = $state.frontier.depth_ceiling
        breadth_boundary = $state.frontier.breadth_boundary
        selection_strategy = $state.frontier.selection_strategy
        handoff_independent_tracks = $state.frontier.handoff_independent_tracks
    }
    $state.frontier.mode = $Mode
    $state.frontier.automatic = $Automatic
    $state.frontier.depth_ceiling = $DepthCeiling
    $state.frontier.breadth_boundary = $BreadthBoundary
    $state.frontier.selection_strategy = $SelectionStrategy
    if ($null -ne $HandoffIndependentTracks) {
        $state.frontier.handoff_independent_tracks = [bool]$HandoffIndependentTracks
    }
    Add-WorkScopeEvent -Root $Root -State $state -Type 'frontier_configured' -Data @{
        before = $before
        after = [ordered]@{
            mode = $Mode
            automatic = $Automatic
            depth_ceiling = $DepthCeiling
            breadth_boundary = $BreadthBoundary
            selection_strategy = $SelectionStrategy
            handoff_independent_tracks = $state.frontier.handoff_independent_tracks
        }
    } | Out-Null
    Sync-WorkScopeViews -Root $Root | Out-Null
    return $state.frontier
}

function Add-WorkScopeDiscovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [string]$Title,
        [Parameter(Mandatory)] [string]$SuggestedTrack,
        [Parameter(Mandatory)] [string]$SuggestedCapability,
        [Parameter(Mandatory)] [ValidateSet('D0', 'D1', 'D2', 'D3', 'D4', 'D5')] [string]$EntryDepth,
        [Parameter(Mandatory)] [string]$DiscoveredFrom,
        [Parameter(Mandatory)] [ValidateSet('adjacent', 'prerequisite', 'follow-up', 'defect', 'opportunity')] [string]$Relationship,
        [string[]]$Dependencies = @(),
        [string[]]$Blockers = @(),
        [string[]]$Conflicts = @(),
        [Parameter(Mandatory)] [ValidateSet('low', 'medium', 'high')] [string]$Value,
        [Parameter(Mandatory)] [ValidateSet('low', 'medium', 'high')] [string]$Risk,
        [Parameter(Mandatory)] [string[]]$Evidence
    )
    if (-not (Test-WorkScopeLockHeld -Root $Root)) {
        $arguments = Copy-WorkScopeBoundParameters -BoundParameters $PSBoundParameters
        return Invoke-WithWorkScopeLock -Root $Root -Action { Add-WorkScopeDiscovery @arguments }
    }
    Assert-SafeWorkScopeId -Id $Id -Label 'Backburner id'
    Assert-SafeWorkScopeId -Id $SuggestedTrack -Label 'Suggested track id'
    Assert-SafeWorkScopeId -Id $SuggestedCapability -Label 'Suggested capability id'
    $evidenceReceipts = @(ConvertTo-WorkScopeEvidenceReceipts -Evidence $Evidence -Root $Root -Context 'Discovery capture')
    $state = Read-WorkScopeState -Root $Root
    if (@($state.backburner | Where-Object { $_.id -eq $Id }).Count -gt 0) {
        throw "Backburner item '$Id' already exists."
    }
    $dependencyList = @(ConvertTo-NormalizedArray $Dependencies)
    $blockerList = @(ConvertTo-NormalizedArray $Blockers)
    $item = [ordered]@{
        id = $Id
        title = $Title
        project = $state.project.id
        suggested_track = $SuggestedTrack
        suggested_capability = $SuggestedCapability
        entry_depth = $EntryDepth
        discovered_from = $DiscoveredFrom
        relationship = $Relationship
        dependencies = $dependencyList
        blockers = $blockerList
        conflicts = @(ConvertTo-NormalizedArray $Conflicts)
        value = $Value
        risk = $Risk
        evidence = $evidenceReceipts
        status = if ($dependencyList.Count -gt 0 -or $blockerList.Count -gt 0 -or @(ConvertTo-NormalizedArray $Conflicts).Count -gt 0) { 'blocked' } else { 'ready' }
        captured_at = Get-UtcTimestamp
    }
    $state.backburner = @($state.backburner) + @($item)
    $state.active.discoveries = @($state.active.discoveries) + @($Id)
    Add-WorkScopeEvent -Root $Root -State $state -Type 'discovery_captured' -Evidence $evidenceReceipts -Data @{ backburner_id = $Id } | Out-Null
    Sync-WorkScopeViews -Root $Root | Out-Null
    return $item
}

function Set-WorkScopeDiscoveryStatus {
    <# The backburner had capture but no disposition: an item that became stale or was
       overtaken by other work could only be edited by hand, which the contract forbids.
       This is the guarded retirement path — same lock, same evidence gate, same event
       chain as capture. It refuses to touch an item already selected into active work,
       because that item's fate belongs to its scope cell. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [ValidateSet('ready', 'blocked', 'closed', 'rejected')] [string]$Status,
        [Parameter(Mandatory)] [string]$Reason,
        [Parameter(Mandatory)] [string[]]$Evidence,
        # What a blocked item is waiting on -- a prerequisite discovery id, a task id, or an
        # open decision id from the owning project's Open Decisions document. Reason alone
        # cannot carry this: it goes to the event log and never lands on the item, so before
        # 2026-08-08 there was no guarded way to record why an item was blocked, while
        # Test-TaskStateFormat.ps1 required exactly that record. The gate demanded a field the
        # only legal writer could not set, and hand-editing the state file is forbidden.
        [string[]]$Blockers = @()
    )
    if (-not (Test-WorkScopeLockHeld -Root $Root)) {
        $arguments = Copy-WorkScopeBoundParameters -BoundParameters $PSBoundParameters
        return Invoke-WithWorkScopeLock -Root $Root -Action { Set-WorkScopeDiscoveryStatus @arguments }
    }
    Assert-SafeWorkScopeId -Id $Id -Label 'Backburner id'
    if ([string]::IsNullOrWhiteSpace($Reason)) {
        throw 'Discovery disposition requires a reason.'
    }
    $evidenceReceipts = @(ConvertTo-WorkScopeEvidenceReceipts -Evidence $Evidence -Root $Root -Context 'Discovery disposition')
    $state = Read-WorkScopeState -Root $Root
    $matches = @($state.backburner | Where-Object { $_.id -eq $Id })
    if ($matches.Count -ne 1) {
        throw "Backburner item '$Id' does not exist."
    }
    $item = $matches[0]
    $previousStatus = [string]$item.status
    if ($previousStatus -eq 'selected') {
        throw "Backburner item '$Id' is selected into active work; close its scope cell instead of disposing of the discovery."
    }
    if ($previousStatus -eq $Status) {
        throw "Backburner item '$Id' is already '$Status'."
    }
    $cleanBlockers = @($Blockers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { ([string]$_).Trim() })
    if ($cleanBlockers.Count -gt 0 -and $Status -ne 'blocked') {
        throw "Blockers are only meaningful on a blocked item; '$Id' is being set to '$Status'."
    }
    if ($Status -eq 'blocked' -and $cleanBlockers.Count -eq 0 -and @($item.blockers).Count -eq 0 -and @($item.dependencies).Count -eq 0) {
        throw "Blocking '$Id' requires -Blockers naming what it waits on: a prerequisite id, or an open decision id from the owning project's Open Decisions document."
    }
    $item.status = $Status
    if ($cleanBlockers.Count -gt 0) {
        $item.blockers = $cleanBlockers
    }
    elseif ($Status -ne 'blocked') {
        # A status change regenerates the record in place rather than leaving a stale reason
        # beside a new status -- the contract's rule that task state never accumulates
        # parallel sections telling different stories about the same item.
        $item.blockers = @()
    }
    $resumedCapabilityId = $null
    if ($previousStatus -eq 'blocked' -and $Status -eq 'ready') {
        $resumeTrack = Get-StateTrack -State $state -TrackId $item.suggested_track
        $resumeCapability = if ($null -ne $resumeTrack) {
            Get-StateCapability -State $state -TrackId $item.suggested_track -CapabilityId $item.suggested_capability
        } else { $null }
        if ($null -ne $resumeCapability -and $resumeCapability.status -eq 'blocked') {
            # The guarded blocked -> ready disposition is the explicit assertion that this
            # discovery's prerequisite has resolved. The capability was parked with the same
            # work item, so clear its stale blocker at the same transition; otherwise the
            # selector immediately re-blocks the discovery and there is no supported resume.
            $resumeCapability.status = 'active'
            $resumeCapability.blockers = @()
            $resumedCapabilityId = $resumeCapability.id
        }
    }
    $item.evidence = @($item.evidence) + $evidenceReceipts
    Add-WorkScopeEvent -Root $Root -State $state -Type 'discovery_disposition' -Evidence $evidenceReceipts -Data @{
        backburner_id = $Id
        previous_status = $previousStatus
        status = $Status
        reason = $Reason
        blockers = $cleanBlockers
        resumed_capability_id = $resumedCapabilityId
    } | Out-Null
    Sync-WorkScopeViews -Root $Root | Out-Null
    return $item
}

function Get-WorkScopeOptionalMember {
    # State reaches the view renderer as a hashtable on one path and as PSCustomObject-shaped JSON
    # on another, and StrictMode makes a missing property a terminating error rather than $null --
    # so reading a field that older state files simply do not have has to ask both shapes whether
    # it exists. Every item captured before corrections existed is exactly that case.
    param($Item, [Parameter(Mandatory)] [string]$Name)
    if ($null -eq $Item) { return @() }
    if ($Item -is [System.Collections.IDictionary]) {
        if (-not $Item.Contains($Name)) { return @() }
        return @($Item[$Name] | Where-Object { $_ })
    }
    $property = $Item.PSObject.Properties[$Name]
    if (-not $property) { return @() }
    return @($property.Value | Where-Object { $_ })
}

function Get-WorkScopeMemberPairs {
    param($Item)
    if ($null -eq $Item) { return @() }
    if ($Item -is [System.Collections.IDictionary]) {
        return @($Item.Keys | ForEach-Object { [pscustomobject]@{ Name = $_; Value = $Item[$_] } })
    }
    return @($Item.PSObject.Properties | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Value = $_.Value } })
}

function Add-WorkScopeDiscoveryCorrection {
    <# Capture and disposition were the only two things a discovery could receive, so a finding
       whose facts decayed had exactly one route: close it and recapture it under a new id, which
       loses the thread between the two records. A closed item had no route at all --
       Set-WorkScopeDiscoveryStatus refuses a repeat of the status it already holds, so a wrong
       fact in a closure reason was permanent and the correction ended up living outside the state
       file, which is the one place the contract says it must not live.

       This is deliberately not a second status writer. It never touches status, so retirement
       keeps exactly one owner; what it changes is the descriptive record, and it always appends
       the correction rather than overwriting silently -- the previous value of every field it
       touches is kept on the item. Legal on a closed or rejected item, which is the whole point.
       Refused on a selected one, for the same reason disposition is: that item's fate belongs to
       its scope cell. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [string]$Id,
        # What is being corrected and why. This is the correcting entry itself, not a note about
        # one, so it goes onto the item as well as into the event.
        [Parameter(Mandatory)] [string]$Reason,
        [Parameter(Mandatory)] [string[]]$Evidence,
        [string]$Title,
        [ValidateSet('low', 'medium', 'high')] [string]$Value,
        [ValidateSet('low', 'medium', 'high')] [string]$Risk
    )
    if (-not (Test-WorkScopeLockHeld -Root $Root)) {
        $arguments = Copy-WorkScopeBoundParameters -BoundParameters $PSBoundParameters
        return Invoke-WithWorkScopeLock -Root $Root -Action { Add-WorkScopeDiscoveryCorrection @arguments }
    }
    Assert-SafeWorkScopeId -Id $Id -Label 'Backburner id'
    if ([string]::IsNullOrWhiteSpace($Reason)) {
        throw 'Discovery correction requires a reason.'
    }
    $evidenceReceipts = @(ConvertTo-WorkScopeEvidenceReceipts -Evidence $Evidence -Root $Root -Context 'Discovery correction')
    $state = Read-WorkScopeState -Root $Root
    $matches = @($state.backburner | Where-Object { $_.id -eq $Id })
    if ($matches.Count -ne 1) {
        throw "Backburner item '$Id' does not exist."
    }
    $item = $matches[0]
    if ([string]$item.status -eq 'selected') {
        throw "Backburner item '$Id' is selected into active work; correct it through its scope cell."
    }
    $changed = [ordered]@{}
    if ($PSBoundParameters.ContainsKey('Title')) {
        if ([string]::IsNullOrWhiteSpace($Title)) { throw 'A corrected title cannot be empty.' }
        if ([string]$item.title -cne $Title) { $changed['title'] = [string]$item.title }
    }
    if ($PSBoundParameters.ContainsKey('Value') -and [string]$item.value -cne $Value) {
        $changed['value'] = [string]$item.value
    }
    if ($PSBoundParameters.ContainsKey('Risk') -and [string]$item.risk -cne $Risk) {
        $changed['risk'] = [string]$item.risk
    }
    $correction = [ordered]@{
        corrected_at = Get-UtcTimestamp
        reason = $Reason.Trim()
        previous = $changed
    }
    if ($changed.Contains('title')) { $item.title = $Title }
    if ($changed.Contains('value')) { $item.value = $Value }
    if ($changed.Contains('risk')) { $item.risk = $Risk }
    $item.corrections = @(Get-WorkScopeOptionalMember -Item $item -Name 'corrections') + @($correction)
    $item.evidence = @($item.evidence) + $evidenceReceipts
    Add-WorkScopeEvent -Root $Root -State $state -Type 'discovery_corrected' -Evidence $evidenceReceipts -Data @{
        backburner_id = $Id
        status = [string]$item.status
        reason = $Reason.Trim()
        corrected_fields = @($changed.Keys)
        previous = $changed
    } | Out-Null
    Sync-WorkScopeViews -Root $Root | Out-Null
    return $item
}

function Find-WorkScopeLegacyArchiveSource {
    # Enrollment archives the authored task files into .agents\work\legacy-task-state-<timestamp>\
    # before the first generated view overwrites them. A project that enrolled without importing
    # therefore has its only surviving copy there, and no import event will ever name it -- that is
    # the exact state this lookup recovers from. The hash is the binding, as it is for an imports\
    # snapshot: a file is accepted only when its SHA-256 equals the one the record declares, so an
    # archive edited since enrollment is refused rather than trusted.
    param(
        [Parameter(Mandatory)] [string]$WorkRoot,
        [Parameter(Mandatory)] [string]$SourceName,
        [Parameter(Mandatory)] [string]$Sha256
    )
    if (-not (Test-Path -LiteralPath $WorkRoot -PathType Container)) { return $null }
    foreach ($archiveDirectory in @(
        Get-ChildItem -LiteralPath $WorkRoot -Directory -Force |
            Where-Object { $_.Name -like 'legacy-task-state-*' } |
            Sort-Object -Property Name -Descending
    )) {
        $candidate = Join-Path $archiveDirectory.FullName $SourceName
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        if ((Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Sha256.ToLowerInvariant()) { continue }
        return $candidate
    }
    return $null
}

function Import-WorkScopeLegacyRecords {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [object[]]$Records
    )
    if (-not (Test-WorkScopeLockHeld -Root $Root)) {
        $arguments = Copy-WorkScopeBoundParameters -BoundParameters $PSBoundParameters
        return Invoke-WithWorkScopeLock -Root $Root -Action { Import-WorkScopeLegacyRecords @arguments }
    }

    $paths = Get-WorkScopePaths -Root $Root
    if (-not (Test-Path -LiteralPath $paths.State -PathType Leaf)) {
        throw "Work Scope legacy import requires enrollment at '$($paths.State)'."
    }
    $authoritativeValidation = Test-WorkScopeState -Root $Root
    if (-not $authoritativeValidation.valid) {
        throw "Authoritative state or event chain is invalid before legacy import: $($authoritativeValidation.errors -join '; ')"
    }
    $state = Read-WorkScopeState -Root $Root
    $legacyImportEvents = @()
    if (Test-Path -LiteralPath $paths.Events) {
        $legacyImportEvents = @(
            Get-Content -LiteralPath $paths.Events |
                Where-Object { $_ } |
                ForEach-Object { $_ | ConvertFrom-Json -AsHashtable } |
                Where-Object { $_.type -eq 'legacy_records_imported' }
        )
    }
    $normalized = [System.Collections.Generic.List[object]]::new()
    $incomingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $sourceFacts = @{}

    foreach ($inputRecord in @($Records)) {
        $record = if ($inputRecord -is [System.Collections.IDictionary]) {
            $inputRecord
        }
        else {
            $inputRecord | ConvertTo-Json -Depth 30 | ConvertFrom-Json -AsHashtable
        }
        foreach ($required in @(
            'id', 'title', 'status', 'source_path', 'source_sha256',
            'source_line', 'original_marker', 'markdown_block', 'blockers'
        )) {
            if (-not $record.Contains($required)) {
                throw "Legacy import record is missing '$required'."
            }
        }
        $id = [string]$record.id
        Assert-SafeWorkScopeId -Id $id -Label 'Legacy record id'
        if (-not $incomingIds.Add($id)) {
            throw "Legacy import contains duplicate id '$id'."
        }
        $sourcePath = Resolve-WorkScopeArtifact -Root $paths.Root -Artifact ([string]$record.source_path)
        $sourceName = [System.IO.Path]::GetFileName($sourcePath)
        if ($sourceName -cnotin @('TASK.md', 'BACKBURNER.md') -or
            $sourcePath -cne $sourceName) {
            throw "Legacy import source '$sourcePath' must be the project-root TASK.md or BACKBURNER.md."
        }
        $sourceLine = [int64]$record.source_line
        if ($sourceLine -lt 1) {
            throw "Legacy record '$id' has invalid source line '$sourceLine'."
        }
        $expectedId = if ($sourceName -ceq 'TASK.md') {
            "legacy-task-L$sourceLine"
        }
        else {
            "legacy-backburner-L$sourceLine"
        }
        if ($id -cne $expectedId) {
            throw "Legacy record id '$id' is not the deterministic line id '$expectedId'."
        }
        $sourceSha = ([string]$record.source_sha256).ToLowerInvariant()
        if ($sourceSha -notmatch '^[a-f0-9]{64}$') {
            throw "Legacy record '$id' has an invalid source SHA-256."
        }
        $rootSourcePath = Join-Path $paths.Root $sourcePath
        if (-not (Test-Path -LiteralPath $rootSourcePath -PathType Leaf)) {
            throw "Legacy import source '$sourcePath' does not exist."
        }
        $absoluteSourcePath = $rootSourcePath
        $actualSourceSha = (Get-FileHash -LiteralPath $absoluteSourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualSourceSha -cne $sourceSha) {
            $rootSourceContent = [System.IO.File]::ReadAllText($rootSourcePath)
            $isGeneratedView = $rootSourceContent -match '^<!-- GENERATED FROM \.agents/work/(?:state\.json|events\.jsonl)\. DO NOT EDIT DIRECTLY\. -->'
            if (-not $isGeneratedView) {
                throw "Legacy import source '$sourcePath' changed after parsing."
            }
            $matchingSources = @(
                foreach ($legacyEvent in $legacyImportEvents) {
                    foreach ($priorSource in @($legacyEvent.data.sources)) {
                        if ([string]$priorSource.source_path -ceq $sourcePath -and
                            ([string]$priorSource.source_sha256).ToLowerInvariant() -ceq $sourceSha) {
                            $priorSource
                        }
                    }
                }
            )
            $snapshotReferences = @($matchingSources | ForEach-Object { [string]$_.snapshot_reference } | Sort-Object -Unique)
            $archiveSourcePath = $null
            if ($snapshotReferences.Count -eq 0) {
                $archiveSourcePath = Find-WorkScopeLegacyArchiveSource -WorkRoot $paths.WorkRoot -SourceName $sourceName -Sha256 $sourceSha
            }
            if ($archiveSourcePath) {
                $absoluteSourcePath = $archiveSourcePath
                $actualSourceSha = (Get-FileHash -LiteralPath $absoluteSourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($actualSourceSha -cne $sourceSha) {
                    throw "Legacy enrollment archive for '$sourcePath' changed while being read."
                }
            }
            else {
                if ($snapshotReferences.Count -ne 1) {
                    throw "Generated legacy view '$sourcePath' has no unique immutable import snapshot for SHA-256 '$sourceSha'."
                }
                $snapshotReferenceFromHistory = Resolve-WorkScopeArtifact -Root $paths.Root -Artifact $snapshotReferences[0]
                $expectedSnapshotName = "legacy-$([System.IO.Path]::GetFileNameWithoutExtension($sourceName)).$sourceSha.md"
                $expectedSnapshotReference = ".agents/work/imports/$expectedSnapshotName"
                if ($snapshotReferenceFromHistory -cne $expectedSnapshotReference) {
                    throw "Generated legacy view '$sourcePath' has invalid immutable snapshot provenance."
                }
                $absoluteSourcePath = Join-Path $paths.Root $snapshotReferenceFromHistory
                if (-not (Test-Path -LiteralPath $absoluteSourcePath -PathType Leaf)) {
                    throw "Legacy snapshot '$snapshotReferenceFromHistory' is missing for generated view '$sourcePath'."
                }
                $actualSourceSha = (Get-FileHash -LiteralPath $absoluteSourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($actualSourceSha -cne $sourceSha) {
                    throw "Legacy snapshot '$snapshotReferenceFromHistory' changed after import."
                }
            }
        }
        $sourceContent = [System.IO.File]::ReadAllText($absoluteSourcePath)
        $sourceLines = [regex]::Split($sourceContent, '\r?\n')
        if ($sourceLine -gt $sourceLines.Count) {
            throw "Legacy record '$id' points past the end of '$sourcePath'."
        }
        $lineIndex = [int]$sourceLine - 1
        $linePattern = if ($sourceName -ceq 'TASK.md') {
            '^(?:[-*+]|\d+[.)])\s+\[([ xX~!?])\]\s+(.+?)\s*$'
        }
        else {
            '^[-*+]\s+(.+?)\s*$'
        }
        $lineMatch = [regex]::Match($sourceLines[$lineIndex], $linePattern)
        if (-not $lineMatch.Success) {
            throw "Legacy record '$id' does not point to a top-level legacy item."
        }
        $expectedMarker = if ($sourceName -ceq 'TASK.md') {
            $lineMatch.Groups[1].Value.ToLowerInvariant()
        }
        else {
            $sourceLines[$lineIndex].Substring(0, 1)
        }
        $expectedTitle = if ($sourceName -ceq 'TASK.md') {
            $lineMatch.Groups[2].Value.Trim()
        }
        else {
            $lineMatch.Groups[1].Value.Trim()
        }
        if ([string]$record.original_marker -cne $expectedMarker -or
            [string]$record.title -cne $expectedTitle) {
            throw "Legacy record '$id' marker or title disagrees with '$sourcePath'."
        }
        $blockEnd = $lineIndex + 1
        while ($blockEnd -lt $sourceLines.Count) {
            $candidate = $sourceLines[$blockEnd]
            $isNextItem = if ($sourceName -ceq 'TASK.md') {
                $candidate -match '^(?:[-*+]|\d+[.)])\s+'
            }
            else {
                $candidate -match '^[-*+]\s+'
            }
            if ($isNextItem -or $candidate -match '^#{1,6}\s+') { break }
            $blockEnd++
        }
        $blockLines = @($sourceLines[$lineIndex..($blockEnd - 1)])
        while ($blockLines.Count -gt 1 -and [string]::IsNullOrWhiteSpace($blockLines[-1])) {
            $blockLines = @($blockLines[0..($blockLines.Count - 2)])
        }
        $expectedBlock = $blockLines -join "`n"
        if ([string]$record.markdown_block -cne $expectedBlock) {
            throw "Legacy record '$id' does not preserve its complete Markdown block."
        }

        $expectedStatus = 'ready'
        $expectedBlockers = @()
        if ($sourceName -ceq 'TASK.md') {
            switch ($expectedMarker) {
                'x' { $expectedStatus = 'closed' }
                ' ' { $expectedStatus = 'ready' }
                '~' {
                    $expectedStatus = 'blocked'
                    $expectedBlockers = @('Legacy [~] item requires explicit reconfirmation before promotion.')
                }
                '!' {
                    $expectedStatus = 'blocked'
                    $expectedBlockers = @('Legacy [!] item remains explicitly blocked.')
                }
                '?' {
                    $expectedStatus = 'blocked'
                    $expectedBlockers = @('Legacy [?] item requires a decision before promotion.')
                }
            }
        }
        $actualBlockers = @($record.blockers)
        if ([string]$record.status -cne $expectedStatus -or
            ($actualBlockers | ConvertTo-Json -Compress) -cne ($expectedBlockers | ConvertTo-Json -Compress)) {
            throw "Legacy record '$id' has an invalid marker-to-status mapping."
        }
        $snapshotName = "legacy-$([System.IO.Path]::GetFileNameWithoutExtension($sourceName)).$sourceSha.md"
        $snapshotReference = ".agents\work\imports\$snapshotName"
        $snapshotPath = Join-Path $paths.Root $snapshotReference
        $sourceItem = Get-Item -LiteralPath $absoluteSourcePath -Force
        if ($sourceFacts.ContainsKey($sourcePath)) {
            if ($sourceFacts[$sourcePath].source_sha256 -cne $sourceSha) {
                throw "Legacy import source '$sourcePath' has conflicting hashes."
            }
        }
        else {
            $sourceFacts[$sourcePath] = [ordered]@{
                source_path = $sourcePath
                source_sha256 = $sourceSha
                source_size_bytes = [int64]$sourceItem.Length
                absolute_source_path = $absoluteSourcePath
                snapshot_reference = $snapshotReference
                snapshot_path = $snapshotPath
            }
        }
        $normalized.Add([ordered]@{
            id = $id
            title = $expectedTitle
            status = $expectedStatus
            source_path = $sourcePath
            source_sha256 = $sourceSha
            source_line = $sourceLine
            original_marker = $expectedMarker
            markdown_block = $expectedBlock
            blockers = $expectedBlockers
        })
    }

    $priorRecords = @{}
    if (Test-Path -LiteralPath $paths.Events) {
        foreach ($event in $legacyImportEvents) {
            foreach ($priorRecord in @($event.data.records)) {
                $priorId = [string]$priorRecord.id
                $matchingReceipts = @($event.evidence | Where-Object { $_.subject -eq $priorId })
                if ($matchingReceipts.Count -ne 1) {
                    throw "Legacy provenance collision: event history has no exact receipt for '$priorId'."
                }
                $prior = [ordered]@{
                    record_json = ConvertTo-WorkScopeCanonicalValue -Value $priorRecord | ConvertTo-Json -Depth 30 -Compress
                    project_id = [string]$event.project_id
                    track_id = [string]$event.track_id
                    capability_id = [string]$event.capability_id
                    receipt = $matchingReceipts[0]
                }
                $priorJson = ConvertTo-WorkScopeCanonicalValue -Value $prior | ConvertTo-Json -Depth 30 -Compress
                if ($priorRecords.ContainsKey($priorId) -and $priorRecords[$priorId].canonical_json -cne $priorJson) {
                    throw "Legacy provenance collision: event history disagrees for '$priorId'."
                }
                $prior.canonical_json = $priorJson
                $priorRecords[$priorId] = $prior
            }
        }
    }
    $existingItems = @{}
    foreach ($existingItem in @($state.backburner)) {
        $existingItems[[string]$existingItem.id] = $existingItem
    }
    $newRecords = [System.Collections.Generic.List[object]]::new()
    $alreadyPresent = 0
    foreach ($record in $normalized) {
        $recordJson = ConvertTo-WorkScopeCanonicalValue -Value $record | ConvertTo-Json -Depth 30 -Compress
        $hasStateItem = $existingItems.ContainsKey($record.id)
        $hasPriorRecord = $priorRecords.ContainsKey($record.id)
        if ($hasStateItem -or $hasPriorRecord) {
            if (-not $hasStateItem -or -not $hasPriorRecord -or $priorRecords[$record.id].record_json -cne $recordJson) {
                throw "Legacy provenance collision for '$($record.id)'."
            }
            $existing = $existingItems[$record.id]
            $prior = $priorRecords[$record.id]
            $expectedItem = [ordered]@{
                id = $record.id
                title = $record.title
                project = $prior.project_id
                suggested_track = $prior.track_id
                suggested_capability = $prior.capability_id
                entry_depth = 'D0'
                discovered_from = "$($record.source_path):L$($record.source_line)"
                relationship = 'follow-up'
                dependencies = @()
                blockers = @($record.blockers)
                conflicts = @()
                value = 'low'
                risk = 'low'
                evidence = @($prior.receipt)
                status = $record.status
            }
            $actualItem = [ordered]@{
                id = $existing.id
                title = $existing.title
                project = $existing.project
                suggested_track = $existing.suggested_track
                suggested_capability = $existing.suggested_capability
                entry_depth = $existing.entry_depth
                discovered_from = $existing.discovered_from
                relationship = $existing.relationship
                dependencies = @($existing.dependencies)
                blockers = @($existing.blockers)
                conflicts = @($existing.conflicts)
                value = $existing.value
                risk = $existing.risk
                evidence = @($existing.evidence)
                status = $existing.status
            }
            $expectedItemJson = ConvertTo-WorkScopeCanonicalValue -Value $expectedItem | ConvertTo-Json -Depth 30 -Compress
            $actualItemJson = ConvertTo-WorkScopeCanonicalValue -Value $actualItem | ConvertTo-Json -Depth 30 -Compress
            if ($actualItemJson -cne $expectedItemJson) {
                throw "Legacy provenance collision for '$($record.id)'."
            }
            $alreadyPresent++
            continue
        }
        $newRecords.Add($record)
    }

    foreach ($source in $sourceFacts.Values) {
        if (Test-Path -LiteralPath $source.snapshot_path -PathType Leaf) {
            $snapshotItem = Get-Item -LiteralPath $source.snapshot_path -Force
            $snapshotHash = (Get-FileHash -LiteralPath $source.snapshot_path -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($snapshotHash -cne $source.source_sha256 -or
                [int64]$snapshotItem.Length -ne [int64]$source.source_size_bytes) {
                throw "Legacy snapshot collision at '$($source.snapshot_reference)'."
            }
        }
        elseif ($newRecords.Count -eq 0) {
            throw "Legacy snapshot '$($source.snapshot_reference)' is missing for an existing import."
        }
    }
    if ($newRecords.Count -eq 0) {
        return [pscustomobject]@{
            Imported = 0
            AlreadyPresent = $alreadyPresent
            EventId = $null
            Snapshots = @($sourceFacts.Values | ForEach-Object { $_.snapshot_reference })
        }
    }
    if (-not $PSCmdlet.ShouldProcess($paths.WorkRoot, "Import $($newRecords.Count) legacy task records")) {
        return [pscustomobject]@{
            Imported = 0
            AlreadyPresent = $alreadyPresent
            Planned = $newRecords.Count
            EventId = $null
            Snapshots = @()
        }
    }

    $importsRoot = Join-Path $paths.WorkRoot 'imports'
    $createdSnapshots = [System.Collections.Generic.List[string]]::new()
    $temporarySnapshots = [System.Collections.Generic.List[string]]::new()
    try {
        if (-not (Test-Path -LiteralPath $importsRoot)) {
            New-Item -ItemType Directory -Path $importsRoot -Force | Out-Null
        }
        foreach ($staleTemporary in @(Get-ChildItem -LiteralPath $importsRoot -File -Filter '.legacy-*.tmp' -Force)) {
            Remove-Item -LiteralPath $staleTemporary.FullName -Force
        }
        foreach ($source in $sourceFacts.Values) {
            if (-not (Test-Path -LiteralPath $source.snapshot_path)) {
                $snapshotName = [System.IO.Path]::GetFileName($source.snapshot_path)
                $temporarySnapshot = Join-Path $importsRoot ".$snapshotName.$([guid]::NewGuid().ToString('N')).tmp"
                $temporarySnapshots.Add($temporarySnapshot)
                Copy-Item -LiteralPath $source.absolute_source_path -Destination $temporarySnapshot
                $temporaryItem = Get-Item -LiteralPath $temporarySnapshot -Force
                $temporaryHash = (Get-FileHash -LiteralPath $temporarySnapshot -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($temporaryHash -cne $source.source_sha256 -or
                    [int64]$temporaryItem.Length -ne [int64]$source.source_size_bytes) {
                    throw "Legacy temporary snapshot verification failed for '$($source.snapshot_reference)'."
                }
                if (Test-Path -LiteralPath $source.snapshot_path) {
                    $existingItem = Get-Item -LiteralPath $source.snapshot_path -Force
                    $existingHash = (Get-FileHash -LiteralPath $source.snapshot_path -Algorithm SHA256).Hash.ToLowerInvariant()
                    if ($existingHash -cne $source.source_sha256 -or
                        [int64]$existingItem.Length -ne [int64]$source.source_size_bytes) {
                        throw "Legacy snapshot collision at '$($source.snapshot_reference)'."
                    }
                    Remove-Item -LiteralPath $temporarySnapshot -Force
                }
                else {
                    Move-Item -LiteralPath $temporarySnapshot -Destination $source.snapshot_path
                    $createdSnapshots.Add($source.snapshot_path)
                }
                $temporarySnapshots.Remove($temporarySnapshot) | Out-Null
            }
            $snapshotItem = Get-Item -LiteralPath $source.snapshot_path -Force
            $snapshotHash = (Get-FileHash -LiteralPath $source.snapshot_path -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($snapshotHash -cne $source.source_sha256 -or
                [int64]$snapshotItem.Length -ne [int64]$source.source_size_bytes) {
                throw "Legacy snapshot verification failed for '$($source.snapshot_reference)'."
            }
        }

        $receipts = [System.Collections.Generic.List[object]]::new()
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($record in $newRecords) {
            $source = $sourceFacts[$record.source_path]
            $receipt = [ordered]@{
                receipt_id = [guid]::NewGuid().ToString()
                verifier = 'inspection'
                subject = $record.id
                result = 'verified'
                reference = $source.snapshot_reference
                sha256 = $source.source_sha256
                size_bytes = [int64]$source.source_size_bytes
                captured_at = Get-UtcTimestamp
            }
            $receipts.Add($receipt)
            $items.Add([ordered]@{
                id = $record.id
                title = $record.title
                project = $state.project.id
                suggested_track = $state.active.track_id
                suggested_capability = $state.active.capability_id
                entry_depth = 'D0'
                discovered_from = "$($record.source_path):L$($record.source_line)"
                relationship = 'follow-up'
                dependencies = @()
                blockers = @($record.blockers)
                conflicts = @()
                value = 'low'
                risk = 'low'
                evidence = @($receipt)
                status = $record.status
                captured_at = Get-UtcTimestamp
            })
        }
        $state.backburner = @($state.backburner) + @($items)
        $event = Add-WorkScopeEvent -Root $Root -State $state -Type 'legacy_records_imported' -Evidence @($receipts) -Data @{
            record_count = $newRecords.Count
            records = @($newRecords)
            sources = @($sourceFacts.Values | ForEach-Object {
                [ordered]@{
                    source_path = $_.source_path
                    source_sha256 = $_.source_sha256
                    source_size_bytes = $_.source_size_bytes
                    snapshot_reference = $_.snapshot_reference
                }
            })
        }
        $result = [pscustomobject]@{
            Imported = $newRecords.Count
            AlreadyPresent = $alreadyPresent
            EventId = $event.event_id
            Snapshots = @($sourceFacts.Values | ForEach-Object { $_.snapshot_reference })
        }
    }
    catch {
        $transactionPath = Join-Path $paths.WorkRoot 'transaction.json'
        foreach ($temporaryPath in $temporarySnapshots) {
            if (Test-Path -LiteralPath $temporaryPath) {
                Remove-Item -LiteralPath $temporaryPath -Force
            }
        }
        if (-not (Test-Path -LiteralPath $transactionPath)) {
            foreach ($snapshotPath in $createdSnapshots) {
                if (Test-Path -LiteralPath $snapshotPath) {
                    Remove-Item -LiteralPath $snapshotPath -Force
                }
            }
            if ((Test-Path -LiteralPath $importsRoot) -and
                @(Get-ChildItem -LiteralPath $importsRoot -Force).Count -eq 0) {
                Remove-Item -LiteralPath $importsRoot -Force
            }
        }
        throw
    }
    Sync-WorkScopeViews -Root $Root | Out-Null
    return $result
}

function Resolve-WorkScopeDependencies {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Root)
    if (-not (Test-WorkScopeLockHeld -Root $Root)) {
        $arguments = Copy-WorkScopeBoundParameters -BoundParameters $PSBoundParameters
        return Invoke-WithWorkScopeLock -Root $Root -Action { Resolve-WorkScopeDependencies @arguments }
    }
    $state = Read-WorkScopeState -Root $Root
    $items = @($state.backburner | Where-Object { $_.status -notin @('closed', 'rejected', 'selected') })
    $knownIds = @($state.backburner | ForEach-Object { $_.id })
    $closedIds = @($state.backburner | Where-Object { $_.status -eq 'closed' } | ForEach-Object { $_.id })
    $capabilityStatuses = @{}
    foreach ($capability in @($state.tracks | ForEach-Object { @($_.capabilities) })) {
        if (-not $capabilityStatuses.ContainsKey($capability.id)) {
            $capabilityStatuses[$capability.id] = @()
        }
        $capabilityStatuses[$capability.id] = @($capabilityStatuses[$capability.id]) + @([string]$capability.status)
    }
    $inDegree = @{}
    $dependents = @{}
    foreach ($item in $items) {
        $inDegree[$item.id] = 0
        $dependents[$item.id] = [System.Collections.Generic.List[string]]::new()
    }
    foreach ($item in $items) {
        foreach ($dependency in @($item.dependencies)) {
            if ($closedIds -contains $dependency) {
                continue
            }
            if ($inDegree.ContainsKey($dependency)) {
                $inDegree[$item.id]++
                $dependents[$dependency].Add($item.id)
            }
        }
    }
    $queue = [System.Collections.Generic.Queue[string]]::new()
    foreach ($id in @($inDegree.Keys)) {
        if ($inDegree[$id] -eq 0) {
            $queue.Enqueue($id)
        }
    }
    $processed = [System.Collections.Generic.List[string]]::new()
    while ($queue.Count -gt 0) {
        $id = $queue.Dequeue()
        $processed.Add($id)
        foreach ($dependent in $dependents[$id]) {
            $inDegree[$dependent]--
            if ($inDegree[$dependent] -eq 0) {
                $queue.Enqueue($dependent)
            }
        }
    }
    $cycleIds = @($inDegree.Keys | Where-Object { $processed -notcontains $_ })
    foreach ($item in $items) {
        # Discovery ids take precedence when a capability uses the same id. That preserves the
        # existing discovery graph, including its exact status and cycle rules. A capability-only
        # dependency is satisfied only when every matching capability record is closed.
        $missing = @($item.dependencies | Where-Object {
            $knownIds -notcontains $_ -and -not $capabilityStatuses.ContainsKey($_)
        })
        $unclosed = @(
            foreach ($dependency in @($item.dependencies)) {
                if ($knownIds -contains $dependency) {
                    if ($closedIds -notcontains $dependency) {
                        $dependency
                    }
                    continue
                }
                if ($capabilityStatuses.ContainsKey($dependency) -and
                    @($capabilityStatuses[$dependency] | Where-Object { $_ -eq 'closed' }).Count -ne @($capabilityStatuses[$dependency]).Count) {
                    $dependency
                }
            }
        )
        if ($cycleIds -contains $item.id -or $missing.Count -gt 0 -or $unclosed.Count -gt 0 -or
            @($item.blockers).Count -gt 0 -or @($item.conflicts).Count -gt 0) {
            $item.status = 'blocked'
        }
        else {
            $item.status = 'ready'
        }
    }
    $resolutionEvent = if ($cycleIds.Count -gt 0) { 'dependency_cycle_detected' } else { 'dependencies_resolved' }
    Add-WorkScopeEvent -Root $Root -State $state -Type $resolutionEvent -Data @{
        cycles = $cycleIds
        ready = @($items | Where-Object { $_.status -eq 'ready' } | ForEach-Object { $_.id })
        blocked = @($items | Where-Object { $_.status -eq 'blocked' } | ForEach-Object { $_.id })
    } | Out-Null
    Sync-WorkScopeViews -Root $Root | Out-Null
    return [pscustomobject]@{
        cycles = @($cycleIds)
        ready = @($items | Where-Object { $_.status -eq 'ready' } | ForEach-Object { $_.id })
        blocked = @($items | Where-Object { $_.status -eq 'blocked' } | ForEach-Object { $_.id })
    }
}

function New-ActiveCell {
    param(
        [Parameter(Mandatory)] [string]$TrackId,
        [Parameter(Mandatory)] [string]$CapabilityId,
        [Parameter(Mandatory)] [string]$CapabilityName,
        [Parameter(Mandatory)] [string]$Depth
    )
    return [ordered]@{
        track_id = $TrackId
        capability_id = $CapabilityId
        depth = $Depth
        cell_id = "$CapabilityId@$Depth"
        status = 'active'
        opened_at = Get-UtcTimestamp
        closed_at = $null
        goal = "Complete and verify $CapabilityName at $Depth."
        in_scope = @($CapabilityId)
        out_of_scope = @()
        tasks = @()
        evidence = @()
        discoveries = @()
    }
}

function Select-WorkScopeFrontier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Root,
        # Take a foreign-track item into this session for this selection only, without persisting a
        # frontier change. Starting a genuinely new initiative in an enrolled project otherwise means
        # rewriting two global settings that were tuned for unrelated work -- widening the breadth
        # boundary and turning independent-track handoff off -- and then remembering to put both back.
        # This narrows that to one audited call: the settings on disk are untouched, and the override
        # is recorded in the selection event so the reason a foreign track opened stays legible.
        [string]$DiscoveryId,
        [switch]$TakeIndependentTrack,
        [switch]$Confirmed
    )
    if (-not [string]::IsNullOrWhiteSpace($DiscoveryId) -and -not $Confirmed) {
        throw 'Choosing a named frontier item is consequential; show the interpretation and confirm it before selecting.'
    }
    if ($TakeIndependentTrack -and -not $Confirmed) {
        throw 'Taking an independent track into this session is consequential; show the interpretation and confirm it before selecting.'
    }
    if (-not (Test-WorkScopeLockHeld -Root $Root)) {
        $arguments = Copy-WorkScopeBoundParameters -BoundParameters $PSBoundParameters
        return Invoke-WithWorkScopeLock -Root $Root -Action { Select-WorkScopeFrontier @arguments }
    }
    $state = Read-WorkScopeState -Root $Root
    if ($state.active.status -notin @('closed', 'blocked')) {
        throw 'The active scope cell must be closed or explicitly blocked before selecting frontier work.'
    }
    if (-not $state.frontier.automatic) {
        Add-WorkScopeEvent -Root $Root -State $state -Type 'frontier_stopped' -Data @{ reason = 'automatic_disabled' } | Out-Null
        Sync-WorkScopeViews -Root $Root | Out-Null
        return [pscustomobject]@{ transition = 'stop'; reason = 'automatic_disabled'; active = $state.active }
    }
    if (-not [string]::IsNullOrWhiteSpace($DiscoveryId) -and $state.frontier.mode -eq 'drilldown') {
        throw 'A named frontier item is available only in expand mode; drilldown advances the active capability by depth.'
    }
    if ($state.frontier.mode -eq 'drilldown') {
        $capability = Get-StateCapability -State $state -TrackId $state.active.track_id -CapabilityId $state.active.capability_id
        $closedCapabilityIds = @(
            $state.tracks.capabilities |
                Where-Object { $_.status -eq 'closed' } |
                ForEach-Object { $_.id }
        )
        $unmetCapabilityDependencies = @(
            $capability.dependencies |
                Where-Object { $closedCapabilityIds -notcontains $_ }
        )
        if (@($capability.blockers).Count -gt 0 -or $unmetCapabilityDependencies.Count -gt 0) {
            Add-WorkScopeEvent -Root $Root -State $state -Type 'frontier_stopped' -Evidence $state.active.evidence -Data @{
                reason = 'target_capability_blocked'
                blockers = @($capability.blockers)
                unmet_dependencies = $unmetCapabilityDependencies
            } | Out-Null
            Sync-WorkScopeViews -Root $Root | Out-Null
            return [pscustomobject]@{
                transition = 'stop'
                reason = 'target_capability_blocked'
                active = $state.active
            }
        }
        $current = ConvertTo-DepthIndex $state.active.depth
        $limit = [Math]::Min((ConvertTo-DepthIndex $state.frontier.depth_ceiling), (ConvertTo-DepthIndex $capability.target_depth))
        if ($current -ge $limit) {
            Add-WorkScopeEvent -Root $Root -State $state -Type 'frontier_stopped' -Data @{ reason = 'depth_ceiling' } | Out-Null
            Sync-WorkScopeViews -Root $Root | Out-Null
            return [pscustomobject]@{ transition = 'stop'; reason = 'depth_ceiling'; active = $state.active }
        }
        $nextDepth = $script:Depths[$current + 1]
        $state.active = New-ActiveCell -TrackId $state.active.track_id -CapabilityId $capability.id -CapabilityName $capability.name -Depth $nextDepth
        $capability.status = 'active'
        Add-WorkScopeEvent -Root $Root -State $state -Type 'drilldown_opened' -Data @{ depth = $nextDepth } | Out-Null
        Sync-WorkScopeViews -Root $Root | Out-Null
        return [pscustomobject]@{ transition = 'drilldown'; active = $state.active }
    }

    # An override that only silenced the handoff branch would still find nothing to select: at a
    # capability or track boundary the foreign-track item is filtered out here, before that branch is
    # reached. Widening to project scope for this call is what makes the override mean anything.
    $effectiveBoundary = if ($TakeIndependentTrack -and @('capability', 'track') -contains $state.frontier.breadth_boundary) {
        'project'
    }
    else {
        $state.frontier.breadth_boundary
    }
    $selectionMode = if ([string]::IsNullOrWhiteSpace($DiscoveryId)) { 'strategy' } else { 'targeted' }
    if ($selectionMode -eq 'targeted') {
        $requested = @($state.backburner | Where-Object { $_.id -eq $DiscoveryId }) | Select-Object -First 1
        if ($null -eq $requested) {
            throw "Named frontier target '$DiscoveryId' does not exist."
        }
    }

    # Dependency status is derived state. Resolve it before judging a named target so a
    # prerequisite completed since the last pass can make its dependent selectable this call.
    Resolve-WorkScopeDependencies -Root $Root | Out-Null
    $state = Read-WorkScopeState -Root $Root
    if ($selectionMode -eq 'targeted') {
        $requested = @($state.backburner | Where-Object { $_.id -eq $DiscoveryId }) | Select-Object -First 1
        if ($null -eq $requested -or $requested.status -ne 'ready') {
            throw "Named frontier target '$DiscoveryId' is not ready after dependency resolution."
        }
        $insideBoundary = switch ($effectiveBoundary) {
            'capability' { $requested.suggested_capability -eq $state.active.capability_id }
            'track' { $requested.suggested_track -eq $state.active.track_id }
            'project' { $requested.project -eq $state.project.id }
            'portfolio' { $requested.project -eq $state.project.id }
            default { $true }
        }
        if (-not $insideBoundary) {
            throw "Named frontier target '$DiscoveryId' is outside the effective breadth boundary."
        }
        $requestedTrack = Get-StateTrack -State $state -TrackId $requested.suggested_track
        $requestedCapability = if ($null -ne $requestedTrack) {
            $requestedTrack.capabilities | Where-Object { $_.id -eq $requested.suggested_capability } | Select-Object -First 1
        } else { $null }
        if ($null -ne $requestedCapability) {
            $closedCapabilityIds = @($state.tracks.capabilities | Where-Object { $_.status -eq 'closed' } | ForEach-Object { $_.id })
            $unmetCapabilityDependencies = @($requestedCapability.dependencies | Where-Object { $closedCapabilityIds -notcontains $_ })
            if ($requestedCapability.status -eq 'blocked' -or @($requestedCapability.blockers).Count -gt 0 -or $unmetCapabilityDependencies.Count -gt 0) {
                throw "Named frontier target '$DiscoveryId' has a blocked capability."
            }
        }
    }

    $candidates = @($state.backburner | Where-Object { $_.status -eq 'ready' })
    switch ($effectiveBoundary) {
        'capability' {
            $candidates = @($candidates | Where-Object { $_.suggested_capability -eq $state.active.capability_id })
        }
        'track' {
            $candidates = @($candidates | Where-Object { $_.suggested_track -eq $state.active.track_id })
        }
        'project' {
            $candidates = @($candidates | Where-Object { $_.project -eq $state.project.id })
        }
        'portfolio' {
            $candidates = @($candidates | Where-Object { $_.project -eq $state.project.id })
        }
        'system' { }
    }
    if ($candidates.Count -eq 0) {
        throw 'No ready backburner item is eligible inside the declared breadth boundary.'
    }
    $paths = Get-WorkScopePaths -Root $Root
    $selectionRules = Get-Content -LiteralPath $paths.SelectionRules -Raw | ConvertFrom-Json -AsHashtable
    $valueRank = $selectionRules.value_weights
    $riskRank = $selectionRules.risk_weights
    if ($selectionMode -eq 'targeted') {
        $selected = @($candidates | Where-Object { $_.id -eq $DiscoveryId }) | Select-Object -First 1
        if ($null -eq $selected) {
            throw "Named frontier target '$DiscoveryId' is outside the effective breadth boundary."
        }
    }
    else {
    switch ($state.frontier.selection_strategy) {
        'highest-value' {
            $selected = @($candidates | Sort-Object @{ Expression = { $valueRank[$_.value] }; Descending = $true }, @{ Expression = 'captured_at'; Descending = $false })[0]
        }
        'highest-risk' {
            $selected = @($candidates | Sort-Object @{ Expression = { $riskRank[$_.risk] }; Descending = $true }, @{ Expression = 'captured_at'; Descending = $false })[0]
        }
        'shortest-ready' {
            $selected = @($candidates | Sort-Object @{ Expression = { ConvertTo-DepthIndex $_.entry_depth }; Descending = $false }, @{ Expression = 'captured_at'; Descending = $false })[0]
        }
        'balanced' {
            $selected = @($candidates | Sort-Object @{ Expression = { $valueRank[$_.value] + $riskRank[$_.risk] - @(ConvertTo-NormalizedArray $_.dependencies).Count }; Descending = $true }, @{ Expression = 'captured_at'; Descending = $false })[0]
        }
        default {
            $selected = @($candidates | Sort-Object @{ Expression = { @(ConvertTo-NormalizedArray $_.dependencies).Count }; Descending = $false }, @{ Expression = { $valueRank[$_.value] }; Descending = $true }, @{ Expression = 'captured_at'; Descending = $false })[0]
        }
    }
    }
    $track = Get-StateTrack -State $state -TrackId $selected.suggested_track
    $capability = if ($null -ne $track) {
        $track.capabilities | Where-Object { $_.id -eq $selected.suggested_capability } | Select-Object -First 1
    } else { $null }
    if ($null -ne $capability) {
        $closedCapabilityIds = @(
            $state.tracks.capabilities |
                Where-Object { $_.status -eq 'closed' } |
                ForEach-Object { $_.id }
        )
        $unmetCapabilityDependencies = @($capability.dependencies | Where-Object { $closedCapabilityIds -notcontains $_ })
        if ($capability.status -eq 'blocked' -or @($capability.blockers).Count -gt 0 -or $unmetCapabilityDependencies.Count -gt 0) {
            if ($selectionMode -eq 'targeted') {
                throw "Named frontier target '$DiscoveryId' has a blocked capability."
            }
            $selected.status = 'blocked'
            $selected.blockers = @(@($capability.blockers) + @($unmetCapabilityDependencies) | Sort-Object -Unique)
            Add-WorkScopeEvent -Root $Root -State $state -Type 'frontier_stopped' -Evidence $selected.evidence -Data @{
                reason = 'target_capability_blocked'
                backburner_id = $selected.id
                blockers = @($capability.blockers)
                unmet_dependencies = $unmetCapabilityDependencies
            } | Out-Null
            Sync-WorkScopeViews -Root $Root | Out-Null
            return [pscustomobject]@{ transition = 'stop'; reason = 'target_capability_blocked'; active = $state.active }
        }
    }
    $currentCapability = Get-StateCapability -State $state -TrackId $state.active.track_id -CapabilityId $state.active.capability_id
    $foreignOwner = (
        $null -ne $capability -and
        -not [string]::IsNullOrWhiteSpace([string]$capability.owner_session) -and
        $capability.owner_session -ne $currentCapability.owner_session
    )
    # The override waives the independent-*track* handoff only. A capability another session owns is
    # still handed over, because that guard protects someone else's artifacts rather than this
    # session's convenience, and no per-call switch should be able to take it.
    $needsHandoff = (
        $state.frontier.handoff_independent_tracks -and
        (($selected.suggested_track -ne $state.active.track_id -and -not $TakeIndependentTrack) -or $foreignOwner)
    )
    if ($needsHandoff) {
        $handoffPath = Join-Path $paths.HandoffRoot "$($selected.id).md"
        if (Test-Path -LiteralPath $handoffPath) {
            $existingHandoff = Get-Content -LiteralPath $handoffPath -Raw
            if ($existingHandoff -notmatch [regex]::Escape("# Work-scope handoff: $($selected.id)")) {
                throw "Handoff '$handoffPath' already exists and was not generated for '$($selected.id)'."
            }
            $handoff = [pscustomobject]@{ path = $handoffPath; backburner_id = $selected.id }
        }
        else {
            $handoff = New-WorkScopeHandoff -Root $Root -BackburnerId $selected.id
        }
        $state = Read-WorkScopeState -Root $Root
        $selected = $state.backburner | Where-Object { $_.id -eq $selected.id } | Select-Object -First 1
        $selected.status = 'selected'
        Add-WorkScopeEvent -Root $Root -State $state -Type 'frontier_handoff_selected' -Evidence $selected.evidence -Data @{
            backburner_id = $selected.id
            strategy = $state.frontier.selection_strategy
            selection_mode = $selectionMode
            requested_backburner_id = $DiscoveryId
            handoff_path = $handoff.path
            owner_session = if ($foreignOwner) { $capability.owner_session } else { $null }
        } | Out-Null
        Sync-WorkScopeViews -Root $Root | Out-Null
        return [pscustomobject]@{
            transition = 'handoff'
            selected_id = $selected.id
            handoff_path = $handoff.path
            active = $state.active
        }
    }
    $selected.status = 'selected'
    if ($null -eq $track) {
        $track = [ordered]@{ id = $selected.suggested_track; status = 'active'; capabilities = @() }
        $state.tracks = @($state.tracks) + @($track)
    }
    # This is the non-handoff path, so the session that just closed a cell keeps working. Opening
    # the next cell with no owner left the ownership guard with nothing to compare against, and a
    # second session could claim the same artifacts without tripping it. A handoff is where
    # ownership is meant to change hands, and that branch returned above.
    $continuingOwner = if ($null -ne $currentCapability) { [string]$currentCapability.owner_session } else { $null }
    if ($null -eq $capability) {
        $capability = [ordered]@{
            id = $selected.suggested_capability
            name = $selected.title
            current_depth = $null
            target_depth = $selected.entry_depth
            status = 'active'
            dependencies = @(ConvertTo-NormalizedArray $selected.dependencies)
            blockers = @(ConvertTo-NormalizedArray $selected.blockers)
            owner_session = if ([string]::IsNullOrWhiteSpace($continuingOwner)) { $null } else { $continuingOwner }
        }
        $track.capabilities = @($track.capabilities) + @($capability)
    }
    elseif ([string]::IsNullOrWhiteSpace([string]$capability.owner_session) -and
        -not [string]::IsNullOrWhiteSpace($continuingOwner)) {
        $capability.owner_session = $continuingOwner
    }
    if ((ConvertTo-DepthIndex $selected.entry_depth) -gt (ConvertTo-DepthIndex $capability.target_depth)) {
        $capability.target_depth = $selected.entry_depth
    }
    $state.active = New-ActiveCell -TrackId $track.id -CapabilityId $capability.id -CapabilityName $capability.name -Depth $selected.entry_depth
    Add-WorkScopeEvent -Root $Root -State $state -Type 'frontier_item_selected' -Evidence $selected.evidence -Data @{
        backburner_id = $selected.id
        strategy = $state.frontier.selection_strategy
        selection_mode = $selectionMode
        requested_backburner_id = $DiscoveryId
        took_independent_track = [bool]$TakeIndependentTrack
        effective_breadth_boundary = $effectiveBoundary
    } | Out-Null
    Sync-WorkScopeViews -Root $Root | Out-Null
    return [pscustomobject]@{
        transition = 'expand'
        selected_id = $selected.id
        active = $state.active
    }
}

function New-WorkScopeHandoff {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [string]$BackburnerId,
        [switch]$Overwrite
    )
    if (-not (Test-WorkScopeLockHeld -Root $Root)) {
        $arguments = Copy-WorkScopeBoundParameters -BoundParameters $PSBoundParameters
        return Invoke-WithWorkScopeLock -Root $Root -Action { New-WorkScopeHandoff @arguments }
    }
    Assert-SafeWorkScopeId -Id $BackburnerId -Label 'Backburner id'
    $state = Read-WorkScopeState -Root $Root
    $item = $state.backburner | Where-Object { $_.id -eq $BackburnerId } | Select-Object -First 1
    if ($null -eq $item) {
        throw "Backburner item '$BackburnerId' does not exist."
    }
    $paths = Get-WorkScopePaths -Root $Root
    $artifactOwners = @($state.ownership.sessions | ForEach-Object {
        "- $($_.session_id): $(@($_.artifacts) -join ', ')"
    })
    if ($artifactOwners.Count -eq 0) {
        $artifactOwners = @('- None declared')
    }
    $content = @"
# Work-scope handoff: $($item.id)

## Identity

- Project: $($item.project)
- Track: $($item.suggested_track)
- Capability: $($item.suggested_capability)
- Starting depth: $($item.entry_depth)

## Desired outcome

$($item.title)

## Boundaries

- In scope: capability $($item.suggested_capability) at $($item.entry_depth)
- Out of scope: the coordinating session's active cell $($state.active.cell_id)
- Breadth boundary: $($state.frontier.breadth_boundary)
- Depth ceiling: $($state.frontier.depth_ceiling)

## Dependencies and blockers

- Dependencies: $(@($item.dependencies) -join ', ')
- Blockers: $(@($item.blockers) -join ', ')
- Conflicts: $(@($item.conflicts) -join ', ')

## Artifact ownership

$($artifactOwners -join "`n")

## Evidence

$(ConvertTo-MarkdownList -Items $item.evidence)

## Acceptance criteria

- Complete the declared scope cell with concrete verification evidence.
- Capture adjacent discoveries without expanding this track.
- Reconcile generated views with authoritative state.

## Frontier

- Mode: $($state.frontier.mode)
- Selection strategy: $($state.frontier.selection_strategy)
- Independent track handoff: enabled

## Resumption prompt

Resume project $($item.project), track $($item.suggested_track), capability $($item.suggested_capability) at $($item.entry_depth). Read and validate .agents/work/state.json, claim artifact ownership before writes, execute only the active scope cell, and close it only with verification evidence.
"@
    $handoffRoot = [System.IO.Path]::GetFullPath($paths.HandoffRoot).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $path = [System.IO.Path]::GetFullPath((Join-Path $handoffRoot "$BackburnerId.md"))
    $requiredPrefix = $handoffRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $path.StartsWith($requiredPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Handoff path '$path' escapes the handoff directory."
    }
    if ((Test-Path -LiteralPath $path) -and -not $Overwrite) {
        throw "Handoff '$path' already exists. Pass -Overwrite only after explicit authorization."
    }
    $temporaryPath = Join-Path $handoffRoot (".$BackburnerId.$([guid]::NewGuid().ToString('N')).tmp")
    Set-Content -LiteralPath $temporaryPath -Value $content -Encoding utf8NoBOM
    try {
        Add-WorkScopeEvent -Root $Root -State $state -Type 'handoff_generated' -Data @{
            backburner_id = $BackburnerId
            path = $path
            overwrite = [bool]$Overwrite
        } -FileCommit @{
            temporary_path = $temporaryPath
            final_path = $path
            overwrite = [bool]$Overwrite
        } | Out-Null
    }
    catch {
        $transactionPath = Join-Path $paths.WorkRoot 'transaction.json'
        if ((Test-Path -LiteralPath $temporaryPath) -and -not (Test-Path -LiteralPath $transactionPath)) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
        throw
    }
    Sync-WorkScopeViews -Root $Root | Out-Null
    return [pscustomobject]@{ path = $path; backburner_id = $BackburnerId }
}

function Get-WorkScopeResume {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Root)
    $state = Read-WorkScopeState -Root $Root
    Resolve-TaskStatuses -State $state
    $nextAction = $null
    if ($state.active.status -eq 'closed') {
        $hasFrontierWork = $false
        if ($state.frontier.automatic -and $state.frontier.mode -eq 'expand') {
            $hasFrontierWork = @($state.backburner | Where-Object { $_.status -eq 'ready' }).Count -gt 0
        }
        elseif ($state.frontier.automatic -and $state.frontier.mode -eq 'drilldown') {
            $capability = Get-StateCapability -State $state -TrackId $state.active.track_id -CapabilityId $state.active.capability_id
            $nextDepthIndex = (ConvertTo-DepthIndex $state.active.depth) + 1
            $maximumDepthIndex = [Math]::Min(
                (ConvertTo-DepthIndex $capability.target_depth),
                (ConvertTo-DepthIndex $state.frontier.depth_ceiling)
            )
            $hasFrontierWork = (
                $nextDepthIndex -le $maximumDepthIndex -and
                @($capability.blockers).Count -eq 0
            )
        }
        $nextAction = if ($hasFrontierWork) {
            [pscustomobject]@{ type = 'frontier_transition'; task_id = $null }
        }
        else {
            [pscustomobject]@{ type = 'stop'; task_id = $null }
        }
    }
    else {
        $ready = @($state.active.tasks | Where-Object { $_.status -eq 'ready' })
        if ($ready.Count -gt 0) {
            $nextAction = [pscustomobject]@{
                type = 'execute_task'
                task_id = $ready[0].id
                title = $ready[0].title
                acceptance = $ready[0].acceptance
                acceptance_checks = @($ready[0].acceptance_checks)
            }
        }
        elseif (@($state.active.tasks).Count -eq 0) {
            $nextAction = [pscustomobject]@{ type = 'materialize_tasks'; task_id = $null }
        }
        else {
            $nextAction = [pscustomobject]@{ type = 'resolve_blocker'; task_id = $null }
        }
    }
    return [pscustomobject]@{
        project_id = $state.project.id
        track_id = $state.active.track_id
        capability_id = $state.active.capability_id
        owner_session = (
            Get-StateCapability -State $state -TrackId $state.active.track_id -CapabilityId $state.active.capability_id
        ).owner_session
        depth = $state.active.depth
        cell_id = $state.active.cell_id
        status = $state.active.status
        next_action = $nextAction
    }
}

function ConvertTo-MarkdownList {
    param(
        $Items,
        [string]$EmptyText = 'None'
    )
    $array = @(ConvertTo-NormalizedArray $Items)
    if ($array.Count -eq 0) {
        return "- $EmptyText"
    }
    return ($array | ForEach-Object {
        if ($_ -is [System.Collections.IDictionary] -and $_.Contains('receipt_id')) {
            $shortHash = ([string]$_.sha256).Substring(0, 12)
            "- [$($_.verifier)/$($_.result)] $($_.subject) | $($_.reference) | sha256:$shortHash | receipt:$($_.receipt_id)"
        }
        else {
            "- $_"
        }
    }) -join "`n"
}

function Get-WorkScopeRenderedViews {
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [hashtable]$State
    )
    $track = Get-StateTrack -State $State -TrackId $State.active.track_id
    $capability = Get-StateCapability -State $State -TrackId $State.active.track_id -CapabilityId $State.active.capability_id
    $taskLines = if (@($State.active.tasks).Count -eq 0) {
        '- [ ] No tasks materialized'
    }
    else {
        @($State.active.tasks | ForEach-Object {
            $mark = if ($_.status -eq 'closed') { 'x' } else { ' ' }
            "- [$mark] $($_.id): $($_.title) (status: $($_.status); acceptance: $($_.acceptance))"
        }) -join "`n"
    }
    $checkLines = if (@($State.active.tasks).Count -eq 0) {
        '- None'
    }
    else {
        @(
            foreach ($task in @($State.active.tasks)) {
                foreach ($check in @($task.acceptance_checks)) {
                    $argumentsJson = ConvertTo-Json -InputObject @($check.arguments) -Compress
                    $inputReferences = @($check.verifier_inputs | ForEach-Object { $_.reference }) -join ', '
                    $artifactReferences = @($check.artifacts) -join ', '
                    "- $($task.id)/$($check.id): $($check.executable) argv=$argumentsJson; inputs=[$inputReferences]; artifacts=[$artifactReferences]; timeout=$($check.timeout_seconds)s; max-output=$($check.max_output_bytes)B"
                }
            }
        ) -join "`n"
    }
    $evidence = ConvertTo-MarkdownList -Items $State.active.evidence
    $discoveries = ConvertTo-MarkdownList -Items $State.active.discoveries
    $blockers = @($State.active.tasks | Where-Object { $_.status -eq 'blocked' } | ForEach-Object { "$($_.id): dependencies $(@($_.dependencies) -join ', ')" })
    $blockerText = ConvertTo-MarkdownList -Items $blockers
    $next = Get-WorkScopeResume -Root $Root
    $nextText = "$($next.next_action.type)"
    if ($next.next_action.task_id) {
        $nextText += ": $($next.next_action.task_id)"
    }

    $projectView = @"
<!-- GENERATED FROM .agents/work/state.json. DO NOT EDIT DIRECTLY. -->
# Project

- Project: $($State.project.id)
- Kind: $($State.project.kind)
- Initiative: $($State.project.initiative_id)
- Root: $($State.project.root)$(if ($State.project.Contains('remote') -and -not [string]::IsNullOrWhiteSpace([string]$State.project.remote)) { "`n- Remote: $($State.project.remote)" })
- Breadth boundary: $($State.frontier.breadth_boundary)

## Global definition of done

$(ConvertTo-MarkdownList -Items $State.project.definition_of_done)
"@

    $trackRows = [System.Collections.Generic.List[string]]::new()
    foreach ($stateTrack in @($State.tracks)) {
        foreach ($stateCapability in @($stateTrack.capabilities)) {
            $trackRows.Add("| $($stateTrack.id) | $($stateCapability.id) | $($stateCapability.current_depth) | $($stateCapability.target_depth) | $($stateCapability.status) | $($stateCapability.owner_session) |")
        }
    }
    # A markdown backtick immediately before "$(" would be read as the PowerShell
    # escape character, emitting a literal "$(" and stringifying $State. Build the
    # code spans outside the here-string so the backticks can never escape anything.
    $activeCellSpan = '`' + [string]$State.active.cell_id + '`'
    $activeTrackSpan = '`' + [string]$State.active.track_id + '`'
    $tracksView = @"
<!-- GENERATED FROM .agents/work/state.json. DO NOT EDIT DIRECTLY. -->
# Tracks and capability frontier

| Track | Capability | Current depth | Target depth | Status | Owner session |
|---|---|---|---|---|---|
$($trackRows -join "`n")

## Active cell

$activeCellSpan in track $activeTrackSpan.
"@

    $taskView = @"
<!-- GENERATED FROM .agents/work/state.json. DO NOT EDIT DIRECTLY. -->
# Active Work

Project: $($State.project.id)
Initiative: $($State.project.initiative_id)
Primary track: $($State.active.track_id)
Capability: $($State.active.capability_id)
Depth: $($State.active.depth) ($($script:DepthNames[$State.active.depth]))
Frontier mode: $($State.frontier.mode)
Depth ceiling: $($State.frontier.depth_ceiling)
Breadth boundary: $($State.frontier.breadth_boundary)
Selection strategy: $($State.frontier.selection_strategy)
Status: $($State.active.status)

## Goal

$($State.active.goal)

## In scope

$(ConvertTo-MarkdownList -Items $State.active.in_scope)

## Out of scope

$(ConvertTo-MarkdownList -Items $State.active.out_of_scope)

## Done when

- Every task below is closed.
- Scope-cell verification evidence is recorded.
- Generated views reconcile with canonical state.

## Tasks

$taskLines

## Declared acceptance checks

$checkLines

## Blockers and dependencies

$blockerText

## Verification evidence

$evidence

## Discoveries captured

$discoveries

## Next transition

$nextText
"@

    $backburnerRows = if (@($State.backburner).Count -eq 0) {
        '| - | No discoveries captured | - | - | - | - |'
    }
    else {
        @($State.backburner | ForEach-Object {
            "| $($_.id) | $($_.title) | $($_.suggested_track) | $($_.suggested_capability) | $($_.entry_depth) | $($_.status) |"
        }) -join "`n"
    }
    # A correction that only exists in state.json is invisible to the reader the view is for,
    # which is the failure it was built to fix. The table above shows the corrected title; this
    # section is what says the record was corrected at all, and what it used to say.
    $correctedItems = @($State.backburner | Where-Object { @(Get-WorkScopeOptionalMember -Item $_ -Name 'corrections').Count -gt 0 })
    $correctionSection = if ($correctedItems.Count -eq 0) {
        ''
    }
    else {
        $correctionLines = @(
            foreach ($correctedItem in $correctedItems) {
                foreach ($correction in (Get-WorkScopeOptionalMember -Item $correctedItem -Name 'corrections')) {
                    $previousPairs = @(Get-WorkScopeMemberPairs -Item $correction.previous)
                    $previousText = if ($previousPairs.Count -eq 0) {
                        'no field changed'
                    }
                    else {
                        (@($previousPairs | ForEach-Object { "$($_.Name) was '$($_.Value)'" }) -join '; ')
                    }
                    "- **$($correctedItem.id)** ($($correction.corrected_at)) — $($correction.reason) [$previousText]"
                }
            }
        ) -join "`n"
        @"

## Corrections

$correctionLines
"@
    }
    $backburnerView = @"
<!-- GENERATED FROM .agents/work/state.json. DO NOT EDIT DIRECTLY. -->
# Backburner

This is a discovery queue. It does not become active until a verified frontier transition selects an item.

| ID | Title | Suggested track | Suggested capability | Entry depth | Status |
|---|---|---|---|---|---|
$backburnerRows
$correctionSection
"@

    $paths = Get-WorkScopePaths -Root $Root
    $eventLines = @()
    if (Test-Path -LiteralPath $paths.Events) {
        $eventLines = @(Get-Content -LiteralPath $paths.Events | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
            $event = $_ | ConvertFrom-Json
            # No "- " here: ConvertTo-MarkdownList below owns the list prefix, so adding one
            # rendered every LOG line as "- - 07/31/2026 ...".
            "$($event.occurred_at) [$($event.type)] cell=$($event.cell_id) event=$($event.event_id)"
        })
    }
    $logView = @"
<!-- GENERATED FROM .agents/work/events.jsonl. DO NOT EDIT DIRECTLY. -->
# Work log

$(ConvertTo-MarkdownList -Items $eventLines)
"@

    return [ordered]@{
        'PROJECT.md' = $projectView.TrimEnd() + "`n"
        'TRACKS.md' = $tracksView.TrimEnd() + "`n"
        'TASK.md' = $taskView.TrimEnd() + "`n"
        'BACKBURNER.md' = $backburnerView.TrimEnd() + "`n"
        'LOG.md' = $logView.TrimEnd() + "`n"
    }
}

function Sync-WorkScopeViews {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Root)
    if (-not (Test-WorkScopeLockHeld -Root $Root)) {
        $arguments = Copy-WorkScopeBoundParameters -BoundParameters $PSBoundParameters
        return Invoke-WithWorkScopeLock -Root $Root -Action { Sync-WorkScopeViews @arguments }
    }
    $state = Read-WorkScopeState -Root $Root
    $views = Get-WorkScopeRenderedViews -Root $Root -State $state
    foreach ($entry in $views.GetEnumerator()) {
        Set-Content -LiteralPath (Join-Path $Root $entry.Key) -Value $entry.Value -Encoding utf8NoBOM -NoNewline
    }
    return [pscustomobject]@{ rendered = @($views.Keys) }
}

function Test-WorkScopeReconciliation {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Root)
    $state = Read-WorkScopeState -Root $Root
    $validation = Test-WorkScopeState -Root $Root
    $expected = Get-WorkScopeRenderedViews -Root $Root -State $state
    $drifted = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $expected.GetEnumerator()) {
        $path = Join-Path $Root $entry.Key
        if (-not (Test-Path -LiteralPath $path)) {
            $drifted.Add($entry.Key)
            continue
        }
        $actual = Get-Content -LiteralPath $path -Raw
        if ($actual -ne $entry.Value) {
            $drifted.Add($entry.Key)
        }
    }
    return [pscustomobject]@{
        reconciled = ($validation.valid -and $drifted.Count -eq 0)
        state_valid = $validation.valid
        state_errors = $validation.errors
        drifted_files = @($drifted)
    }
}

Export-ModuleMember -Function @(
    'Expand-WorkScopePackedArgument'
    'Initialize-WorkScopeProject'
    'Invoke-WorkScopeVerification'
    'Repair-WorkScopeTransaction'
    'Read-WorkScopeState'
    'Test-WorkScopeState'
    'Add-WorkScopeTask'
    'Complete-WorkScopeTask'
    'Set-WorkScopeTaskRetired'
    'Close-WorkScopeCell'
    'Block-WorkScopeCell'
    'Set-WorkScopeOwnership'
    'Move-WorkScopeOwnership'
    'Invoke-WorkScopeGuard'
    'Set-WorkScopeFrontier'
    'Add-WorkScopeDiscovery'
    'Set-WorkScopeDiscoveryStatus'
    'Add-WorkScopeDiscoveryCorrection'
    'Import-WorkScopeLegacyRecords'
    'Resolve-WorkScopeDependencies'
    'Select-WorkScopeFrontier'
    'New-WorkScopeHandoff'
    'Get-WorkScopeResume'
    'Sync-WorkScopeViews'
    'Test-WorkScopeReconciliation'
    'ConvertTo-WorkScopeRemoteIdentity'
    'Get-WorkScopeRepositoryIdentity'
    'Set-WorkScopeProjectRemote'
)
