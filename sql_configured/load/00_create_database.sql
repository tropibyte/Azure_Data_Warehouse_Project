/* =====================================================================
   00 - Create the serverless SQL database.

   RUN THIS FIRST, AND RUN IT ON ITS OWN.

   A new Synapse workspace gives you a Built-in (serverless) SQL endpoint with
   only `master` on it. Every other script in this repo needs a real database to
   live in, and you cannot create one and use it in the same execution - the
   session is still bound to master.

   So:
     1. Connect to:  Built-in     Use database: master
     2. Run this script.
     3. Hit the refresh arrow next to the database dropdown.
     4. Switch Use database to: divvy
     5. Run 01_setup_data_source_and_formats.sql and everything after it.

   The collation matters. PARSER_VERSION 2.0 - the serverless default - reads
   UTF-8 delimited files into VARCHAR columns only when the column collation is
   a UTF8 one. Setting it at the database level means none of the external table
   scripts need a COLLATE clause on every column.
   ===================================================================== */

IF DB_ID('divvy') IS NULL
    CREATE DATABASE divvy COLLATE Latin1_General_100_CI_AS_SC_UTF8;
GO

SELECT name, collation_name
FROM sys.databases
WHERE name = 'divvy';
GO
