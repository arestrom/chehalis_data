
# Main reach_point query
get_reach_point = function(waterbody_id) {
  # First check if any geometry exists
  qry_one = glue("select loc.location_id, ",
                 "lc.location_coordinates_id, ",
                 "loc.river_mile_measure as river_mile, ",
                 "loc.location_code as reach_point_code, ",
                 "loc.location_name as reach_point_name, ",
                 "lt.location_type_description as reach_point_type, ",
                 "loc.location_description as reach_point_description, ",
                 "datetime(loc.created_datetime, 'localtime') as created_date, loc.created_by, ",
                 "datetime(loc.modified_datetime, 'localtime') as modified_date, loc.modified_by ",
                 "from location as loc ",
                 "left join location_type_lut as lt on loc.location_type_id = lt.location_type_id ",
                 "left join location_coordinates as lc on loc.location_id = lc.location_id ",
                 "where loc.waterbody_id = '{waterbody_id}' ",
                 "and lt.location_type_description in ('Reach boundary point', 'Section break point')")
  con = poolCheckout(pool)
  reach_points_one = DBI::dbGetQuery(con, qry_one)
  poolReturn(con)
  # Pull out any lc_ids
  lc_id = reach_points_one %>%
    filter(!is.na(location_coordinates_id)) %>%
    pull(location_coordinates_id)
  # Only get coordinates if they exist....avoids sfc error
  if ( length(lc_id) > 0 ) {
    location_coordinates_id = paste0(paste0("'", lc_id, "'"), collapse = ", ")
    qry_two = glue("select loc.location_id, ",
                   "lc.location_coordinates_id, ",
                   "loc.river_mile_measure as river_mile, ",
                   "loc.location_code as reach_point_code, ",
                   "loc.location_name as reach_point_name, ",
                   "lt.location_type_description as reach_point_type, ",
                   "lc.geom as geometry, ",
                   "lc.horizontal_accuracy as horiz_accuracy, ",
                   "loc.location_description as reach_point_description, ",
                   "datetime(loc.created_datetime, 'localtime') as created_date, loc.created_by, ",
                   "datetime(loc.modified_datetime, 'localtime') as modified_date, loc.modified_by ",
                   "from location as loc ",
                   "left join location_type_lut as lt on loc.location_type_id = lt.location_type_id ",
                   "left join location_coordinates as lc on loc.location_id = lc.location_id ",
                   "where loc.waterbody_id = '{waterbody_id}' ",
                   "and lt.location_type_description in ('Reach boundary point', 'Section break point') ",
                   "and lc.location_coordinates_id in ({location_coordinates_id})")
    con = poolCheckout(pool)
    reach_points_two = sf::st_read(con, query = qry_two, crs = 2927)
    poolReturn(con)
    # st_coordinates does not work with missing coordinates, so parse out separately
    reach_point_coords = reach_points_two %>%
      st_transform(., 4326) %>%
      mutate(longitude = as.numeric(st_coordinates(geometry)[,1])) %>%
      mutate(latitude = as.numeric(st_coordinates(geometry)[,2])) %>%
      mutate(latitude = round(latitude, 7)) %>%
      mutate(longitude = round(longitude, 7)) %>%
      st_drop_geometry()
  }
  # Pull out no_coords data
  reach_point_no_coords = reach_points_one %>%
    filter(is.na(location_coordinates_id)) %>%
    mutate(longitude = NA_real_) %>%
    mutate(latitude = NA_real_) %>%
    mutate(horiz_accuracy = NA_real_)
  # Combine
  if ( length(lc_id) > 0 ) {
    reach_points = bind_rows(reach_point_no_coords, reach_point_coords)
  } else {
    reach_points = reach_point_no_coords
  }
  reach_points = reach_points %>%
    mutate(river_mile = round(river_mile, 2)) %>%
    mutate(created_date = as.POSIXct(created_date, tz = "America/Los_Angeles")) %>%
    mutate(created_dt = format(created_date, "%m/%d/%Y %H:%M")) %>%
    mutate(modified_date = as.POSIXct(modified_date, tz = "America/Los_Angeles")) %>%
    mutate(modified_dt = format(modified_date, "%m/%d/%Y %H:%M")) %>%
    select(location_id, location_coordinates_id, reach_point_code,
           river_mile, reach_point_name, reach_point_type,
           latitude, longitude, horiz_accuracy, reach_point_description,
           created_date, created_dt, created_by, modified_date, modified_dt,
           modified_by) %>%
    arrange(river_mile)
  return(reach_points)
}

