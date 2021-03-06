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

# Set data for query
# Absher Cr
waterbody_id = '05a031e6-62b7-411f-9e3c-b5d6efbda33b'
# Alder Cr
# waterbody_id = '3fd8a43f-505c-4e1b-9474-94046099af62'
up_rm = 0.50
#up_rm = "null"
lo_rm = 0.00
#lo_rm = "null"
survey_date = "2019-12-04"
# survey_date = "null"
# # Chinook
# species_id = "e42aa0fc-c591-4fab-8481-55b0df38dcb1"
# Coho
species_id = "a0f5b3af-fa07-449c-9f02-14c5368ab304"
#created_by = Sys.getenv("USERNAME")

get_new_fish_location = function(waterbody_id) {
  # Define query for new fish locations...no attached surveys yet...finds new entries
  qry = glue("select floc.location_id as fish_location_id, ",
             "floc.location_name as fish_name, ",
             "lc.location_coordinates_id, lc.geom as geometry, ",
             "lc.horizontal_accuracy as horiz_accuracy, ",
             "sc.channel_type_description as channel_type, ",
             "lo.orientation_type_description as orientation_type, ",
             "floc.location_description, ",
             "datetime(floc.created_datetime, 'localtime') as created_date, ",
             "datetime(floc.modified_datetime, 'localtime') as modified_date, ",
             "floc.created_by, floc.modified_by ",
             "from location as floc ",
             "inner join location_type_lut as lt on floc.location_type_id = lt.location_type_id ",
             "left join location_coordinates as lc on floc.location_id = lc.location_id ",
             "left join fish_encounter as fe on floc.location_id = fe.fish_location_id ",
             "inner join stream_channel_type_lut as sc on floc.stream_channel_type_id = sc.stream_channel_type_id ",
             "inner join location_orientation_type_lut as lo on floc.location_orientation_type_id = lo.location_orientation_type_id ",
             "where date(floc.created_datetime) > date('now', '-1 day') ",
             "and fe.fish_encounter_id is null ",
             "and floc.waterbody_id = '{waterbody_id}' ",
             "and lt.location_type_description = 'Fish encounter'")
  con = dbConnect(RSQLite::SQLite(), dbname = 'database/spawning_ground_lite.sqlite')
  new_loc = sf::st_read(con, query = qry, crs = 2927)
  dbDisconnect(con)
  return(new_loc)
}

# Test
strt = Sys.time()
new_fish_loc = get_new_fish_location(waterbody_id)
nd = Sys.time(); nd - strt

get_previous_fish_location = function(waterbody_id, up_rm, lo_rm, survey_date, species_id) {
  # Define query for fish locations already tied to surveys
  qry = glue("select datetime(s.survey_datetime, 'localtime') as fish_survey_date, ",
             "se.species_id as db_species_id, ",
             "sp.common_name as species, uploc.river_mile_measure as up_rm, ",
             "loloc.river_mile_measure as lo_rm, floc.location_id as fish_location_id, ",
             "floc.location_name as fish_name, fs.fish_status_description as fish_status, ",
             "lc.location_coordinates_id, lc.geom as geometry, ",
             "lc.horizontal_accuracy as horiz_accuracy, ",
             "sc.channel_type_description as channel_type, ",
             "lo.orientation_type_description as orientation_type, ",
             "floc.location_description, ",
             "datetime(floc.created_datetime, 'localtime') as created_date, ",
             "datetime(floc.modified_datetime, 'localtime') as modified_date,  ",
             "floc.created_by, floc.modified_by ",
             "from survey as s ",
             "inner join location as uploc on s.upper_end_point_id = uploc.location_id ",
             "inner join location as loloc on s.lower_end_point_id = loloc.location_id ",
             "inner join survey_event as se on s.survey_id = se.survey_id ",
             "inner join species_lut as sp on se.species_id = sp.species_id ",
             "inner join fish_encounter as fe on se.survey_event_id = fe.survey_event_id ",
             "inner join fish_status_lut as fs on fe.fish_status_id = fs.fish_status_id ",
             "inner join location as floc on fe.fish_location_id = floc.location_id ",
             "left join location_coordinates as lc on floc.location_id = lc.location_id ",
             "inner join stream_channel_type_lut as sc on floc.stream_channel_type_id = sc.stream_channel_type_id ",
             "inner join location_orientation_type_lut as lo on floc.location_orientation_type_id = lo.location_orientation_type_id ",
             "where date(s.survey_datetime) between date('{survey_date}', '-3 month') and date('{survey_date}') ",
             "and floc.waterbody_id = '{waterbody_id}' ",
             "and uploc.river_mile_measure <= {up_rm} ",
             "and loloc.river_mile_measure >= {lo_rm} ",
             "and se.species_id = '{species_id}' ",
             "and fs.fish_status_description = 'Dead'")
  con = dbConnect(RSQLite::SQLite(), dbname = 'database/spawning_ground_lite.sqlite')
  prev_loc = sf::st_read(con, query = qry, crs = 2927)
  dbDisconnect(con)
  return(prev_loc)
}

