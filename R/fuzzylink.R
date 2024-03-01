#' Probabilistic Record Linkage Using Pretrained Text Embeddings
#'
#' @param dfA,dfB A pair of data frames or data frame extensions (e.g. tibbles)
#' @param by A character denoting the name of the variable to use for fuzzy matching
#' @param blocking.variables A character vector of variables that must match exactly in order to match two records
#' @param verbose TRUE to print progress updates, FALSE for no output
#' @param record_type A character describing what type of entity the `by` variable represents. Should be a singular noun (e.g. "person", "organization", "interest group", "city").
#' @param model Which OpenAI model to prompt; defaults to 'gpt-3.5-turbo-instruct'
#' @param openai_api_key Your OpenAI API key. By default, looks for a system environment variable called "OPENAI_API_KEY" (recommended option). Otherwise, it will prompt you to enter the API key as an argument.
#' @param max_validations The maximum number of LLM prompts to submit during the validation stage; defaults to 100,000
#' @param pmin,pmax Numbers between 0 and 1, denoting the range of estimated match probabilities within which `fuzzylink()` will validate record pairs using an LLM prompt; defaults to 0.1 and 0.9
#'
#' @return A dataframe with all rows of `dfA` joined with any matches from `dfB`
#' @export
#'
#' @examples
#' dfA <- data.frame(state.x77)
#' dfA$name <- rownames(dfA)
#' dfB <- data.frame(name = state.abb, state.division)
#' df <- fuzzylink(dfA, dfB, by = 'name', record_type = 'US state government')
fuzzylink <- function(dfA, dfB,
                      by, blocking.variables = NULL,
                      verbose = TRUE,
                      record_type = 'entity',
                      model = 'gpt-3.5-turbo-instruct',
                      openai_api_key = NULL,
                      max_validations = 1e5,
                      pmin = 0.1, pmax = 0.9){


  # Check for errors in inputs
  if(is.null(dfA[[by]])){
    stop(cat("There is no variable called \'", by, "\' in dfA.", sep = ''))
  }
  if(is.null(dfB[[by]])){
    stop(cat("There is no variable called \'", by, "\' in dfB.", sep = ''))
  }
  if(Sys.getenv('OPENAI_API_KEY') == '' & is.null(openai_api_key)){
    stop("No API key detected in system environment. You can enter it manually using the 'openai_api_key' argument.")
  }



  ## Step 0: Blocking -----------------

  if(!is.null(blocking.variables)){
    # get every unique combination of blocking variables in dfA
    blocks <- unique(dfA[,blocking.variables,drop = FALSE])

    # keep only the rows in dfB with exact matches on the blocking variables
    dfB <- dplyr::inner_join(dfB, blocks,
                             by = blocking.variables)
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
  embeddings <- get_embeddings(all_strings)

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

  ## Step 3: Create training set -------------
  if(verbose){
    cat('Labeling training set (',
        format(Sys.time(), '%X'),
        ')\n\n', sep = '')
  }
  train <- get_training_set(sim, record_type = record_type,
                            model = model, openai_api_key = openai_api_key)

  ## Step 4: Fit model -------------------
  if(verbose){
    cat('Fitting model (',
        format(Sys.time(), '%X'),
        ')\n\n', sep = '')
  }
  fit <- stats::glm(as.numeric(match == 'Yes') ~ sim + jw,
                    data = train |> dplyr::filter(match %in% c('Yes', 'No')),
                    family = 'binomial')

  # Step 5: Create matched dataset ---------------

  if(verbose){
    cat('Linking datasets (',
        format(Sys.time(), '%X'),
        ')\n\n', sep = '')
  }

  # df is the dataset of all within-block name pairs
  df <- stats::na.omit(reshape2::melt(sim))
  # rename columns
  namekey <- c(Var1 = 'A', Var2 = 'B', value = 'sim', L1 = 'block')
  names(df) <- namekey[names(df)]

  # add lexical string distance measures
  df$jw <- stringdist::stringsim(df$A, df$B, method = 'jw', p = 0.1)

  df$match_probability <- stats::predict.glm(fit, df, type = 'response')

  ## Step 6: Validate uncertain matches --------------

  validations_remaining <- max_validations

  get_matches_to_validate <- function(df, k = 50){

    mtv <- df |>
      # merge with labels from train set
      dplyr::left_join(train |>
                         dplyr::select(A, B, match),
                       by = c('A', 'B')) |>
      # keep name pairs within the user-specified uncertainty range
      dplyr::filter(match_probability > pmin,
                    match_probability < pmax,
                    is.na(match)) |>
      # remove duplicate name pairs
      dplyr::select(-block) |>
      unique()

    # if there are no name pairs remaining within the uncertainty range,
    # validate the k nearest neighbors of records in A with no validated matches
    if(nrow(mtv) == 0){

      mtv <- df |>
        # merge with labels from train set
        dplyr::left_join(train |>
                           dplyr::select(A, B, match),
                         by = c('A', 'B')) |>
        # keep only records from A with no validated matches
        dplyr::group_by(A) |>
        dplyr::filter(sum(match == 'Yes', na.rm = TRUE) == 0) |>
        dplyr::ungroup() |>
        # only validate within the range [1%, pmin]
        dplyr::filter(match_probability > 0.01,
                      match_probability < pmin) |>
        # get the k nearest neighbors for each unvalidated record in dfA
        dplyr::group_by(A) |>
        dplyr::slice_max(match_probability, n = k) |>
        dplyr::ungroup() |>
        dplyr::filter(is.na(match)) |>
        # remove duplicate name pairs
        dplyr::select(-block) |>
        unique()

      # how many nearest neighbors to include
      # k <- max(floor(max_n / length(unique(mtv$A))), 1)

    }
    return(mtv)
  }


  matches_to_validate <- get_matches_to_validate(df)

    # dplyr::filter(match_probability > 0.2,
    #               match_probability < 0.9,
    #               is.na(match))

  while(nrow(matches_to_validate) > 0 & validations_remaining > 0){

    # if you've reached the user-specified cap, only validate a sample
    if(nrow(matches_to_validate) > validations_remaining){
      matches_to_validate <- matches_to_validate |>
        dplyr::slice_sample(n = validations_remaining)
    }

    if(verbose){
      cat('Validating ',
          prettyNum(nrow(matches_to_validate), big.mark = ','),
          ' matches (',
          format(Sys.time(), '%X'),
          ')\n\n', sep = '')
    }

    matches_to_validate$match <- check_match(matches_to_validate$A,
                                             matches_to_validate$B,
                                             model = model,
                                             record_type = record_type,
                                             openai_api_key = openai_api_key)

    # if you've validated all pairs within the range [pmin, pmax], set validations_remaining = 0
    # otherwise, decrement validations_remaining as normal
    if(sum(matches_to_validate$match_probability >= pmin) == 0){
      validations_remaining <- 0
    } else{
      validations_remaining <- validations_remaining - nrow(matches_to_validate)
    }

    # append new labeled pairs to the train set
    train <- train |>
      dplyr::bind_rows(matches_to_validate |>
                         dplyr::select(A,B,sim,jw,match))

    # refine the model (train only on the properly formatted labels)
    fit <- stats::glm(as.numeric(match == 'Yes') ~ sim + jw,
                      data = train |> dplyr::filter(match %in% c('Yes', 'No')),
                      family = 'binomial')

    df$match_probability <- stats::predict.glm(fit, df, type = 'response')

    matches_to_validate <- get_matches_to_validate(df)
  }

  # if blocking, merge with the blocking variables prior to linking
  if(!is.null(blocking.variables)){
    blocks$block <- 1:nrow(blocks)
    df <- dplyr::left_join(df, blocks, by = 'block')
  }

  matches <- df |>
    # join with match labels from the training set
    dplyr::left_join(train |>
                       dplyr::select(A, B, match),
                     by = c('A', 'B')) |>
    # only keep pairs that have been validated or have a match probability > pmin
    dplyr::filter((match_probability > pmin &
                     is.na(match)) | match == 'Yes') |>
    dplyr::right_join(dfA,
                      by = c('A' = by, blocking.variables),
                      relationship = 'many-to-many') |>
    dplyr::left_join(dfB,
                     by = c('B' = by, blocking.variables),
                     relationship = 'many-to-many') |>
    dplyr::rename(validated = match)

  # } else{ # otherwise, no need to include blocking variables in the joins
  #   matches <- df |>
  #     # join with match labels from the training set
  #     dplyr::left_join(train |>
  #                        dplyr::select(A, B, match),
  #                      by = c('A', 'B')) |>
  #     # only keep pairs that have been validated or have a match probability > 0.2
  #     dplyr::filter((match_probability > 0.2 & is.na(match)) | match == 'Yes') |>
  #     dplyr::right_join(dfA, by = c('A' = by),
  #                       relationship = 'many-to-many') |>
  #     # dplyr::select(-dplyr::all_of(blocking.variables)) |>
  #     dplyr::left_join(dfB, by = c('B' = by),
  #                      relationship = 'many-to-many')
  # }

  if(is.null(blocking.variables)) matches <- dplyr::select(matches, -block)


  if(verbose){
    cat('Done! (',
        format(Sys.time(), '%X'),
        ')\n', sep = '')
  }

  return(matches)

}
