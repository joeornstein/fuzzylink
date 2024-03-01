#' Create a training set
#'
#' @description
#' Creates a training set from a list of similarity matrices and labels it using a zero-shot GPT prompt.
#'
#'
#' @param sim A matrix of similarity scores
#' @param num_bins Number of bins to split similarity scores for stratified random sampling (defaults to 50)
#' @param samples_per_bin Number of string pairs to sample from each bin (defaults to 5)
#' @param n Sample size for the training dataset
#' @param record_type A character describing what type of entity the rows and columns of `sim` represent. Should be a singular noun (e.g. "person", "organization", "interest group", "city").
#' @param model Which OpenAI model to prompt; defaults to 'gpt-3.5-turbo-instruct'
#' @param openai_api_key Your OpenAI API key. By default, looks for a system environment variable called "OPENAI_API_KEY" (recommended option). Otherwise, it will prompt you to enter the API key as an argument.
#'
#' @return A dataset with string pairs `A` and `B`, along with a `match` column indicating whether they match.
#' @export
#'
get_training_set <- function(sim, num_bins = 50, samples_per_bin = 10, n = 500,
                             record_type = 'entity', model = 'gpt-3.5-turbo-instruct',
                             openai_api_key = NULL){

  if(Sys.getenv('OPENAI_API_KEY') == '' & is.null(openai_api_key)){
    stop("No API key detected in system environment. You can enter it manually using the 'openai_api_key' argument.")
  }

  # convert similarity matrix to long dataframe
  sim <- reshape2::melt(sim)
  # rename columns
  namekey <- c(Var1 = 'A', Var2 = 'B', value = 'sim', L1 = 'block')
  names(sim) <- namekey[names(sim)]
  # remove rows with missing values (generally from blocks with no exact matches)
  sim <- stats::na.omit(sim)

  # remove duplicate name pairs
  sim <- dplyr::select(sim, -block)
  sim <- unique(sim)

  # how many nearest neighbors to include in the training set?
  # k must be at least 1
  k <- max(floor(n / length(unique(sim$A))), 1)

  # if using knn sampling
  train <- sim |>
    # get the k nearest neighbors for each record in dfA
    dplyr::group_by(A) |>
    dplyr::slice_max(sim, n = k) |>
    dplyr::ungroup() |>
    # keep a random sample of at most n
    dplyr::slice_sample(n = n)

  # if using stratified sampling
  # train <- sim |>
  #   # split embedding distance into equal-sized bins
  #   dplyr::mutate(bin = cut(sim, breaks = num_bins)) |>
  #   # draw randomly from each bin to create the training set
  #   dplyr::group_by(bin) |>
  #   dplyr::slice_sample(n = samples_per_bin) |>
  #   dplyr::ungroup() |>
  #   dplyr::select(-bin) |>
  #   # shuffle rows
  #   dplyr::slice_sample(prop = 1)

  # add lexical string distance measures
  train$jw <- stringdist::stringsim(train$A, train$B, method = 'jw', p = 0.1)

  # hand-label a set of few-shot examples?
  manual_few_shot <- FALSE
  if(manual_few_shot){
    few_shot_examples <- hand_label(utils::head(train, 5))
    train <- dplyr::slice_tail(train, n = -5)
  }

  # label each name pair using zero-shot GPT prompt
  train$match <- check_match(train$A, train$B,
                             record_type = record_type,
                             model = model,
                             openai_api_key = openai_api_key)

  if(manual_few_shot){
    train <- dplyr::bind_rows(few_shot_examples, train)
  }

  # filter out improperly formatted labels
  # train <- train |>
  #   dplyr::filter(match %in% c('Yes', 'No'))

  return(train)

}
