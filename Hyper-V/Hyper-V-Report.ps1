<#PSScriptInfo
 
.VERSION 1.0.0
 
.GUID 82f7bbd0-9a74-49b4-8447-856aea46e16d
 
.AUTHOR Andreas Sobczyk, CloudMechanic.net
 
.COMPANYNAME CloudMechanic.net
 
.COPYRIGHT
 
.TAGS HyperV
 
.LICENSEURI
 
.PROJECTURI
 
.ICONURI
 
.EXTERNALMODULEDEPENDENCIES
 
.REQUIREDSCRIPTS
 
.EXTERNALSCRIPTDEPENDENCIES
 
.RELEASENOTES
#>
<# 
 .Synopsis
  Creates a configuration report for each Hyper-V host specified in the $Nodes variable.
 
 .Description
  Creates a configuration report for each Hyper-V host specified in the $Nodes variable.
  Requires credentials with administrative access to the Hyper-V hosts.
  Author: Andreas Sobczyk, CloudMechanic.net       

 .Parameter -OutputPath
  The output path for the reports to be stored. - Example: C:\Temp\

 .Parameter -Nodes
  An array containing the hostnames for the hosts to create reports for. - Example: @("HV01","HV02","HV03")

 .Parameter -Credential
  Administrative credentials for the Hyper-V Hosts.

 .Example
  .\Hyper-V-Report.ps1 -OutputPath c:\temp\ -Nodes @("HV01","HV02","HV03")
#>
Param(
    [Parameter(Mandatory=$true,HelpMessage='Please enter the output path for the reports to be stored')][String]$OutputPath,
    [Parameter(Mandatory=$true,HelpMessage='Please provide a array with hostname for the hosts you wish to create reports for')][Array]$Nodes,
    [Parameter(Mandatory=$true,HelpMessage='Please provide administrative credentials for the Hyper-V Hosts')][PSCredential]$Credential
)
$ErrorActionPreference = "SilentlyContinue"