#==========================================================================
# Get generic lut input values
#==========================================================================

# Location type....Some bios distinguish section breaks from reach end points
get_location_type = function() {
  qry = glue("select location_type_id, location_type_description as reach_point_type ",
             "from location_type_lut ",
             "where obsolete_datetime is null ",
             "and location_type_description in ('Reach boundary point', 'Section break point')")
  con = poolCheckout(pool)
  reach_point_type_list = DBI::dbGetQuery(con, qry) %>%
    arrange(reach_point_type) %>%
    select(location_type_id, reach_point_type)
  poolReturn(con)
  return(reach_point_type_list)
}

#========================================================
# Insert callback
#========================================================

# Define the insert callback
reach_point_insert = function(new_reach_point_values) {
  new_insert_values = new_reach_point_values
  # Generate location_id
  location_id = remisc::get_uuid(1L)
  created_by = new_insert_values$created_by
  # Pull out location_coordinates table data
  horizontal_accuracy = as.numeric(new_insert_values$horiz_accuracy)
  latitude = new_insert_values$latitude
  longitude = new_insert_values$longitude
  # Pull out location table data
  waterbody_id = new_insert_values$waterbody_id
  wria_id = new_insert_values$wria_id
  location_type_id = new_insert_values$location_type_id
  stream_channel_type_id = new_insert_values$stream_channel_type_id
  location_orientation_type_id = new_insert_values$location_orientation_type_id
  river_mile_measure = new_insert_values$river_mile
  location_code = new_insert_values$reach_point_code
  location_name = new_insert_values$reach_point_name
  location_description = new_insert_values$reach_point_description
  if (is.na(location_code) | location_code == "") { location_code = NA }
  if (is.na(location_name) | location_name == "") { location_name = NA }
  if (is.na(location_description) | location_description == "") { location_description = NA }
  # Insert to location table
  con = poolCheckout(pool)
  DBI::dbWithTransaction(con, {
    insert_rp_result = dbSendStatement(
      con, glue_sql("INSERT INTO location (",
                    "location_id, ",
                    "waterbody_id, ",
                    "wria_id, ",
                    "location_type_id, ",
                    "stream_channel_type_id, ",
                    "location_orientation_type_id, ",
                    "river_mile_measure, ",
                    "location_code, ",
                    "location_name, ",
                    "location_description, ",
                    "created_by) ",
                    "VALUES (",
                    "?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"))
    dbBind(insert_rp_result, list(location_id, waterbody_id, wria_id,
                                  location_type_id, stream_channel_type_id,
                                  location_orientation_type_id, river_mile_measure,
                                  location_code, location_name,
                                  location_description, created_by))
    dbGetRowsAffected(insert_rp_result)
    dbClearResult(insert_rp_result)
    # Insert coordinates to location_coordinates
    if (!is.na(latitude) & !is.na(longitude) ) {
      # Create location_coordinates_id
      location_coordinates_id = remisc::get_uuid(1L)
      # Create a point in hex binary
      geom = st_point(c(longitude, latitude)) %>%
        st_sfc(., crs = 4326) %>%
        st_transform(., 2927) %>%
        st_as_binary(., hex = TRUE)
      insert_lc_result = dbSendStatement(
        con, glue_sql("INSERT INTO location_coordinates (",
                      "location_coordinates_id, ",
                      "location_id, ",
                      "horizontal_accuracy, ",
                      "geom, ",
                      "created_by) ",
                      "VALUES (",
                      "?, ?, ?, ?, ?)"))
      dbBind(insert_lc_result, list(location_coordinates_id, location_id,
                                    horizontal_accuracy, geom, created_by))
      dbGetRowsAffected(insert_lc_result)
      dbClearResult(insert_lc_result)
    }
  })
  poolReturn(con)
}

