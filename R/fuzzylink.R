#' Probabilistic Record Linkage Using Pretrained Text Embeddings
#'
#' @param dfA,dfB A pair of data frames or data frame extensions (e.g. tibbles)
#' @param by A character denoting the name of the variable to use for fuzzy matching
#' @param blocking.variables A character vector of variables that must match exactly in order to match two records
#' @param verbose TRUE to print progress updates, FALSE for no output
#' @param record_type A character describing what type of entity the `by` variable represents. Should be a singular noun (e.g. "person", "organization", "interest group", "city").
#' @param openai_api_key Your OpenAI API key. By default, looks for a system environment variable called "OPENAI_API_KEY" (recommended option). Otherwise, it will prompt you to enter the API key as an argument.
#' @param max_validations The maximum number of LLM prompts to submit during the validation stage; defaults to 100,000
#'
#' @return A dataframe with all rows of `dfA` joined with any matches from `dfB`
#' @export
#'
#' @examples
#' dfA <- data.frame(state.x77)
#' dfA$name <- rownames(dfA)
#' dfB <- data.frame(name = state.abb, state.division)
#' df <- fuzzylink(dfA, dfB, by = 'name', record_type = 'state')
fuzzylink <- function(dfA, dfB,
                      by, blocking.variables = NULL,
                      verbose = TRUE,
                      record_type = 'entity',
                      openai_api_key = NULL,
                      max_validations = 1e5){


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



  ## Step 1: Blocking -----------------

  if(!is.null(blocking.variables)){
    # get every unique combination of blocking variables in dfA
    blocks <- unique(dfA[,blocking.variables,drop = FALSE])

    # keep only the rows in dfB with exact matches on the blocking variables
    dfB <- dplyr::inner_join(dfB, blocks,
                             by = blocking.variables)
  } else{
    blocks <- data.frame(block = 1)
  }

  ## Step 2: Get embeddings ----------------
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
  sim <- list()
  for(i in 1:nrow(blocks)){

    if(!is.null(blocking.variables)){

      if(verbose){
        cat('Block ', i, ' of ', nrow(blocks), ':\n', sep = '')
        print(unlist(blocks[i,]))
        cat('\n')
      }

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
    if(verbose){
      cat('Computing similarity matrix (',
          format(Sys.time(), '%X'),
          ')\n\n', sep = '')
    }
    sim[[i]] <- get_similarity_matrix(embeddings, strings_A, strings_B)
  }

  ## Step 3: Create training set -------------
  if(verbose){
    cat('Labeling training set (',
        format(Sys.time(), '%X'),
        ')\n\n', sep = '')
  }
  train <- get_training_set(sim, record_type = record_type, openai_api_key = openai_api_key)

  ## Step 4: Fit model -------------------
  if(verbose){
    cat('Fitting model (',
        format(Sys.time(), '%X'),
        ')\n\n', sep = '')
  }
  model <- stats::glm(as.numeric(match == 'Yes') ~ sim + jw,
                      data = train,
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

  df$match_probability <- stats::predict.glm(model, df, type = 'response')

  ## Step 6: Validate uncertain matches --------------

  validations_remaining <- max_validations

  matches_to_validate <- df |>
    dplyr::left_join(train |>
                       dplyr::select(A, B, match),
                     by = c('A', 'B')) |>
    dplyr::filter(match_probability > 0.2,
                  match_probability < 0.9,
                  is.na(match))

  while(nrow(matches_to_validate) > 0 & validations_remaining > 0){

    # if you've reached the user-specified cap, only validate a sample
    if(nrow(matches_to_validate) > validations_remaining){
      matches_to_validate <- matches_to_validate |>
        dplyr::slice_sample(n = validations_remaining)
    }

    if(verbose){
      cat('Validating ',
          nrow(matches_to_validate),
          ' matches (',
          format(Sys.time(), '%X'),
          ')\n\n', sep = '')
    }

    matches_to_validate$match <- check_match(matches_to_validate$A,
                                             matches_to_validate$B,
                                             record_type = record_type,
                                             openai_api_key = openai_api_key)

    validations_remaining <- validations_remaining - nrow(matches_to_validate)

    # append new labeled pairs to the train set
    train <- train |>
      dplyr::bind_rows(matches_to_validate |>
                         dplyr::select(A,B,sim,match))

    # refine the model
    model <- stats::glm(as.numeric(match == 'Yes') ~ sim + jw,
                 data = train,
                 family = 'binomial')

    df$match_probability <- stats::predict.glm(model, df, type = 'response')

    matches_to_validate <- df |>
      dplyr::left_join(train |>
                         dplyr::select(A, B, match),
                       by = c('A', 'B')) |>
      dplyr::filter(match_probability > 0.2,
                    match_probability < 0.9,
                    is.na(match))
  }


  matches <- df |>
    # join with match labels from the training set
    dplyr::left_join(train |>
                       dplyr::select(A, B, match),
                     by = c('A', 'B')) |>
    # only keep pairs that have been validated or have a match probability > 0.2
    dplyr::filter((match_probability > 0.2 & is.na(match)) | match == 'Yes') |>
    dplyr::right_join(dfA, by = c('A' = by),
                      relationship = 'many-to-many') |>
    dplyr::select(-dplyr::all_of(blocking.variables)) |>
    dplyr::left_join(dfB, by = c('B' = by),
                     relationship = 'many-to-many')

  if(is.null(blocking.variables)) matches <- dplyr::select(matches, -block)


  if(verbose){
    cat('Done! (',
        format(Sys.time(), '%X'),
        ')\n', sep = '')
  }

  return(matches)

}
