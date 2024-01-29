fuzzylink <- function(dfA, dfB,
                      by, blocking.variables = NULL,
                      verbose = TRUE){

  ## Step 1: Blocking -----------------

  if(!is.null(blocking.variables)){
    # get every unique combination of blocking variables in dfA
    blocks <- unique(dfA[,blocking.variables])

    # keep only the rows in dfB with exact matches on the blocking variables
    dfB <- dplyr::inner_join(dfB, blocks,
                             by = blocking.variables)
  } else{
    blocks <- data.frame(block = 1)
  }

  ## Step 2: Get similarity matrix within each block ------------
  sim <- list()
  for(i in 1:nrow(blocks)){

    if(!is.null(blocking.variables)){

      if(verbose){
        cat('Block ', i, ':\n', sep = '')
        print(unlist(blocks[i,]))
        cat('\n\n')
      }

      # subset the data for each block from dfA and dfB
      subset_A <- mapply(`==`,
                         dfA[, blocking.variables],
                         blocks[i,]) |>
        apply(1, all)
      block_A <- dfA[subset_A, ]

      subset_B <- mapply(`==`,
                         dfB[, blocking.variables],
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

    # get embeddings
    if(verbose){
      cat('Retrieving embeddings (',
          format(Sys.time(), '%X'),
          ')\n\n', sep = '')
    }
    embeddings <- get_embeddings(unique(c(strings_A, strings_B)))

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
  train <- get_training_set(sim)

  ## Step 4: Fit model -------------------
  if(verbose){
    cat('Fitting model (',
        format(Sys.time(), '%X'),
        ')\n\n', sep = '')
  }
  model <- glm(as.numeric(match == 'Yes') ~ sim,
               data = train,
               family = 'binomial')

  # Step 5: Create matched dataset ---------------
  if(verbose){
    cat('Linking datasets (',
        format(Sys.time(), '%X'),
        ')\n\n', sep = '')
  }

  # df is the dataset of all within-block name pairs
  df <- na.omit(reshape2::melt(sim))
  # rename columns
  namekey <- c(Var1 = 'A', Var2 = 'B', value = 'sim', L1 = 'block')
  names(df) <- namekey[names(df)]

  df$match_probability <- predict.glm(model, df, type = 'response')

  matches <- df |>
    dplyr::filter(match_probability > 0.2) |>
    dplyr::right_join(dfA, by = c('A' = by)) |>
    dplyr::select(-all_of(blocking.variables)) |>
    dplyr::left_join(dfB, by = c('B' = by)) |>
    # join with match labels from the training set
    dplyr::left_join(train, by = c('A', 'B', 'sim', 'block'))

  if(is.null(blocking.variables)) df <- dplyr::select(df, -block)

  ## Step 6: Validate uncertain matches --------------

  matches_to_validate <- matches |>
    dplyr::filter(match_probability > 0.2,
                  match_probability < 0.9,
                  is.na(match))

  if(nrow(matches_to_validate) > 0){
    if(verbose){
      cat('Validating ',
          nrow(matches_to_validate),
          ' matches (',
          format(Sys.time(), '%X'),
          ')\n\n', sep = '')
    }

    matches_to_validate$match <- check_match(matches_to_validate$A,
                                             matches_to_validate$B)

    # append new labeled pairs to the train set
    train <- train |>
      dplyr::bind_rows(matches_to_validate |>
                         dplyr::select(A,B,sim,match))

    # refine the model
    model <- glm(as.numeric(match == 'Yes') ~ sim,
                 data = train,
                 family = 'binomial')

    df$match_probability <- predict.glm(model, df, type = 'response')

    matches <- df |>
      dplyr::filter(match_probability > 0.2) |>
      dplyr::filterright_join(dfA, by = c('A' = 'name')) |>
      dplyr::filterleft_join(dfB, by = c('B' = 'name')) |>
      # join with match labels for those pairs in the training set
      dplyr::filterleft_join(train)
  }


  if(verbose){
    cat('Done! (',
        format(Sys.time(), '%X'),
        ')\n', sep = '')
  }

  return(matches)

}
