#' Test whether two strings match with an LLM prompt.
#'
#' @param string1 A string or vector of strings
#' @param string2 A string or vector of strings
#' @param model Which LLM to prompt; defaults to 'gpt-4o-2024-11-20'
#' @param record_type A character describing what type of entity `string1` and `string2` represent. Should be a singular noun (e.g. "person", "organization", "interest group", "city").
#' @param instructions A string containing additional instructions to include in the LLM prompt.
#' @param openai_api_key Your OpenAI API key. By default, looks for a system environment variable called "OPENAI_API_KEY" (recommended option). Otherwise, it will prompt you to enter the API key as an argument.
#' @param parallel TRUE to submit API requests in parallel. Setting to FALSE can reduce rate limit errors at the expense of longer runtime.
#'
#' @return A vector the same length as `string1` and `string2`. "Yes" if the pair of strings match, "No" otherwise.
#' @export
#'
#' @examples
#' \dontrun{
#' check_match('UPS', 'United Parcel Service')
#' check_match('UPS', 'United States Postal Service')
#' check_match(c('USPS', 'USPS', 'USPS'),
#'             c('Post Office', 'United Parcel', 'US Postal Service'))
#' }
check_match <- function(string1, string2,
                        model = 'gpt-4o-2024-11-20',
                        record_type = 'entity',
                        instructions = NULL,
                        openai_api_key = Sys.getenv('OPENAI_API_KEY'),
                        parallel = TRUE){

  if(length(string1) != length(string2)){
    stop('Inputs must have the same number of elements.')
  }

  if(openai_api_key == ''){
    stop("No API key detected in system environment. You can add one using the 'openai_api_key()' function.")
  }

  # if non-NULL, pad the instructions
  if(!is.null(instructions)){
    instructions <- paste0(instructions, ' ')
  }

  # encode strings as characters
  string1 <- as.character(string1)
  string2 <- as.character(string2)

  # use the Completions endpoint if the model is a "Legacy" model
  if(model %in% c('gpt-3.5-turbo-instruct', 'davinci-002', 'babbage-002')){

    # format the prompt
    p <- paste0('Decide if the following two names refer to the same ',
                record_type, '. ', instructions,
                'Think carefully. Respond \"Yes\" or \"No\".\n\n',
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
    max_prompts <- 1500 # 2048
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
          warning(paste0('Exceeded Rate Limit. Waiting ', time_to_wait, ' seconds.\n\n'))

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
                                      record_type, '. ', instructions,
                                      ## '. Misspellings, alternative names, and acronyms may be acceptable matches. ',
                                      'Think carefully. Respond "Yes" or "No".'))
      p[[2]] <- list(role = 'user',
                     content = paste0('Name A: ', string1[i], '\nName B: ', string2[i]))

      return(p)
    }

    # function to return a formatted API request
    format_request <- function(prompt,
                               base_url = "https://api.openai.com/v1/chat/completions",
                               api_key = openai_api_key){

      # if using a Mistral model, change base_url and api_key,
      # but everything else is the same!
      if(stringr::str_detect(model, 'mistral|mixtral')){
        base_url <- 'https://api.mistral.ai/v1/chat/completions'
        api_key <- Sys.getenv('MISTRAL_API_KEY')

        if(api_key == ''){
          stop("No API key detected in system environment. You can add one using the 'mistral_api_key()' function.")
        }
      }

      # o3 models do not accept logprobs or temperature headers
      if(model %in% c('o3-mini', 'o1', 'o1-mini')){
        httr2::request(base_url) |>
          # headers
          httr2::req_headers('Authorization' = paste("Bearer", api_key)) |>
          httr2::req_headers("Content-Type" = "application/json") |>
          # body
          httr2::req_body_json(list(model = model,
                                    messages = prompt))
      } else{
        httr2::request(base_url) |>
          # headers
          httr2::req_headers('Authorization' = paste("Bearer", api_key)) |>
          httr2::req_headers("Content-Type" = "application/json") |>
          # body
          httr2::req_body_json(list(model = model,
                                    messages = prompt,
                                    temperature = 0.0001,
                                    max_tokens = 1,
                                    logprobs = TRUE,
                                    top_logprobs = 20))
      }

    }

    # get the user's rate limits
    if(stringr::str_detect(model, 'mistral|mixtral')){
      tpm <- 2e6
      rpm <- 5*60
    } else{
      req <- format_request(format_chat_prompt(1))
      resp <- httr2::req_perform(req)
      # requests per minute
      rpm <- as.numeric(httr2::resp_header(resp, 'x-ratelimit-limit-requests'))
      # tokens per minute
      tpm <- as.numeric(httr2::resp_header(resp, 'x-ratelimit-limit-tokens'))
    }

    # format prompts
    prompt_list <- lapply(1:length(string1), format_chat_prompt)

    # format a list of requests
    reqs <- lapply(prompt_list, format_request)
    #Map(f = format_request, prompt = prompt_list)

    # 1. break up reqs into chunks of size tpm
    # 2. request each chunk in parallel, making sure it takes no shorter than 1 minute
    # 3. combine the response lists

    # submit prompts in parallel (20 concurrent requests per host seems to be the optimum)
    if(parallel & stringr::str_detect(model, 'mistral|mixtral', negate = TRUE)){
      resps <- httr2::req_perform_parallel(reqs, max_active = 20)
    } else{
      resps <- reqs |>
        lapply(httr2::req_throttle, rate = rpm / 60) |>
        httr2::req_perform_sequential()
    }

    # parse the responses
    parsed <- resps |>
      lapply(httr2::resp_body_string) |>
      lapply(jsonlite::fromJSON, flatten=TRUE)

    # get the labels associated with the highest returned log probability
    if(model %in% c('o3-mini', 'o1', 'o1-mini')){
      labels <- sapply(parsed, function(x) x$choices$message.content)
    } else{
      labels <- sapply(parsed, function(x) x$choices$logprobs.content[[1]]$top_logprobs[[1]][1,]$token)
    }

  }
  return(labels)
}
