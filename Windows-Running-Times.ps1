# Fetch the specific events from the System event log
$events = Get-WinEvent -LogName 'System' -FilterXPath "*[(System[Provider[@Name='Microsoft-Windows-Kernel-Power'] 
and (EventID=41 or EventID=42)]) or (System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]) 
or (System[Provider[@Name='USER32'] and EventID=1074]) or (System[Provider[@Name='EventLog'] and (EventID=6005 or EventID=6006)])]" | Sort-Object TimeCreated

$systemActivity = @()
$startEvent = $null
$shutdownEvent = $null

function Format-Duration {
    param ([TimeSpan]$duration)
    return "{0} Days, {1:D2}:{2:D2}:{3:D2}" -f $duration.Days, $duration.Hours, $duration.Minutes, $duration.Seconds
}

foreach ($event in $events) {
    switch ($event.Id) {
        # Startups 
        {($_ -eq 1) -or ($_ -eq 41) -or ($_ -eq 6005)} {
            if ($startEvent) {
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
        # Shutdowns
        {($_ -eq 42) -or ($_ -eq 1074) -or ($_ -eq 6006)} { 
            if ($startEvent) {
                $shutdownEvent = $event
                $shutdownType = if ($event.Id -eq 42) {"Sleep Mode"} else {"User Initiated"}
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