#==============================================================
# Identify reach_point surveys prior to update or delete
#==============================================================

# Identify reach_point dependencies prior to delete
get_reach_point_surveys = function(location_id) {
  qry = glue("select datetime(s.survey_datetime, 'localtime') as survey_date, ",
             "locu.river_mile_measure as upper_river_mile, ",
             "locl.river_mile_measure as lower_river_mile, ",
             "s.observer_last_name as observer ",
             "from survey as s ",
             "left join location as locu on s.upper_end_point_id = locu.location_id ",
             "left join location as locl on s.lower_end_point_id = locl.location_id ",
             "where locu.location_id = '{location_id}' or locl.location_id = '{location_id}'")
  con = poolCheckout(pool)
  reach_point_surveys = DBI::dbGetQuery(con, qry)
  poolReturn(con)
  reach_point_surveys = reach_point_surveys %>%
    mutate(survey_date = as.POSIXct(survey_date, tz = "America/Los_Angeles")) %>%
    mutate(survey_dt = format(survey_date, "%m/%d/%Y"))
  return(reach_point_surveys)
}

#========================================================
# Edit reach_point callback
#========================================================

# Define update callback
reach_point_update = function(reach_point_edit_values, selected_reach_point_data) {
  edit_values = reach_point_edit_values
  # Pull out data for location table
  location_id = edit_values$location_id
  location_type_id = edit_values$location_type_id
  river_mile_measure = edit_values$river_mile
  location_code= edit_values$reach_point_code
  location_name = edit_values$reach_point_name
  location_description = edit_values$reach_point_description
  if (is.na(location_code) | location_code == "") { location_code = NA }
  if (is.na(location_name) | location_name == "") { location_name = NA }
  if (is.na(location_description) | location_description == "") { location_description = NA }
  mod_dt = format(lubridate::with_tz(Sys.time(), "UTC"))
  mod_by = Sys.getenv("USERNAME")
  created_by = Sys.getenv("USERNAME")
  # Pull out data for location_coordinates table
  horizontal_accuracy = edit_values$horiz_accuracy
  latitude = edit_values$latitude
  longitude = edit_values$longitude
  # Checkout a connection
  con = poolCheckout(pool)
  DBI::dbWithTransaction(con, {
    update_result = dbSendStatement(
      con, glue_sql("UPDATE location SET ",
                    "location_type_id = ?, ",
                    "river_mile_measure = ?, ",
                    "location_code = ?, ",
                    "location_name = ?, ",
                    "location_description = ?, ",
                    "modified_datetime = ?, ",
                    "modified_by = ? ",
                    "where location_id = ?"))
    dbBind(update_result, list(location_type_id, river_mile_measure,
                               location_code, location_name,
                               location_description,
                               mod_dt, mod_by,
                               location_id))
    dbGetRowsAffected(update_result)
    dbClearResult(update_result)
    # Insert coordinates to location_coordinates if previous entry does not exist
    if ( is.na(selected_reach_point_data$latitude) & is.na(selected_reach_point_data$longitude) ) {
      if ( !is.na(latitude) & !is.na(longitude) ) {
        # Insert coordinates to location_coordinates
        # Create location_coordinates_id
        location_coordinates_id = remisc::get_uuid(1L)
        # Create a point in hex binary
        geom = st_point(c(longitude, latitude)) %>%
          st_sfc(., crs = 4326) %>%
          st_transform(., 2927) %>%
          st_as_binary(., hex = TRUE)
        insert_lc_result = dbSendStatement(
          con, glue_sql("INSERT INTO location_coordinates (",
                        "location_coordinates_id, ",
                        "location_id, ",
                        "horizontal_accuracy, ",
                        "geom, ",
                        "created_by) ",
                        "VALUES (",
                        "?, ?, ?, ?, ?)"))
        dbBind(insert_lc_result, list(location_coordinates_id, location_id,
                                      horizontal_accuracy, geom, created_by))
        dbGetRowsAffected(insert_lc_result)
        dbClearResult(insert_lc_result)
      }
      # Otherwise update coordinates if previous entry does exist
    } else if (!is.na(selected_reach_point_data$latitude) & !is.na(selected_reach_point_data$longitude) ) {
      if ( !is.na(latitude) & !is.na(longitude) ) {
        # Create a point in hex binary
        geom = st_point(c(longitude, latitude)) %>%
          st_sfc(., crs = 4326) %>%
          st_transform(., 2927) %>%
          st_as_binary(., hex = TRUE)
        update_lc_result = dbSendStatement(
          con, glue_sql("UPDATE location_coordinates SET ",
                        "horizontal_accuracy = ?, ",
                        "geom = ?, ",
                        "modified_datetime = ?, ",
                        "modified_by = ? ",
                        "where location_id = ?"))
        dbBind(update_lc_result, list(horizontal_accuracy, geom,
                                      mod_dt, mod_by, location_id))
        dbGetRowsAffected(update_lc_result)
        dbClearResult(update_lc_result)
      }
    }
  })
  poolReturn(con)
}

