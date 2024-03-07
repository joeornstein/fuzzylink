
<!-- README.md is generated from README.Rmd. Please edit that file -->

# fuzzylink

<!-- badges: start -->
<!-- badges: end -->

The goal of the `fuzzylink` package is to allow users to merge datasets
with non-exact matches on a key identifying variable. Suppose, for
example, you have the following two datasets:

``` r
dfA
#>                 name age
#> 1    Timothy B. Ryan  28
#> 2   James J. Pointer  40
#> 3 Jennifer C. Reilly  32
dfB
#>                name        hobby
#> 1          Tim Ryan  Woodworking
#> 2     Jimmy Pointer       Guitar
#> 3   Jessica Pointer      Camping
#> 4          Tom Ryan Making Pasta
#> 5       Jenny Romer  Salsa Dance
#> 6    Jeremy Creilly    Gardening
#> 7 Jennifer R. Riley       Acting
```

We would like a procedure that correctly identifies which records in
`dfB` are likely matches for each record in `dfA`. The `fuzzylink()`
function performs this record linkage with a single line of code.

    library(fuzzylink)
    df <- fuzzylink(dfA, dfB, by = 'name', record_type = 'person')
    df

    #>                    A             B       sim        jw match_probability
    #> 1    Timothy B. Ryan      Tim Ryan 0.7159697 0.7102778                 1
    #> 2   James J. Pointer Jimmy Pointer 0.7865519 0.8182692                 1
    #> 3 Jennifer C. Reilly          <NA>        NA        NA                NA
    #>   validated age       hobby
    #> 1       Yes  28 Woodworking
    #> 2       Yes  40      Guitar
    #> 3      <NA>  32        <NA>

The procedure works by using *pretrained text embeddings* from OpenAI’s
GPT-3 to construct a measure of similarity for each pair of names. These
similarity measures are then used as predictors in a statistical model
to estimate the probability that two name pairs represent the same
entity. In the guide below, I will walk step-by-step through what’s
happening under the hood when we call the `fuzzylink()` function.

## Installation

