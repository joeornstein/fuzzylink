#' Probabilistic Record Linkage Using Pretrained Text Embeddings
#'
#' @param dfA,dfB A pair of data frames or data frame extensions (e.g. tibbles)
#' @param by A character denoting the name of the variable to use for fuzzy matching
#' @param blocking.variables A character vector of variables that must match exactly in order to match two records
#' @param verbose TRUE to print progress updates, FALSE for no output
#' @param record_type A character describing what type of entity the `by` variable represents. Should be a singular noun (e.g. "person", "organization", "interest group", "city").
#' @param instructions A string containing additional instructions to include in the LLM prompt during validation.
#' @param model Which LLM to prompt when validating matches; defaults to 'gpt-4o'
#' @param openai_api_key Your OpenAI API key. By default, looks for a system environment variable called "OPENAI_API_KEY" (recommended option). Otherwise, it will prompt you to enter the API key as an argument.
#' @param embedding_dimensions The dimension of the embedding vectors to retrieve. Defaults to 256
#' @param embedding_model Which pretrained embedding model to use; defaults to 'text-embedding-3-large' (OpenAI), but will also accept 'mistral-embed' (Mistral).
#' @param fmla By default, logistic regression model predicts whether two records match as a linear combination of embedding similarity and Jaro-Winkler similarity (`match ~ sim + jw`). Change this input for alternate specifications.
#' @param max_labels The maximum number of LLM prompts to submit when labeling record pairs. Defaults to 10,000
#' @param p The range of estimated match probabilities within which `fuzzylink()` will validate record pairs using an LLM prompt. Defaults to c(0.1, 0.95)
#' @param k Number of nearest neighbors to validate for records in `dfA` with no identified matches. Higher values may improve recall at expense of precision. Defaults to 0
#' @param parallel TRUE to submit API requests in parallel. Setting to FALSE can reduce rate limit errors at the expense of longer runtime.
#' @param return_all_pairs If TRUE, returns *every* within-block record pair from dfA and dfB, not just validated pairs. Defaults to FALSE.
#'
#' @return A dataframe with all rows of `dfA` joined with any matches from `dfB`
#' @export
#'
#' @examples
#' dfA <- data.frame(state.x77)
#' dfA$name <- rownames(dfA)
#' dfB <- data.frame(name = state.abb, state.division)
#' df <- fuzzylink(dfA, dfB,
#'                 by = 'name',
#'                 record_type = 'US state government',
#'                 instructions = 'The first dataset contains full US state names. The second dataset contains US postal codes.')
fuzzylink <- function(dfA, dfB,
                      by, blocking.variables = NULL,
                      verbose = TRUE,
                      record_type = 'entity',
                      instructions = NULL,
                      model = 'gpt-4o',
                      openai_api_key = Sys.getenv('OPENAI_API_KEY'),
                      embedding_dimensions = 256,
                      embedding_model = 'text-embedding-3-large',
                      fmla = match ~ sim + jw,
                      max_labels = 1e4,
                      parallel = TRUE,
                      return_all_pairs = FALSE){


  # Check for errors in inputs
  if(is.null(dfA[[by]])){
    stop(cat("There is no variable called \'", by, "\' in dfA.", sep = ''))
  }
  if(is.null(dfB[[by]])){
    stop(cat("There is no variable called \'", by, "\' in dfB.", sep = ''))
  }
  if(openai_api_key == ''){
    stop("No API key detected in system environment. You can enter it manually using the 'openai_api_key' argument.")
  }


  ## Step 0: Blocking -----------------

  if(!is.null(blocking.variables)){

    # get every unique combination of blocking variables in dfA
    blocks <- unique(dfA[,blocking.variables,drop = FALSE])

    # keep only the rows in dfB with exact matches on the blocking variables
    dfB <- dplyr::inner_join(dfB, blocks,
                             by = blocking.variables)

    if(nrow(dfB) == 0){
      stop("There are no exact matches in dfB on the blocking.variables specified.")
    }

  } else{
    blocks <- data.frame(block = 1)
  }

  ## Step 1: Get embeddings ----------------
  all_strings <- unique(c(dfA[[by]], dfB[[by]]))
  if(verbose){
    cat('Retrieving ',
        prettyNum(length(all_strings), big.mark = ','),
        ' embeddings (',
        format(Sys.time(), '%X'),
        ')\n\n', sep = '')
  }
  embeddings <- get_embeddings(all_strings,
                               model = embedding_model,
                               dimensions = embedding_dimensions,
                               openai_api_key = openai_api_key,
                               parallel = parallel)

  ## Step 2: Get similarity matrix within each block ------------
  if(verbose){
    cat('Computing similarity matrix (',
        format(Sys.time(), '%X'),
        ')\n\n', sep = '')
  }
  sim <- list()
  for(i in 1:nrow(blocks)){

    if(!is.null(blocking.variables)){

      # if(verbose){
      #   cat('Block ', i, ' of ', nrow(blocks), ':\n', sep = '')
      #   print(data.frame(blocks[i,]))
      #   cat('\n')
      # }

      # subset the data for each block from dfA and dfB
      subset_A <- mapply(`==`,
                         dfA[, blocking.variables,drop=FALSE],
                         blocks[i,]) |>
        apply(1, all)
      block_A <- dfA[subset_A, ]

      subset_B <- mapply(`==`,
                         dfB[, blocking.variables,drop=FALSE],
                         blocks[i,]) |>
        apply(1, all)
      block_B <- dfB[subset_B, ]

      # if you can't find any matches in dfA or dfB, go to the next block
      if(nrow(block_A) == 0 | nrow(block_B) == 0){
        sim[[i]] <- NA
        next
      }

    } else{
      # if not blocking, compute similarity matrix for all dfA and dfB
      block_A <- dfA
      block_B <- dfB
    }

    # get a unique list of strings in each dataset
    strings_A <- unique(block_A[[by]])
    strings_B <- unique(block_B[[by]])

    # compute cosine similarity matrix
    sim[[i]] <- get_similarity_matrix(embeddings, strings_A, strings_B)
  }

  ## Step 3: Label Training Set -------------
  if(verbose){
    cat('Labeling 500 Record Pairs (',
        format(Sys.time(), '%X'),
        ')\n\n', sep = '')
  }

  # df is the dataset of all within-block name pairs
  df <- reshape2::melt(sim)
  # rename columns
  namekey <- c(Var1 = 'A', Var2 = 'B', value = 'sim', L1 = 'block')
  names(df) <- namekey[names(df)]
  df <- dplyr::filter(df, !is.na(sim))

  # add lexical string distance measures
  df$jw <- stringdist::stringsim(df$A, df$B, method = 'jw', p = 0.1)

  # label initial training set (n_t=500)
  df$match <- NA
  n_t <- 500
  k <- max(floor(n_t / length(unique(df$A))), 1)
  pairs_to_label <- df |>
    # create index number
    dplyr::mutate(index = dplyr::row_number()) |>
    # remove any duplicate A/B pairs
    dplyr::distinct(A, B, .keep_all = TRUE) |>
    # get the k largest sim values in each group
    dplyr::group_by(A) |>
    dplyr::slice_max(sim, n = k) |>
    dplyr::ungroup() |>
    # only keep n_t record pairs
    dplyr::slice_sample(n = n_t) |>
    dplyr::pull(index)

  df$match[pairs_to_label] <- check_match(
    df$A[pairs_to_label],
    df$B[pairs_to_label],
    record_type = record_type,
    instructions = instructions,
    model = model,
    openai_api_key = openai_api_key,
    parallel = parallel
  )


  # train <- get_training_set(sim, record_type = record_type,
  #                           instructions = instructions,
  #                           model = model, openai_api_key = openai_api_key,
  #                           parallel = parallel)

  ## Step 4: Fit model -------------------
  if(verbose){
    cat('Fitting model (',
        format(Sys.time(), '%X'),
        ')\n\n', sep = '')
  }
  fit <- stats::glm(fmla,
                    data = df |>
                      dplyr::filter(match %in% c('Yes', 'No')) |>
                      dplyr::mutate(match = as.numeric(match == 'Yes')),
                    family = 'binomial')

  # Step 5: Active Learning Loop ---------------

  i <- 1
  window_size <- 5
  gradient_estimate <- 0
  stop_threshold <- 0.01
  kernel_sd <- 0.2
  batch_size <- 100
  stop_condition_met <- FALSE
  df$match_probability <- stats::predict.glm(fit, df, type = 'response')

  while(!stop_condition_met){

    if(verbose){
      cat('Refining Model ',
          i, ' (',
          format(Sys.time(), '%X'),
          ')\n\n', sep = '')
    }

    # Gaussian kernel
    log_prob <- qlogis(df$match_probability)
    p_draw <- ifelse(is.na(df$match),
                     dnorm(log_prob, mean = 0, sd = kernel_sd),
                     0)
    if(sum(p_draw > 0) == 0){
      break
    }

    pairs_to_label <- sample(
      1:nrow(df),
      size = ifelse(sum(p_draw > 0) < batch_size, sum(p_draw > 0), batch_size),
      replace = FALSE,
      prob = p_draw
    )

    # add the labels to the dataset
    df$match[pairs_to_label] <- check_match(
      df$A[pairs_to_label],
      df$B[pairs_to_label],
      record_type = record_type,
      instructions = instructions,
      model = model,
      openai_api_key = openai_api_key,
      parallel = parallel
    )

    # refit the model
    fit <- stats::glm(fmla,
                      data = df |>
                        dplyr::filter(match %in% c('Yes', 'No')) |>
                        dplyr::mutate(match = as.numeric(match == 'Yes')),
                      family = 'binomial')

    # re-estimate match probabilities
    old_probs <- df$match_probability
    df$match_probability <- stats::predict.glm(fit, df, type = 'response')
    gradient_estimate[i] <- max(abs(old_probs - df$match_probability))

    if(i >= window_size){
      if(mean(gradient_estimate[(i-window_size+1):i]) < stop_threshold){
        stop_condition_met <- TRUE
      }
    }

    i <- i + 1
  }

  ## Step 6: Recall Search -----------------

  # 1. Identify records in A without matches in B
  # 2. Sample from kernel in batches of 100; label but do not update model.
  # Loop 1-2 until either there are no remaining record pairs to label or you've hit
  # user-specified label maximum

  stop_condition_met <- FALSE
  while(!stop_condition_met){

    matches_found <- tapply(as.numeric(df$match == 'Yes'),
                            list(df$A, df$block), sum, na.rm=TRUE)
    no_matches_found <- apply(df, 1,
                              function(row) matches_found[row["A"], row["block"]] == 0)

    # Gaussian kernel
    log_prob <- qlogis(df$match_probability)
    p_draw <- ifelse(is.na(df$match) & no_matches_found,
                     dnorm(log_prob, mean = 0, sd = kernel_sd),
                     0)
    if(sum(p_draw > 0) == 0){
      break
    }

    print(paste0('Record Pairs Left To Search: ', sum(p_draw>0)))

    pairs_to_label <- sample(
      1:nrow(df),
      size = ifelse(sum(p_draw > 0) < batch_size, sum(p_draw > 0), batch_size),
      replace = FALSE,
      prob = p_draw
    )

    # add the labels to the dataset
    df$match[pairs_to_label] <- check_match(
      df$A[pairs_to_label],
      df$B[pairs_to_label],
      record_type = record_type,
      instructions = instructions,
      model = model,
      openai_api_key = openai_api_key,
      parallel = parallel
    )

    # check if stopping condition has been met
    if(sum(!is.na(df$match)) >= max_labels){
      stop_condition_met <- TRUE
    }
  }

  # if blocking, merge with the blocking variables prior to linking
  if(!is.null(blocking.variables)){
    blocks$block <- 1:nrow(blocks)
    df <- dplyr::left_join(df, blocks, by = 'block')
  }

  if(!return_all_pairs){

    # return the cutoff that maximizes expected F-score
    get_cutoff <- function(df, fit){
      df <- df[order(df$match_probability),]
      df$expected_false_negatives <- cumsum(df$match_probability)
      df$identified_false_negatives <- cumsum(ifelse(is.na(df$match), 0, as.numeric(df$match == 'Yes')))
      df <- df[order(-df$match_probability),]
      df$expected_false_positives <- cumsum(1-df$match_probability)
      df$identified_false_positives <- cumsum(1 - ifelse(is.na(df$match_probability), 1, as.numeric(df$match == 'Yes')))
      df$expected_true_positives <- cumsum(df$match_probability)
      df$identified_true_positives <- cumsum(ifelse(is.na(df$match), 0, as.numeric(df$match == 'Yes')))

      total_labeled_true <- sum(df$match == 'Yes', na.rm = TRUE)

      df$tp <- total_labeled_true + (df$expected_true_positives - df$identified_true_positives)
      df$fp <- df$expected_false_positives - df$identified_false_positives
      df$fn <- df$expected_false_negatives - df$identified_false_negatives

      df$expected_recall <- df$tp / (df$tp + df$fn)
      df$expected_precision <- df$tp / (df$tp + df$fp)
      df$expected_f1 = 2 * (df$expected_recall * df$expected_precision) /
        (df$expected_recall + df$expected_precision)

      return(df$match_probability[which.max(df$expected_f1)])
    }

    df <- df |>
      # only keep pairs that have been labeled Yes or have a match probability > p_cutoff
      dplyr::filter((match_probability > get_cutoff(df, fit) &
                       is.na(match)) | match == 'Yes') |>
      dplyr::right_join(dfA,
                        by = c('A' = by, blocking.variables),
                        relationship = 'many-to-many') |>
      dplyr::left_join(dfB,
                       by = c('B' = by, blocking.variables),
                       relationship = 'many-to-many')
  }

  if(is.null(blocking.variables)) df <- dplyr::select(df, -block)

  if(verbose){
    cat('Done! (',
        format(Sys.time(), '%X'),
        ')\n', sep = '')
  }

  return(df)

}
