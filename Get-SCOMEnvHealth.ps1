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
# Script-Name:       Get-SCOMEnvHealth.ps1
# Version:           V1.0
# Date:              19.08.2022
# Author:            Mario Linowski, CSAE, Microsoft Deutschland GmbH
#
########################################################################################################
#
# This script uses intellectual property from Kevin Holman in the form of TSQL queries to evaluate 
# the healthstate of an SCOM environment (https://kevinholman.com/2016/11/11/scom-sql-queries/).
#
# It creates a report with the result of 17 database queries. The result of these queries allows to draw 
# a conclusion about the health state of the SCOM environment against whose database these queries run.
#
########################################################################################################
#
# YOU HAVE TO adjust the variables listed here further down in the script to your needs:
#
# $SQLServer = <THE NAME OF YOUR DB SERVER OR LISTENER OF YOUR OPERATIONS MANAGER DATABASE>
# $OpsDB = <THE NAME OF YOUR SCOM OPERATIONAL DATABASE, NORMALY OperationsManager>
# $DWH = <THE NAME OF YOUR SCOM DATAWAREHOUSE DATABASE, NORMALY OperationsManagerDW>
# $ReportFile = <ADJUST THE PATH FOR THE REPORT FILE HERE (LEAVE THE FILE ANME AS IS)>
#
########################################################################################################
# the script starts here

######################################
# Measuring Execution-Time
######################################
$startScript = (Get-Date).Millisecond

######################################
# load OpsMgr Module
######################################
if(@(get-module | where-object {$_.Name -eq "OperationsManager"}  ).count -eq 0)
        {Import-Module OperationsManager -ErrorVariable err -Force}
New-SCOMManagementGroupConnection -ComputerName $ManagementServer

######################################
# set some variable's
######################################
$Creator = whoami
$MgmtGrpName = (Get-SCOMManagementGroup).Name
$ReportDate = Get-Date -format "dddd dd.MM.yyyy HH.mm"
$SQLServer = "CPS-OM2022"
$OpsDB = "OperationsManager"
$DWH = "OperationsManagerDW"
$ReportFile = "C:\temp\MgmtGrpReport $MgmtGrpName $ReportDate.txt"

######################################
# putting queries into variable's
######################################

# Database Size and used space
######################################
$qName01 = "OpsDB - Database Size and used space"
$query01 = "SELECT convert(decimal(12,0),round(sf.size/128.000,2)) AS 'FileSize(MB)', 
convert(decimal(12,0),round(fileproperty(sf.name,'SpaceUsed')/128.000,2)) AS 'SpaceUsed(MB)', 
convert(decimal(12,0),round((sf.size-fileproperty(sf.name,'SpaceUsed'))/128.000,2)) AS 'FreeSpace(MB)', 
CASE smf.is_percent_growth WHEN 1 THEN CONVERT(VARCHAR(10),smf.growth) +' %' ELSE convert(VARCHAR(10),smf.growth/128) +' MB' END AS 'AutoGrow',
convert(decimal(12,0),round(sf.maxsize/128.000,2)) AS 'AutoGrowthMB(MAX)',
left(sf.NAME,15) AS 'NAME', 
left(sf.FILENAME,120) AS 'PATH',
sf.FILEID
from dbo.sysfiles sf
JOIN sys.master_files smf on smf.physical_name = sf.filename"

