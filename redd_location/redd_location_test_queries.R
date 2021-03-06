#===============================================================================
# Verify queries work
#
# AS 2020-02-25
#===============================================================================

# Load libraries
library(DBI)
library(RSQLite)
library(tibble)
library(sf)
library(glue)

# # Set data for query

# # Absher Cr
# waterbody_id = '05a031e6-62b7-411f-9e3c-b5d6efbda33b'

# # Alder Cr
# waterbody_id = '3fd8a43f-505c-4e1b-9474-94046099af62'

# SF Newaukum
waterbody_id = '2cffd913-8e7a-4967-bed3-2c437b81f15b'

up_rm = 27.0
#up_rm = "null"
lo_rm = 23.1
#lo_rm = "null"

survey_date = "2019-10-31"
# survey_date = "null"

# # Chinook
# species_id = "e42aa0fc-c591-4fab-8481-55b0df38dcb1"

# Coho
species_id = "a0f5b3af-fa07-449c-9f02-14c5368ab304"
#created_by = Sys.getenv("USERNAME")

get_new_redd_location = function(waterbody_id) {
  # Define query for new redd locations...no attached surveys yet...finds new entries
  qry = glue("select rloc.location_id as redd_location_id, ",
             "rloc.location_name as redd_name, ",
             "lc.location_coordinates_id, lc.geom as geometry, ",
             "lc.horizontal_accuracy as horiz_accuracy, ",
             "sc.channel_type_description as channel_type, ",
             "lo.orientation_type_description as orientation_type, ",
             "rloc.location_description, ",
             "datetime(rloc.created_datetime, 'localtime') as created_date, ",
             "datetime(rloc.modified_datetime, 'localtime') as modified_date, ",
             "rloc.created_by, rloc.modified_by ",
             "from location as rloc ",
             "inner join location_type_lut as lt on rloc.location_type_id = lt.location_type_id ",
             "left join location_coordinates as lc on rloc.location_id = lc.location_id ",
             "left join redd_encounter as rd on rloc.location_id = rd.redd_location_id ",
             "inner join stream_channel_type_lut as sc on rloc.stream_channel_type_id = sc.stream_channel_type_id ",
             "inner join location_orientation_type_lut as lo on rloc.location_orientation_type_id = lo.location_orientation_type_id ",
             "where date(rloc.created_datetime) > date('now', '-1 day') ",
             "and rd.redd_encounter_id is null ",
             "and rloc.waterbody_id = '{waterbody_id}' ",
             "and lt.location_type_description = 'Redd encounter'")
  con = dbConnect(RSQLite::SQLite(), dbname = 'database/spawning_ground_lite.sqlite')
  new_loc = sf::st_read(con, query = qry, crs = 2927)
  dbDisconnect(con)
  return(new_loc)
}

# Test
strt = Sys.time()
new_redd_loc = get_query_one(waterbody_id)
nd = Sys.time(); nd - strt