if(!($OutputPath.EndsWith("\"))){
    $OutputPath = $OutputPath + "\"
}

foreach($ComputerName in $nodes){

$HTMLOutput = Invoke-command -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
######################################################
$fragments=@()
$fragments+="<a href='javascript:toggleAll();' title='Click to toggle all sections'>Uncollaps/Collaps All</a>"

#region#OS Details
$os = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $computername | Select @{Name="OS";Expression={$_.caption}},Version

$Text="Operating System"
$div=$Text.Replace(" ","_")
$fragments+= "<a href='javascript:toggleDiv(""$div"");' title='Collapse or expand'><h2>$Text</h2></a><div id=""$div"">"
$fragments+= $os | ConvertTo-Html -Fragment
$fragments+="</div>"

#endregion OS Details end

#region Hardware
$ComputerSysetm = Get-CimInstance -ClassName Win32_ComputerSystem -ComputerName $computername |
Select Manufacturer,Model,@{Name="Total Memory GB";Expression={[int]($_.TotalPhysicalMemory/1GB)}},
NumberOfProcessors,NumberOfLogicalProcessors, @{Expression={(gwmi win32_bios | Select SerialNumber).SerialNumber};Label="SerialNumber"}

$Text="Computer System"
$div=$Text.Replace(" ","_")
$fragments+= "<a href='javascript:toggleDiv(""$div"");' title='Collapse or expand'><h2>$Text</h2></a><div id=""$div"">"
$fragments+= $ComputerSysetm | ConvertTo-HTML -Fragment
$fragments+="</div>"

#endregion

#region DISK

$vols = Get-Volume  | 
Where drivetype -eq 'fixed' | Sort FileSystemLabel,DriveLetter  |
Select FileSystemLabel,@{Name="Drive";Expression={
if ($_.DriveLetter) { $_.driveletter} else {"none"}
}},Path,FileSystem,HealthStatus,
@{Name="Size GB";Expression={[math]::Round(($_.Size/1gb),2)}},
@{Name="Free GB";Expression={[math]::Round(($_.SizeRemaining/1gb),2)}},
@{Name="Percent Free";Expression={[math]::Round((($_.SizeRemaining/$_.Size)*100),2)}}

$Text="Volumes"
$div=$Text.Replace(" ","_")
$fragments+= "<a href='javascript:toggleDiv(""$div"");' title='Collapse or expand'><h2>$Text</h2></a><div id=""$div"">"

[xml]$html = $vols | ConvertTo-Html -Fragment

#check each row, skipping the TH header row
#add alert class if volume is not healthy
for ($i=1;$i -le $html.table.tr.count-1;$i++) {
  $class = $html.CreateAttribute("class")
    
  if ($html.table.tr[$i].td[4] -ne "Healthy") {
    $class.value = "alert"    
    $html.table.tr[$i].ChildNodes[4].Attributes.Append($class) | Out-Null
  }
  else {
    $class.value = "green"    
    $html.table.tr[$i].ChildNodes[4].Attributes.Append($class) | Out-Null
  }
  
}

$fragments+= $html.innerXML
$fragments+="</div>"
#endregion

#region MPIO
$Text="MPIO"
$div=$Text.Replace(" ","_")
$fragments+= "<a href='javascript:toggleDiv(""$div"");' title='Collapse or expand'><h2>$Text</h2></a><div id=""$div"">"

$fragments += Get-MPIOAvailableHW | Select VendorId,ProductId,IsMultipathed,BusType,@{Expression={(Get-ItemProperty "hklm:\SYSTEM\CurrentControlSet\Services\msdsm\Parameters" -Name PathVerifyEnabled -ErrorAction SilentlyContinue).PathVerifyEnabled};Label="PathVerificationState"} | ConvertTo-Html -Fragment
$fragments+="</div>"
#endregion

#region MPIO Disk
$Text="MPIO  Disk Info"
$div=$Text.Replace(" ","_")
$fragments+= "<a href='javascript:toggleDiv(""$div"");' title='Collapse or expand'><h2>$Text</h2></a><div id=""$div"">"

$fragments += (Get-Wmiobject -Namespace root\wmi -Class mpio_disk_info).DriveInfo | Select Name,DsmName,NumberPaths |  Sort Name | ConvertTo-Html -Fragment
$fragments+="</div>"
#endregion

#region FiberChannel Adapter
$Text="FiberChannel Adapters"
$div=$Text.Replace(" ","_")
$fragments+= "<a href='javascript:toggleDiv(""$div"");' title='Collapse or expand'><h2>$Text</h2></a><div id=""$div"">"

$fragments +=Get-WmiObject -class MSFC_FCAdapterHBAAttributes -namespace "root\WMI" | select Manufacturer,Model,Active,DriverVersion,FirmwareVersion,@{Expression={((($_.NodeWWN) | ForEach-Object {"{0:X2}" -f $_}) -join ":").Toupper()};Label="NodeWWN"},@{Expression={((Get-InitiatorPort -InstanceName ($_.InstanceName)).PortAddress -replace '(..(?!$))','$1:').Toupper()};Label="Port WWN"} | ConvertTo-Html -Fragment
$fragments+="</div>"
#endregion

#region Adapter
$Text="Network Adapters"
$div=$Text.Replace(" ","_")
$fragments+= "<a href='javascript:toggleDiv(""$div"");' title='Collapse or expand'><h2>$Text</h2></a><div id=""$div"">"

$fragments +=Get-NetAdapter | select Name,InterfaceDescription,MacAddress,LinkSpeed,MediaConnectionState,DriverVersion,MtuSize | Sort Name | ConvertTo-Html -Fragment
$fragments+="</div>"
#endregion

#region IP
$Text="IP Configuration"
$div=$Text.Replace(" ","_")
$fragments+= "<a href='javascript:toggleDiv(""$div"");' title='Collapse or expand'><h2>$Text</h2></a><div id=""$div"">"

$fragments +=Get-NetIPConfiguration | select InterfaceAlias,@{Expression={$_.IPv4Address.IPAddress};Label="IPv4Address"},@{Expression={$_.IPv4DefaultGateway.nexthop};Label="IPv4DefaultGateway"},@{Expression={$_.DNSServer.ServerAddresses};Label="DNSServer"} | Sort InterfaceAlias | ConvertTo-Html -Fragment
$fragments+="</div>"
#endregion

#region DNS cleint
$Text="DNS Enabled Adapters"
$div=$Text.Replace(" ","_")
$fragments+= "<a href='javascript:toggleDiv(""$div"");' title='Collapse or expand'><h2>$Text</h2></a><div id=""$div"">"

$fragments +=Get-DnsClient -RegisterThisConnectionsAddress $true| Select InterfaceAlias,RegisterThisConnectionsAddress,Suffix | Sort InterfaceAlias | ConvertTo-Html -Fragment
$fragments+="</div>"
#endregion

#region NIC Teams
$Text="NIC LbfoTeam"
$div=$Text.Replace(" ","_")
$fragments+= "<a href='javascript:toggleDiv(""$div"");' title='Collapse or expand'><h2>$Text</h2></a><div id=""$div"">"

$fragments +=Get-NetLbfoTeam | select Name,Members,TeamingMode,LoadBalancingAlgorithm | Sort Name | ConvertTo-Html -Fragment
$fragments+="</div>"
#endregion

#region RSS
$Text="RSS Adapters"
$div=$Text.Replace(" ","_")
$fragments+= "<a href='javascript:toggleDiv(""$div"");' title='Collapse or expand'><h2>$Text</h2></a><div id=""$div"">"

$fragments +=Get-NetAdapterRss | ? {$_.Enabled -eq $true} | Select Name,Enabled,Profile,NumberOfReceiveQueues,BaseProcessorNumber,MaxProcessorNumber,MaxProcessors,BaseProcessorGroup | Sort BaseProcessorNumber | ConvertTo-Html -Fragment
$fragments+="</div>"
#endregion

#region VMQ
$Text="VMQ Adapters"
$div=$Text.Replace(" ","_")
$fragments+= "<a href='javascript:toggleDiv(""$div"");' title='Collapse or expand'><h2>$Text</h2></a><div id=""$div"">"

$fragments +=Get-NetAdapterVMQ | ? {$_.Enabled -eq $true} | Select Name,Enabled,NumberOfReceiveQueues,BaseProcessorNumber,MaxProcessorNumber,MaxProcessors,BaseProcessorGroup | Sort BaseProcessorNumber | ConvertTo-Html -Fragment
$fragments+="</div>"
#endregion

#region RDMA
$Text="RDMA Adapters"
$div=$Text.Replace(" ","_")
$fragments+= "<a href='javascript:toggleDiv(""$div"");' title='Collapse or expand'><h2>$Text</h2></a><div id=""$div"">"

$fragments +=Get-NetAdapterRDMA | ? {$_.Enabled -eq $true} | Select Name,Enabled,MaxInboundReadLimit,MaxOutboundReadLimit,MaxQueuePairCount | Sort Name | ConvertTo-Html -Fragment
$fragments+="</div>"
#endregion

#region Live Migrations
$Text="Live Migration Settings"
$div=$Text.Replace(" ","_")
$fragments+= "<a href='javascript:toggleDiv(""$div"");' title='Collapse or expand'><h2>$Text</h2></a><div id=""$div"">"

$fragments += (Get-VMHost | Select VirtualMachineMigrationEnabled,@{Expression={$_.MaximumVirtualMachineMigrations};Label="MaximumVMMigrations"},MaximumStorageMigrations,@{Expression={$_.VirtualMachineMigrationAuthenticationType};Label="AuthenticationType"},@{Expression={$_.VirtualMachineMigrationPerformanceOption};Label="PerformanceOption"},UseAnyNetworkForMigration,@{Expression={ Get-VMMigrationNetwork | ForEach-Object {$String += $($_.Subnet) + "#NEWLINE#" } ; return $String };Label="VMMigrationNetwork"} | ConvertTo-Html -Fragment).Replace("#NEWLINE#","<br>")
#endregion

#region VMSWITCH
$Text="VM Switch"
$div=$Text.Replace(" ","_")
$fragments+= "<a href='javascript:toggleDiv(""$div"");' title='Collapse or expand'><h2>$Text</h2></a><div id=""$div"">"

$fragments += (Get-VMSwitch | Select Name,NetAdapterInterfaceDescription,SwitchType,AllowManagementOS,AvailableVMQueues,IovEnabled,@{Expression={ $_.Extensions | ForEach-Object {$String += $($_.Name) + "#NEWLINE#" } ; return $String };Label="Extensions"} | ConvertTo-Html -Fragment).Replace("#NEWLINE#","<br>")
$fragments+="</div>"
#endregion

#region VMs
$Text="VMs"
$div=$Text.Replace(" ","_")
$fragments+= "<a href='javascript:toggleDiv(""$div"");' title='Collapse or expand'><h2>$Text</h2></a><div id=""$div"">"

$fragments+= Get-VM | select Name,State,Generation,Status,Version,IntegrationServicesState,Path | ConvertTo-Html -Fragment
$fragments+="</div>"
#endregion

#region Installed Programs
$Text="Installed Programs"
$div=$Text.Replace(" ","_")
$fragments+= "<a href='javascript:toggleDiv(""$div"");' title='Collapse or expand'><h2>$Text</h2></a><div id=""$div"">"

$fragments+= Get-WmiObject win32_product | Select Name,Vendor,Version | sort name | ConvertTo-Html -Fragment
$fragments+="</div>"
#endregion

$HTMLOutput = $fragments
$HTMLOutput

}

$head = @"
<Title>$("CloudMechanic.net - Hyper-V Configuration Report")</Title>
<style>

@import url(http://fonts.googleapis.com/css?family=Roboto:400,500,700,300,100);

h1{
color: #fafafa;
}

h2 
{
color: #fafafa;
   font-size: 16px;
   font-weight: 400;
   font-style:normal;
   font-family: "Roboto", helvetica, arial, sans-serif;
   text-shadow: -1px -1px 1px rgba(0, 0, 0, 0.1);
   text-transform:uppercase;
}
caption 
{
background-color:#A9A9F5;
text-align:left;
font-weight:bold;
}
body 
{ 
 background-color: #404040;
  font-family: "Roboto", helvetica, arial, sans-serif;
  font-size: 12px;
  font-weight: 400;
  text-rendering: optimizeLegibility;
}
td, th 
{ 
 border:1px solid black; 
 border-collapse:collapse; 
}

th 
{
color:#D5DDE5;;
  background:#1b1e24;
  border-bottom:4px solid #9ea7af;
  border-right: 1px solid #343a45;
  font-size:16px;
  font-weight: 100;
  text-align:left;
  text-shadow: 0 1px 1px rgba(0, 0, 0, 0.1);
  vertical-align:middle;
}
th:first-child {
  border-top-left-radius:4px;
}
 
th:last-child {
  border-top-right-radius:4px;
  border-right:none;
}

tr{
border-top: 1px solid #C1C3D1;
  border-bottom-: 1px solid #C1C3D1;
  color:#262626;
  font-size:12px;
  font-weight:normal;
  text-shadow: 0 1px 1px rgba(256, 256, 256, 0.1);
}

tr:first-child {
  border-top:none;
}

tr:last-child {
  border-bottom:none;
}
tr:nth-child(odd) td {
  background:#EBEBEB;
}
tr:last-child td:first-child {
  border-bottom-left-radius:4px;
}
tr:last-child td:last-child {
  border-bottom-right-radius:4px;
}

td{
background:#FFFFFF;
  padding:20px;
  text-align:left;
  vertical-align:middle;
  font-weight:300;
  font-size:12px;
  text-shadow: -1px -1px 1px rgba(0, 0, 0, 0.1);
  border-right: 1px solid #C1C3D1;
}
td:last-child {
  border-right: 0px;
}
table, tr, td, th 
{ 
padding: 3px; 
border-spacing:0;
}
table 
{ 
width:95%;
margin-left:5px; 
}

td:first-child  {  
  font-weight:bold;
}

tr:nth-child(odd) {background-color: lightgray}
.alert {color:red}
.green {color:green}
.memalert {background-color: red}
.memwarn {background-color: yellow}
a:link { color: black; margin-left:5px;}
a:visited { color: black}
a:hover {color:blue}
</style>

<script type='text/javascript' src='https://ajax.googleapis.com/ajax/libs/jquery/1.4.4/jquery.min.js'>
</script>
<script type='text/javascript'>
function toggleDiv(divId) {
   `$("#"+divId).toggle();
}
function toggleAll() {
    var divs = document.getElementsByTagName('div');
    for (var i = 0; i < divs.length; i++) {
        var div = divs[i];
        `$("#"+div.id).toggle();
    }
}
</script>

<H1>Computer Name: $($ComputerName.ToUpper())</H1>
<H2>CloudMechanic.net - Hyper-V Configuration Report</H2>
"@

$footer=@"
<p style='color:white'><i>Created $(Get-Date) by $($env:userdomain)\$($env:username)
"@

$out = ConvertTo-Html -Head $head -Body $HTMLOutput -PostContent $footer

$out | Out-File $($OutputPath + $ComputerName + "_" + $(get-date -Format yyyy-MM-dd) +".htm") -Encoding ascii
}