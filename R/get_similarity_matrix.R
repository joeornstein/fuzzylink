#' Create matrix of embedding similarities
#'
#' @description
#' Create a matrix of pairwise similarities between each string in `strings_A` and `strings_B`.
#'
#'
#' @param embeddings A matrix of text embeddings
#' @param strings_A A list of strings in Dataset A
#' @param strings_B A list of strings in Dataset B
#'
#' @return A similarity matrix
#' @export
#'
#' @examples
#' get_embeddings(c('UPS', 'USPS', 'Postal Service')) |>
#'   get_similarity_matrix(c('UPS', 'USPS'), 'Postal Service')
get_similarity_matrix <- function(embeddings, strings_A, strings_B){

  A <- embeddings[strings_A, , drop = FALSE]
  B <- embeddings[strings_B, , drop = FALSE]

  # use parallelized version of tcrossprod() for fast matrix multiplication
  sim <- Rfast::Tcrossprod(A, B)
  rownames(sim) <- strings_A
  colnames(sim) <- strings_B

  return(sim)

}
