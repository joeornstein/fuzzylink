#' Test whether two strings match with a zero-shot LLM prompt.
#'
#' @param name1 A string
#' @param name2 A string
#'
#' @return "Yes" if the two strings match, "No" otherwise.
#' @export
#'
#' @examples
#' check_match('UPS', 'United Parcel Service')
#' check_match('UPS', 'United States Postal Service')
#' check_match('USPS', 'United Parcel Service')
#' check_match('USPS', 'United States Postal Service')
#' check_match('USPS', 'Post Office')
check_match <- function(name1, name2){

  # format GPT prompt
  p <- list()
  p[[1]] <- list(role = 'user',
                 content = 'Decide whether the two names below probably refer to the same entity (nicknames, typos, acronyms, and abbreviations are acceptable matches). Respond "Yes" or "No".')
  p[[2]] <- list(role = 'user', content = paste0('\"', name1, '\" and \"', name2, '\"'))

  # submit to OpenAI API
  resp <- openai::create_chat_completion(model = 'gpt-3.5-turbo',
                                         messages = p,
                                         temperature = 0,
                                         max_tokens = 1)

  return(resp$choices$message.content)

}
