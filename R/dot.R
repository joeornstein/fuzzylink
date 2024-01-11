#' Compute the dot product between two vectors
#'
#' @param vec1 A numeric vector
#' @param vec2 Another numeric vector
#'
#' @return A numeric
#' @export
#'
#' @examples
#' dot(c(0,1), c(1,0))
dot <- function(vec1, vec2){
  sum(vec1 * vec2)
}