You can install the development version of `fuzzylink` from
[GitHub](https://github.com/) with:

``` r
# install.packages("devtools")
devtools::install_github("joeornstein/fuzzylink")
```

You will also need an account with OpenAI. You can sign up
[here](https://beta.openai.com/signup), after which you will need to
create an API key [here](https://platform.openai.com/account/api-keys).
For best performance, you may also want to provide credit card
information (this significantly boosts your API rate limit, even if
you’re not spending money).

Once your account is created, copy-paste your API key into the following
line of R code.

    library(fuzzylink)

    openai_api_key('YOUR API KEY GOES HERE', install = TRUE)

Now you’re all set up!

## Example

Let’s look at the example from the introduction, and walk through the
steps that `fuzzylink()` takes to join the two dataframes.

### Step 1: Embedding

First, the function encodes each unique string in `dfA` and `dfB` as a
256-dimensional vector called an *embedding*. You can learn more about
embeddings
[here](https://platform.openai.com/docs/guides/embeddings/embedding-models),
but the basic idea is to represent text using a vector of real-valued
numbers, such that two vectors close to one another in space have
similar meanings.

``` r
library(tidyverse)

strings_A <- unique(dfA$name)
strings_B <- unique(dfB$name)
all_strings <- unique( c(strings_A, strings_B) )
embeddings <- get_embeddings(all_strings)

dim(embeddings)
#> [1]  10 256
rownames(embeddings)
#>  [1] "Timothy B. Ryan"    "James J. Pointer"   "Jennifer C. Reilly"
#>  [4] "Tim Ryan"           "Jimmy Pointer"      "Jessica Pointer"   
#>  [7] "Tom Ryan"           "Jenny Romer"        "Jeremy Creilly"    
#> [10] "Jennifer R. Riley"
```

### Step 2: Similarity Scores

Next, we compute the *cosine similarity* between each name pair. This is
our measure of how closely related two pieces of text are, where 0 is
completely unrelated and 1 is identical. If you include
`blocking.variables` in the call to `fuzzylink()`, the function will
only consider *within-block* name pairs (i.e. it will only compute
similarity scores for records with an exact match on each blocking
variable). I highly recommend blocking wherever possible, as it
significantly reduces cost and speeds up computation.

``` r
sim <- get_similarity_matrix(embeddings, strings_A, strings_B)
sim
#>                     Tim Ryan Jimmy Pointer Jessica Pointer  Tom Ryan
#> Timothy B. Ryan    0.7159697     0.3469817       0.3030329 0.6437172
#> James J. Pointer   0.4271890     0.7865519       0.6706029 0.4177391
#> Jennifer C. Reilly 0.4244224     0.2518819       0.4040852 0.3175173
#>                    Jenny Romer Jeremy Creilly Jennifer R. Riley
#> Timothy B. Ryan      0.3723864      0.4715908         0.6091323
#> James J. Pointer     0.3486939      0.4728189         0.4957477
#> Jennifer C. Reilly   0.4293938      0.4983237         0.7468081
```

### Step 3: Create a Training Set

We would like to use those cosine similarity scores to predict whether
two names refer to the same entity. In order to do that, we need to
first create a labeled dataset to fit a statistical model. The
`get_training_set()` function selects a sample of name pairs and labels
them using the following prompt to GPT-3.5 (brackets denote input
variables).

    Decide if the following two names refer to the same {record_type}.

    Name A: {A}
    Name B: {B}
    Same {record_type} (Yes or No):

``` r
train <- get_training_set(list(sim), record_type = 'person')
train
#> # A tibble: 21 × 5
#>    A                  B                   sim    jw match
#>    <fct>              <fct>             <dbl> <dbl> <chr>
#>  1 Timothy B. Ryan    Tim Ryan          0.716 0.710 Yes  
#>  2 James J. Pointer   Jimmy Pointer     0.787 0.818 Yes  
#>  3 Timothy B. Ryan    Jennifer R. Riley 0.609 0.501 No   
#>  4 Jennifer C. Reilly Tom Ryan          0.318 0.347 No   
#>  5 Timothy B. Ryan    Jessica Pointer   0.303 0.428 No   
#>  6 James J. Pointer   Jessica Pointer   0.671 0.778 No   
#>  7 James J. Pointer   Jenny Romer       0.349 0.636 No   
#>  8 Timothy B. Ryan    Jimmy Pointer     0.347 0.549 No   
#>  9 Jennifer C. Reilly Jimmy Pointer     0.252 0.550 No   
#> 10 Timothy B. Ryan    Jenny Romer       0.372 0.429 No   
#> # ℹ 11 more rows
```

### Step 4: Fit Model

Next, we fit a logistic regression model on the `train` dataset, so that
we can map similarity scores onto a probability that two records match.
We use both the cosine similarity (`sim`) and a measure of lexical
similarity (`jw`) as predictors in this model.

``` r
model <- glm(as.numeric(match == 'Yes') ~ sim + jw, 
             data = train,
             family = 'binomial')
```

Append these predictions to each name pair in `dfA` and `dfB`.

``` r
# create a dataframe with each name pair
df <- sim |> 
  reshape2::melt() |> 
  set_names(c('A', 'B', 'sim')) |> 
  # compute lexical similarity measures for each name pair
  mutate(jw = stringdist::stringsim(A, B, method = 'jw', p = 0.1))

df$match_probability <- predict(model, df, type = 'response')

head(df)
#>                    A             B       sim        jw match_probability
#> 1    Timothy B. Ryan      Tim Ryan 0.7159697 0.7102778      1.000000e+00
#> 2   James J. Pointer      Tim Ryan 0.4271890 0.4583333      2.220446e-16
#> 3 Jennifer C. Reilly      Tim Ryan 0.4244224 0.4074074      2.220446e-16
#> 4    Timothy B. Ryan Jimmy Pointer 0.3469817 0.5493284      2.220446e-16
#> 5   James J. Pointer Jimmy Pointer 0.7865519 0.8182692      1.000000e+00
#> 6 Jennifer C. Reilly Jimmy Pointer 0.2518819 0.5496337      2.220446e-16
```

### Step 5: Validate Uncertain Matches

We now have a dataset with estimated match probabilities for each pair
of records in `dfA` and `dfB`. We could stop there and just report the
match probabilities. But for larger datasets we can get better results
if we conduct a final validation step. For each name pair within a range
of estimated match probabilities (by default 0.1 to 0.95), we will use
the GPT-3.5 prompt above to check whether the name pair is a match.
These labeled pairs are then added to the training dataset, the logistic
regression model is refined, and we repeat this process until there are
no matches left to validate. At that point, every record in `dfA` is
either linked to a record in `dfB` or there are no candidate matches in
`dfB` with an estimated probability higher than the threshold.

Note that, by default, the `fuzzylink()` function will validate at most
100,000 name pairs during this step. This setting reduces both cost and
runtime (see “A Note On Cost” below), but users who wish to validate
more name pairs within larger datasets can increase the cap using the
`max_validations` argument.

``` r
# find all unlabeled name pairs within a range of match probabilities
matches_to_validate <- df |> 
  left_join(train, by = c('A', 'B', 'sim')) |> 
  filter(match_probability > 0.1, 
         match_probability < 0.95,
         is.na(match))

while(nrow(matches_to_validate) > 0){
  
  # validate matches using LLM prompt
  matches_to_validate$match <- check_match(matches_to_validate$A,
                                         matches_to_validate$B)
  
  # append new labeled pairs to the train set
  train <- train |> 
    bind_rows(matches_to_validate |> 
              select(A,B,sim,match))
  
  # refine the model
  model <- glm(as.numeric(match == 'Yes') ~ sim + jw,
             data = train,
             family = 'binomial')
  
  # re-estimate match probabilities
  df$match_probability <- predict(model, df, type = 'response')
  
  # find all unlabeled name pairs within a range of match probabilities
  matches_to_validate <- df |> 
    left_join(train, by = c('A', 'B', 'sim')) |> 
    filter(match_probability > 0.1, 
           match_probability < 0.95,
           is.na(match))
  
}
```

### Step 6: Link Datasets

Finally, we take all name pairs whose match probability is higher than a
user-specified threshold and merge them into a single dataset.

``` r
matches <- df |>
    # join with match labels from the training set
    left_join(train |> select(A, B, match),
              by = c('A', 'B')) |>
    # only keep pairs that have been validated or have a match probability > 0.2
    filter((match_probability > 0.1 & is.na(match)) | match == 'Yes') |>
    right_join(dfA, by = c('A' = 'name'),
               relationship = 'many-to-many') |>
    left_join(dfB, by = c('B' = 'name'),
                     relationship = 'many-to-many')

matches
#>                    A             B       sim        jw match_probability match
#> 1    Timothy B. Ryan      Tim Ryan 0.7159697 0.7102778                 1   Yes
#> 2   James J. Pointer Jimmy Pointer 0.7865519 0.8182692                 1   Yes
#> 3 Jennifer C. Reilly          <NA>        NA        NA                NA  <NA>
#>   age       hobby
#> 1  28 Woodworking
#> 2  40      Guitar
#> 3  32        <NA>
```

## A Note On Cost

Because the `fuzzylink()` function makes several calls to the OpenAI
API—which charges a [per-token fee](https://openai.com/pricing)—there is
a monetary cost associated with each use. Based on the package defaults
and API pricing as of March 2024, here is a table of approximate costs
for merging datasets of various sizes.

| dfA       | dfB       | Approximate Cost (Default Settings) |
|:----------|:----------|:------------------------------------|
| 10        | 10        | \$0                                 |
| 10        | 100       | \$0                                 |
| 10        | 1,000     | \$0                                 |
| 10        | 10,000    | \$0.01                              |
| 10        | 100,000   | \$0.06                              |
| 10        | 1,000,000 | \$0.59                              |
| 100       | 10        | \$0.02                              |
| 100       | 100       | \$0.02                              |
| 100       | 1,000     | \$0.02                              |
| 100       | 10,000    | \$0.03                              |
| 100       | 100,000   | \$0.08                              |
| 100       | 1,000,000 | \$0.61                              |
| 1,000     | 10        | \$0.23                              |
| 1,000     | 100       | \$0.23                              |
| 1,000     | 1,000     | \$0.23                              |
| 1,000     | 10,000    | \$0.23                              |
| 1,000     | 100,000   | \$0.28                              |
| 1,000     | 1,000,000 | \$0.81                              |
| 10,000    | 10        | \$2.26                              |
| 10,000    | 100       | \$2.26                              |
| 10,000    | 1,000     | \$2.26                              |
| 10,000    | 10,000    | \$2.26                              |
| 10,000    | 100,000   | \$2.31                              |
| 10,000    | 1,000,000 | \$2.84                              |
| 100,000   | 10        | \$4.56                              |
| 100,000   | 100       | \$4.56                              |
| 100,000   | 1,000     | \$4.56                              |
| 100,000   | 10,000    | \$4.56                              |
| 100,000   | 100,000   | \$4.62                              |
| 100,000   | 1,000,000 | \$5.14                              |
| 1,000,000 | 10        | \$5.09                              |
| 1,000,000 | 100       | \$5.09                              |
| 1,000,000 | 1,000     | \$5.09                              |
| 1,000,000 | 10,000    | \$5.09                              |
| 1,000,000 | 100,000   | \$5.14                              |
| 1,000,000 | 1,000,000 | \$5.67                              |

Note that cost scales more quickly with the size of `dfA` than with
`dfB`, because it is more costly to complete LLM prompts for validation
than it is to retrieve embeddings. For particularly large datasets, one
can reduce costs by blocking and/or reducing the maximum number of
validations (`max_validations`).
