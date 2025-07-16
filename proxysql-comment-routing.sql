-- ProxySQL Configuration for Comment-Based Tenant Routing
-- This configuration handles SQL comments injected by the modified MySQL driver

-- Clear existing rules
DELETE FROM mysql_query_rules;

-- Rule 1: Route queries with tenant_db comment to appropriate backend
-- Priority 1000 - highest priority for tenant routing
INSERT INTO mysql_query_rules (
    rule_id, active, match_pattern, destination_hostgroup, apply, comment
) VALUES (
    1000, 1, 
    '/\\* tenant_db:([^\\*]+) \\*/', 
    1, 1, 
    'Route based on tenant_db comment'
);

-- Rule 2: Default routing for queries without tenant comments
-- Priority 9999 - lowest priority as fallback
INSERT INTO mysql_query_rules (
    rule_id, active, match_pattern, destination_hostgroup, apply, comment
) VALUES (
    9999, 1, 
    '^SELECT|^INSERT|^UPDATE|^DELETE|^REPLACE', 
    0, 1, 
    'Default routing for non-tenant queries'
);

-- Configure hostgroups for tenant databases
DELETE FROM mysql_servers;

-- Hostgroup 0: Default/admin database
INSERT INTO mysql_servers (hostgroup_id, hostname, port, weight, comment) VALUES 
(0, '127.0.0.1', 3306, 1000, 'Default database server');

-- Hostgroup 1: Tenant databases (same physical server, different routing logic)
INSERT INTO mysql_servers (hostgroup_id, hostname, port, weight, comment) VALUES 
(1, '127.0.0.1', 3306, 1000, 'Tenant database server');

-- Configure users
DELETE FROM mysql_users;
INSERT INTO mysql_users (username, password, active, default_hostgroup, max_connections, comment) VALUES 
('root', 'root', 1, 0, 200, 'Admin user');

-- Apply configuration
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
LOAD MYSQL SERVERS TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS TO DISK;

-- Enable query logging for debugging
SET mysql-eventslog_enabled='true';
SET mysql-eventslog_filename='/var/lib/proxysql/queries.log';
LOAD MYSQL VARIABLES TO RUNTIME;
SAVE MYSQL VARIABLES TO DISK;