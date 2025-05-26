#' Create matrix of embedding similarities
#'
#' @description
#' Create a matrix of pairwise similarities between each string in `strings_A` and `strings_B`.
#'
#'
#' @param embeddings A matrix of text embeddings
#' @param strings_A A string vector
#' @param strings_B A string vector
#'
#' @return A matrix of cosine similarities between the embeddings of strings_A and the embeddings of strings_B
#' @export
#'
#' @examples
#'
#' \dontrun{
#' embeddings <- get_embeddings(c('UPS', 'USPS', 'Postal Service'))
#' get_similarity_matrix(embeddings)
#' get_similarity_matrix(embeddings, 'Postal Service')
#' get_similarity_matrix(embeddings, 'Postal Service', c('UPS', 'USPS'))
#' }
get_similarity_matrix <- function(embeddings,
                                  strings_A = NULL,
                                  strings_B = NULL){

  # if no input for strings_A or strings_B, default to the full list from embeddings object
  if(is.null(strings_A)){
    strings_A <- rownames(embeddings)
  }
  if(is.null(strings_B)){
    strings_B <- rownames(embeddings)
  }

  A <- embeddings[strings_A, , drop = FALSE]
  B <- embeddings[strings_B, , drop = FALSE]

  # use parallelized version of tcrossprod() for fast matrix multiplication
  sim <- Rfast::Tcrossprod(A, B)
  rownames(sim) <- strings_A
  colnames(sim) <- strings_B

  return(sim)

}
