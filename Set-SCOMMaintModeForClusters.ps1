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
# Script-Name:       Set-SCOMMaintModeForClusters.ps1
# Version:           V1.0
# Date:              19.08.2022
# Author:            Mario Linowski, CSAE, Microsoft Deutschland GmbH
#
########################################################################################################
#
# This script sets an SCOM agent into maintenance mode. If this agent is a member of a cluster, the 
# entire cluster is set to Maintenance Mode. If this node or another member of the cluster is already in 
# maintenance mode, the MM window is either extended to the specified time or not adjusted if the cluster 
# member is already in a longer MM window.
#
########################################################################################################
# the script starts here
param($serverhostname,$duration,$comment)

######################################
# doing some SCOM specific stuff
######################################
# Add Ops Mgr 2012R2 PS Module
Import-Module OperationsManager
$RMS = Get-SCOMRMSEmulator
# Connect to the given Management Group (FQDN of the RMS Emulator)
$MGC = New-SCOMManagementGroupConnection -ComputerName: $RMS.DisplayName -Passthru

######################################
# defining Maintenance-Mode Start- 
# and End-Time
######################################
$startTime = $(get-date)
$endTimeON  = $startTime.AddMinutes($duration)

######################################
# Distinguish between Agent and 
# Cluster Node
######################################
# get Class objects
$computerClass = get-SCOMClass -Displayname "Windows-Computer"
$clusterClass = get-SCOMClass -Displayname "Monitoring Cluster Service"
# get Computer object
$computer = Get-SCOMClassInstance -Class $computerClass | Where-Object {$_.Displayname -like "${serverhostname}*"};
# check if computer is part of a cluster (IsClusNode)
if ($IsClusNode = Get-SCOMClassInstance -Class $clusterClass | Where-Object {$_.Path -like "${serverhostname}*"}) 
{ 
    # getting list of cluster member (nodes)
    ######################################################################################################################
    $cls = get-SCOMClassInstance -Class $clusterClass
    $arrayData = @()
    $propValue = $IsClusNode.Values
    $splitValue = $propValue -split ","
    $clusName = $splitValue[2]
    # Get Virtual Servers Array
    $VirtualServer = Get-SCOMClass -name 'Microsoft.Windows.Cluster.VirtualServer' | Get-SCOMClassInstance | where {$_.DisplayName -like "$clusName*"} | Sort
    #Get the relationship
    $rid = Get-SCOMRelationship -DisplayName 'Health Service manages Entity'
    #Set Array to empty
    [array]$VirtualClusterItems = @()
    [string]$VirtualServerName = $VirtualServer.DisplayName
    #Create a PowerShell Object to assign properties
    $VirtualClusterItem = New-Object PSObject
    $VirtualClusterItem | Add-Member -type NoteProperty -Name 'VirtualServer' -Value $VirtualServerName
    #Get the nodes in an array which have a health service relationship managing the cluster name
    $Nodes = Get-SCOMRelationshipInstance -TargetInstance $VirtualServer | Where-Object {$_.relationshipid -eq $rid.id} | where {$_.TargetObject -like "$clusName*"} | Select-Object -Property SourceObject
    $clsNodes = $Nodes.SourceObject.DisplayName | Sort-Object
    $clusInst = Get-SCOMClassInstance $clusName
    Write-Host "List of cluster member is $clsnodes"
    
    # read possibly already existing maintenance modes from each cluster member
    ######################################################################################################################
    foreach ($clsNode in $clsNodes)
    {
        $IsInMM = (Get-SCOMClassInstance -Name $clsNode).InMaintenanceMode
        if ($IsInMM[0] -eq $true) {
            write-host $clsNode
            # getting original Maintenance Mode configuration
            $inMM = Get-SCOMMaintenanceMode -Instance (Get-SCOMClassInstance -Name $clsNode) -ErrorAction SilentlyContinue
            if ($inMM) {
                $arrayData += @([pscustomobject]@{Agent=$clsNode;MModeTo=$inMM[0].ScheduledEndTime;Comments=$inMM[0].Comments;User=$inMM[0].User})
            }
        }
    }  
    
    # set Maintenance-Mode to Cluster
    ######################################################################################################################
    Start-SCOMMaintenanceMode -Instance:$clusInst -endTime:$endTimeON -comment:$comment
    
        
    # processing every cluster member (node)
    ######################################################################################################################
    foreach ($clsNode in $clsNodes)
    {
        
        $IsInMM = ((Get-SCOMClassInstance -Name $clsNode).InMaintenanceMode -and  $arrayData.Agent -contains $clsNode)
        if ($IsInMM[0] -eq $true) {
            write-host "$clsNode is in Maintenance-Mode"
            $agtInst = Get-SCOMClassInstance -Class $computerClass | Where-Object {$_.Displayname -like $clsNode};
            #if ($inMM.ScheduledEndTime -gt $endTimeON)
            $mmConf = ($arrayData | where-object {$_.Agent -like $clsNode}).MModeTo
            [string]$mmOldCom = ($arrayData | where-object {$_.Agent -like $clsNode}).Comments
            [string]$mmOldUser = ($arrayData | where-object {$_.Agent -like $clsNode}).User
            if ($mmConf -gt $endTimeON)
            {
                #write-host "mmset #1"
                $MMEntry = Get-SCOMMaintenanceMode -Instance $agtInst
                Set-SCOMMaintenanceMode -MaintenanceModeEntry $MMEntry -EndTime $mmconf -Comment "$Comment - Maintenance Mode was modified by MM Script. Original Comment was: $MMOldCom set by $mmOldUser."
            }
            else
            {
                #write-host "mmset #1"
                $MMEntry = Get-SCOMMaintenanceMode -Instance $agtInst
                Set-SCOMMaintenanceMode -MaintenanceModeEntry $MMEntry -EndTime $endTimeON -Comment "$Comment - Maintenance Mode was modified by MM Script. Original Comment was: $MMOldCom set by $mmOldUser"
            }
        }
    }
}
else
{
    if ($computer.InMaintenanceMode -eq $true) {
        write-host $computer
        # getting original Maintenance Mode configuration
        $MMEntry = Get-SCOMMaintenanceMode -Instance (Get-SCOMClassInstance -Name $computer) -ErrorAction SilentlyContinue
        $agtInst = Get-SCOMClassInstance -Class $computerClass | Where-Object {$_.Displayname -like $computer};
        if ($MMEntry) {
            Write-Host "Computer $computer IS in MM"
            if ($endTimeOn -gt $MMEntry.ScheduledEndTime) {
                #write-host "mmset #2"
                [string]$mmOldCom = $MMEntry.Comments
                [string]$mmOldUser = $MMEntry.User
                Set-SCOMMaintenanceMode -MaintenanceModeEntry $MMEntry -endTime:$endTimeON -comment:"$Comment - Maintenance Mode was modified by MM Script. Original Comment was: $MMOldCom set by $mmOldUser" -ErrorAction SilentlyContinue
            }
            else {
                write-host "Maintenance Mode is already set for a longer time window! Leaving ist untouched."
            }
         }
    }
    else {
        Write-Host "Computer $computer NOT in MM"
        #write-host "mmset #3"
        Start-SCOMMaintenanceMode -Instance:$computer -endTime:$endTimeON -comment:$comment -ErrorAction SilentlyContinue   
    }
}
Write-Host "End of Script."

######################################
# enable only for testing
######################################
#get-date >> c:\temp\test.txt # enable only for test purposes