get_previous_redd_location = function(waterbody_id, up_rm, lo_rm, survey_date, species_id) {
  # Define query for existing redd location entries with surveys attached
  qry = glue("select datetime(s.survey_datetime, 'localtime') as redd_survey_date, ",
             "se.species_id as db_species_id, ",
             "sp.common_name as species, uploc.river_mile_measure as up_rm, ",
             "loloc.river_mile_measure as lo_rm, rloc.location_id as redd_location_id, ",
             "rloc.location_name as redd_name, rs.redd_status_short_description as redd_status, ",
             "lc.location_coordinates_id, lc.geom as geometry, ",
             "lc.horizontal_accuracy as horiz_accuracy, ",
             "sc.channel_type_description as channel_type, ",
             "lo.orientation_type_description as orientation_type, ",
             "rloc.location_description, ",
             "datetime(rloc.created_datetime, 'localtime') as created_date, ",
             "datetime(rloc.modified_datetime, 'localtime') as modified_date,  ",
             "rloc.created_by, rloc.modified_by ",
             "from survey as s ",
             "inner join location as uploc on s.upper_end_point_id = uploc.location_id ",
             "inner join location as loloc on s.lower_end_point_id = loloc.location_id ",
             "inner join survey_event as se on s.survey_id = se.survey_id ",
             "inner join species_lut as sp on se.species_id = sp.species_id ",
             "inner join redd_encounter as rd on se.survey_event_id = rd.survey_event_id ",
             "inner join redd_status_lut as rs on rd.redd_status_id = rs.redd_status_id ",
             "inner join location as rloc on rd.redd_location_id = rloc.location_id ",
             "left join location_coordinates as lc on rloc.location_id = lc.location_id ",
             "inner join stream_channel_type_lut as sc on rloc.stream_channel_type_id = sc.stream_channel_type_id ",
             "inner join location_orientation_type_lut as lo on rloc.location_orientation_type_id = lo.location_orientation_type_id ",
             "where date(s.survey_datetime) between date('{survey_date}', '-4 month') and date('{survey_date}') ",
             "and rloc.waterbody_id = '{waterbody_id}' ",
             "and uploc.river_mile_measure <= {up_rm} ",
             "and loloc.river_mile_measure >= {lo_rm} ",
             "and se.species_id = '{species_id}' ",
             "and not rs.redd_status_short_description in ('Previous redd, not visible')")
  con = dbConnect(RSQLite::SQLite(), dbname = 'database/spawning_ground_lite.sqlite')
  prev_loc = sf::st_read(con, query = qry, crs = 2927)
  dbDisconnect(con)
  return(prev_loc)
}

# Test
strt = Sys.time()
prev_loc = get_previous_redd_location(waterbody_id, up_rm, lo_rm, survey_date, species_id)
nd = Sys.time(); nd - strt



get_redd_locations = function(waterbody_id, up_rm, lo_rm, survey_date, species_id) {
  new_redd_loc = get_new_redd_location(waterbody_id)
  # st_coordinates does not work with missing coordinates, so parse out separately
  new_coords = new_redd_loc %>%
    filter(!is.na(location_coordinates_id)) %>%
    mutate(geometry = st_transform(geometry, 4326)) %>%
    mutate(longitude = as.numeric(st_coordinates(geometry)[,1])) %>%
    mutate(latitude = as.numeric(st_coordinates(geometry)[,2])) %>%
    st_drop_geometry()
  new_no_coords = new_redd_loc %>%
    filter(is.na(location_coordinates_id)) %>%
    st_drop_geometry()
  # Combine
  new_locs = bind_rows(new_no_coords, new_coords) %>%
    mutate(created_date = as.character(created_date)) %>%
    mutate(modified_date = as.character(modified_date))
  # Get pre-existing redd locations
  prev_redd_loc = get_previous_redd_location(waterbody_id, up_rm, lo_rm, survey_date, species_id)
  # st_coordinates does not work with missing coordinates, so parse out separately
  prev_coords = prev_redd_loc %>%
    filter(!is.na(location_coordinates_id)) %>%
    mutate(geometry = st_transform(geometry, 4326)) %>%
    mutate(longitude = as.numeric(st_coordinates(geometry)[,1])) %>%
    mutate(latitude = as.numeric(st_coordinates(geometry)[,2])) %>%
    st_drop_geometry()
  prev_no_coords = prev_redd_loc %>%
    filter(is.na(location_coordinates_id)) %>%
    st_drop_geometry()
  # Combine
  prev_locs = bind_rows(prev_no_coords, prev_coords) %>%
    mutate(created_date = as.character(created_date)) %>%
    mutate(modified_date = as.character(modified_date))
  redd_locations = bind_rows(new_locs, prev_locs) %>%
    mutate(latitude = round(latitude, 7)) %>%
    mutate(longitude = round(longitude, 7)) %>%
    mutate(redd_survey_date = as.POSIXct(redd_survey_date, tz = "America/Los_Angeles")) %>%
    mutate(survey_dt = format(redd_survey_date, "%m/%d/%Y")) %>%
    mutate(created_date = as.POSIXct(created_date, tz = "America/Los_Angeles")) %>%
    mutate(created_dt = format(created_date, "%m/%d/%Y %H:%M")) %>%
    mutate(modified_date = as.POSIXct(modified_date, tzone = "America/Los_Angeles")) %>%
    mutate(modified_dt = format(modified_date, "%m/%d/%Y %H:%M")) %>%
    select(redd_location_id, location_coordinates_id,
           survey_date = redd_survey_date, survey_dt, species,
           redd_name, redd_status, latitude, longitude, horiz_accuracy,
           channel_type, orientation_type, location_description,
           created_date, created_dt, created_by, modified_date,
           modified_dt, modified_by) %>%
    arrange(created_date)
  return(redd_locations)
}

