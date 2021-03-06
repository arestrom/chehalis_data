#===============================================================================
# Initialize and set up a sqlite version of the SG database
#
#
# Notes on sqlite, spatialite:
#  1. To load spatialite:
#     https://www.gaia-gis.it/fossil/libspatialite/wiki?name=mod_spatialite
#     https://github.com/sqlitebrowser/sqlitebrowser/wiki/SpatiaLite-on-Windows   Issues for Windows 10
#     https://gdal.org/index.html   Fabulous resource
#     https://www.datacamp.com/community/tutorials/sqlite-in-r   Automate building parametrized queries
#     https://keen-swartz-3146c4.netlify.com/intro.html    New book...looks great.
#  2. The mod_spatialite dlls must be placed in the root directory of the project
#  3. In DB Browser, can load spatialite module as below by specifying path to module
#     Use -- Load extension
#  4. May want to convert all geometries to binary using: x = st_as_binary(x) before
#     writing. May then be able to write directly to field without sf_write.
#     See: https://r-spatial.github.io/sf/articles/sf2.html
#  5. See also: https://github.com/poissonconsulting/readwritesqlite
#  6. Joe Thorley used BLOB for geometry...check how to read, write, manipulate, and display using sf.
#     I should probably always just write as binary object...avoids select into queries.
#     He also stored dates as REAL not TEXT...what are benefits of real vs text? Faster?
#     Any chances of rounding? Truncation.
#  7. See: https://www.sqlitetutorial.net/sqlite-foreign-key/
#     Need to use: PRAGMA foreign_keys = ON; to make sure constraints are used.
#     I tested to verify foreign key constraints are possible for current DB
#
#
# Notes on R procedure:
#  1. Running dbConnect() will create the database if it does not already exist
#  2. Use DB Browser for SQLite to connect to sg_lite.sqlite. Then run create
#     script to create database.
#
#
# ToDo:
#  1. Test writing to sqlite as BLOB and reading and manipulating as BLOB. The
#     meuse.sqlite db is already in BLOB format. Try to emulate. Using strictly
#     BLOBs may avoid having to use select into statements. The only case where
#     we may want geometry columns in sqlite is if in-database spatial queries
#     are needed. Postgis data is in binary format...and still allows spatial
#     queries. But there the metadata and architecture is likely to be more
#     explicit around binary geometries.
#
# AS 2020-02-25
#===============================================================================

# Load libraries
library(DBI)
library(RSQLite)
library(readwritesqlite)
library(tibble)
library(sf)
library(glue)

# Create database connection
con <- dbConnect(RSQLite::SQLite(), dbname = 'data/sg_lite.sqlite')

# Load a table...you can drop manually in spatilite gui later and it will still open without error
# There just needs to be a table in the DB to ensure the magic number stuff works out correctly.
qry = glue("CREATE TABLE adipose_clip_status_lut ( ",
	         "adipose_clip_status_id text DEFAULT (CreateUUID()) PRIMARY KEY, ",
           "adipose_clip_status_code text NOT NULL, ",
           "adipose_clip_status_description text NOT NULL, ",
           "obsolete_flag integer NOT NULL, ",
           "obsolete_datetime text DEFAULT (datetime('now')) ",
           ") WITHOUT ROWID;")

# Write new table
dbExecute(con, qry)

# Check
dbListTables(con)
dbListFields(con, name = 'adipose_clip_status_lut')

# Disconnect
dbDisconnect(con)

# # Load the spatialite extension....spatialite dlls must be in the root directory
# qry = "SELECT load_extension('mod_spatialite')"
# rs = dbGetQuery(con, qry)
#
# # Test....works !!
# dbGetQuery(con, "SELECT CreateUUID() as uuid")
#
# # Disconnect
# dbDisconnect(con)

# #===============================================================================
# # Inspect the meuse.sqlite database to see structure. How are geometries stored?
# # They are stored as blobs
# #===============================================================================
#
# # Create database connection
# con <- dbConnect(RSQLite::SQLite(), dbname = 'data/meuse.sqlite', loadable.extensions = TRUE)
#
# # Check
# dbListTables(con)
#
# # Disconnect
# dbDisconnect(con)
#
# #===============================================================================
# # Check using readwritesqlite
# #===============================================================================
#
# # Opens connection to sqlite db in memory....does not exist yet
# conn <- rws_connect()
#
# # Gets rws dataset
# rws_data <- readwritesqlite::rws_data
# rws_data
#
# # Write to the db in memory
# rws_write(rws_data, exists = FALSE, conn = conn)
#
# # Read from db in memory
# rws_db = rws_read_table("rws_data", conn = conn)
#
# # Write to sqlite on disk
# db_con = rws_connect(dbname = "data/rws_db.sqlite")
#
# # Write to the db on disk
# rws_write(rws_db, exists = FALSE, conn = db_con)
#
# # Disconnect
# rws_disconnect(conn)
# rws_disconnect(db_con)
#
# #===============================================================================
# # Playing with hex and binary
# #===============================================================================
#
# # Create point as wkt
# (stpt = st_point(c(-122.1234,47.3487)))
#
# # See wkt printed
# st_as_text(stpt)
#
# # Convert to binary
# (st_bin = st_as_binary(stpt))
#
# # Convert to hex
# (st_hex = rawToHex(st_bin))
#
# # Convert back to binary
# (st_bin_two = wkb::hex2raw(st_hex))
#
# # Convert back to sfc
# (x = st_as_sfc(st_bin_two))
#
# #===============================================================================
# # Test to see if built-in SQLite uuid() function works (new in latest version)
# # Not yet
# #===============================================================================
#
# # Create new in memory database
# con <- dbConnect(RSQLite::SQLite(), "my-db.sqlite")
#
# # Test...no go yet
# dbGetQuery(con, "SELECT uuid() as uuid")
#
# # Disconnect
# dbDisconnect(con)
# unlink("my-db.sqlite")













