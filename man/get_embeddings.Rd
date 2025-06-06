% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/get_embeddings.R
\name{get_embeddings}
\alias{get_embeddings}
\title{Get pretrained text embeddings}
\usage{
get_embeddings(
  text,
  model = "text-embedding-3-large",
  dimensions = 256,
  openai_api_key = Sys.getenv("OPENAI_API_KEY"),
  parallel = TRUE
)
}
\arguments{
\item{text}{A character vector}

\item{model}{Which embedding model to use. Defaults to 'text-embedding-3-large'.}

\item{dimensions}{The dimension of the embedding vectors to return. Defaults to 256. Note that the 'mistral-embed' model will always return 1024 vectors.}

\item{openai_api_key}{Your OpenAI API key. By default, looks for a system environment variable called "OPENAI_API_KEY".}

\item{parallel}{TRUE to submit API requests in parallel. Setting to FALSE can reduce rate limit errors at the expense of longer runtime.}
}
\value{
A matrix of embedding vectors (one per row).
}
\description{
Get pretrained text embeddings from the OpenAI or Mistral API. Automatically batches requests to handle rate limits.
}
\examples{
\dontrun{
embeddings <- get_embeddings(c('dog', 'cat', 'canine', 'feline'))
embeddings['dog',] |> dot(embeddings['canine',])
embeddings['dog',] |> dot(embeddings['feline',])
}
}
