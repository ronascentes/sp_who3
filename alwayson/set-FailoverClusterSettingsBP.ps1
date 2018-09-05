<#  
 .Synopsis 
  Unexpected failover happens
 
 .Description 
  Uses this script to set cluster settings as per Microsoft best practices in order to prevent unexpected failovers
    
  .Notes
  Author: Rodrigo - @ronascentes  
  
 .Link
  References:
  http://blogs.msdn.com/b/clustering/archive/2012/11/21/10370765.aspx
  http://blogs.technet.com/b/askcore/archive/2012/02/08/having-a-problem-with-nodes-being-removed-from-active-failover-cluster-membership.aspx
  http://blogs.technet.com/b/askcore/archive/2013/06/03/nodes-being-removed-from-failover-cluster-membership-on-vmware-esx.aspx
  http://kb.vmware.com/selfservice/microsites/search.do?language=en_US&cmd=displayKC&externalId=2039495
       
 .Parameter  
  None
 
 .Example 
   NA
#> 

CLS

import-module failoverclusters

$res = Get-ClusterResource | ?{$_.ResourceType -match "SQL Server Availability Group"} | Select-Object Name
foreach ($r in $res) { Get-ClusterResource | Where-Object {$_.OwnerGroup -match $r.Name} | ForEach-Object {$_.RestartThreshold = 5} }
foreach ($r in $res) { Get-ClusterResource | Where-Object {$_.OwnerGroup -match $r.Name} | ForEach-Object {$_.RestartDelay = 2000} }
foreach ($r in $res) { (Get-ClusterGroup -name $r.name).FailoverThreshold = 50 }
foreach ($r in $res) { (Get-ClusterGroup -name $r.Name).FailoverPeriod = 1 }


# to view the current cluster hearbeat configuration 
get-cluster | fl *subnet*

#change cluster hearbeat configuration to relaxed monitoring
(get-cluster).CrossSubnetDelay = 2000
(get-cluster).CrossSubnetThreshold = 15
(get-cluster).SameSubnetDelay = 2000 
(get-cluster).SameSubnetThreshold = 15
(get-cluster).RouteHistoryLength = 10

get-cluster | fl *subnet*
