#' Test whether two strings match with an LLM prompt.
#'
#' @param string1 A string or vector of strings
#' @param string2 A string or vector of strings
#' @param model Which OpenAI model to prompt; defaults to 'gpt-3.5-turbo-instruct'
#' @param record_type A character describing what type of entity `string1` and `string2` represent. Should be a singular noun (e.g. "person", "organization", "interest group", "city").
#' @param openai_api_key Your OpenAI API key. By default, looks for a system environment variable called "OPENAI_API_KEY" (recommended option). Otherwise, it will prompt you to enter the API key as an argument.
#'
#' @return A vector the same length as `string1` and `string2`. "Yes" if the pair of strings match, "No" otherwise.
#' @export
#'
#' @examples
#' check_match('UPS', 'United Parcel Service')
#' check_match('UPS', 'United States Postal Service')
#' check_match(c('USPS', 'USPS', 'USPS'),
#'             c('Post Office', 'United Parcel', 'US Postal Service'))
check_match <- function(string1, string2,
                        model = 'gpt-3.5-turbo-instruct',
                        record_type = 'entity',
                        openai_api_key = Sys.getenv('OPENAI_API_KEY')){

  if(length(string1) != length(string2)){
    stop('Inputs must have the same number of elements.')
  }

  if(openai_api_key == ''){
    stop("No API key detected in system environment. You can enter it manually using the 'openai_api_key' argument.")
  }

  # encode strings as characters
  string1 <- as.character(string1)
  string2 <- as.character(string2)

  # use the Completions endpoint if the model is a "Legacy" model
  if(model %in% c('gpt-3.5-turbo-instruct', 'davinci-002', 'babbage-002')){

    # format the prompt
    p <- paste0('Decide if the following two names refer to the same ', record_type,
                '. Misspellings, alternative names, and acronyms may be acceptale matches. Think carefully. Respond \"Yes\" or \"No\".\n\n',
                'Name A: ', string1, '\nName B: ', string2,
                '\n\nResponse:')

    # empty vector of labels
    labels <- character(length = length(string1))

    # labels="Yes" wherever the two strings match exactly
    labels[string1==string2] <- 'Yes'

    # don't submit prompts for exact string matches
    p <- p[string1 != string2]

    # build path parameters
    base_url <- "https://api.openai.com/v1/completions"

    headers <- c(
      "Authorization" = paste("Bearer", openai_api_key),
      "Content-Type" = "application/json"
    )

    # batch prompts to handle API rate limits
    max_prompts <- 2048
    start_index <- 1

    while(start_index <= length(p)){

      end_index <- min(length(p), start_index + max_prompts - 1)

      # build request body
      body <- list()
      body[['model']] <- model
      body[['prompt']] <- p[start_index:end_index]
      body[['max_tokens']] <- 1
      body[['temperature']] <- 0

      repeat{
        # make API request
        response <- httr::POST(
          url = base_url,
          httr::add_headers(.headers = headers),
          body = body,
          encode = "json"
        )

        # parse the response
        parsed <- response |>
          httr::content(as = "text", encoding = "UTF-8") |>
          jsonlite::fromJSON(flatten = TRUE)

        # if you've hit a rate limit, wait and resubmit
        if(response$status_code == 429){

          time_to_wait <- gsub('.*Please try again in\\s(.+)\\.\\sVisit.*', '\\1', parsed$error$message)
          cat(paste0('Exceeded Rate Limit. Waiting ', time_to_wait, '.\n\n'))

          time_val <- as.numeric(gsub('[^0-9.]+', '', time_to_wait))
          time_unit <- gsub('[^A-z]+', '', time_to_wait)

          time_to_wait <- ceiling(time_val / ifelse(time_unit == 'ms', 1000, 1))

          Sys.sleep(time_to_wait)

        } else{
          break
        }
      }

      # update labels vector (non-exact matches)
      labels[string1!=string2][start_index:end_index] <- gsub(' |\n', '', parsed$choices$text) |>
        stringr::str_to_title()

      start_index <- end_index + 1

    }

  } else{ # if model is not one of the "Legacy" text models, use Chat Endpoint

    # function to return a chat prompt formatted as a list of lists
    format_chat_prompt <- function(i){
      p <- list()
      p[[1]] <- list(role = 'user',
                     content = paste0('Decide if the following two names refer to the same ',
                                      record_type, '. Misspellings, alternative names, and acronyms may be acceptable matches. Think carefully. Respond "Yes" or "No".'))
      p[[2]] <- list(role = 'user',
                     content = paste0('Name A: ', string1[i], '\nName B: ', string2[i]))

      return(p)
    }

    # function to return a formatted API request
    format_request <- function(base_url = "https://api.openai.com/v1/chat/completions",
                               prompt){

      httr2::request(base_url) |>
        # headers
        httr2::req_headers('Authorization' = paste("Bearer", openai_api_key)) |>
        httr2::req_headers("Content-Type" = "application/json") |>
        # body
        httr2::req_body_json(list(model = model,
                                  messages = prompt,
                                  temperature = 0,
                                  max_tokens = 1))
    }


    # format prompts
    prompt_list <- lapply(1:length(string1), format_chat_prompt)

    # format a list of requests
    reqs <- Map(f = format_request, prompt = prompt_list)

    # submit prompts in parallel (20 concurrent requests per host seems to be the optimum)
    resps <- httr2::req_perform_parallel(reqs,
                                         pool = curl::new_pool(host_con = 20))

    # parse the responses
    parsed <- resps |>
      lapply(httr2::resp_body_string) |>
      lapply(jsonlite::fromJSON, flatten=TRUE)

    # get the labels
    labels <- sapply(parsed, function(x) x$choices$message.content)
  }
  return(labels)
}



