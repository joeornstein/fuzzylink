#' Get pretrained GPT-3 text embeddings
#'
#' @description
#' Get pretrained text embeddings from the OpenAI API. Automatically batches requests to handle rate limits.
#'
#'
#' @param text A character vector
#' @param model Which variant of the GPT-3 embedding model to use. Defaults to 'text-embedding-3-large'.
#'
#' @return A matrix of embedding vectors (one per row), the same length as the text input.
#' @export
#'
#' @examples
#' embeddings <- get_embeddings(c('dog', 'cat', 'canine', 'feline'))
#' embeddings['dog',] |> dot(embeddings['canine',])
#' embeddings['dog',] |> dot(embeddings['feline',])
get_embeddings <- function(text, model = 'text-embedding-3-large'){

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
    emb <- openai::create_embedding(model = model,
                                    input = chunk)


    embeddings[index:end] <- emb$data$embedding

    # increment the index
    index <- index + chunk_size

  }

  # bind into a matrix
  embeddings <- do.call(rbind, embeddings)

  return(embeddings)

}
