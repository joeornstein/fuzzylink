#' Test whether two strings match with an LLM prompt.
#'
#' @param string1 A string or vector of strings
#' @param string2 A string or vector of strings
#' @param batch_size The number of string pairs to include in each prompt
#' @param model Which OpenAI model to prompt; defaults to 'gpt-4-turbo-preview'
#'
#' @return A string or vector of strings the same length as `string1` and `string2`. "Yes" if the pair of strings match, "No" otherwise.
#' @export
#'
#' @examples
#' check_match('UPS', 'United Parcel Service')
#' check_match('UPS', 'United States Postal Service')
#' check_match(c('USPS', 'USPS', 'USPS'),
#'             c('Post Office', 'United Parcel', 'US Postal Service'))
check_match <- function(string1, string2,
                        batch_size = 50,
                        model = 'gpt-4-turbo-preview'){

  if(length(string1) != length(string2)){
    stop('Inputs must have the same number of elements.')
  }

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
                                             temperature = 0)

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
                     content = 'For each pair of names, decide whether they probably refer to the same entity. Nicknames, acronyms, abbreviations, and misspellings are all acceptable matches. Respond with "Yes" or "No".')

      # submit to OpenAI API
      resp <- openai::create_chat_completion(model = model,
                                             messages = p,
                                             temperature = 0)

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

  return(labels)

}
