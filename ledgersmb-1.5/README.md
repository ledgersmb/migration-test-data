
## Migration Test Data From LedgerSMB 1.5

This directory contains data originating from LedgerSMB 1.5

### File: demo15_pg13.8.sql

`demo15_pg13.8.sql` is an export from LedgerSMB version 1.5.24 online demo. It contains a lot of made up data provided by internet users and should be good for fuzz testing.  The data does not represent an operating company.

In order to import into LedgerSMB 1.5.30 Postgres 9.6, line 23238, creating view `role_view` had to be modified.  The old line is still in the file as a comment.  Not sure why this was required.

This data has to be imported into Postgres 13 or earlier because of a change in Postgres. See "User-defined objects that reference certain built-in array functions along with their argument types must be recreated"
in the [Postgres 14.0 release notes](https://www.postgresql.org/docs/release/14.0/).

The migration of this file was tested using LedgerSMB 1.11-dev (master after commit [63a9959](https://github.com/ledgersmb/LedgerSMB/commit/63a9959d9e15e5221b11e4aa41160089f1c33400), 23 Oct 2022) and Postgres 13.8.

### File: demo15_pg14-roles.sqlc

`demo15_pg14-roles.sqlc` is an export of the roles after `demo15_pg13.8.sql` was migrated. This file is suitable for importing into Postgres 14+ database.

Note that Postgres 14 changed password encryption defaults.  To import this file you may need to comment out the lines starting with `CREATE ROLE postgres` and `ALTER ROLE postgres` or otherwise handle the security change.

This file was tested using Postgres 14.5 on 24 October 2022 using LedgerSMB 1.11-dev.

### File: demo15_pg14-db.sql

`demo15_pg14-db.sql` is an export of the database after `demo15_pg13.8.sql` was migrated. This file is suitable for importing into Postgres 14+ database.

This file was tested using Postgres 14.5 on 24 October 2022 using LedgerSMB 1.11-dev.