# Large Table Query Top 10
######################################
$qName02 = "OpsDB - Large Table Query"
$query02 = "SELECT TOP 10 
a2.name AS 'Tablename', 
CAST((a1.reserved + ISNULL(a4.reserved,0))* 8/1024.0 AS DECIMAL(10, 0)) AS 'TotalSpace(MB)', 
CAST(a1.data * 8/1024.0 AS DECIMAL(10, 0)) AS 'DataSize(MB)', 
CAST((CASE WHEN (a1.used + ISNULL(a4.used,0)) > a1.data THEN (a1.used + ISNULL(a4.used,0)) - a1.data ELSE 0 END) * 8/1024.0 AS DECIMAL(10, 0)) AS 'IndexSize(MB)', 
CAST((CASE WHEN (a1.reserved + ISNULL(a4.reserved,0)) > a1.used THEN (a1.reserved + ISNULL(a4.reserved,0)) - a1.used ELSE 0 END) * 8/1024.0 AS DECIMAL(10, 0)) AS 'Unused(MB)',
a1.rows as 'RowCount', 
(row_number() over(order by (a1.reserved + ISNULL(a4.reserved,0)) desc))%2 as l1, 
a3.name AS 'Schema' 
FROM (SELECT ps.object_id, SUM (CASE WHEN (ps.index_id < 2) THEN row_count ELSE 0 END) AS [rows], 
SUM (ps.reserved_page_count) AS reserved, 
SUM (CASE WHEN (ps.index_id < 2) THEN (ps.in_row_data_page_count + ps.lob_used_page_count + ps.row_overflow_used_page_count) 
ELSE (ps.lob_used_page_count + ps.row_overflow_used_page_count) END ) AS data, 
SUM (ps.used_page_count) AS used 
FROM sys.dm_db_partition_stats ps 
GROUP BY ps.object_id) AS a1 
LEFT OUTER JOIN (SELECT it.parent_id, SUM(ps.reserved_page_count) AS reserved, 
SUM(ps.used_page_count) AS used 
FROM sys.dm_db_partition_stats ps 
INNER JOIN sys.internal_tables it ON (it.object_id = ps.object_id) 
WHERE it.internal_type IN (202,204) 
GROUP BY it.parent_id) AS a4 ON (a4.parent_id = a1.object_id) 
INNER JOIN sys.all_objects a2  ON ( a1.object_id = a2.object_id ) 
INNER JOIN sys.schemas a3 ON (a2.schema_id = a3.schema_id)"

# Number of Console Alerts per Day
######################################
$qName03 = "OpsDB - Number of Console Alerts per Day"
$query03 = "SELECT CONVERT(VARCHAR(20), TimeAdded, 102) AS DayAdded, COUNT(*) AS NumAlertsPerDay 
FROM Alert WITH (NOLOCK) 
WHERE TimeRaised is not NULL 
GROUP BY CONVERT(VARCHAR(20), TimeAdded, 102) 
ORDER BY DayAdded DESC"

# Top 20 Alerts in an Operational Database, by Alert Count Top 10
##################################################################
$qName04 = "OpsDB - Top 10 Alerts in an Operational Database, by Alert Count"
$query04 = "SELECT TOP 10 SUM(1) AS AlertCount,
AlertStringName AS 'AlertName',
AlertStringDescription AS 'Description',
Name,
MonitoringRuleId
FROM Alertview WITH (NOLOCK) 
WHERE TimeRaised is not NULL 
GROUP BY AlertStringName, AlertStringDescription, Name, MonitoringRuleId 
ORDER BY AlertCount DESC"

# Top 20 Objects generating the most Alerts in an Operational Database, by Alert Count Top 10
##############################################################################################
$qName05 = "OpsDB - Top 10 Objects generating the most Alerts in an Operational Database, by Alert Count"
$query05 = "SELECT TOP 10 SUM(1) AS AlertCount,
MonitoringObjectPath AS 'Path'
FROM Alertview WITH (NOLOCK) 
WHERE TimeRaised is not NULL 
GROUP BY MonitoringObjectPath
ORDER BY AlertCount DESC"

# Top 20 Objects generating the most Alerts in an Operational Database, by Repeat Count TOP 10
###############################################################################################
$qName06 = "OpsDB - Top 10 Objects generating the most Alerts in an Operational Database, by Repeat Count"
$query06 = "SELECT TOP 10 SUM(RepeatCount+1) AS RepeatCount,
 MonitoringObjectPath AS 'Path'
FROM Alertview WITH (NOLOCK) 
WHERE Timeraised is not NULL 
GROUP BY MonitoringObjectPath 
ORDER BY RepeatCount DESC"

