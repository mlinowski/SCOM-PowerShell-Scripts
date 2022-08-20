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
# Script-Name:       Get-SCOMMPName.ps1
# Version:           V1.0
# Date:              19.08.2022
# Author:            Mario Linowski, CSAE, Microsoft Deutschland GmbH
#
########################################################################################################
#
# This Script get the Managementpack-Name which the named Alert is included.
#
########################################################################################################
# the script starts here

param($AlertName)
$Alert = Get-SCOMAlert -Name $AlertName

if (($alert).Count -ge 1)
{
    if ($Alert[1].IsMonitorAlert -eq $true)
    {
        Write-Host "This is a MONITOR created Alert."
        $MonitorID = $Alert.MonitoringRuleId
        $MonitorName = Get-SCOMMonitor -id $MonitorID
        $managementpack = $MonitorName.GetManagementPack()
        $managementpackname = $managementpack.DisplayName
        Write-Host "Management Pack Name : " -nonewline; Write-Host $managementpackname -foregroundcolor Green
    }
    Elseif ($Alert[1].IsMonitorAlert -eq $false)
    {
        Write-Host "This is a RULE created Alert."
        $RuleID = $Alert.MonitoringRuleId
        $RuleName = Get-SCOMRule -id $RuleID
        $managementpack = $RuleName.GetManagementPack()
        $managementpackname = $managementpack.DisplayName
        Write-Host "Management Pack Name : " -nonewline; Write-Host $managementpackname -foregroundcolor Green
    }
}
Else
{
    write-host "There are no Alerts with this name or Alert Name incorrect!"
}

