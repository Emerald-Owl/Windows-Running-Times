# Windows-Running-Times

A PowerShell script to display a table of when a Windows system was on. 

Displays the StartTime, ShutdownTime, Duration, and ShutdownType. 
Uses event IDs 1, 41, 42, 1074, 6005, 6006, from the System event log. 

Accepts parameters -startdate and -enddate in MM/dd/yyyy format for zoning in on specific timeframes.
