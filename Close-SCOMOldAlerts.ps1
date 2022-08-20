#
# +---------------------+
# | D I S C L A I M E R |
# +---------------------+
#
# This is an example without guarantees and any liability for any damage that 
# may occur. Test this script extensively and adjust it according to your needs
# before using it in a productive or system critical environment!
#
########################################################################################################
#
# Script-Name:       Close-SCOMOldAlerts.ps1
# Version:           V1.0
# Date:              19.08.2022
# Author:            Mario Linowski, CSAE, Microsoft Deutschland GmbH
#
########################################################################################################
#
# This script closes all alerts that have an age defined with the $DayTresh variable and have the 
# Resolution-State "New". Rule alerts are normaly closed and monitor alerts are closed by resetting 
# the associated monitor.
#
########################################################################################################
#
# YOU HAVE TO adjust the variables listed here further down in the script to your needs:
#
# $DayThresh = <Number of days after the open alert should be closed>
#
########################################################################################################
#
# VERSIONS:
#
# V1.0     - Initial release
#
########################################################################################################
# the script starts here

######################################
# load OpsMgr Module
######################################
if(@(get-module | where-object {$_.Name -eq "OperationsManager"}  ).count -eq 0)
        {Import-Module OperationsManager -ErrorVariable err -Force}
New-SCOMManagementGroupConnection -ComputerName $ManagementServer

######################################
# delete Alerts older than X Days 
######################################
$startTime = $(get-date)
$DayThresh  = $startTime.AddDays(-30)

######################################
# get all Alerts with State New
######################################
$AlertsToClose = get-scomalert | where {$_.ResolutionState -eq 0 -and $_.TimeRaised -lt $DayThresh}
$AlertsCount = ($AlertsToClose).Count
if ($AlertsCount -gt 0) {
    Write-Host " "
    Write-Host "There are $AlertsCount Alerts to close. Working on it ..." 
    foreach ($Alert in $AlertsToClose) {
        if ($Alert.IsMonitorAlert -eq $True) {
            $MonitorID = $Alert.MonitoringRuleId
            $MonitorObjectID = $Alert.MonitoringObjectId
            $monitor = Get-SCOMMonitor -Id $MonitorID
            $monitoringObject = Get-SCOMMonitoringObject | where {$_.Id -eq $MonitorObjectID}
            #Create ManagementPackMonitor collection, needed by the GetMonitoringStates method
            $MonitorsToReset = New-Object "System.Collections.Generic.List[Microsoft.EnterpriseManagement.Configuration.ManagementPackMonitor]";
            $MonitorsToReset.Add($monitor)
            #Get the newest MonitorState
            $MonitorState = $monitoringObject.GetMonitoringStates($MonitorsToReset)[0];
            if(($MonitorState.HealthState -eq "Error" -or $MonitorState.HealthState -eq "Warning")) #-and ($healthState.LastTimeModified -gt $DayThresh))
            {
                $ResetCounter = 0
                $AlertName = $Alert.Name
                $AlertObjName = $Alert.MonitoringObjectName
                Write-Host "Resetting Monitor for Alert -> " -NoNewline
                Write-Host "$AlertName -> " -Foregroundcolor Yellow -NoNewline
                Write-Host "$AlertObjName" -ForegroundColor Green
                $MonitoringTaskResult = $MonitoringObject.ResetMonitoringState($monitor)
                if ($? -eq $True) {
                    $ResetCounter++
                }
                else {
                    Write-Host " "
                    Write-Host "There where Errors trying to reset monitor for the Alert -> $AlertName" -ForegroundColor Red
                }
            }
        }
        else {
            $RuleClose = 0
            $AlertName = $Alert.Name
            Write-Host "Close Alert Alert -> " -NoNewline
            Write-Host "$AlertName -> " -Foregroundcolor Yellow
            $Alert | Set-SCOMAlert -CustomField1 "Alert was closed by script." -ResolutionState 255
            $MonitoringTaskResult = $MonitoringObject.ResetMonitoringState($monitor)
            if ($? -eq $True) {
                $RuleClose++
            }
            else {
                    Write-Host " "
                    Write-Host "There where Errors trying to close the Alert -> $AlertName" -ForegroundColor Red
            }
        }
    }
}
else {
    Write-Host " "
    Write-Host "No Alerts to close!" -ForegroundColor Green

}
Write-Host " "
Write-Host "End of Script"