# All Events by count by day, with total for entire database
##############################################################
$qName07 = "OpsDB - All Events by count by day, with total for entire database"
$query07 = "SELECT CASE WHEN(GROUPING(CONVERT(VARCHAR(20), TimeAdded, 102)) = 1) 
THEN 'All Days' 
ELSE CONVERT(VARCHAR(20), TimeAdded, 102) END AS DayAdded, 
COUNT(*) AS EventsPerDay 
FROM EventAllView 
GROUP BY CONVERT(VARCHAR(20), TimeAdded, 102) WITH ROLLUP 
ORDER BY DayAdded DESC"

# Most common events by event number and event source
######################################################
$qName08 = "OpsDB - Most common events by event number and event source"
$query08 = "SELECT top 10 Number as EventID, 
 COUNT(*) AS TotalEvents,
 Publishername as EventSource 
FROM EventAllView eav with (nolock) 
GROUP BY Number, Publishername 
ORDER BY TotalEvents DESC"

# Computers generating the most events
#######################################
$qName09 = "OpsDB - Computers generating the most events"
$query09 = "SELECT top 10 LoggingComputer as ComputerName,
 COUNT(*) AS TotalEvents 
FROM EventallView with (NOLOCK) 
GROUP BY LoggingComputer 
ORDER BY TotalEvents DESC"

# Performance insertions per day
#######################################
$qName10 = "OpsDB - Performance insertions per day"
$query10 = "SELECT CASE WHEN(GROUPING(CONVERT(VARCHAR(20), TimeSampled, 102)) = 1) 
 THEN 'All Days' 
 ELSE CONVERT(VARCHAR(20), TimeSampled, 102) 
 END AS DaySampled, COUNT(*) AS PerfInsertPerDay 
FROM PerformanceDataAllView with (NOLOCK) 
GROUP BY CONVERT(VARCHAR(20), TimeSampled, 102) WITH ROLLUP 
ORDER BY DaySampled DESC"

# Top 20 performance insertions by perf object and counter name
################################################################
$qName11 = "OpsDB - Top 10 performance insertions by perf object and counter name"
$query11 = "SELECT TOP 10 pcv.ObjectName,
 pcv.CounterName,
 COUNT (pcv.countername) AS Total 
FROM performancedataallview AS pdv, performancecounterview AS pcv 
WHERE (pdv.performancesourceinternalid = pcv.performancesourceinternalid) 
GROUP BY pcv.objectname, pcv.countername 
ORDER BY COUNT (pcv.countername) DESC"

# To find out how old your StateChange data is
################################################################
$qName12 = "OpsDB - To find out how old your StateChange data is"
$query12 = "declare @statedaystokeep INT 
SELECT @statedaystokeep = DaysToKeep from PartitionAndGroomingSettings 
WHERE ObjectName = 'StateChangeEvent'
SELECT COUNT(*) as 'Total StateChanges', 
count(CASE WHEN sce.TimeGenerated > dateadd(dd,-@statedaystokeep,getutcdate()) THEN sce.TimeGenerated ELSE NULL END) as 'within grooming retention', 
count(CASE WHEN sce.TimeGenerated < dateadd(dd,-@statedaystokeep,getutcdate()) THEN sce.TimeGenerated ELSE NULL END) as '> grooming retention', 
count(CASE WHEN sce.TimeGenerated < dateadd(dd,-30,getutcdate()) THEN sce.TimeGenerated ELSE NULL END) as '> 30 days', 
count(CASE WHEN sce.TimeGenerated < dateadd(dd,-90,getutcdate()) THEN sce.TimeGenerated ELSE NULL END) as '> 90 days', 
count(CASE WHEN sce.TimeGenerated < dateadd(dd,-365,getutcdate()) THEN sce.TimeGenerated ELSE NULL END) as '> 365 days' 
from StateChangeEvent sce"

# State changes per day
################################################################
$qName13 = "OpsDB - State changes per day"
$query13 = "SELECT CASE WHEN(GROUPING(CONVERT(VARCHAR(20), TimeGenerated, 102)) = 1) 
THEN 'All Days' ELSE CONVERT(VARCHAR(20), TimeGenerated, 102) 
END AS DayGenerated, COUNT(*) AS StateChangesPerDay 
FROM StateChangeEvent WITH (NOLOCK) 
GROUP BY CONVERT(VARCHAR(20), TimeGenerated, 102) WITH ROLLUP 
ORDER BY DayGenerated DESC"

