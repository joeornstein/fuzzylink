estimate_tokens <- function(text) {
  # Split the text by spaces, punctuation, and new lines
  tokens <- strsplit(text, "\\s|\\.|,|;|:|!|\\?|\\n")

  # Flatten the list of tokens into a vector
  # tokens <- unlist(tokens)

  # Uncomment to remove empty tokens
  # tokens <- tokens[nchar(tokens) > 0]

  # Return the number of tokens in each element
  return(sapply(tokens, length))
}

