link_within_block <- function(dfA, dfB,
                              fuzzy.string,
                              blocking.variables,
                              prob_threshold = 0){


  # get a unique list of strings in each dataset
  strings_A <- unique(dfA[[fuzzy.string]])
  strings_B <- unique(dfB[[fuzzy.string]])

  all_unique_strings <- unique(c(strings_A, strings_B))

  # get the pre-trained text embeddings (GPT-3)
  embeddings <- get_embeddings(all_unique_strings)

  # Compute all pairwise similarity scores
  df <- expand.grid(string_A = strings_A,
                    string_B = strings_B,
                    stringsAsFactors = FALSE)

  df$embedding_score <- NA
  for(i in 1:nrow(df)){
    df$embedding_score[i] <- dot(embeddings[[df$string_A[i]]],
                                 embeddings[[df$string_B[i]]])
  }

  # Compute lexical string distance measures
  df$jw = RecordLinkage::jarowinkler(str1 = str_to_lower(df$string_A),
                                     str2 = str_to_lower(df$string_B),
                                     r = 0.1)

  df$jaccard <- stringdist::stringsim(str_to_lower(df$string_A),
                          str_to_lower(df$string_B),
                          method = 'jaccard')

  df$cosine <- stringdist::stringsim(str_to_lower(df$string_A),
                         str_to_lower(df$string_B),
                         method = 'cosine')

  df$levenshtein <- stringdist::stringdist(str_to_lower(df$string_A),
                               str_to_lower(df$string_B),
                               method = 'lv')

  df$lcsstr <- stringdist::stringdist(str_to_lower(df$string_A),
                          str_to_lower(df$string_B),
                          method = 'lcs')


  # Estimate predicted match probability
  df$prob_match <- predict(model, df)$predictions

  # return merged dataset with all variables
  dfA$string_A <- dfA[[fuzzy.string]]
  dfB$string_B <- dfB[[fuzzy.string]]

  # remove the duplicate variable names in dfB
  dfB <- dplyr::select(dfB, -dplyr::all_of(c(blocking.variables, fuzzy.string)))

  df <- dfA |>
    dplyr::left_join(df, by = 'string_A',
              relationship = 'many-to-many') |>
    dplyr::left_join(dfB, by = 'string_B',
              relationship = 'many-to-many')

  return(df)

}
