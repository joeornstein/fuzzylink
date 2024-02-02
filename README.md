
<!-- README.md is generated from README.Rmd. Please edit that file -->

# fuzzylink

<!-- badges: start -->
<!-- badges: end -->

The goal of the `fuzzylink` package is to allow users to merge datasets
with non-exact matches on key identifying variables. Suppose, for
example, you have the following two datasets:

``` r
dfA
#> # A tibble: 3 × 2
#>   name                 age
#>   <chr>              <dbl>
#> 1 Timothy B. Ryan       28
#> 2 James J. Pointer      40
#> 3 Jennifer C. Reilly    32
dfB
#> # A tibble: 7 × 2
#>   name              hobby       
#>   <chr>             <chr>       
#> 1 Tim Ryan          Woodworking 
#> 2 Jimmy Pointer     Guitar      
#> 3 Jessica Pointer   Camping     
#> 4 Tom Ryan          Making Pasta
#> 5 Jenny Romer       Salsa Dance 
#> 6 Jeremy Creilly    Gardening   
#> 7 Jennifer R. Riley Acting
```

We would like a procedure that correctly identifies which records in
`dfB` are likely matches for the records in `dfA`. The `fuzzylink()`
function performs this record linkage with a single line of code.

``` r
library(fuzzylink)
df <- fuzzylink(dfA, dfB, by = 'name', record_type = 'person')
#> Retrieving 10 embeddings (12:25:37 PM)
#> 
#> Computing similarity matrix (12:25:38 PM)
#> 
#> Labeling training set (12:25:38 PM)
#> 
#> Fitting model (12:25:39 PM)
#> 
#> Linking datasets (12:25:39 PM)
#> 
#> Done! (12:25:39 PM)
df
#>                    A             B       sim        jw match_probability match
#> 1    Timothy B. Ryan      Tim Ryan 0.6916803 0.7102778                 1   Yes
#> 2   James J. Pointer Jimmy Pointer 0.7673960 0.8182692                 1   Yes
#> 3 Jennifer C. Reilly          <NA>        NA        NA                NA  <NA>
#>   age       hobby
#> 1  28 Woodworking
#> 2  40      Guitar
#> 3  32        <NA>
```

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
[here](https://beta.openai.com/signup), after which you’ll need to
create an API key [here](https://platform.openai.com/account/api-keys).
I recommend adding this API key as a variable in your operating system
environment called `OPENAI_API_KEY`; that way you won’t risk leaking it
by hard-coding it into your R scripts. The `fuzzylink` package will
automatically look for your API key under that variable name, and will
prompt you to enter the API key manually if it can’t find one there. If
you’re unfamiliar with setting Environment Variables in your operating
system,
[here](https://dev.to/biplov/handling-passwords-and-secret-keys-using-environment-variables-2ei0)
are some helpful instructions. Note that you may need to restart your
computer after completing this step.

## Example

Let’s look at the example from the introduction, and walk through the
steps that `fuzzylink()` takes to join the two dataframes.

### Step 1: Embedding

First, the function encodes each unique string in `dfA` and `dfB` as a
3,072-dimensional vector called an *embedding*. You can learn more about
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
#> [1]   10 3072
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
#> Timothy B. Ryan    0.6916803     0.2901356       0.2357985 0.6336776
#> James J. Pointer   0.2539563     0.7673960       0.6228653 0.2874345
#> Jennifer C. Reilly 0.3384956     0.1969335       0.3453105 0.3374179
#>                    Jenny Romer Jeremy Creilly Jennifer R. Riley
#> Timothy B. Ryan      0.2270235      0.3754056         0.4666738
#> James J. Pointer     0.2129737      0.3148329         0.3629020
#> Jennifer C. Reilly   0.3929493      0.4237705         0.7162645
```

### Step 3: Create a Training Set

We would like to use those cosine similarity scores to predict whether
two names refer to the same entity. In order to do that, we need to
first create a labeled dataset that we can use to fit a statistical
model. The `get_training_set()` function selects a sample of name pairs
and labels them using the following prompt to GPT-3.5 (brackets denote
input variables).

    Decide if the following two names refer to the same {record_type}.

    Name A: {A}
    Name B: {B}
    Same {record_type} (Yes or No):

``` r
train <- get_training_set(sim, record_type = 'person')
train
#> # A tibble: 21 × 5
#>    A                B                   sim    jw match
#>    <fct>            <fct>             <dbl> <dbl> <chr>
#>  1 Timothy B. Ryan  Tim Ryan          0.692 0.710 Yes  
#>  2 Timothy B. Ryan  Tom Ryan          0.634 0.567 No   
#>  3 Timothy B. Ryan  Jennifer R. Riley 0.467 0.501 No   
#>  4 Timothy B. Ryan  Jeremy Creilly    0.375 0.517 No   
#>  5 Timothy B. Ryan  Jimmy Pointer     0.290 0.549 No   
#>  6 Timothy B. Ryan  Jessica Pointer   0.236 0.428 No   
#>  7 Timothy B. Ryan  Jenny Romer       0.227 0.429 No   
#>  8 James J. Pointer Jimmy Pointer     0.767 0.818 Yes  
#>  9 James J. Pointer Jessica Pointer   0.623 0.778 No   
#> 10 James J. Pointer Jennifer R. Riley 0.363 0.569 No   
#> # ℹ 11 more rows
```

### Step 4: Fit Model

Next, we fit a logistic regression model on the `train` dataset, so that
we can map similarity scores onto a probability that two records match.
We use both the cosine similarity (`sim`) and a lexical similarity
measure (`jw`) as predictors in this model.

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
#> 1    Timothy B. Ryan      Tim Ryan 0.6916803 0.7102778      1.000000e+00
#> 2   James J. Pointer      Tim Ryan 0.2539563 0.4583333      2.220446e-16
#> 3 Jennifer C. Reilly      Tim Ryan 0.3384956 0.4074074      2.220446e-16
#> 4    Timothy B. Ryan Jimmy Pointer 0.2901356 0.5493284      2.220446e-16
#> 5   James J. Pointer Jimmy Pointer 0.7673960 0.8182692      1.000000e+00
#> 6 Jennifer C. Reilly Jimmy Pointer 0.1969335 0.5496337      2.220446e-16
```

### Step 5: Validate Uncertain Matches

We now have a dataset with estimated match probabilities for each pair
of records in `dfA` and `dfB`. We could stop there, and just report the
match probabilities. But we can get better results if we conduct a final
validation step. For every name pair within a range of estimated match
probabilities (by default 0.2 to 0.9), we will use the GPT-3.5 prompt
above to check whether the name pair is a match or not. These labeled
pairs are then added to the training dataset, the logistic regression
model is refined, and we repeat this process until there are no matches
left to validate. At that point, every record in `dfA` is either linked
to a record in `dfB` or there are no candidate matches in `dfB` with an
estimated probability higher than the threshold.

``` r

# find all unlabeled name pairs within a range of match probabilities
matches_to_validate <- df |> 
  left_join(train, by = c('A', 'B', 'sim')) |> 
  filter(match_probability > 0.2, 
         match_probability < 0.9,
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
    filter(match_probability > 0.2, 
           match_probability < 0.9,
           is.na(match))
  
}
```

### Step 6: Link Datasets

Finally, we take all name pairs whose match probability is higher than a
given threshold and merge them into a single dataset.

``` r
matches <- df |>
    # join with match labels from the training set
    left_join(train |> select(A, B, match),
              by = c('A', 'B')) |>
    # only keep pairs that have been validated or have a match probability > 0.2
    filter((match_probability > 0.2 & is.na(match)) | match == 'Yes') |>
    right_join(dfA, by = c('A' = 'name'),
               relationship = 'many-to-many') |>
    left_join(dfB, by = c('B' = 'name'),
                     relationship = 'many-to-many')

matches
#>                    A             B       sim        jw match_probability match
#> 1    Timothy B. Ryan      Tim Ryan 0.6916803 0.7102778                 1   Yes
#> 2   James J. Pointer Jimmy Pointer 0.7673960 0.8182692                 1   Yes
#> 3 Jennifer C. Reilly          <NA>        NA        NA                NA  <NA>
#>   age       hobby
#> 1  28 Woodworking
#> 2  40      Guitar
#> 3  32        <NA>
```
