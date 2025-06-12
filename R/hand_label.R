#' Hand Label A Dataset
#'
#' @description
#' This function prompts the user to manually label a set of name pairs through the `R` console.
#'
#' @param df A dataframe with a column called `A` and a column called `B`
#'
#' @return A labeled dataframe (`match` column)
#'
hand_label <- function(df){

  df$match <- NA

  for(i in 1:nrow(df)){

    message(paste0('\n\n\n\n\n\n\n\n\nDo these match? (1=Yes, 0=No)\n',
               df$A[i], '\n',
               df$B[i]))

    x <- readline()

    if(!(x %in% c('0','1'))) break

    df$match[i] <- ifelse(x == '1', 'match', 'mismatch')

  }

  # remove the unlabeled rows
  df <- subset(df, !is.na(match))

  return(df)

}