# Noisiest monitors changing state in the database in the last 7 days
######################################################################
$qName14 = "OpsDB - Noisiest monitors changing state in the database in the last 7 days"
$query14 = "SELECT DISTINCT TOP 50 count(sce.StateId) as StateChanges, 
  m.DisplayName as MonitorName, 
  m.Name as MonitorId, 
  mt.typename AS TargetClass 
FROM StateChangeEvent sce with (nolock) 
join state s with (nolock) on sce.StateId = s.StateId 
join monitorview m with (nolock) on s.MonitorId = m.Id 
join managedtype mt with (nolock) on m.TargetMonitoringClassId = mt.ManagedTypeId 
where m.IsUnitMonitor = 1 
  -- Scoped to within last 7 days 
AND sce.TimeGenerated > dateadd(dd,-7,getutcdate()) 
group by m.DisplayName, m.Name,mt.typename 
order by StateChanges desc"

# Monitors with the most instances of critical state
################################################################
$qName15 = "OpsDB - Monitors with the most instances of critical state"
$query15 = "SELECT 
 count(*) as 'MonitorCount',
mv.DisplayName AS 'MonitorDisplayName',
mv.Name AS 'MonitorName'
FROM State s
JOIN MonitorView mv ON mv.Id = s.MonitorId
WHERE s.HealthState = 3
AND mv.IsUnitMonitor = 1
--ORDER BY mv.DisplayName
GROUP BY mv.Name,mv.DisplayName
ORDER by count(*) DESC"

# Misc OpsDB - View Grooming info
################################################################
$qName16 = "Misc OpsDB - View Grooming info"
$query16 = "SELECT * FROM PartitionAndGroomingSettings WITH (NOLOCK)"

# Misc OpsDB - View Grooming history
################################################################
$qName17 = "Misc OpsDB - View Grooming history"
$query17 = "select * from InternalJobHistory
order by InternalJobHistoryId DESC"