#========================================================
# Identify reach_point dependencies prior to delete
#========================================================

# Identify fish_encounter dependencies prior to delete
get_reach_point_dependencies = function(location_id) {
  qry = glue("select ",
             "count(fp.fish_passage_feature_id) as fish_passage_feature, ",
             "count(fce.fish_capture_event_id) as fish_capture_event, ",
             "count(fe.fish_encounter_id) as fish_encounter, ",
             "count(ml.media_location_id) as media_location, ",
             "count(oo.other_observation_id) as other_observation, ",
             "count(rd.redd_encounter_id) as redd_encounter, ",
             "count(s.survey_id) as survey ",
             "from location as loc ",
             "left join fish_passage_feature as fp on loc.location_id = fp.feature_location_id ",
             "left join fish_capture_event as fce on loc.location_id = fce.disposition_location_id ",
             "left join fish_encounter as fe on loc.location_id = fe.fish_location_id ",
             "left join media_location as ml on loc.location_id = ml.location_id ",
             "left join other_observation as oo on loc.location_id = oo.observation_location_id ",
             "left join redd_encounter as rd on loc.location_id = rd.redd_location_id ",
             "left join survey as s on (loc.location_id = s.upper_end_point_id or ",
             "loc.location_id = s.lower_end_point_id) ",
             "where loc.location_id = '{location_id}'")
  con = poolCheckout(pool)
  reach_point_dependents = DBI::dbGetQuery(con, qry)
  poolReturn(con)
  has_entries = function(x) any(x > 0L)
  reach_point_dependents = reach_point_dependents %>%
    select_if(has_entries)
  return(reach_point_dependents)
}

#========================================================
# Delete callback
#========================================================

# Define delete callback
reach_point_delete = function(delete_values) {
  location_id = delete_values$location_id
  # Checkout a connection
  con = poolCheckout(pool)
  DBI::dbWithTransaction(con, {
    delete_result_one = dbSendStatement(
      con, glue_sql("DELETE FROM location_coordinates WHERE location_id = ?"))
    dbBind(delete_result_one, list(location_id))
    dbGetRowsAffected(delete_result_one)
    dbClearResult(delete_result_one)
    delete_result_two = dbSendStatement(
      con, glue_sql("DELETE FROM location WHERE location_id = ?"))
    dbBind(delete_result_two, list(location_id))
    dbGetRowsAffected(delete_result_two)
    dbClearResult(delete_result_two)
  })
  poolReturn(con)
}
