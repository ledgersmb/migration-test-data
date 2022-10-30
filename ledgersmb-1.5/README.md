
## Migration Test Data From LedgerSMB 1.5

This directory contains data originating from LedgerSMB 1.5

### File: demo-1.5-pg9.6.sql

`demo-1.5-pg9.6.sql` is an export from LedgerSMB version 1.5.24 online demo. It contains a lot of made up data provided by internet users and should be good for fuzz testing.  The data does not represent an operating company.

In order to import into LedgerSMB 1.5.30 Postgres 9.6, line 23238, creating view `role_view` had to be modified.  The old line is still in the file as a comment.  Not sure why this was required.

This file should load into any LedgerSMB version later than 1.10.3 and Postgres 9 through 13.

This data has to be imported into Postgres 13 or earlier because of a change in Postgres. See "User-defined objects that reference certain built-in array functions along with their argument types must be recreated"
in the [Postgres 14.0 release notes](https://www.postgresql.org/docs/release/14.0/).

The migration of this file was tested using LedgerSMB 1.10.3 and Postgres 13.8 on 30 October 2022.


