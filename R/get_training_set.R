#' Create a training set
#'
#' @description
#' Creates a training set from an embedding similarity matrix and labels it using a zero-shot GPT prompt.
#'
#'
#' @param sim A matrix of similarity scores
#' @param num_bins Number of bins to split similarity scores for stratified random sampling (defaults to 50)
#' @param samples_per_bin Number of string pairs to sample from each bin (defaults to 5)
#' @param few_shot_examples A dataframe with few-shot examples; must include columns `A`, `B`, and `match`
#'
#' @return A dataset with string pairs and a `match` column indicating whether they match.
#' @export
#'
get_training_set <- function(sim, num_bins = 50, samples_per_bin = 5,
                             batch_size = 50, few_shot_examples = NULL){

  # convert similarity matrix to long dataframe
  sim <- reshape2::melt(sim)
  # rename columns
  namekey <- c(Var1 = 'A', Var2 = 'B', value = 'sim', L1 = 'block')
  names(sim) <- namekey[names(sim)]
  # remove rows with missing values (generally from blocks with no exact matches)
  sim <- na.omit(sim)


  train <- sim |>
    # split embedding distance into equal-sized bins
    dplyr::mutate(bin = cut(sim, breaks = num_bins)) |>
    # draw randomly from each bin to create the training set
    dplyr::group_by(bin) |>
    dplyr::slice_sample(n = samples_per_bin) |>
    dplyr::ungroup() |>
    dplyr::select(-bin) |>
    # shuffle rows
    dplyr::slice_sample(prop = 1)

  # if not provided with few-shot examples, hand label the first 10 pairs (and remove from train)
  if(is.null(few_shot_examples)){
    few_shot_examples <- hand_label(head(train, 10))
    train <- dplyr::slice_tail(train, n = -10)
  }

  # label each name pair using zero-shot GPT-4 prompt
  train$match <- check_match(train$A, train$B,
                             batch_size = batch_size,
                             few_shot_examples = few_shot_examples)

  # merge hand-labeled and GPT-labeled name pairs
  train <- dplyr::bind_rows(few_shot_examples, train)

  return(train)

}