# Test
strt = Sys.time()
redd_locs = get_redd_locations(waterbody_id, up_rm, lo_rm, survey_date, species_id)
nd = Sys.time(); nd - strt

# Redd_coordinates query...for setting redd_marker when redd_location row is selected
redd_location_id = redd_locs$redd_location_id[[1]]
get_redd_coordinates = function(redd_location_id) {
  qry = glue("select loc.location_id, lc.location_coordinates_id, ",
             "lc.geom as geometry, ",
             "lc.horizontal_accuracy as horiz_accuracy, ",
             "datetime(lc.created_datetime, 'localtime') as created_date, lc.created_by, ",
             "datetime(lc.modified_datetime, 'localtime') as modified_date, lc.modified_by ",
             "from location as loc ",
             "inner join location_coordinates as lc on loc.location_id = lc.location_id ",
             "where loc.location_id = '{redd_location_id}'")
  con = dbConnect(RSQLite::SQLite(), dbname = 'data/sg_lite.sqlite')
  #con = poolCheckout(pool)
  redd_coordinates = sf::st_read(con, query = qry, crs = 2927)
  dbDisconnect(con)
  #poolReturn(con)
  # Only do the rest if nrows > 0
  if (nrow(redd_coordinates) > 0 ) {
    redd_coordinates = redd_coordinates %>%
      st_transform(., 4326) %>%
      mutate(longitude = as.numeric(st_coordinates(geometry)[,1])) %>%
      mutate(latitude = as.numeric(st_coordinates(geometry)[,2])) %>%
      st_drop_geometry() %>%
      mutate(latitude = round(latitude, 7)) %>%
      mutate(longitude = round(longitude, 7)) %>%
      mutate(created_date = as.POSIXct(created_date, tz = "America/Los_Angeles")) %>%
      mutate(created_dt = format(created_date, "%m/%d/%Y %H:%M")) %>%
      mutate(modified_date = as.POSIXct(modified_date, tz = "America/Los_Angeles")) %>%
      mutate(modified_dt = format(modified_date, "%m/%d/%Y %H:%M")) %>%
      select(redd_location_id = location_id, location_coordinates_id,
             latitude, longitude, horiz_accuracy, created_date,
             created_dt, created_by, modified_date, modified_dt,
             modified_by) %>%
      arrange(created_date)
  }
  return(redd_coordinates)
}

# Test
strt = Sys.time()
redd_coords = get_redd_coordinates(redd_location_id)
nd = Sys.time(); nd - strt

# Stream centroid query
get_stream_centroid = function(waterbody_id) {
  qry = glue("select DISTINCT st.waterbody_id, ",
             "st.geom as geometry ",
             "from stream as st ",
             "where st.waterbody_id = '{waterbody_id}'")
  con = dbConnect(RSQLite::SQLite(), dbname = 'data/sg_lite.sqlite')
  #con = poolCheckout(pool)
  stream_centroid = sf::st_read(con, query = qry) %>%
    mutate(stream_center = st_centroid(geometry)) %>%
    mutate(stream_center = st_transform(stream_center, 4326)) %>%
    mutate(center_lon = as.numeric(st_coordinates(stream_center)[,1])) %>%
    mutate(center_lat = as.numeric(st_coordinates(stream_center)[,2])) %>%
    st_drop_geometry() %>%
    select(waterbody_id, center_lon, center_lat)
  dbDisconnect(con)
  #poolReturn(con)
  return(stream_centroid)
}

# Test
strt = Sys.time()
stream_center_pt = get_stream_centroid(waterbody_id)
nd = Sys.time(); nd - strt













