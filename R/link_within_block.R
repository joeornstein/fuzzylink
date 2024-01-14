link_within_block <- function(dfA, dfB,
                              fuzzy.string,
                              blocking.variables = NULL,
                              prob_threshold = 0,
                              verbose = TRUE){


  # get a unique list of strings in each dataset
  strings_A <- unique(dfA[[fuzzy.string]])
  strings_B <- unique(dfB[[fuzzy.string]])

  all_unique_strings <- unique(c(strings_A, strings_B))

  # get the pre-trained text embeddings (GPT-3)
  if(verbose){
    print(paste0('Retrieving ', length(all_unique_strings),
                 ' embeddings.'))
  }
  embeddings <- get_embeddings(all_unique_strings)
  if(verbose) print('Embeddings retrieved. Computing pairwise similarities...')

  # similarity matrix from crossproduct (matrix operations *much* faster)
  emb <- do.call(rbind, embeddings)
  emb_A <- emb[strings_A,]
  emb_B <- emb[strings_B,]
  similarity_matrix <- tcrossprod(emb_A, emb_B)


  # Compute all pairwise similarity scores
  df <- expand.grid(string_A = strings_A,
                    string_B = strings_B,
                    stringsAsFactors = FALSE)


  # this is a lot slower than matrix multiplication
  # df$embedding_score <- mapply(function(a, b) dot(embeddings[[a]],
  #                                                 embeddings[[b]]),
  #                              df$string_A, df$string_B)

  if(verbose) print('JW')
  # Compute lexical string distance measures
  # df$jw <- RecordLinkage::jarowinkler(str1 = tolower(df$string_A),
  #                                    str2 = tolower(df$string_B),
  #                                    r = 0.1)
  df$jw <- stringdist::stringsim(tolower(df$string_A),
                                 tolower(df$string_B),
                                 method = 'jw',
                                 p = 0.1)

  if(verbose) print('Jaccard')
  df$jaccard <- stringdist::stringsim(tolower(df$string_A),
                          tolower(df$string_B),
                          method = 'jaccard')

  if(verbose) print('Cosine')
  df$cosine <- stringdist::stringsim(tolower(df$string_A),
                         tolower(df$string_B),
                         method = 'cosine')

  if(verbose) print('Levenshtein')
  df$levenshtein <- stringdist::stringdist(tolower(df$string_A),
                               tolower(df$string_B),
                               method = 'lv')

  if(verbose) print('LCS')
  df$lcsstr <- stringdist::stringdist(tolower(df$string_A),
                          tolower(df$string_B),
                          method = 'lcs')


  if(verbose) print('Estimating match probabilities...')
  # Estimate predicted match probability
  df$prob_match <- predict(base_model, df)$predictions

  if(verbose) print('Merging records...')
  # return merged dataset with all variables
  dfA$string_A <- dfA[[fuzzy.string]]
  dfB$string_B <- dfB[[fuzzy.string]]

  # remove the duplicate variable names in dfB
  dfB <- dplyr::select(dfB, -dplyr::all_of(blocking.variables), -dplyr::all_of(fuzzy.string))

  df <- dfA |>
    dplyr::left_join(df, by = 'string_A',
              relationship = 'many-to-many') |>
    dplyr::left_join(dfB, by = 'string_B',
              relationship = 'many-to-many')

  return(df)

}
