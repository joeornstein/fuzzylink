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
                           openai_api_key = Sys.getenv("OPENAI_API_KEY")){

  if(openai_api_key == ''){
    stop("No API key detected in system environment. You can enter it manually using the 'openai_api_key' argument.")
  }

  # split the embeddings into chunks, because the OpenAI
  # embeddings endpoint will only take so many tokens at a time

  # max characters per chunk is approximately max tokens times 4
  max_characters <- 8000 * 4 # 8192 is max tokens, so a little buffer
  # Calculate cumulative sum of character lengths
  cumulative_length <- cumsum(nchar(text))
  # Find the indices where to split
  split_indices <- cumulative_length %/% max_characters
  # Split the vector based on the calculated indices
  chunks <- split(text, split_indices)

  # format a list of API requests
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
  resps <- httr2::req_perform_parallel(reqs, pool = curl::new_pool(host_con = 20))

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

#
#
#
#   # initialize empty list
#   embeddings <- vector(mode='list', length=length(text))
#   names(embeddings) <- text
#
#   # get the embeddings in chunks, because the OpenAI API
#   # will only take so many tokens at a time
#   chunk_size <- 1000
#   index <- 1
#
#   repeat{
#
#     # if index is greater than the length of list, break the loop
#     if(index > length(text)) break
#
#     # create the chunk
#     end <- min(index + chunk_size - 1, length(text))
#     chunk <- text[index:end]
#
#     # get the embeddings for that chunk
#     # emb <- openai::create_embedding(model = model,
#     #                                 input = chunk)
#     base_url <- "https://api.openai.com/v1/embeddings"
#     headers <- c(Authorization = paste("Bearer", openai_api_key),
#                  `Content-Type` = "application/json")
#     body <- list()
#     body[["model"]] <- model
#     body[["input"]] <- chunk
#     body[["dimensions"]] <- dimensions
#
#     repeat{
#       # make API request
#       response <- httr::POST(url = base_url, httr::add_headers(.headers = headers),
#                              body = body, encode = "json")
#
#       # parse the response and append it to the embeddings list
#       emb <- response |>
#         httr::content(as = "text", encoding = "UTF-8") |>
#         jsonlite::fromJSON(flatten = TRUE)
#
#       # if you've hit a rate limit, wait and resubmit
#       if(response$status_code == 429){
#
#         time_to_wait <- gsub('.*Please try again in\\s(.+)\\.\\sVisit.*', '\\1', emb$error$message)
#         cat(paste0('Exceeded Rate Limit. Waiting ', time_to_wait, '.\n\n'))
#
#         time_val <- as.numeric(gsub('[^0-9.]+', '', time_to_wait))
#         time_unit <- gsub('[^A-z]+', '', time_to_wait)
#
#         time_to_wait <- ceiling(time_val / ifelse(time_unit == 'ms', 1000, 1))
#
#         Sys.sleep(time_to_wait)
#
#       } else{
#         break
#       }
#     }
#
#     embeddings[index:end] <- emb$data$embedding
#
#     # increment the index
#     index <- index + chunk_size
#
#   }
#
#   # bind into a matrix
#   embeddings <- do.call(rbind, embeddings)
#
#   return(embeddings)

}
