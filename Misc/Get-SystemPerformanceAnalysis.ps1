<#
.SYNOPSIS
    Identifies processes and system resources causing machine lag.

.DESCRIPTION
    This script performs a deep analysis of CPU, memory, disk, network, event logs,
    process anomalies, and system configuration to identify performance bottlenecks
    and provide actionable remediation recommendations.

.PARAMETER TopProcessCount
    Number of top processes to display for each resource category. Default is 10.

.PARAMETER MonitorDuration
    Duration in seconds to monitor system performance. Default is 30 seconds.

.PARAMETER IncludeDiskIO
    Include disk I/O analysis (may require elevated permissions).

.PARAMETER EventLogHours
    How many hours back to scan System and Application event logs for errors. Default is 24.

.PARAMETER IncludeProcessAnomalies
    Scan for suspicious or anomalous processes (unsigned, running from temp paths, etc.).

.EXAMPLE
    .\Get-SystemPerformanceAnalysis.ps1
    Runs a standard performance analysis with default settings.

.EXAMPLE
    .\Get-SystemPerformanceAnalysis.ps1 -TopProcessCount 15 -MonitorDuration 60
    Monitors for 60 seconds and shows top 15 processes for each category.

.EXAMPLE
    .\Get-SystemPerformanceAnalysis.ps1 -IncludeDiskIO -IncludeProcessAnomalies -EventLogHours 48
    Full deep analysis including disk I/O, process anomalies, and 48 hours of event log history.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$TopProcessCount = 10,
    
    [Parameter(Mandatory = $false)]
    [int]$MonitorDuration = 30,
    
    [Parameter(Mandatory = $false)]
    [switch]$IncludeDiskIO,

    [Parameter(Mandatory = $false)]
    [int]$EventLogHours = 24,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeProcessAnomalies
)

