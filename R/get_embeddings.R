#' Get pretrained GPT-3 text embeddings
#'
#' @description
#' Get pretrained text embeddings from the OpenAI API. Automatically batches requests to handle rate limits.
#'
#'
#' @param text A character vector
#' @param model Which variant of the GPT-3 embedding model to use. Defaults to 'text-embedding-3-large'.
#' @param dimensions The dimension of the embedding vectors to return. Defaults to 256.
#' @param openai_api_key Your OpenAI API key. By default, looks for a system environment variable called "OPENAI_API_KEY" (recommended option). Otherwise, it will prompt you to enter the API key as an argument.
#' @param parallel TRUE to submit API requests in parallel. Setting to FALSE can reduce rate limit errors at the expense of longer runtime.
#'
#' @return A matrix of embedding vectors (one per row).
#' @export
#'
#' @examples
#' embeddings <- get_embeddings(c('dog', 'cat', 'canine', 'feline'))
#' embeddings['dog',] |> dot(embeddings['canine',])
#' embeddings['dog',] |> dot(embeddings['feline',])
get_embeddings <- function(text,
                           model = 'text-embedding-3-large',
                           dimensions = 256,
                           openai_api_key = Sys.getenv("OPENAI_API_KEY"),
                           parallel = FALSE){

  if(openai_api_key == ''){
    stop("No API key detected in system environment. You can enter it manually using the 'openai_api_key' argument.")
  }

  # split the embeddings into chunks, because the OpenAI
  # embeddings endpoint will only take so many tokens at a time

  # max characters per chunk is approximately max tokens times 4
  max_characters <- 7000 * 4 # 8192 is max tokens, so include a little buffer
  # Calculate cumulative sum of character lengths
  cumulative_length <- cumsum(nchar(text))
  # Find the indices where to split
  split_indices <- cumulative_length %/% max_characters
  # Split the vector based on the calculated indices
  chunks <- split(text, split_indices)

  # format an API request
  format_request <- function(chunk,
                             base_url = "https://api.openai.com/v1/embeddings"){

    httr2::request(base_url) |>
      # headers
      httr2::req_headers('Authorization' = paste("Bearer", openai_api_key)) |>
      httr2::req_headers("Content-Type" = "application/json") |>
      # body
      httr2::req_body_json(list(model = model,
                                input = chunk,
                                dimensions = dimensions))
  }

  reqs <- lapply(chunks, format_request)

  # submit prompts in parallel (20 concurrent requests per host seems to be the optimum)
  if(parallel){
    resps <- httr2::req_perform_parallel(reqs, pool = curl::new_pool(host_con = 20))
  } else{
    resps <- httr2::req_perform_sequential(reqs)
  }


  # parse the responses
  parsed <- resps |>
    lapply(httr2::resp_body_string) |>
    lapply(jsonlite::fromJSON, flatten=TRUE)

  # get the embeddings
  embeddings <- sapply(parsed, function(x) x$data$embedding)

  # bind into a matrix
  if(length(chunks) > 1) embeddings <- lapply(embeddings, function(x) do.call(rbind, x))
  embeddings <- do.call(rbind, embeddings)
  rownames(embeddings) <- text

  return(embeddings)

}
