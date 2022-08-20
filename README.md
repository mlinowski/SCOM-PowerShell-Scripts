# SCOM-PowerShell-Scripts
Usefull PowerShell-Scripts for System Center Operations Manager

Get-SCOMEnvHealth.ps1 - This script uses intellectual property from Kevin Holman in the form of TSQL queries to evaluate 
the healthstate of an SCOM environment (https://kevinholman.com/2016/11/11/scom-sql-queries/).
It creates a report with the result of 17 database queries. The result of these queries allows to draw 
a conclusion about the health state of the SCOM environment against whose database these queries run.

Close-SCOMOldAlerts.ps1 - This script closes all alerts that have an age defined with the $DayTresh variable and have the 
Resolution-State "New". Rule alerts are normaly closed and monitor alerts are closed by resetting 
the associated monitor.
