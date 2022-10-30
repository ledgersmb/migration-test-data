
## Migration Test Data From LedgerSMB 1.10

This directory contains data originating from LedgerSMB 1.10

### File: demo-1.10-pg14-roles.sqlc

`demo-1.10-pg14-roles.sqlc` is an export of the roles from LedgerSMB 1.10.3 and Postgres 13.8, after `demo-1.5-pg9.6.sql` was migrated.  

This file is suitable for importing into Postgres 14 or later database.

The original data came from an online demo. It contains a lot of made up data provided by internet users and should be good for fuzz testing. The data does not represent an operating company.

Note that Postgres 14 changed password encryption defaults.  To import this file you may need to comment out the lines starting with `CREATE ROLE postgres` and `ALTER ROLE postgres` or otherwise handle the security change.

This file was tested using LedgerSMB 1.10.3 and Postgres 14.5 on 30 October 2022.

### File: demo-1.10-pg14-db.sql

`demo-1.10-pg14-db.sql` is an export of the database from LedgerSMB 1.10.3 and Postgres 13.8, after `demo-1.5-pg9.6.sql` was migrated. 

This file is suitable for importing into Postgres 14+ database.

This file was tested using LedgerSMB 1.10.3 and Postgres 14.5 on 30 October 2022.