# Test
strt = Sys.time()
prev_fish_loc = get_previous_fish_location(waterbody_id, up_rm, lo_rm, survey_date, species_id)
nd = Sys.time(); nd - strt

# Define full query
get_fish_locations = function(waterbody_id, up_rm, lo_rm, survey_date, species_id) {
  new_fish_loc = get_new_fish_location(waterbody_id)
  # st_coordinates does not work with missing coordinates, so parse out separately
  new_coords = new_fish_loc %>%
    filter(!is.na(location_coordinates_id)) %>%
    mutate(geometry = st_transform(geometry, 4326)) %>%
    mutate(longitude = as.numeric(st_coordinates(geometry)[,1])) %>%
    mutate(latitude = as.numeric(st_coordinates(geometry)[,2])) %>%
    st_drop_geometry()
  new_no_coords = new_fish_loc %>%
    filter(is.na(location_coordinates_id)) %>%
    st_drop_geometry()
  # Combine
  new_locs = bind_rows(new_no_coords, new_coords) %>%
    mutate(created_date = as.character(created_date)) %>%
    mutate(modified_date = as.character(modified_date))
  # Get pre-existing redd locations
  prev_fish_loc = get_previous_fish_location(waterbody_id, up_rm, lo_rm, survey_date, species_id)
  # st_coordinates does not work with missing coordinates, so parse out separately
  prev_coords = prev_fish_loc %>%
    filter(!is.na(location_coordinates_id)) %>%
    mutate(geometry = st_transform(geometry, 4326)) %>%
    mutate(longitude = as.numeric(st_coordinates(geometry)[,1])) %>%
    mutate(latitude = as.numeric(st_coordinates(geometry)[,2])) %>%
    st_drop_geometry()
  prev_no_coords = prev_fish_loc %>%
    filter(is.na(location_coordinates_id)) %>%
    st_drop_geometry()
  # Combine
  prev_locs = bind_rows(prev_no_coords, prev_coords) %>%
    mutate(created_date = as.character(created_date)) %>%
    mutate(modified_date = as.character(modified_date))
  fish_locations = bind_rows(new_locs, prev_locs) %>%
    mutate(latitude = round(latitude, 7)) %>%
    mutate(longitude = round(longitude, 7)) %>%
    mutate(fish_survey_date = as.POSIXct(fish_survey_date, tz = "America/Los_Angeles")) %>%
    mutate(survey_dt = format(fish_survey_date, "%m/%d/%Y")) %>%
    mutate(created_date = as.POSIXct(created_date, tz = "America/Los_Angeles")) %>%
    mutate(created_dt = format(created_date, "%m/%d/%Y %H:%M")) %>%
    mutate(modified_date = as.POSIXct(modified_date, tzone = "America/Los_Angeles")) %>%
    mutate(modified_dt = format(modified_date, "%m/%d/%Y %H:%M")) %>%
    select(fish_location_id, location_coordinates_id,
           survey_date = fish_survey_date, survey_dt, species,
           fish_name, fish_status, latitude, longitude, horiz_accuracy,
           channel_type, orientation_type, location_description,
           created_date, created_dt, created_by, modified_date,
           modified_dt, modified_by) %>%
    arrange(created_date)
  return(fish_locations)
}

# Test
strt = Sys.time()
fish_locs = get_fish_locations(waterbody_id, up_rm, lo_rm, survey_date, species_id)
nd = Sys.time(); nd - strt


# fish_coordinates query
fish_location_id = fish_locs$fish_location_id[[5]]
get_fish_coordinates = function(fish_location_id) {
  qry = glue("select loc.location_id, lc.location_coordinates_id, ",
             "lc.geom as geometry, ",
             "lc.horizontal_accuracy as horiz_accuracy, ",
             "datetime(lc.created_datetime, 'localtime') as created_date, lc.created_by, ",
             "datetime(lc.modified_datetime, 'localtime') as modified_date, lc.modified_by ",
             "from location as loc ",
             "inner join location_coordinates as lc on loc.location_id = lc.location_id ",
             "where loc.location_id = '{fish_location_id}'")
  con = dbConnect(RSQLite::SQLite(), dbname = 'data/sg_lite.sqlite')
  #con = poolCheckout(pool)
  fish_coordinates = sf::st_read(con, query = qry, crs = 2927)
  dbDisconnect(con)
  #poolReturn(con)
  # Only do the rest if nrows > 0
  if (nrow(fish_coordinates) > 0 ) {
    fish_coordinates = fish_coordinates %>%
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
      select(fish_location_id = location_id, location_coordinates_id,
             latitude, longitude, horiz_accuracy, created_date,
             created_dt, created_by, modified_date, modified_dt,
             modified_by) %>%
      arrange(created_date)
  }
  return(fish_coordinates)
}

# Test
strt = Sys.time()
fish_coords = get_fish_coordinates(fish_location_id)
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












