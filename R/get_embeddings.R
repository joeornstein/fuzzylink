#' Get pretrained text embeddings
#'
#' @description
#' Get pretrained text embeddings from the OpenAI, Mistral, or OpenRouter API. Automatically batches requests to handle rate limits.
#'
#' Embeddings are cached to disk so that repeated calls only send API requests for strings that have not been embedded before. Cache entries are keyed by the text string together with the `model` and `dimensions`, so switching models or dimension settings will never return mismatched vectors.
#'
#' @param text A character vector
#' @param model Which embedding model to use. Defaults to 'text-embedding-3-large'. OpenRouter models are detected if they contain a slash (e.g. 'nvidia/llama-nemotron-embed-vl-1b-v2:free').
#' @param dimensions The dimension of the embedding vectors to return. Defaults to 256. Note that the 'mistral-embed' model will always return 1024 vectors.
#' @param openai_api_key Your OpenAI API key. By default, looks for a system environment variable called "OPENAI_API_KEY".
#' @param parallel TRUE to submit API requests in parallel. Setting to FALSE can reduce rate limit errors at the expense of longer runtime.
#' @param cache Controls on-disk caching of embeddings. `TRUE` (the default) caches to a default file under `tools::R_user_dir("fuzzylink", "cache")`. Pass a file path to use a specific cache file, or `FALSE`/`NULL` to disable caching entirely.
#'
#' @return A matrix of embedding vectors (one per row).
#' @export
#'
#' @examples
#' \dontrun{
#' embeddings <- get_embeddings(c('dog', 'cat', 'canine', 'feline'))
#' embeddings['dog',] |> dot(embeddings['canine',])
#' embeddings['dog',] |> dot(embeddings['feline',])
#' }
get_embeddings <- function(text,
                           model = 'text-embedding-3-large',
                           dimensions = 256,
                           openai_api_key = Sys.getenv("OPENAI_API_KEY"),
                           parallel = TRUE,
                           cache = TRUE) {

  # ---- Resolve the cache location ----
  # `cache` may be TRUE (default file), a file path, or FALSE/NULL (disabled).
  cache_path <- NULL
  if (is.character(cache)) {
    cache_path <- cache
  } else if (isTRUE(cache)) {
    cache_path <- file.path(tools::R_user_dir("fuzzylink", which = "cache"),
                            "embeddings.rds")
  }
  use_cache <- !is.null(cache_path)

  # Entries are keyed by (model, dimensions) so that vectors from different
  # models/dimension settings are never mixed together.
  cache_key <- paste(model, dimensions, sep = "|")

  # ---- Load any previously cached embeddings for this configuration ----
  cache_store <- list()
  cached_embeddings <- NULL
  if (use_cache && file.exists(cache_path)) {
    cache_store <- readRDS(cache_path)
    cached_embeddings <- cache_store[[cache_key]]
  }

  # Only fetch strings we haven't already embedded under this configuration.
  if (!is.null(cached_embeddings)) {
    already_cached <- text %in% rownames(cached_embeddings)
  } else {
    already_cached <- rep(FALSE, length(text))
  }
  text_to_fetch <- unique(text[!already_cached])

  new_embeddings <- NULL

  if (length(text_to_fetch) > 0) {

    if (grepl("/", model)) {
      api_key <- Sys.getenv("OPENROUTER_API_KEY")
      if (api_key == '') {
        stop("No API key detected for OpenRouter. You can add one using the 'openrouter_api_key()' function.")
      }

      # check whether the provided model string is indeed an OpenRouter embeddings model
      check_req <- httr2::request("https://openrouter.ai/api/v1/embeddings/models") |>
        httr2::req_headers(
          "Authorization" = paste("Bearer", api_key),
          "HTTP-Referer" = "https://github.com/joeornstein/fuzzylink",
          "X-Title" = "fuzzylink"
        )
      check_resp <- httr2::req_perform(check_req)
      models_data <- httr2::resp_body_json(check_resp)$data
      available_models <- sapply(models_data, function(x) x$id)
      if (!model %in% available_models) {
        stop(paste("Model", model, "is not available on OpenRouter or is not a text embedding model."))
      }
    }

    if (model == 'mistral-embed') {
      if (Sys.getenv('MISTRAL_API_KEY') == '') {
        stop("No API key detected in system environment. Add to Renviron as MISTRAL_API_KEY.")
      }

      # function to format an API request
      format_mistral_request <- function(chunk, base_url = "https://api.mistral.ai/v1/embeddings") {
        httr2::request(base_url) |>
          httr2::req_headers(
            "Content-Type" = 'application/json',
            "Accept" = 'application/json',
            "Authorization" = paste("Bearer", Sys.getenv('MISTRAL_API_KEY'))
          ) |>
          httr2::req_body_json(list(model = model, input = chunk)) |>
          httr2::req_retry(max_tries = 5,
                           is_transient = \(resp) httr2::resp_status(resp) %in% c(429, 500:504))
      }

      # max tokens per request
      tpr <- 8192
      # max characters per chunk is approximately max tokens times 2 (*very* conservative)
      max_characters <- tpr * 2

      # Calculate cumulative sum of character lengths
      cumulative_length <- cumsum(nchar(text_to_fetch))
      # Find the indices where to split
      split_indices <- cumulative_length %/% max_characters
      # Split the vector based on the calculated indices
      chunks <- split(text_to_fetch, split_indices)

    } else if (grepl("/", model)) {
      api_key <- Sys.getenv("OPENROUTER_API_KEY")
      base_url <- "https://openrouter.ai/api/v1/embeddings"

      # format an API request to embeddings endpoint
      format_openrouter_request <- function(chunk) {
        headers <- c(
          "Authorization" = paste("Bearer", api_key),
          "Content-Type" = "application/json",
          "HTTP-Referer" = "https://github.com/joeornstein/fuzzylink",
          "X-Title" = "fuzzylink"
        )

        httr2::request(base_url) |>
          httr2::req_headers(!!!headers) |>
          httr2::req_body_json(list(
            model = model,
            input = chunk,
            dimensions = dimensions
          )) |>
          httr2::req_retry(max_tries = 5,
                           is_transient = \(resp) httr2::resp_status(resp) %in% c(429, 500:504))
      }

      # max tokens per request
      tpr <- 8192
      max_characters <- tpr * 2
      cumulative_length <- cumsum(nchar(text_to_fetch))
      split_indices <- cumulative_length %/% max_characters
      chunks <- split(text_to_fetch, split_indices)

    } else {
      if (openai_api_key == '') {
        stop("No API key detected. Set OPENAI_API_KEY in .Renviron or pass openai_api_key as argument.")
      }

      # format an API request to embeddings endpoint
      format_request <- function(chunk) {
        headers <- c(
          "Authorization" = paste("Bearer", openai_api_key),
          "Content-Type" = "application/json"
        )

        httr2::request("https://api.openai.com/v1/embeddings") |>
          httr2::req_headers(!!!headers) |>
          httr2::req_body_json(list(
            model = model,
            input = chunk,
            dimensions = dimensions
          )) |>
          httr2::req_retry(max_tries = 5,
                           is_transient = \(resp) httr2::resp_status(resp) %in% c(429, 500:504))
      }

      # max tokens per request is currently 8192
      tpr <- 8192

      # split the embeddings into chunks, because the OpenAI
      # embeddings endpoint will only take so many tokens at a time

      # max characters per chunk is approximately max tokens times 2 (*very* conservative)
      max_characters <- tpr * 2
      # Calculate cumulative sum of character lengths
      cumulative_length <- cumsum(nchar(text_to_fetch))
      # Find the indices where to split
      split_indices <- cumulative_length %/% max_characters
      # Split the vector based on the calculated indices
      chunks <- split(text_to_fetch, split_indices)
    }

    # format list of requests
    if(model == 'mistral-embed'){
      reqs <- lapply(chunks, format_mistral_request)
    } else if (grepl("/", model)){
      reqs <- lapply(chunks, format_openrouter_request)
    } else{
      reqs <- lapply(chunks, format_request)
    }

    # perform requests
    if (parallel & model != 'mistral-embed') {
      # submit prompts in parallel (20 concurrent requests per host seems to be the optimum)
      resps <- httr2::req_perform_parallel(reqs, max_active = 20, on_error = 'continue')
    } else {
      resps <- httr2::req_perform_sequential(reqs)
    }

    status_codes <- vapply(resps, function(x)
      x$status, numeric(1))
    if (any(status_codes == 400)) {
      stop("HTTP 400 Bad Request. Likely due to malformed input or batching.")
    } else if (any(status_codes == 401)) {
      stop('401 Unauthorized. Your API key is missing, invalid, or expired. Double-check your credentials.')
    } else if (any(status_codes == 403)) {
      stop('403 Forbidden. Your API key does not have permission to perform this action.')
    } else if (any(status_codes == 404)) {
      stop('404 Not Found. Check the spelling of the `model` or `embedding_model` inputs.')
    } else if (any(status_codes == 429)) {
      stop('429 Too Many Requests. The API is not allowing you to retrieve this many embeddings. Please ensure that you have enough credits to use the API.')
    } else if (any(status_codes %in% 500:504)) {
        stop('500-504 Server Side Error. Something went wrong with the OpenAI server. Not your fault. Try again later.')
    }

    # parse the responses
    parsed <- lapply(lapply(resps, httr2::resp_body_string),
                     jsonlite::fromJSON,
                     flatten = TRUE)

    # get the embeddings
    new_embeddings <- sapply(parsed, function(x)
      x$data$embedding)

    # bind into a matrix
    if (length(chunks) > 1)
      new_embeddings <- lapply(new_embeddings, function(x)
        do.call(rbind, x))
    new_embeddings <- do.call(rbind, new_embeddings)
    rownames(new_embeddings) <- text_to_fetch
  }

  # ---- Combine cached + newly fetched embeddings and update the cache ----
  all_embeddings <- rbind(cached_embeddings, new_embeddings)

  if (use_cache && !is.null(new_embeddings)) {
    cache_store[[cache_key]] <- all_embeddings
    dir.create(dirname(cache_path), recursive = TRUE, showWarnings = FALSE)
    saveRDS(cache_store, cache_path)
  }

  # Return rows aligned to the requested `text` (preserves order and duplicates)
  embeddings <- all_embeddings[text, , drop = FALSE]
  rownames(embeddings) <- text

  return(embeddings)
}