######################################
# Script Action
######################################
Write-Host " "
Write-Host "Starting Report for Management-Group " -NoNewline; 
Write-Host "$MgmtGrpName / $OpsDB" -ForegroundColor Yellow
Write-Host "----------------------------------------------------------------------------"
Write-Host " "
######################################
# loading data into variable's
######################################
Write-Host "Loading Data from Database: " -NoNewline; 
Write-Host "$qName01" -ForegroundColor Green
$result01 = Invoke-Sqlcmd -ServerInstance $SQLServer -Database $OpsDB -Query $query01
Write-Host "Loading Data from Database: " -NoNewline; 
Write-Host "$qName02" -ForegroundColor Green
$result02 = Invoke-Sqlcmd -ServerInstance $SQLServer -Database $OpsDB -Query $query02
Write-Host "Loading Data from Database: " -NoNewline; 
Write-Host "$qName03" -ForegroundColor Green
$result03 = Invoke-Sqlcmd -ServerInstance $SQLServer -Database $OpsDB -Query $query03
Write-Host "Loading Data from Database: " -NoNewline; 
Write-Host "$qName04" -ForegroundColor Green
$result04 = Invoke-Sqlcmd -ServerInstance $SQLServer -Database $OpsDB -Query $query04
Write-Host "Loading Data from Database: " -NoNewline; 
Write-Host "$qName05" -ForegroundColor Green
$result05 = Invoke-Sqlcmd -ServerInstance $SQLServer -Database $OpsDB -Query $query05
Write-Host "Loading Data from Database: " -NoNewline; 
Write-Host "$qName06" -ForegroundColor Green
$result06 = Invoke-Sqlcmd -ServerInstance $SQLServer -Database $OpsDB -Query $query06
Write-Host "Loading Data from Database: " -NoNewline; 
Write-Host "$qName07" -ForegroundColor Green
$result07 = Invoke-Sqlcmd -ServerInstance $SQLServer -Database $OpsDB -Query $query07
Write-Host "Loading Data from Database: " -NoNewline; 
Write-Host "$qName08" -ForegroundColor Green
$result08 = Invoke-Sqlcmd -ServerInstance $SQLServer -Database $OpsDB -Query $query08
Write-Host "Loading Data from Database: " -NoNewline; 
Write-Host "$qName09" -ForegroundColor Green
$result09 = Invoke-Sqlcmd -ServerInstance $SQLServer -Database $OpsDB -Query $query09
Write-Host "Loading Data from Database: " -NoNewline; 
Write-Host "$qName10" -ForegroundColor Green
$result10 = Invoke-Sqlcmd -ServerInstance $SQLServer -Database $OpsDB -Query $query10
Write-Host "Loading Data from Database: " -NoNewline; 
Write-Host "$qName11" -ForegroundColor Green
$result11 = Invoke-Sqlcmd -ServerInstance $SQLServer -Database $OpsDB -Query $query11
Write-Host "Loading Data from Database: " -NoNewline; 
Write-Host "$qName12" -ForegroundColor Green
$result12 = Invoke-Sqlcmd -ServerInstance $SQLServer -Database $OpsDB -Query $query12
Write-Host "Loading Data from Database: " -NoNewline; 
Write-Host "$qName13" -ForegroundColor Green
$result13 = Invoke-Sqlcmd -ServerInstance $SQLServer -Database $OpsDB -Query $query13
Write-Host "Loading Data from Database: " -NoNewline; 
Write-Host "$qName14" -ForegroundColor Green
$result14 = Invoke-Sqlcmd -ServerInstance $SQLServer -Database $OpsDB -Query $query14
Write-Host "Loading Data from Database: " -NoNewline; 
Write-Host "$qName15" -ForegroundColor Green
$result15 = Invoke-Sqlcmd -ServerInstance $SQLServer -Database $OpsDB -Query $query15
Write-Host "Loading Data from Database: " -NoNewline; 
Write-Host "$qName16" -ForegroundColor Green
$result16 = Invoke-Sqlcmd -ServerInstance $SQLServer -Database $OpsDB -Query $query16
Write-Host "Loading Data from Database: " -NoNewline; 
Write-Host "$qName17" -ForegroundColor Green
$result17 = Invoke-Sqlcmd -ServerInstance $SQLServer -Database $OpsDB -Query $query17

######################################
# create the report
######################################

Write-Host " "
Write-Host "Writing Results to file " -NoNewline; 
Write-Host "$ReportFile" -ForegroundColor Yellow
Write-Host " "

"Report of automated Database-Queries from SCOM Database" | Out-File -FilePath $ReportFile
"=======================================================" | Out-File -FilePath $ReportFile -Append
" " | Out-File -FilePath $ReportFile -Append
"Date of Report:                    $ReportDate" | Out-File -FilePath $ReportFile -Append
"Name of SCOM Management-Group:     $MgmtGrpName" | Out-File -FilePath $ReportFile -Append
"Database:                          $OpsDB" | Out-File -FilePath $ReportFile -Append
"Report Creator:                    $Creator" | Out-File -FilePath $ReportFile -Append
" " | Out-File -FilePath $ReportFile -Append
" " | Out-File -FilePath $ReportFile -Append

"# $qName01" | Out-File -FilePath $ReportFile -Append
"##################################################################################################"  | Out-File -FilePath $ReportFile -Append
$result01 | Out-File -FilePath $ReportFile -Append
" " | Out-File -FilePath $ReportFile -Append

"# $qName02" | Out-File -FilePath $ReportFile -Append
"##################################################################################################"  | Out-File -FilePath $ReportFile -Append
$result02 | Out-File -FilePath $ReportFile -Append
" " | Out-File -FilePath $ReportFile -Append

"# $qName03" | Out-File -FilePath $ReportFile -Append
"##################################################################################################"  | Out-File -FilePath $ReportFile -Append
$result03 | Out-File -FilePath $ReportFile -Append
" " | Out-File -FilePath $ReportFile -Append

