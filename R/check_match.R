#' Test whether two strings match with an LLM prompt.
#'
#' @param string1 A string or vector of strings
#' @param string2 A string or vector of strings
#' @param batch_size The number of string pairs to include in each prompt
#' @param model Which OpenAI model to prompt; defaults to 'gpt-3.5-turbo-instruct'
#' @param few_shot_examples A dataframe with few-shot examples for prompt; must include columns `A`, `B`, and `match`
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
                        batch_size = 50,
                        model = 'gpt-3.5-turbo-instruct',
                        few_shot_examples = NULL,
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

  use_completions_endpoint <- TRUE

  if(use_completions_endpoint){

    # few_shot_preamble <- '"Timothy B. Ryan" and "Jimmy Pointer": No\n"Timoth B. Ryan" and "Tim Ryan": Yes\n"Michael V. Johnson" and "Michael E Johnson": No\n'
    # p <- paste0(few_shot_preamble, '\"', string1, '\" and \"', string2, '\":')

    # format the few-shot examples
    if(!is.null(few_shot_examples)){
      few_shot_preamble <- paste0(few_shot_examples$A, ' : ', few_shot_examples$B, ' = ', few_shot_examples$match, collapse = '\n')
      p <- paste0(few_shot_preamble, '\n', string1, ' : ', string2, ' =')
    } else{
      p <- paste0('Decide if the following two names refer to the same ', stringr::str_to_lower(record_type),
                  '.\n\nName A: ', string1,
                  '\nName B: ', string2,
                  '\nSame ', stringr::str_to_title(record_type), ' (Yes or No):')
    }

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

  }

  # legacy code: zero-shot with chat models
  if(!use_completions_endpoint){
    # create an empty vector of labels
    labels <- character(length = length(string1))

    # submit prompts in batches
    if(batch_size == 1){
      # if batch_size = 1, we'll submit each prompt one at a time, using a modified (more accurate) prompt
      for(i in 1:length(string1)){
        # format GPT prompt
        p <- list()
        p[[1]] <- list(role = 'user',
                       content = 'For each pair of names below, decide whether they probably refer to the same entity. Nicknames, acronyms, abbreviations, and misspellings are all acceptable matches. Respond with "Yes" or "No".')

        # format content as a numbered list of string pairs
        p[[2]] <- list(role = 'user',
                       content = paste0(
                         '\"', string1[i],
                         '\" and \"', string2[i], '\"'))

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