#   Keep old code as comment while we experiment with httr2
#   batch_size <- 1
#   if(batch_size == 1){
#     # if batch_size = 1, we'll submit each prompt one at a time, using a modified (more accurate) prompt
#     for(i in 1:length(string1)){
#       # format GPT prompt
#       p <- list()
#       p[[1]] <- list(role = 'user',
#                      content = paste0('Decide if the following two names refer to the same ',
#                                       record_type, '. Think carefully. Respond "Yes" or "No".'))
#
#       # format content
#       p[[2]] <- list(role = 'user',
#                      content = paste0('Name A: ', string1[i], '\nName B: ', string2[i]))
#
#
#       # submit to OpenAI API
#       body <- list()
#       body[['model']] <- model
#       body[['messages']] <- p
#       body[['temperature']] <- 0
#       body[['max_tokens']] <- 1
#
#       repeat{
#         # make a request
#         response <- httr::POST(
#           url = base_url,
#           httr::add_headers(.headers = headers),
#           body = body,
#           encode = "json"
#         )
#
#         # parse the response
#         parsed <- response |>
#           httr::content(as = "text", encoding = "UTF-8") |>
#           jsonlite::fromJSON(flatten = TRUE)
#
#         # if you've hit a rate limit, wait and resubmit
#         if(response$status_code == 429){
#
#           time_to_wait <- gsub('.*Please try again in\\s(.+)\\.\\sVisit.*', '\\1', parsed$error$message)
#           cat(paste0('Exceeded Rate Limit. Waiting ', time_to_wait, '.\n\n'))
#
#           time_val <- as.numeric(gsub('[^0-9.]+', '', time_to_wait))
#           time_unit <- gsub('[^A-z]+', '', time_to_wait)
#
#           time_to_wait <- ceiling(time_val / ifelse(time_unit == 'ms', 1000, 1))
#
#           Sys.sleep(time_to_wait)
#
#         } else{
#           break
#         }
#       }
#
#
#
#
#       # resp <- openai::create_chat_completion(model = model,
#       #                                        messages = p,
#       #                                        temperature = 0,
#       #                                        openai_api_key = openai_api_key)
#
#       # add to labels vector
#       labels[i] <- parsed$choices$message.content
#
#     }
#
#   } else{
#     start_index <- 1
#     while(start_index <= length(string1)){
#       end_index <- min(c(start_index + batch_size - 1, length(string1)))
#       substring1 <- string1[start_index:end_index]
#       substring2 <- string2[start_index:end_index]
#
#       # format GPT prompt
#       p <- list()
#       p[[1]] <- list(role = 'user',
#                      content = 'I am trying to merge two datasets, but the names do not always match exactly. Below is a list of name pairs.')
#
#       # format content as a numbered list of string pairs
#       p[[2]] <- list(role = 'user',
#                      content = paste0(
#                        1:length(substring1), '. \"', substring1,
#                        '\" and \"', substring2, '\"',
#                        collapse = '\n'))
#
#       # provide instructions
#       p[[3]] <- list(role = 'user',
#                      content = 'For each pair of names, decide whether they probably refer to the same entity. Nicknames, acronyms, abbreviations, and misspellings are all acceptable matches. Respond only with a numbered list of "Yes" or "No".')
#
#       # submit to OpenAI API
#       body <- list()
#       body[['model']] <- model
#       body[['messages']] <- p
#       body[['temperature']] <- 0
#       body[['max_tokens']] <- 1
#
#       repeat{
#         # make a request
#         response <- httr::POST(
#           url = base_url,
#           httr::add_headers(.headers = headers),
#           body = body,
#           encode = "json"
#         )
#
#         # parse the response
#         parsed <- response |>
#           httr::content(as = "text", encoding = "UTF-8") |>
#           jsonlite::fromJSON(flatten = TRUE)
#
#         # if you've hit a rate limit, wait and resubmit
#         if(response$status_code == 429){
#
#           time_to_wait <- gsub('.*Please try again in\\s(.+)\\.\\sVisit.*', '\\1', parsed$error$message)
#           cat(paste0('Exceeded Rate Limit. Waiting ', time_to_wait, '.\n\n'))
#
#           time_val <- as.numeric(gsub('[^0-9.]+', '', time_to_wait))
#           time_unit <- gsub('[^A-z]+', '', time_to_wait)
#
#           time_to_wait <- ceiling(time_val / ifelse(time_unit == 'ms', 1000, 1))
#
#           Sys.sleep(time_to_wait)
#
#         } else{
#           break
#         }
#       }
#       # resp <- openai::create_chat_completion(model = model,
#       #                                        messages = p,
#       #                                        temperature = 0,
#       #                                        openai_api_key = openai_api_key)
#
#       # convert response into vector
#       response_vector <- gsub('[0-9]+. ', '',
#                               unlist(strsplit(parsed$choices$message.content, '\n')))
#
#       if(length(response_vector) != length(substring1)){
#         stop('Problem with the API response: labels not the same length as input. Try smaller batch size.')
#       }
#
#       labels[start_index:end_index] <- response_vector
#
#       # update start_index
#       start_index <- start_index + batch_size
#
#     }
#   }
#