function Write-SectionHeader {
    param([string]$Title)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

function Get-FormattedBytes {
    param([long]$Bytes)
    if ($Bytes -gt 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    elseif ($Bytes -gt 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    elseif ($Bytes -gt 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    else { return "$Bytes Bytes" }
}

function Write-Alert {
    param([string]$Message, [ValidateSet('Critical','Warning','Info','Good')]$Level = 'Warning')
    $color = switch ($Level) {
        'Critical' { 'Red' }
        'Warning'  { 'Yellow' }
        'Info'     { 'Cyan' }
        'Good'     { 'Green' }
    }
    $prefix = switch ($Level) {
        'Critical' { '[CRITICAL]' }
        'Warning'  { '[WARNING] ' }
        'Info'     { '[INFO]    ' }
        'Good'     { '[OK]      ' }
    }
    Write-Host "$prefix $Message" -ForegroundColor $color
}

# Global recommendations list
$recommendations = [System.Collections.Generic.List[string]]::new()

function Add-Recommendation {
    param([string]$Message, [string]$Severity = 'WARNING')
    $script:recommendations.Add("[$Severity] $Message")
}

# ──────────────────────────────────────────────────────────────────────────────
# Check admin rights
# ──────────────────────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

Write-Host "Starting Deep System Performance Analysis..." -ForegroundColor Green
Write-Host "Monitor Duration: $MonitorDuration seconds | Event Log Lookback: $EventLogHours hours" -ForegroundColor Yellow
Write-Host "Admin Rights: $isAdmin" -ForegroundColor $(if ($isAdmin) { "Green" } else { "Yellow" })
if (-not $isAdmin) {
    Write-Host "NOTE: Some sections require administrator rights and will be skipped." -ForegroundColor Yellow
}

# ──────────────────────────────────────────────────────────────────────────────
# System Overview
# ──────────────────────────────────────────────────────────────────────────────
Write-SectionHeader "System Overview"

$computerSystem = Get-CimInstance Win32_ComputerSystem
$os             = Get-CimInstance Win32_OperatingSystem
$cpu            = Get-CimInstance Win32_Processor | Select-Object -First 1
$bios           = Get-CimInstance Win32_BIOS
$uptime         = (Get-Date) - $os.LastBootUpTime
$totalMemBytes  = $computerSystem.TotalPhysicalMemory
$freeMemBytes   = $os.FreePhysicalMemory * 1KB
$usedMemBytes   = $totalMemBytes - $freeMemBytes
$memUsagePct    = [math]::Round(($usedMemBytes / $totalMemBytes) * 100, 2)

Write-Host "Computer Name   : $($computerSystem.Name)"
Write-Host "OS              : $($os.Caption) (Build $($os.BuildNumber))"
Write-Host "Architecture    : $($os.OSArchitecture)"
Write-Host "CPU             : $($cpu.Name) — $($cpu.NumberOfCores) cores / $($cpu.NumberOfLogicalProcessors) logical"
Write-Host "CPU Socket      : $($cpu.SocketDesignation)  |  Max Clock: $($cpu.MaxClockSpeed) MHz"
Write-Host "Total RAM       : $(Get-FormattedBytes $totalMemBytes)"
Write-Host "Available RAM   : $(Get-FormattedBytes $freeMemBytes)  ($([math]::Round(($freeMemBytes/$totalMemBytes)*100,1))% free)"
Write-Host "Memory Usage    : $memUsagePct%"
Write-Host "System Uptime   : $($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m"
Write-Host "Last Boot       : $($os.LastBootUpTime)"
Write-Host "BIOS Version    : $($bios.SMBIOSBIOSVersion)  |  Released: $($bios.ReleaseDate)"

if ($uptime.TotalDays -gt 14) {
    Add-Recommendation "System has been running for $([math]::Round($uptime.TotalDays,1)) days without a reboot. Consider rebooting to reclaim memory and apply pending patches." "WARNING"
}

# ──────────────────────────────────────────────────────────────────────────────
# Power Plan
# ──────────────────────────────────────────────────────────────────────────────
Write-SectionHeader "Power Plan"

try {
    $powerPlan = powercfg /getactivescheme 2>$null
    Write-Host $powerPlan
    if ($powerPlan -match 'Power saver') {
        Write-Alert "Active power plan is 'Power saver'. This throttles CPU performance." 'Critical'
        Add-Recommendation "Change power plan from 'Power saver' to 'High performance' or 'Balanced' to stop CPU throttling." "CRITICAL"
    } elseif ($powerPlan -match 'Balanced') {
        Write-Alert "Active power plan is 'Balanced'. May throttle CPU under load. Consider 'High performance' for sustained workloads." 'Warning'
        Add-Recommendation "Consider switching to 'High performance' power plan for sustained CPU-intensive workloads." "INFO"
    } else {
        Write-Alert "Power plan appears optimal." 'Good'
    }
} catch {
    Write-Host "Could not read power plan." -ForegroundColor Yellow
}

# ──────────────────────────────────────────────────────────────────────────────
# CPU Deep Analysis (per-core + interrupt/DPC overhead)
# ──────────────────────────────────────────────────────────────────────────────
Write-SectionHeader "CPU Deep Analysis"

Write-Host "Collecting CPU performance counters for $MonitorDuration seconds..." -ForegroundColor Yellow

# Per-core utilization
$coreCounters = @('\Processor(*)\% Processor Time', '\Processor(*)\% Privileged Time',
                  '\Processor(*)\% Interrupt Time', '\Processor(*)\% DPC Time',
                  '\Processor(_Total)\% Processor Time')

$perfSample1 = Get-Counter -Counter $coreCounters -ErrorAction SilentlyContinue

# Also capture process CPU baselines
$processes1 = Get-Process | Where-Object { $_.CPU -ne $null } |
    Select-Object Id, ProcessName, CPU,
        @{Name='CPUTime1'; Expression={ $_.TotalProcessorTime }},
        @{Name='Threads';  Expression={ $_.Threads.Count }},
        @{Name='Handles';  Expression={ $_.HandleCount }}

Start-Sleep -Seconds $MonitorDuration

$perfSample2   = Get-Counter -Counter $coreCounters -ErrorAction SilentlyContinue

# Use CIM for process paths/metadata — avoids access-denied errors on protected processes
$cimProcessMap = @{}
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object {
    $cimProcessMap[$_.ProcessId] = $_.ExecutablePath
}

$processes2    = Get-Process | Where-Object { $_.CPU -ne $null } |
    Select-Object Id, ProcessName, CPU,
        @{Name='CPUTime2';       Expression={ $_.TotalProcessorTime }},
        @{Name='WorkingSet';     Expression={ $_.WorkingSet64 }},
        @{Name='PeakWorkingSet'; Expression={ $_.PeakWorkingSet64 }},
        @{Name='PrivateMemory';  Expression={ $_.PrivateMemorySize64 }},
        @{Name='Threads';        Expression={ $_.Threads.Count }},
        @{Name='Handles';        Expression={ $_.HandleCount }},
        @{Name='PageFaults';     Expression={ $_.PagedMemorySize64 }},
        @{Name='Description';    Expression={ $_.Description }},
        @{Name='Path';           Expression={ if ($cimProcessMap.ContainsKey($_.Id)) { $cimProcessMap[$_.Id] } else { 'N/A' } }},
        @{Name='Company';        Expression={
            $exePath = if ($cimProcessMap.ContainsKey($_.Id)) { $cimProcessMap[$_.Id] } else { $null }
            if ($exePath -and (Test-Path $exePath -ErrorAction SilentlyContinue)) {
                try { [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exePath).CompanyName } catch { '' }
            } else { '' }
        }}

# Per-core results
if ($perfSample2) {
    $coreResults = $perfSample2.CounterSamples |
        Where-Object { $_.InstanceName -ne '_total' -and $_.Path -like '*% processor time*' } |
        Sort-Object { [int]($_.InstanceName) } |
        Select-Object @{Name='Core'; Expression={ "Core $($_.InstanceName)" }},
                      @{Name='CPU %'; Expression={ [math]::Round($_.CookedValue, 1) }}

    Write-Host "Per-Core Utilization (sorted by core number):" -ForegroundColor Green
    $coreLines = $coreResults | ForEach-Object { "$($_.Core): $($_.'CPU %')%".PadRight(22) }
    $colCount  = 4
    for ($i = 0; $i -lt $coreLines.Count; $i += $colCount) {
        Write-Host ('  ' + ($coreLines[$i..([math]::Min($i + $colCount - 1, $coreLines.Count - 1))] -join ''))
    }
    Write-Host ""

    $hotCore = $coreResults | Where-Object { $_.'CPU %' -gt 90 }
    if ($hotCore) {
        Write-Alert "$($hotCore.Count) core(s) above 90% — possible single-threaded bottleneck." 'Critical'
        Add-Recommendation "$($hotCore.Count) CPU core(s) are pegged above 90%. If a single core is saturated, suspect a single-threaded process or runaway thread. Use Process Explorer for thread-level CPU attribution." "CRITICAL"
    }

    # Interrupt / DPC overhead
    $interruptPct = ($perfSample2.CounterSamples |
        Where-Object { $_.InstanceName -eq '_total' -and $_.Path -like '*% interrupt time*' } |
        Select-Object -First 1).CookedValue
    $dpcPct = ($perfSample2.CounterSamples |
        Where-Object { $_.InstanceName -eq '_total' -and $_.Path -like '*% dpc time*' } |
        Select-Object -First 1).CookedValue

    if ($null -ne $interruptPct) {
        $interruptPct = [math]::Round($interruptPct, 2)
        $dpcPct       = [math]::Round($dpcPct, 2)
        Write-Host "`nInterrupt time (total): $interruptPct%   DPC time: $dpcPct%" -ForegroundColor $(if ($interruptPct -gt 10 -or $dpcPct -gt 5) { 'Red' } else { 'Green' })
        if ($interruptPct -gt 10) {
            Add-Recommendation "High CPU interrupt time ($interruptPct%). Likely cause: faulty/outdated driver (network, storage, or GPU). Run 'xperf' or 'WPA' to identify the offending driver." "CRITICAL"
        }
        if ($dpcPct -gt 5) {
            Add-Recommendation "Elevated DPC time ($dpcPct%). Often caused by Wi-Fi, audio, or NIC drivers. Update or replace the driver. Consider disabling 'Receive Side Scaling' on the NIC as a test." "WARNING"
        }
    }
}

# Process CPU delta
$cpuUsage = foreach ($p2 in $processes2) {
    $p1 = $processes1 | Where-Object { $_.Id -eq $p2.Id }
    if ($p1) {
        $cpuDelta   = ($p2.CPUTime2 - $p1.CPUTime1).TotalSeconds
        $cpuPercent = [math]::Round(($cpuDelta / $MonitorDuration) * 100 / $env:NUMBER_OF_PROCESSORS, 2)
        [PSCustomObject]@{
            ProcessName    = $p2.ProcessName
            PID            = $p2.Id
            'CPU %'        = $cpuPercent
            'Total CPU(s)' = [math]::Round($p2.CPU, 2)
            Threads        = $p2.Threads
            Handles        = $p2.Handles
            Company        = $p2.Company
        }
    }
}

$topCPU = $cpuUsage | Where-Object { $_.'CPU %' -gt 0 } |
    Sort-Object 'CPU %' -Descending |
    Select-Object -First $TopProcessCount

Write-Host "`nTop $TopProcessCount CPU-Intensive Processes (over $MonitorDuration s sample):" -ForegroundColor Green
$topCPU | Select-Object ProcessName, PID, 'CPU %', 'Total CPU(s)', Threads, Handles |
    Format-Table -AutoSize

$overallCPULoad = [math]::Round(($perfSample2.CounterSamples |
    Where-Object { $_.InstanceName -eq '_total' -and $_.Path -like '*% processor time*' } |
    Select-Object -First 1).CookedValue, 1)

$cpuLoad = if ($overallCPULoad -gt 0) { $overallCPULoad } else {
    (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
}
Write-Host "Overall CPU Load (counter): $cpuLoad%" -ForegroundColor $(if ($cpuLoad -gt 80) { 'Red' } elseif ($cpuLoad -gt 50) { 'Yellow' } else { 'Green' })

if ($cpuLoad -gt 80) {
    Add-Recommendation "Sustained CPU load of $cpuLoad%. Identify the top process above and consider terminating, restarting, or scheduling it for off-peak hours." "CRITICAL"
}

# Processes with excessive thread counts (possible thread leak)
$threadHogs = $processes2 | Where-Object { $_.Threads -gt 500 } | Sort-Object Threads -Descending
if ($threadHogs) {
    Write-Host "`nProcesses with excessive thread counts (>500):" -ForegroundColor Red
    $threadHogs | Select-Object ProcessName, Id, Threads | Format-Table -AutoSize
    foreach ($p in $threadHogs) {
        Add-Recommendation "Process '$($p.ProcessName)' (PID $($p.Id)) has $($p.Threads) threads — possible thread leak. Restart the process if it is non-critical." "WARNING"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# Memory Deep Analysis
# ──────────────────────────────────────────────────────────────────────────────
Write-SectionHeader "Memory Deep Analysis"

# Pagefile
$pageFile = Get-CimInstance Win32_PageFileUsage
if ($pageFile) {
    foreach ($pf in $pageFile) {
        $pfUsedPct = if ($pf.AllocatedBaseSize -gt 0) { [math]::Round(($pf.CurrentUsage / $pf.AllocatedBaseSize) * 100, 1) } else { 0 }
        Write-Host "Pagefile: $($pf.Name)  |  Allocated: $($pf.AllocatedBaseSize) MB  |  In Use: $($pf.CurrentUsage) MB  |  Peak: $($pf.PeakUsage) MB  |  Usage: $pfUsedPct%" -ForegroundColor $(if ($pfUsedPct -gt 75) { 'Red' } elseif ($pfUsedPct -gt 50) { 'Yellow' } else { 'Green' })
        if ($pfUsedPct -gt 75) {
            Add-Recommendation "Pagefile '$($pf.Name)' is $pfUsedPct% full ($($pf.CurrentUsage) MB of $($pf.AllocatedBaseSize) MB). System is paging heavily — adding RAM or increasing pagefile size will help." "CRITICAL"
        }
    }
} else {
    Write-Host "No pagefile detected (or pagefile on system-managed setting)." -ForegroundColor Yellow
}

# Pool / commit via performance counters
$memCounters = @('\Memory\Available MBytes', '\Memory\Committed Bytes', '\Memory\Commit Limit',
                 '\Memory\Page Faults/sec', '\Memory\Pages/sec', '\Memory\Pool Nonpaged Bytes',
                 '\Memory\Pool Paged Bytes', '\Memory\Cache Bytes')
try {
    $memPerf = (Get-Counter -Counter $memCounters -ErrorAction Stop).CounterSamples
    $pagesSec       = [math]::Round(($memPerf | Where-Object Path -like '*pages/sec*').CookedValue, 0)
    $pageFaultsSec  = [math]::Round(($memPerf | Where-Object Path -like '*page faults/sec*').CookedValue, 0)
    $commitBytes    = ($memPerf | Where-Object Path -like '*committed bytes*').CookedValue
    $commitLimit    = ($memPerf | Where-Object Path -like '*commit limit*').CookedValue
    $commitPct      = [math]::Round(($commitBytes / $commitLimit) * 100, 1)
    $nonPagedPool   = Get-FormattedBytes ([long]($memPerf | Where-Object Path -like '*pool nonpaged*').CookedValue)
    $pagedPool      = Get-FormattedBytes ([long]($memPerf | Where-Object Path -like '*pool paged bytes*').CookedValue)
    $cacheBytes     = Get-FormattedBytes ([long]($memPerf | Where-Object Path -like '*cache bytes*').CookedValue)

    Write-Host "`nMemory Commit   : $(Get-FormattedBytes ([long]$commitBytes)) of $(Get-FormattedBytes ([long]$commitLimit))  ($commitPct%)"
    Write-Host "Pages/sec       : $pagesSec  (> 1000 indicates memory pressure)" -ForegroundColor $(if ($pagesSec -gt 1000) { 'Red' } elseif ($pagesSec -gt 200) { 'Yellow' } else { 'Green' })
    Write-Host "Page Faults/sec : $pageFaultsSec"
    Write-Host "Non-Paged Pool  : $nonPagedPool"
    Write-Host "Paged Pool      : $pagedPool"
    Write-Host "File Cache      : $cacheBytes"

    if ($commitPct -gt 85) {
        Add-Recommendation "Memory commit charge is at $commitPct% of the commit limit. Add RAM or increase pagefile size to prevent out-of-memory conditions." "CRITICAL"
    }
    if ($pagesSec -gt 1000) {
        Add-Recommendation "Pages/sec rate is $pagesSec — severe memory thrashing. The system is actively paging. Immediate RAM upgrade recommended." "CRITICAL"
    } elseif ($pagesSec -gt 200) {
        Add-Recommendation "Pages/sec rate is $pagesSec — moderate paging. Consider closing memory-hungry applications or adding RAM." "WARNING"
    }
} catch {
    Write-Host "Could not retrieve memory performance counters." -ForegroundColor Yellow
}

# Per-process memory
$topMemory = $processes2 |
    Select-Object ProcessName, Id,
        @{Name='RAM (MB)';      Expression={ [math]::Round($_.WorkingSet / 1MB, 1) }},
        @{Name='Peak (MB)';     Expression={ [math]::Round($_.PeakWorkingSet / 1MB, 1) }},
        @{Name='Private (MB)'; Expression={ [math]::Round($_.PrivateMemory / 1MB, 1) }},
        @{Name='Threads';      Expression={ $_.Threads }} |
    Sort-Object 'RAM (MB)' -Descending |
    Select-Object -First $TopProcessCount

Write-Host "`nTop $TopProcessCount Memory-Intensive Processes:" -ForegroundColor Green
$topMemory | Format-Table -AutoSize

if ($memUsagePct -gt 85) {
    Add-Recommendation "Physical memory usage is at $memUsagePct%. The top consumers above are your best candidates for termination or scheduling." "CRITICAL"
}

# ──────────────────────────────────────────────────────────────────────────────
# Handle & Thread Analysis
# ──────────────────────────────────────────────────────────────────────────────
Write-SectionHeader "Handle & Thread Analysis"

$handles = $processes2 |
    Select-Object ProcessName, Id,
        @{Name='Handles';     Expression={ $_.Handles }},
        @{Name='Threads';     Expression={ $_.Threads }},
        @{Name='RAM (MB)';    Expression={ [math]::Round($_.WorkingSet / 1MB, 1) }} |
    Sort-Object Handles -Descending |
    Select-Object -First $TopProcessCount

Write-Host "Top $TopProcessCount Processes by Handle Count:" -ForegroundColor Green
$handles | Format-Table -AutoSize

foreach ($h in ($handles | Where-Object { $_.Handles -gt 10000 })) {
    Add-Recommendation "Process '$($h.ProcessName)' (PID $($h.Id)) has $($h.Handles) handles — likely a handle leak. Restart the process if possible." "WARNING"
}

# ──────────────────────────────────────────────────────────────────────────────
# Disk Analysis (space + I/O queue depth + latency)
# ──────────────────────────────────────────────────────────────────────────────
Write-SectionHeader "Disk Analysis"

$disks = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 } |
    Select-Object DeviceID,
        @{Name='Size (GB)';  Expression={ [math]::Round($_.Size / 1GB, 2) }},
        @{Name='Free (GB)';  Expression={ [math]::Round($_.FreeSpace / 1GB, 2) }},
        @{Name='Used %';     Expression={ [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 2) }},
        @{Name='FileSystem'; Expression={ $_.FileSystem }}

Write-Host "Disk Space:" -ForegroundColor Green
$disks | Format-Table -AutoSize

foreach ($d in $disks) {
    if ($d.'Used %' -gt 95) {
        Add-Recommendation "Drive $($d.DeviceID) is $($d.'Used %')% full ($($d.'Free (GB)') GB free). Critically low — OS and apps may malfunction. Free space immediately." "CRITICAL"
    } elseif ($d.'Used %' -gt 85) {
        Add-Recommendation "Drive $($d.DeviceID) is $($d.'Used %')% full. Low disk space can severely degrade performance. Clean up or expand storage." "WARNING"
    }
}

# Disk queue length and throughput via perf counters
try {
    $diskCounters = @('\PhysicalDisk(*)\Avg. Disk Queue Length',
                      '\PhysicalDisk(*)\Avg. Disk sec/Read',
                      '\PhysicalDisk(*)\Avg. Disk sec/Write',
                      '\PhysicalDisk(*)\Disk Read Bytes/sec',
                      '\PhysicalDisk(*)\Disk Write Bytes/sec')
    $diskPerf = (Get-Counter -Counter $diskCounters -SampleInterval 2 -MaxSamples 3 -ErrorAction Stop).CounterSamples |
        Group-Object InstanceName

    Write-Host "`nPhysical Disk I/O Metrics (3-sample avg):" -ForegroundColor Green
    $diskPerfResults = foreach ($disk in $diskPerf | Where-Object { $_.Name -ne '_total' }) {
        $getVal = { param($pattern) ($disk.Group | Where-Object Path -like $pattern | Measure-Object CookedValue -Average).Average }
        $queue   = [math]::Round((& $getVal '*queue length*'), 2)
        $readMs  = [math]::Round((& $getVal '*sec/read*') * 1000, 2)
        $writeMs = [math]::Round((& $getVal '*sec/write*') * 1000, 2)
        $readMB  = [math]::Round((& $getVal '*read bytes*') / 1MB, 2)
        $writeMB = [math]::Round((& $getVal '*write bytes*') / 1MB, 2)
        [PSCustomObject]@{
            Disk            = $disk.Name
            'Queue Depth'   = $queue
            'Read Lat (ms)' = $readMs
            'Write Lat(ms)' = $writeMs
            'Read MB/s'     = $readMB
            'Write MB/s'    = $writeMB
        }
    }
    $diskPerfResults | Format-Table -AutoSize

    foreach ($dr in $diskPerfResults) {
        if ($dr.'Queue Depth' -gt 2) {
            Add-Recommendation "Disk '$($dr.Disk)' has a queue depth of $($dr.'Queue Depth'). Values >2 indicate the disk cannot keep up with demand. Possible HDD under heavy load or a failing drive. Check with CrystalDiskInfo." "WARNING"
        }
        if ($dr.'Read Lat (ms)' -gt 20 -or $dr.'Write Lat(ms)' -gt 20) {
            Add-Recommendation "Disk '$($dr.Disk)' has high latency (Read: $($dr.'Read Lat (ms)')ms / Write: $($dr.'Write Lat(ms)')ms). Acceptable is <10ms for HDD, <1ms for SSD. Consider defrag (HDD) or health check." "WARNING"
        }
    }
} catch {
    Write-Host "Could not retrieve disk performance counters." -ForegroundColor Yellow
}

# Disk I/O per process (admin only, if requested)
if ($IncludeDiskIO) {
    if ($isAdmin) {
        Write-Host "`nCollecting per-process Disk I/O..." -ForegroundColor Yellow
        try {
            $ioSamples = Get-Counter '\Process(*)\IO Data Bytes/sec' -SampleInterval 2 -MaxSamples 3 -ErrorAction Stop
            $topDiskIO = $ioSamples.CounterSamples |
                Where-Object { $_.CookedValue -gt 0 -and $_.InstanceName -ne '_total' } |
                Group-Object InstanceName |
                ForEach-Object {
                    [PSCustomObject]@{
                        Process      = $_.Name
                        'IO (MB/s)'  = [math]::Round(($_.Group | Measure-Object CookedValue -Average).Average / 1MB, 3)
                    }
                } |
                Sort-Object 'IO (MB/s)' -Descending |
                Select-Object -First $TopProcessCount

            Write-Host "`nTop $TopProcessCount Processes by Disk I/O:" -ForegroundColor Green
            $topDiskIO | Format-Table -AutoSize
        } catch {
            Write-Host "Could not collect per-process I/O counters." -ForegroundColor Yellow
        }
    } else {
        Write-Alert "Per-process Disk I/O analysis requires administrator privileges." 'Warning'
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# Network Analysis (throughput + TCP connections)
# ──────────────────────────────────────────────────────────────────────────────
Write-SectionHeader "Network Analysis"

$networkAdapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } |
    Select-Object Name, InterfaceDescription,
        @{Name='Speed'; Expression={ if ($_.LinkSpeed -ge 1GB) { "$([math]::Round($_.LinkSpeed/1GB,0)) Gbps" } else { "$([math]::Round($_.LinkSpeed/1MB,0)) Mbps" } }},
        MacAddress, Status

Write-Host "Active Network Adapters:" -ForegroundColor Green
$networkAdapters | Format-Table -AutoSize

# Network throughput via perf counters
try {
    $nicNames  = (Get-NetAdapter | Where-Object Status -eq 'Up').InterfaceDescription
    $nicCounters = $nicNames | ForEach-Object {
        $safe = $_ -replace '[()#*\\]', '?'
        "\Network Interface($safe)\Bytes Received/sec"
        "\Network Interface($safe)\Bytes Sent/sec"
    }
    if ($nicCounters) {
        $netSamples  = (Get-Counter -Counter $nicCounters -SampleInterval 2 -MaxSamples 3 -ErrorAction Stop).CounterSamples |
            Group-Object InstanceName
        Write-Host "`nNIC Throughput (3-sample avg):" -ForegroundColor Green
        $netResults = foreach ($nic in $netSamples) {
            $nicShort = if ($nic.Name.Length -gt 40) { $nic.Name.Substring(0,37) + '...' } else { $nic.Name }
            [PSCustomObject]@{
                NIC           = $nicShort
                'Recv (Mbps)' = [math]::Round(($nic.Group | Where-Object Path -like '*received*' | Measure-Object CookedValue -Average).Average * 8 / 1MB, 3)
                'Send (Mbps)' = [math]::Round(($nic.Group | Where-Object Path -like '*sent*'     | Measure-Object CookedValue -Average).Average * 8 / 1MB, 3)
            }
        }
        $netResults | Format-Table -AutoSize
    }
} catch {
    Write-Host "Could not retrieve network throughput counters." -ForegroundColor Yellow
}

# TCP connection states
try {
    $tcpStats = Get-NetTCPConnection -ErrorAction Stop |
        Group-Object State |
        Select-Object @{Name='State'; Expression={ $_.Name }}, @{Name='Count'; Expression={ $_.Count }} |
        Sort-Object Count -Descending

    Write-Host "`nTCP Connection States:" -ForegroundColor Green
    $tcpStats | Format-Table -AutoSize

    $timeWait  = ($tcpStats | Where-Object State -eq 'TimeWait').Count
    $closeWait = ($tcpStats | Where-Object State -eq 'CloseWait').Count
    if ($timeWait -gt 500) {
        Add-Recommendation "$timeWait connections in TIME_WAIT. Likely a high-throughput service creating/destroying connections rapidly. Consider enabling TCP keep-alives or connection pooling in the application." "WARNING"
    }
    if ($closeWait -gt 100) {
        Add-Recommendation "$closeWait connections in CLOSE_WAIT. The local application is not closing sockets properly — possible connection leak. Identify the owning process and review code or restart the service." "WARNING"
    }

    # Top processes by connection count
    $topConnProcs = Get-NetTCPConnection -ErrorAction Stop |
        Where-Object { $_.OwningProcess -gt 0 } |
        Group-Object OwningProcess |
        ForEach-Object {
            $proc = Get-Process -Id $_.Name -ErrorAction SilentlyContinue
            [PSCustomObject]@{
                Process     = if ($proc) { $proc.ProcessName } else { "PID $($_.Name)" }
                PID         = $_.Name
                Connections = $_.Count
            }
        } |
        Sort-Object Connections -Descending |
        Select-Object -First 10

    Write-Host "`nTop Processes by TCP Connection Count:" -ForegroundColor Green
    $topConnProcs | Format-Table -AutoSize
} catch {
    Write-Host "Could not retrieve TCP connection data." -ForegroundColor Yellow
}

# ──────────────────────────────────────────────────────────────────────────────
# Event Log Analysis
# ──────────────────────────────────────────────────────────────────────────────
Write-SectionHeader "Event Log Analysis (Last $EventLogHours hours)"

$since     = (Get-Date).AddHours(-$EventLogHours)
$logs      = @('System', 'Application')
$allEvents = [System.Collections.Generic.List[object]]::new()

foreach ($log in $logs) {
    try {
        $events = Get-WinEvent -FilterHashtable @{ LogName = $log; Level = 1,2; StartTime = $since } -ErrorAction SilentlyContinue
        if ($events) { $events | ForEach-Object { $allEvents.Add($_) } }
    } catch { }
}

if ($allEvents.Count -eq 0) {
    Write-Alert "No Critical or Error events found in the last $EventLogHours hours." 'Good'
} else {
    $eventSummary = $allEvents |
        Group-Object { "$($_.LogName)|$($_.ProviderName)|$($_.Id)" } |
        ForEach-Object {
            $first = $_.Group | Select-Object -First 1
            [PSCustomObject]@{
                Log          = $first.LogName
                Source       = $first.ProviderName
                EventID      = $first.Id
                Level        = $first.LevelDisplayName
                Count        = $_.Count
                'Last Seen'  = ($_.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated
                Message      = ($first.Message -split "`n")[0] -replace '\s+', ' '
            }
        } |
        Sort-Object Count -Descending |
        Select-Object -First 20

    Write-Host "Top recurring errors/critical events (last $EventLogHours hours):" -ForegroundColor Red
    $eventSummary | Format-Table -AutoSize -Property Log,
        @{Name='Source';    Expression={ if ($_.Source.Length -gt 30) { $_.Source.Substring(0,27)+'...' } else { $_.Source } }},
        EventID, Level, Count, 'Last Seen'
    Write-Host "Sample messages from top 5 events:" -ForegroundColor Green
    $eventSummary | Select-Object -First 5 | ForEach-Object {
        $msg = ($_.Message -replace '\s+', ' ').Trim()
        $msg = if ($msg.Length -gt 110) { $msg.Substring(0,107) + '...' } else { $msg }
        Write-Host "  [ID $($_.EventID) / $($_.Source -replace '.+\.', '')] $msg" -ForegroundColor Yellow
    }

    $critCount = ($allEvents | Where-Object LevelDisplayName -eq 'Critical').Count
    $errCount  = ($allEvents | Where-Object LevelDisplayName -eq 'Error').Count
    Add-Recommendation "$critCount Critical and $errCount Error events in the last $EventLogHours hours. Review the event sources above — repeated disk, NTFS, WHEA, disk controller, or memory errors require immediate attention." "$(if ($critCount -gt 0) { 'CRITICAL' } else { 'WARNING' })"
}

# Specific high-value event IDs
$criticalEventIds = @{
    41    = 'Kernel-Power — unexpected reboot (crash/power loss)'
    1001  = 'BugCheck — system crash (BSOD)'
    7034  = 'Service crashed unexpectedly'
    7031  = 'Service terminated unexpectedly'
    7023  = 'Service terminated with error'
    51    = 'Disk warning — possible impending disk failure'
    11    = 'Disk controller error'
    55    = 'NTFS file system corruption'
    4    = 'atapi — bad block on disk'
    6008  = 'Dirty shutdown / unexpected power loss'
}

$foundCritical = foreach ($eid in $criticalEventIds.Keys) {
    $matchedEvents = $allEvents | Where-Object Id -eq $eid
    if ($matchedEvents) {
        [PSCustomObject]@{
            EventID     = $eid
            Count       = $matchedEvents.Count
            Description = $criticalEventIds[$eid]
        }
    }
}

if ($foundCritical) {
    Write-Host "`nHigh-Priority Event IDs detected:" -ForegroundColor Red
    $foundCritical | Format-Table -AutoSize
    foreach ($fe in $foundCritical) {
        Add-Recommendation "EventID $($fe.EventID) detected $($fe.Count) time(s): '$($fe.Description)'. This requires investigation." "CRITICAL"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# Problematic Devices / Drivers
# ──────────────────────────────────────────────────────────────────────────────
Write-SectionHeader "Device & Driver Health"

try {
    $problemDevices = Get-CimInstance Win32_PnPEntity |
        Where-Object { $_.ConfigManagerErrorCode -ne 0 } |
        Select-Object Name, DeviceID,
            @{Name='ErrorCode'; Expression={ $_.ConfigManagerErrorCode }},
            @{Name='Status';    Expression={ $_.Status }}

    if ($problemDevices) {
        Write-Alert "$($problemDevices.Count) device(s) with errors detected!" 'Critical'
        $problemDevices | Select-Object `
            @{Name='Name';      Expression={ if ($_.Name.Length -gt 45) { $_.Name.Substring(0,42)+'...' } else { $_.Name } }},
            @{Name='DeviceID';  Expression={ ($_.DeviceID -split '\\')[-1] }},
            ErrorCode, Status |
            Format-Table -AutoSize
        foreach ($dev in $problemDevices) {
            Add-Recommendation "Device '$($dev.Name)' has ConfigManager error code $($dev.ErrorCode). Update or reinstall the driver, or check Device Manager for details." "CRITICAL"
        }
    } else {
        Write-Alert "No device/driver errors detected." 'Good'
    }
} catch {
    Write-Host "Could not query device health." -ForegroundColor Yellow
}

# ──────────────────────────────────────────────────────────────────────────────
# Service Analysis
# ──────────────────────────────────────────────────────────────────────────────
Write-SectionHeader "Service Analysis"

$runningCount  = (Get-Service | Where-Object Status -eq 'Running' | Measure-Object).Count
Write-Host "Running Services: $runningCount" -ForegroundColor Yellow

$autoNotRunning = Get-Service | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' }
if ($autoNotRunning) {
    Write-Alert "$($autoNotRunning.Count) Automatic service(s) are not running:" 'Warning'
    $autoNotRunning | Select-Object Name, DisplayName, Status | Sort-Object DisplayName | Format-Table -AutoSize
    foreach ($svc in $autoNotRunning) {
        Add-Recommendation "Service '$($svc.DisplayName)' is set to Automatic but is not running. If this is a critical service (e.g., Windows Update, DNS Client, BITS), restart it with: Start-Service -Name '$($svc.Name)'" "WARNING"
    }
}

# Services with high CPU — cross-reference
$svcHostCPU = $topCPU | Where-Object { $_.ProcessName -eq 'svchost' }
if ($svcHostCPU) {
    Write-Host "`nHigh-CPU svchost processes detected. Drilling into hosted services:" -ForegroundColor Yellow
    foreach ($sh in $svcHostCPU) {
        try {
            $hostedSvcs = Get-CimInstance -Query "ASSOCIATORS OF {Win32_Process.Handle='$($sh.PID)'} WHERE AssocClass=Win32_ServiceToProcess" -ErrorAction SilentlyContinue
            if ($hostedSvcs) {
                $svcNames = $hostedSvcs.Name -join ', '
                Write-Host "  PID $($sh.PID) ($($sh.'CPU %')% CPU) hosts: $svcNames" -ForegroundColor Yellow
                Add-Recommendation "svchost PID $($sh.PID) using $($sh.'CPU %')% CPU hosts: $svcNames. Investigate these services individually." "WARNING"
            }
        } catch { }
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# Startup Programs
# ──────────────────────────────────────────────────────────────────────────────
Write-SectionHeader "Startup Impact"

$startupApps = Get-CimInstance Win32_StartupCommand |
    Select-Object Name, Command, Location, User

Write-Host "Total Startup Programs: $($startupApps.Count)" -ForegroundColor Yellow
$startupApps | Sort-Object Location, Name |
    Select-Object `
        @{Name='Name';     Expression={ if ($_.Name.Length -gt 35)     { $_.Name.Substring(0,32)+'...' }     else { $_.Name } }},
        @{Name='Location'; Expression={ if ($_.Location.Length -gt 30) { $_.Location.Substring(0,27)+'...' } else { $_.Location } }},
        User |
    Format-Table -AutoSize

if ($startupApps.Count -gt 20) {
    Add-Recommendation "You have $($startupApps.Count) startup programs. Use Task Manager > Startup tab or 'msconfig' to disable non-essential entries. Each adds latency at boot and consumes background resources." "WARNING"
}

# ──────────────────────────────────────────────────────────────────────────────
# Windows Update Pending Reboot Check
# ──────────────────────────────────────────────────────────────────────────────
Write-SectionHeader "Pending Reboot Check"

$rebootRequired  = $false
$rebootReasons   = @()

$cbsKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
$wuKey  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
$pfKey  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'

if (Test-Path $cbsKey)  { $rebootRequired = $true; $rebootReasons += 'CBS (Component Based Servicing)' }
if (Test-Path $wuKey)   { $rebootRequired = $true; $rebootReasons += 'Windows Update' }
try {
    $pfValue = Get-ItemProperty -Path $pfKey -Name 'PendingFileRenameOperations' -ErrorAction Stop
    if ($pfValue) { $rebootRequired = $true; $rebootReasons += 'Pending File Rename Operations' }
} catch { }

if ($rebootRequired) {
    Write-Alert "Reboot is pending for: $($rebootReasons -join ', ')" 'Warning'
    Add-Recommendation "A system reboot is pending ($($rebootReasons -join '; ')). Reboot to complete updates and potentially improve performance." "WARNING"
} else {
    Write-Alert "No pending reboot detected." 'Good'
}

# ──────────────────────────────────────────────────────────────────────────────
# Process Anomaly Detection
# ──────────────────────────────────────────────────────────────────────────────
if ($IncludeProcessAnomalies) {
    Write-SectionHeader "Process Anomaly Detection"

    $suspicious = [System.Collections.Generic.List[object]]::new()
    $tempPaths  = @($env:TEMP, $env:TMP, "$env:SystemRoot\Temp", "$env:LOCALAPPDATA\Temp")

    foreach ($p in $processes2) {
        if ($p.Path -eq 'N/A' -or [string]::IsNullOrEmpty($p.Path)) { continue }
        $flags = @()

        # Running from a temp directory
        foreach ($tp in $tempPaths) {
            if ($p.Path -like "$tp*") { $flags += "Runs from temp path ($tp)" }
        }

        # Running from Downloads or AppData\Roaming
        if ($p.Path -like '*\Downloads\*')        { $flags += "Runs from Downloads folder" }
        if ($p.Path -like '*AppData\Roaming\*' -and $p.Company -notmatch 'Microsoft|Google|Mozilla|Adobe') {
            $flags += "Runs from AppData\Roaming"
        }

        # No company name and no description
        if ([string]::IsNullOrEmpty($p.Company) -and [string]::IsNullOrEmpty($p.Description)) {
            $flags += "No company or description metadata"
        }

        # Check signature (skip paths that are inaccessible)
        if ($p.Path -ne 'N/A' -and $p.Path -and (Test-Path $p.Path -ErrorAction SilentlyContinue)) {
            try {
                $sig = Get-AuthenticodeSignature -FilePath $p.Path -ErrorAction SilentlyContinue
                if ($sig -and $sig.Status -eq 'NotSigned') {
                    $flags += "Executable is unsigned"
                } elseif ($sig -and $sig.Status -notin @('Valid','UnknownError')) {
                    $flags += "Signature invalid ($($sig.Status))"
                }
            } catch { }
        }

        if ($flags.Count -gt 0) {
            $suspicious.Add([PSCustomObject]@{
                ProcessName = $p.ProcessName
                PID         = $p.Id
                Path        = $p.Path
                Company     = $p.Company
                Flags       = $flags -join ' | '
            })
        }
    }

    if ($suspicious.Count -gt 0) {
        Write-Alert "$($suspicious.Count) potentially anomalous process(es) found:" 'Warning'
        foreach ($s in $suspicious) {
            Write-Host "`n  Process : $($s.ProcessName)  (PID $($s.PID))" -ForegroundColor Yellow
            Write-Host "  Flags   : $($s.Flags)" -ForegroundColor Yellow
            Write-Host "  Path    : $($s.Path)" -ForegroundColor DarkYellow
        }
        Add-Recommendation "$($suspicious.Count) process(es) exhibit anomalous traits (unsigned, running from temp, no metadata). Review them carefully with Process Explorer or VirusTotal." "WARNING"
    } else {
        Write-Alert "No obviously anomalous processes detected." 'Good'
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# Consolidated Recommendations
# ──────────────────────────────────────────────────────────────────────────────
Write-SectionHeader "Actionable Recommendations Summary"

if ($recommendations.Count -eq 0) {
    Write-Alert "No significant performance issues detected. System appears healthy." 'Good'
} else {
    $critical = $recommendations | Where-Object { $_ -like '*[CRITICAL]*' }
    $warnings = $recommendations | Where-Object { $_ -like '*[WARNING]*' }
    $info     = $recommendations | Where-Object { $_ -like '*[INFO]*' }

    if ($critical) {
        Write-Host "`n--- CRITICAL ($($critical.Count)) ---" -ForegroundColor Red
        $critical | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    }
    if ($warnings) {
        Write-Host "`n--- WARNINGS ($($warnings.Count)) ---" -ForegroundColor Yellow
        $warnings | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    }
    if ($info) {
        Write-Host "`n--- INFO ($($info.Count)) ---" -ForegroundColor Cyan
        $info | ForEach-Object { Write-Host $_ -ForegroundColor Cyan }
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Analysis Complete — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan
