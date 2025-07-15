# setup-task-scheduler.ps1 - Setup automated weekly backups using Windows Task Scheduler
# Usage: powershell -ExecutionPolicy Bypass -File setup-task-scheduler.ps1 [-Install|-Remove|-Status]

param(
    [string]$Action = "Install",
    [switch]$Push
)

$ErrorActionPreference = "Stop"

# Configuration
$TaskName = "SaveDotFiles Weekly Backup"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BackupScript = Join-Path $ScriptDir "archive-dot-files.sh"
$LogFile = Join-Path $env:USERPROFILE ".local\log\savedotfiles-backup.log"

# Ensure log directory exists
$LogDir = Split-Path -Parent $LogFile
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Install-BackupTask {
    Write-Host "Setting up weekly backup task..." -ForegroundColor Yellow
    
    # Check if task already exists
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Host "Task already exists. Use -Remove first to reinstall." -ForegroundColor Yellow
        return
    }
    
    # Get user preferences
    Write-Host "`nConfigure your backup schedule:" -ForegroundColor Blue
    
    # Day of week
    $dayMap = @{
        '0' = 'Sunday'
        '1' = 'Monday'
        '2' = 'Tuesday'
        '3' = 'Wednesday'
        '4' = 'Thursday'
        '5' = 'Friday'
        '6' = 'Saturday'
    }
    
    Write-Host "`nWhich day of the week?"
    Write-Host "  0 = Sunday"
    Write-Host "  1 = Monday"
    Write-Host "  2 = Tuesday"
    Write-Host "  3 = Wednesday"
    Write-Host "  4 = Thursday"
    Write-Host "  5 = Friday"
    Write-Host "  6 = Saturday"
    
    do {
        $dayInput = Read-Host "Day [default: 0 (Sunday)]"
        if ([string]::IsNullOrEmpty($dayInput)) { $dayInput = "0" }
    } while ($dayInput -notmatch '^[0-6]$')
    
    $dayOfWeek = $dayMap[$dayInput]
    
    # Hour
    do {
        Write-Host "`nWhat hour? (0-23, 24-hour format)"
        Write-Host "  Examples: 0 = midnight, 2 = 2 AM, 14 = 2 PM, 18 = 6 PM"
        $hourInput = Read-Host "Hour [default: 2 (2 AM)]"
        if ([string]::IsNullOrEmpty($hourInput)) { $hourInput = "2" }
    } while ($hourInput -notmatch '^([0-9]|1[0-9]|2[0-3])$')
    
    $hour = [int]$hourInput
    
    # Push to GitHub?
    if (-not $Push) {
        $pushResponse = Read-Host "`nPush backups to GitHub? (y/N)"
        $Push = $pushResponse -match '^[Yy]$'
    }
    
    $pushArg = if ($Push) { "--push" } else { "" }
    
    # Detect WSL or Git Bash
    $wslPath = (Get-Command wsl -ErrorAction SilentlyContinue)
    $gitBashPath = @(
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files (x86)\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    
    if ($wslPath) {
        Write-Host "`nWSL detected. The task will run using WSL." -ForegroundColor Green
        $program = "wsl"
        $arguments = "cd `"$($ScriptDir -replace '\\', '/' -replace '^([A-Za-z]):', '/mnt/$1'.ToLower())`" && ./archive-dot-files.sh weekly-auto-backup $pushArg >> `"$($LogFile -replace '\\', '/' -replace '^([A-Za-z]):', '/mnt/$1'.ToLower())`" 2>&1"
    }
    elseif ($gitBashPath) {
        Write-Host "`nGit Bash detected at: $gitBashPath" -ForegroundColor Green
        $program = $gitBashPath
        $scriptPath = $ScriptDir -replace '\\', '/' -replace '^([A-Za-z]):', '/$1'.ToLower()
        $logPath = $LogFile -replace '\\', '/' -replace '^([A-Za-z]):', '/$1'.ToLower()
        $arguments = "-c `"cd '$scriptPath' && ./archive-dot-files.sh weekly-auto-backup $pushArg >> '$logPath' 2>&1`""
    }
    else {
        Write-Host "Neither WSL nor Git Bash found! Please install one of them." -ForegroundColor Red
        Write-Host "Download Git for Windows from: https://git-scm.com/download/win" -ForegroundColor Yellow
        return
    }
    
    # Create the scheduled task
    $action = New-ScheduledTaskAction -Execute $program -Argument $arguments
    
    # Weekly trigger
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $dayOfWeek -At "${hour}:00"
    
    # Task settings
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable `
        -MultipleInstances IgnoreNew
    
    # Register the task
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Description "Weekly backup of dotfiles using SaveDotFiles" `
        -RunLevel Limited
    
    Write-Host "`n✓ Backup task installed successfully!" -ForegroundColor Green
    Write-Host "  Schedule: Every $dayOfWeek at ${hour}:00"
    Write-Host "  Log file: $LogFile"
    if ($Push) {
        Write-Host "  GitHub push: Enabled" -ForegroundColor Green
    }
    else {
        Write-Host "  GitHub push: Disabled" -ForegroundColor Red
    }
    
    Write-Host "`n✓ Windows Task Scheduler will run missed backups when the computer is back online" -ForegroundColor Green
}

function Remove-BackupTask {
    Write-Host "Removing backup task..." -ForegroundColor Yellow
    
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "✓ Task removed successfully!" -ForegroundColor Green
    }
    else {
        Write-Host "No task found to remove." -ForegroundColor Yellow
    }
}

function Show-TaskStatus {
    Write-Host "Backup Task Status:" -ForegroundColor Blue
    Write-Host ""
    
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Write-Host "Status: Installed" -ForegroundColor Green
        Write-Host ""
        Write-Host "Task Information:"
        Write-Host "  State: $($task.State)"
        
        $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName
        Write-Host "  Last Run Time: $($taskInfo.LastRunTime)"
        Write-Host "  Last Result: 0x$($taskInfo.LastTaskResult.ToString('X'))"
        Write-Host "  Next Run Time: $($taskInfo.NextRunTime)"
        
        # Show recent log entries
        if (Test-Path $LogFile) {
            Write-Host "`nLast 5 backup entries:"
            Get-Content $LogFile -Tail 5 | ForEach-Object { Write-Host "  $_" }
        }
        else {
            Write-Host "`nNo backup logs found yet."
        }
    }
    else {
        Write-Host "Status: Not installed" -ForegroundColor Red
        Write-Host "`nRun 'powershell -ExecutionPolicy Bypass -File setup-task-scheduler.ps1' to set up automatic backups."
    }
}

# Main logic
switch ($Action.ToLower()) {
    "install" { Install-BackupTask }
    "remove" { Remove-BackupTask }
    "status" { Show-TaskStatus }
    default {
        Write-Host "Usage: setup-task-scheduler.ps1 [-Install|-Remove|-Status]" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Options:"
        Write-Host "  -Install  Set up weekly backup task (default)"
        Write-Host "  -Remove   Remove the backup task"
        Write-Host "  -Status   Show current task status"
    }
}