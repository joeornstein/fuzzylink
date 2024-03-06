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

  # initialize empty list
  embeddings <- vector(mode='list', length=length(text))
  names(embeddings) <- text

  # get the embeddings in chunks, because the OpenAI API
  # will only take so many tokens at a time
  chunk_size <- 1000
  index <- 1

  repeat{

    # if index is greater than the length of list, break the loop
    if(index > length(text)) break

    # create the chunk
    end <- min(index + chunk_size - 1, length(text))
    chunk <- text[index:end]

    # get the embeddings for that chunk
    # emb <- openai::create_embedding(model = model,
    #                                 input = chunk)
    base_url <- "https://api.openai.com/v1/embeddings"
    headers <- c(Authorization = paste("Bearer", openai_api_key),
                 `Content-Type` = "application/json")
    body <- list()
    body[["model"]] <- model
    body[["input"]] <- chunk
    body[["dimensions"]] <- dimensions

    repeat{
      # make API request
      response <- httr::POST(url = base_url, httr::add_headers(.headers = headers),
                             body = body, encode = "json")

      # parse the response and append it to the embeddings list
      emb <- response |>
        httr::content(as = "text", encoding = "UTF-8") |>
        jsonlite::fromJSON(flatten = TRUE)

      # if you've hit a rate limit, wait and resubmit
      if(response$status_code == 429){

        time_to_wait <- gsub('.*Please try again in\\s(.+)\\.\\sVisit.*', '\\1', emb$error$message)
        cat(paste0('Exceeded Rate Limit. Waiting ', time_to_wait, '.\n\n'))

        time_val <- as.numeric(gsub('[^0-9.]+', '', time_to_wait))
        time_unit <- gsub('[^A-z]+', '', time_to_wait)

        time_to_wait <- ceiling(time_val / ifelse(time_unit == 'ms', 1000, 1))

        Sys.sleep(time_to_wait)

      } else{
        break
      }
    }

    embeddings[index:end] <- emb$data$embedding

    # increment the index
    index <- index + chunk_size

  }

  # bind into a matrix
  embeddings <- do.call(rbind, embeddings)

  return(embeddings)

}
