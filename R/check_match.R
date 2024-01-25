#' Test whether two strings match with an LLM prompt.
#'
#' @param string1 A string or vector of strings
#' @param string2 A string or vector of strings
#'
#' @return A string or vector of strings the same length as `string1` and `string2`. "Yes" if the pair of strings match, "No" otherwise.
#' @export
#'
#' @examples
#' check_match('UPS', 'United Parcel Service')
#' check_match('UPS', 'United States Postal Service')
#' check_match(c('USPS', 'USPS'), c('Post Office', 'United Parcel'))
check_match <- function(string1, string2){

  ## TODO: submit in batches of 100

  if(length(string1) != length(string2)){
    stop('Inputs must have the same number of elements.')
  }

  # format GPT prompt
  p <- list()
  p[[1]] <- list(role = 'user',
                 content = 'I am trying to merge two datasets, but the names do not always match exactly. Below is a list of name pairs.')

  # format content as a numbered list of string pairs
  p[[2]] <- list(role = 'user',
                 content = paste0(
                   1:length(string1), '. \"', string1,
                   '\" and \"', string2, '\"',
                   collapse = '\n'))

  # provide instructions
  p[[3]] <- list(role = 'user',
                 content = 'For each pair of names, decide whether they probably refer to the same entity. Nicknames, acronyms, abbreviations, and misspellings are all acceptable matches. Respond with "Yes" or "No".')

  # submit to OpenAI API
  resp <- openai::create_chat_completion(model = 'gpt-3.5-turbo',
                                         messages = p,
                                         temperature = 0)

  # convert response into vector
  labels <- gsub('[0-9]+. ', '',
                 unlist(strsplit(resp$choices$message.content, '\n')))

  if(length(labels) != length(string1)){
    stop('Problem with the API response: labels not the same length as input. Try smaller batch size.')
  }

  return(labels)

}
