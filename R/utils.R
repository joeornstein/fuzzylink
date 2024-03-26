## Some helper functions that get used in the functions that call the OpenAI API

# a function to convert wait times from the API response header into seconds
convert_to_seconds <- function(time_str) {
  # Split the string into separate parts
  parts <- stringr::str_split(time_str, "(?<=\\d)(?=[hms])", n = Inf, simplify = TRUE)

  # Initialize total seconds
  total_seconds <- 0

  # Loop through each part and add the corresponding number of seconds
  for (part in time_parts) {
    # Get the numeric part
    num <- as.numeric(sub("\\D", "", part))

    # Get the time unit
    unit <- sub("\\d", "", part)

    # Add the corresponding number of seconds
    if (unit == "h") {
      total_seconds <- total_seconds + num * 3600
    } else if (unit == "m") {
      total_seconds <- total_seconds + num * 60
    } else if (unit == "s") {
      total_seconds <- total_seconds + num
    } else if (unit == "ms") {
      total_seconds <- total_seconds + num / 1000
    }
  }

  return(total_seconds)
}

# function that returns how long to wait from the API response header
time_to_wait <- function(resp){

  # get string describing how long to wait from the headers
  rpm_wait <- httr2::resp_header(resp, 'x-ratelimit-reset-requests') # requests per minute
  tpm_wait <- httr2::resp_header(resp, 'x-ratelimit-reset-tokens') # tokens per minute

  # parse both strings into a number of seconds








}
