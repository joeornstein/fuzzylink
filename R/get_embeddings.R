#' Get pretrained text embeddings
#'
#' @description
#' Get pretrained text embeddings from the OpenAI or Mistral API. Automatically batches requests to handle rate limits.
#'
#' @param text A character vector
#' @param model Which embedding model to use. Defaults to 'text-embedding-3-large'.
#' @param dimensions The dimension of the embedding vectors to return. Defaults to 256. Note that the 'mistral-embed' model will always return 1024 vectors.
#' @param openai_api_key Your OpenAI API key. By default, looks for a system environment variable called "OPENAI_API_KEY".
#' @param parallel TRUE to submit API requests in parallel. Setting to FALSE can reduce rate limit errors at the expense of longer runtime.
#'
#' @return A matrix of embedding vectors (one per row).
#' @export
get_embeddings <- function(text,
                           model = 'text-embedding-3-large',
                           dimensions = 256,
                           openai_api_key = Sys.getenv("OPENAI_API_KEY"),
                           parallel = TRUE) {

  if (model == 'mistral-embed') {
    if (Sys.getenv('MISTRAL_API_KEY') == '') {
      stop("No API key detected in system environment. Add to Renviron as MISTRAL_API_KEY.")
    }

    format_request <- function(chunk,
                               base_url = "https://api.mistral.ai/v1/embeddings") {
      httr2::request(base_url) |>
        httr2::req_headers(
          "Content-Type" = 'application/json',
          "Accept" = 'application/json',
          "Authorization" = paste("Bearer", Sys.getenv('MISTRAL_API_KEY'))
        ) |>
        httr2::req_body_json(list(model = model, input = chunk))
    }

    tpr <- 8192
    max_characters <- tpr * 2
    rpm <- 5 * 60
    cumulative_length <- cumsum(nchar(text))
    split_indices <- cumulative_length %/% max_characters
    chunks <- split(text, split_indices)

  } else {
    if (openai_api_key == '') {
      stop("No API key detected. Set OPENAI_API_KEY in .Renviron or pass as argument.")
    }

    is_project_scoped <- function(key) {
      grepl("^sk-proj-", key)
    }

    get_project_id <- function(api_key) {
      if (!is_project_scoped(api_key)) return(NULL)
      project_id <- Sys.getenv("OPENAI_PROJECT_ID")
      if (project_id == "") {
        stop("You are using a project-scoped key (sk-proj-...), but OPENAI_PROJECT_ID is not set.\n\nAdd this line to your .Renviron:\nOPENAI_PROJECT_ID=project_xxxxxx\n")
      }
      return(project_id)
    }

    format_request <- function(chunk, base_url = "https://api.openai.com/v1/embeddings") {
      project_id <- get_project_id(openai_api_key)

      # ⚠️ Use a named character vector to avoid collapsing
      headers <- c(
        "Authorization" = paste("Bearer", openai_api_key),
        "Content-Type" = "application/json"
      )
      if (!is.null(project_id)) {
        headers["OpenAI-Project"] <- project_id
      }

      httr2::request(base_url) |>
        # headers
        httr2::req_headers(!!!headers) |>
        # body
        httr2::req_body_json(list(model = model,
                                  input = chunk,
                                  dimensions = dimensions))
    }

    req <- format_request("test")
    resp <- httr2::req_perform(req)
    rpm <- as.numeric(httr2::resp_header(resp, 'x-ratelimit-limit-requests'))
    tpm <- as.numeric(httr2::resp_header(resp, 'x-ratelimit-limit-tokens'))
    tpr <- 8192
    rpm <- min(c(rpm, floor(tpm / tpr)))

    max_characters <- tpr * 2
    cumulative_length <- cumsum(nchar(text))
    split_indices <- cumulative_length %/% max_characters
    chunks <- split(text, split_indices)
  }

  reqs <- lapply(chunks, format_request)

  if (parallel & model != 'mistral-embed') {
    resps <- httr2::req_perform_parallel(reqs,
                                         max_active = 20,
                                         on_error = 'continue')
  } else {
    resps <- lapply(reqs, httr2::req_throttle, rate = rpm / 60) |>
      httr2::req_perform_sequential()
  }

  status_codes <- vapply(resps, function(x) x$status, numeric(1))
  if (any(status_codes == 400)) {
    stop("HTTP 400 Bad Request. Likely due to malformed input or batching.")
  } else if(any(status_codes == 403)){
	 stop(
       'HTTP 403 Bad Request.'
       )
  } else if(any(status_codes == 429)){
    stop(
   'HTTP 429 Bad Request'
   )
  }

  parsed <- lapply(lapply(resps, httr2::resp_body_string), jsonlite::fromJSON, flatten = TRUE)
  embeddings <- sapply(parsed, function(x) x$data$embedding)


  # bind into a matrix
  if (length(chunks) > 1) embeddings <- lapply(embeddings, function(x) do.call(rbind, x))
  embeddings <- do.call(rbind, embeddings)
  rownames(embeddings) <- text

  return(embeddings)
}
