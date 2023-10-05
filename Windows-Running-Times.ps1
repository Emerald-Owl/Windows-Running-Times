# Collect params, start/end date, and how many events to grab. 
# Defaults to 99999 events and anything from 01/01/1980 to the day after execution 
param(
    [string]$startDate = "01/01/1980",
    [string]$endDate = ((Get-Date).AddDays(1)).ToString("MM/dd/yyyy")
)

# Check for MM/dd/yyyy formatting of the start date param
try {
    $startDateTime = [datetime]::ParseExact($startDate, "MM/dd/yyyy", $null)
    $endDateTime = [datetime]::ParseExact($endDate, "MM/dd/yyyy", $null)
} 
catch {
    Write-Host "Invalid date format. Please use MM/dd/yyyy." -ForegroundColor Red
    return
}

function Format-Duration {
    param ([TimeSpan]$duration)
    return "{0} Days, {1:D2}:{2:D2}:{3:D2}" -f $duration.Days, $duration.Hours, $duration.Minutes, $duration.Seconds
}

# Get events with Provider 'Microsoft-Windows-Kernel-Power' and EventID 41 or 42
$eventsKernelPower = Get-WinEvent -FilterHashtable @{
    LogName = 'System';
    ProviderName = 'Microsoft-Windows-Kernel-Power';
    Id = 41,42;
    StartTime=$startDateTime;
    EndTime=$endDateTime;
} -ErrorAction SilentlyContinue

# Get events with Provider 'Microsoft-Windows-Power-Troubleshooter' and EventID 1
$eventsPowerTroubleshooter = Get-WinEvent -FilterHashtable @{
    LogName = 'System';
    ProviderName = 'Microsoft-Windows-Power-Troubleshooter';
    Id = 1;
    StartTime=$startDateTime;
    EndTime=$endDateTime;
} -ErrorAction SilentlyContinue

# Get events with Provider 'USER32' and EventID 1074
$eventsUser32 = Get-WinEvent -FilterHashtable @{
    LogName = 'System';
    ProviderName = 'USER32';
    Id = 1074;
    StartTime=$startDateTime;
    EndTime=$endDateTime;
} -ErrorAction SilentlyContinue

# Get events with Provider 'EventLog' and EventID 6005 or 6006
$eventsEventLog = Get-WinEvent -FilterHashtable @{
    LogName = 'System';
    ProviderName = 'EventLog';
    Id = 6005, 6006;
    StartTime=$startDateTime;
    EndTime=$endDateTime;
} -ErrorAction SilentlyContinue

$systemActivity = @()
$startEvent = $null
$shutdownEvent = $null

# Combine all the events and sort them
$events = $eventsKernelPower + $eventsPowerTroubleshooter + $eventsUser32 + $eventsEventLog | Sort-Object TimeCreated

foreach ($event in $events) {
    switch ($event.Id) {
        # 41: Unexpected Shutdown
        41 {
            if ($startEvent) {
                $systemActivity += [PSCustomObject]@{
                    StartTime    = $startEvent.TimeCreated.ToUniversalTime()
                    ShutdownTime = $null
                    Duration     = "Unknown"
                    ShutdownType = "Unexpected Shutdown!"
                }
                $startEvent = $null
                $shutdownEvent = $null
            }
        }
        # 1: Wake from sleep
        # 6005: Event Log service started
        {($_ -eq 1) -or ($_ -eq 6005)} {
            if ($startEvent) {
                if ($event.TimeCreated - $startEvent.TimeCreated -lt [TimeSpan]::FromMinutes(1)) {
                    continue
                }
                $systemActivity += [PSCustomObject]@{
                    StartTime    = $startEvent.TimeCreated.ToUniversalTime()
                    ShutdownTime = $null
                    Duration     = "Unknown"
                    ShutdownType = "No Shutdown Event"
                }
            }
            $startEvent = $event
            $shutdownEvent = $null
        }
        # 42: Entering sleep
        # 1074: Process initiated a restart 
        # Event log service stoped
        {($_ -eq 42) -or ($_ -eq 1074) -or ($_ -eq 6006)} { 
            if ($startEvent) {
                $shutdownEvent = $event
                $shutdownType = if ($event.Id -eq 42) {
                    "Sleep Mode"
                } else {
                    "User Initiated"
                }
                if ($event.Id -eq 1074) {
                    # Extracting parameter values
                    $shutdownreason = $event.Properties[2].Value
                    $shutdownOrRestart = $event.Properties[4].Value
                    $shutdownType = "$shutdownOrRestart - $shutdownreason"
                }
                $systemActivity += [PSCustomObject]@{
                    StartTime    = $startEvent.TimeCreated.ToUniversalTime()
                    ShutdownTime = $shutdownEvent.TimeCreated.ToUniversalTime()
                    Duration     = Format-Duration ($shutdownEvent.TimeCreated - $startEvent.TimeCreated)
                    ShutdownType = $shutdownType
                }
                $startEvent = $null
            }
        }
    }
}

# Check if the last startup event doesn't have a shutdown event
if ($startEvent -and -not $shutdownEvent) {
    $currentTime = Get-Date
    $currentDuration = $currentTime - $startEvent.TimeCreated
    
    $systemActivity += [PSCustomObject]@{
        StartTime    = $startEvent.TimeCreated.ToUniversalTime()
        ShutdownTime = $null
        Duration     = Format-Duration $currentDuration
        ShutdownType = "System is Active"
    }
}

$systemActivity | Sort-Object StartTime -Descending | Format-Table -AutoSize