"# $qName04" | Out-File -FilePath $ReportFile -Append
"##################################################################################################"  | Out-File -FilePath $ReportFile -Append
$result04 | Out-File -FilePath $ReportFile -Append
" " | Out-File -FilePath $ReportFile -Append

"# $qName05" | Out-File -FilePath $ReportFile -Append
"##################################################################################################"  | Out-File -FilePath $ReportFile -Append
$result05 | Out-File -FilePath $ReportFile -Append
" " | Out-File -FilePath $ReportFile -Append

"# $qName06" | Out-File -FilePath $ReportFile -Append
"##################################################################################################"  | Out-File -FilePath $ReportFile -Append
$result06 | Out-File -FilePath $ReportFile -Append
" " | Out-File -FilePath $ReportFile -Append

"# $qName07" | Out-File -FilePath $ReportFile -Append
"##################################################################################################"  | Out-File -FilePath $ReportFile -Append
$result07 | Out-File -FilePath $ReportFile -Append
" " | Out-File -FilePath $ReportFile -Append

"# $qName08" | Out-File -FilePath $ReportFile -Append
"##################################################################################################"  | Out-File -FilePath $ReportFile -Append
$result08 | Out-File -FilePath $ReportFile -Append
" " | Out-File -FilePath $ReportFile -Append

"# $qName09" | Out-File -FilePath $ReportFile -Append
"##################################################################################################"  | Out-File -FilePath $ReportFile -Append
$result09 | Out-File -FilePath $ReportFile -Append
" " | Out-File -FilePath $ReportFile -Append

"# $qName10" | Out-File -FilePath $ReportFile -Append
"##################################################################################################"  | Out-File -FilePath $ReportFile -Append
$result10 | Out-File -FilePath $ReportFile -Append
" " | Out-File -FilePath $ReportFile -Append

"# $qName11" | Out-File -FilePath $ReportFile -Append
"##################################################################################################"  | Out-File -FilePath $ReportFile -Append
$result11 | Out-File -FilePath $ReportFile -Append
" " | Out-File -FilePath $ReportFile -Append

"# $qName12" | Out-File -FilePath $ReportFile -Append
"##################################################################################################"  | Out-File -FilePath $ReportFile -Append
$result12 | Out-File -FilePath $ReportFile -Append
" " | Out-File -FilePath $ReportFile -Append

"# $qName13" | Out-File -FilePath $ReportFile -Append
"##################################################################################################"  | Out-File -FilePath $ReportFile -Append
$result13 | Out-File -FilePath $ReportFile -Append
" " | Out-File -FilePath $ReportFile -Append

"# $qName14" | Out-File -FilePath $ReportFile -Append
"##################################################################################################"  | Out-File -FilePath $ReportFile -Append
$result14 | Out-File -FilePath $ReportFile -Append
" " | Out-File -FilePath $ReportFile -Append

"# $qName15" | Out-File -FilePath $ReportFile -Append
"##################################################################################################"  | Out-File -FilePath $ReportFile -Append
$result15 | Out-File -FilePath $ReportFile -Append
" " | Out-File -FilePath $ReportFile -Append

"# $qName16" | Out-File -FilePath $ReportFile -Append
"##################################################################################################"  | Out-File -FilePath $ReportFile -Append
$result16 | Out-File -FilePath $ReportFile -Append
" " | Out-File -FilePath $ReportFile -Append

"# $qName17" | Out-File -FilePath $ReportFile -Append
"##################################################################################################"  | Out-File -FilePath $ReportFile -Append
$result17 | Out-File -FilePath $ReportFile -Append
" " | Out-File -FilePath $ReportFile -Append

" " | Out-File -FilePath $ReportFile -Append
"REPORT END" | Out-File -FilePath $ReportFile -Append

# Measure Script-End
############################################################
$endScript = (Get-Date).Millisecond
Write-Host " "
Write-Host "This Script took " -NoNewline; 
Write-Host "$($startScript - $endScript) " -ForegroundColor Yellow -NoNewline;
Write-Host "milliseconds to run."