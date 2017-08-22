SELECT ag.name AS ag_name, ars.role_desc, ar.replica_server_name, adc.database_name,
	d.log_reuse_wait_desc, drs.database_state_desc, ar.availability_mode_desc, drs.synchronization_state_desc, 
	drs.synchronization_health_desc, drs.redo_queue_size, ars.connected_state_desc, 
	ars.operational_state_desc, ars.recovery_health_desc, drs.last_commit_time, 
	datediff(s,last_hardened_time,getdate()) as 'sec behind primary'
FROM sys.databases d
JOIN sys.dm_hadr_database_replica_states AS drs WITH (NOLOCK) ON d.database_id=drs.database_id
JOIN sys.availability_databases_cluster AS adc WITH (NOLOCK) ON drs.group_id = adc.group_id AND drs.group_database_id = adc.group_database_id
JOIN sys.availability_groups AS ag WITH (NOLOCK) ON ag.group_id = drs.group_id
JOIN sys.availability_replicas AS ar WITH (NOLOCK) ON drs.group_id = ar.group_id AND drs.replica_id = ar.replica_id
JOIN sys.dm_hadr_availability_replica_states ars WITH (NOLOCK) ON ar.replica_id = ars.replica_id
ORDER BY ars.role_desc ASC,	ag.name ASC, ar.replica_server_name ASC, adc.database_name ASC;



USE [master]
GO
ALTER AVAILABILITY GROUP [HRMGAGL]
MODIFY REPLICA ON N'AUSPWHRMGRDB01' 
WITH (SECONDARY_ROLE(ALLOW_CONNECTIONS = READ_ONLY))
GO
ALTER AVAILABILITY GROUP [HRMGAGL]
MODIFY REPLICA ON N'AUSPWHRMGRDB01' 
WITH (SECONDARY_ROLE (READ_ONLY_ROUTING_URL = N'TCP://AUSPWHRMGRDB01.aus.amer.dell.com:5022'))
GO