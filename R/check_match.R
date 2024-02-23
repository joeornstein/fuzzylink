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
                        openai_api_key = NULL){

  if(length(string1) != length(string2)){
    stop('Inputs must have the same number of elements.')
  }

  if(Sys.getenv('OPENAI_API_KEY') == '' & is.null(openai_api_key)){
    stop("No API key detected in system environment. You can enter it manually using the 'openai_api_key' argument.")
  }

  if(is.null(openai_api_key)){
    openai_api_key <- Sys.getenv("OPENAI_API_KEY")
  }

  # use the Completions endpoint if the model is a "Legacy" model
  if(model %in% c('gpt-3.5-turbo-instruct', 'davinci-002', 'babbage-002')){

    # few_shot_preamble <- '"Timothy B. Ryan" and "Jimmy Pointer": No\n"Timoth B. Ryan" and "Tim Ryan": Yes\n"Michael V. Johnson" and "Michael E Johnson": No\n'
    # p <- paste0(few_shot_preamble, '\"', string1, '\" and \"', string2, '\":')

    # format the prompt
    p <- paste0('Decide if the following two names refer to the same ', record_type,
                '. Respond \"Yes\" or \"No\".\n\nName A: ', string1,
                '\nName B: ', string2,
                '\nSame ', record_type, ':')

    # empty vector of labels
    labels <- character(length = length(string1))

    # batch prompts to handle API rate limits
    max_prompts <- 2048
    start_index <- 1

    while(start_index <= length(labels)){

      end_index <- min(length(labels), start_index + max_prompts - 1)

      resp <- openai::create_completion(model = model,
                                        prompt = p[start_index:end_index],
                                        max_tokens = 1,
                                        temperature = 0,
                                        openai_api_key = openai_api_key)

      labels[start_index:end_index] <- gsub(' |\n', '', resp$choices$text) |>
        stringr::str_to_title()

      start_index <- end_index + 1

    }

    # # if that loop returned any labels that weren't "Yes" or "No" (e.g. a carriage return),
    # # repeat the prompts with a higher max_token limit
    # missing_labels <- which(!(labels %in% c('Yes','No')))
    #
    # resp <- openai::create_completion(model = model,
    #                                   prompt = p[missing_labels],
    #                                   max_tokens = 4,
    #                                   temperature = 0,
    #                                   openai_api_key = openai_api_key)
    #
    #   labels[missing_labels] <- gsub(' |\n', '', resp$choices$text)

  } else{ # if model is not one of the "Legacy" text models, use Chat Endpoint

    # create an empty vector of labels
    labels <- character(length = length(string1))

    # submit prompts in batches
    batch_size <- 1
    if(batch_size == 1){
      # if batch_size = 1, we'll submit each prompt one at a time, using a modified (more accurate) prompt
      for(i in 1:length(string1)){
        # format GPT prompt
        p <- list()
        p[[1]] <- list(role = 'user',
                       content = paste0('Decide if the following two names refer to the same ',
                                        record_type, '. Respond "Yes" or "No".'))

        # format content string1, two carriage returns, then string2
        p[[2]] <- list(role = 'user',
                       content = paste0(string1[i], '\n\n', string2[i]))

        # submit to OpenAI API
        resp <- openai::create_chat_completion(model = model,
                                               messages = p,
                                               temperature = 0,
                                               openai_api_key = openai_api_key)

        # add to labels vector
        labels[i] <- resp$choices$message.content

      }

    } else{
      start_index <- 1
      while(start_index <= length(string1)){
        end_index <- min(c(start_index + batch_size - 1, length(string1)))
        substring1 <- string1[start_index:end_index]
        substring2 <- string2[start_index:end_index]

        # format GPT prompt
        p <- list()
        p[[1]] <- list(role = 'user',
                       content = 'I am trying to merge two datasets, but the names do not always match exactly. Below is a list of name pairs.')

        # format content as a numbered list of string pairs
        p[[2]] <- list(role = 'user',
                       content = paste0(
                         1:length(substring1), '. \"', substring1,
                         '\" and \"', substring2, '\"',
                         collapse = '\n'))

        # provide instructions
        p[[3]] <- list(role = 'user',
                       content = 'For each pair of names, decide whether they probably refer to the same entity. Nicknames, acronyms, abbreviations, and misspellings are all acceptable matches. Respond only with a numbered list of "Yes" or "No".')

        # submit to OpenAI API
        resp <- openai::create_chat_completion(model = model,
                                               messages = p,
                                               temperature = 0,
                                               openai_api_key = openai_api_key)

        # convert response into vector
        response_vector <- gsub('[0-9]+. ', '',
                                unlist(strsplit(resp$choices$message.content, '\n')))

        if(length(response_vector) != length(substring1)){
          stop('Problem with the API response: labels not the same length as input. Try smaller batch size.')
        }

        labels[start_index:end_index] <- response_vector

        # update start_index
        start_index <- start_index + batch_size

      }
    }

  }

  return(labels)

}
