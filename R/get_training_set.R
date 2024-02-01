#' Create a training set
#'
#' @description
#' Creates a training set from a list of similarity matrices and labels it using a zero-shot GPT prompt.
#'
#'
#' @param sim A matrix of similarity scores
#' @param num_bins Number of bins to split similarity scores for stratified random sampling (defaults to 50)
#' @param samples_per_bin Number of string pairs to sample from each bin (defaults to 5)
#'
#' @return A dataset with string pairs `A` and `B`, along with a `match` column indicating whether they match.
#' @export
#'
get_training_set <- function(sim, num_bins = 50, samples_per_bin = 10){

  # convert similarity matrix to long dataframe
  sim <- reshape2::melt(sim)
  # rename columns
  namekey <- c(Var1 = 'A', Var2 = 'B', value = 'sim', L1 = 'block')
  names(sim) <- namekey[names(sim)]
  # remove rows with missing values (generally from blocks with no exact matches)
  sim <- na.omit(sim)


  train <- sim |>
    # get the five nearest neighbors for each record in dfA
    dplyr::group_by(A) |>
    dplyr::slice_max(sim, n = 5) |>
    dplyr::ungroup() |>
    # split embedding distance into equal-sized bins
    dplyr::mutate(bin = cut(sim, breaks = num_bins)) |>
    # draw randomly from each bin to create the training set
    dplyr::group_by(bin) |>
    dplyr::slice_sample(n = samples_per_bin) |>
    dplyr::ungroup() |>
    dplyr::select(-bin) |>
    # shuffle rows
    dplyr::slice_sample(prop = 1)

  # add lexical string distance measures
  train$jw <- stringdist::stringsim(train$A, train$B, method = 'jw', p = 0.1)

  # hand-label a set of few-shot examples?
  manual_few_shot <- FALSE
  if(manual_few_shot){
    few_shot_examples <- hand_label(head(train, 5))
    train <- dplyr::slice_tail(train, n = -5)
  }

  # label each name pair using zero-shot GPT prompt
  train$match <- check_match(train$A, train$B)

  if(manual_few_shot){
    train <- dplyr::bind_rows(few_shot_examples, train)
  }

  return(train)

}
