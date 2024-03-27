
<!-- README.md is generated from README.Rmd. Please edit that file -->

# fuzzylink

<!-- badges: start -->
<!-- badges: end -->

The goal of the `fuzzylink` package is to allow users to merge datasets
with non-exact matches on a key identifying variable. Suppose, for
example, you have the following two datasets:

``` r
dfA
#>             name age
#> 1      Joe Biden  81
#> 2   Donald Trump  77
#> 3   Barack Obama  62
#> 4 George W. Bush  77
#> 5   Bill Clinton  77
dfB
#>                         name      hobby
#> 1     Joseph Robinette Biden   Football
#> 2         Donald John Trump        Golf
#> 3       Barack Hussein Obama Basketball
#> 4         George Walker Bush    Reading
#> 5  William Jefferson Clinton  Saxophone
#> 6 George Herbert Walker Bush  Skydiving
#> 7                Biff Tannen   Bullying
#> 8                  Joe Riley    Jogging
```

We would like a procedure that correctly identifies which records in
`dfB` are likely matches for each record in `dfA`. The `fuzzylink()`
function performs this record linkage with a single line of code.

    library(fuzzylink)
    df <- fuzzylink(dfA, dfB, by = 'name', record_type = 'person')
    df

    #>                A                         B       sim        jw
    #> 1      Joe Biden    Joseph Robinette Biden 0.7666187 0.7208273
    #> 2   Donald Trump        Donald John Trump  0.8389039 0.9333333
    #> 3   Barack Obama      Barack Hussein Obama 0.8456774 0.9200000
    #> 4 George W. Bush        George Walker Bush 0.8446634 0.9301587
    #> 5   Bill Clinton William Jefferson Clinton 0.8731945 0.5788889
    #>   match_probability validated age      hobby
    #> 1                 1       Yes  81   Football
    #> 2                 1       Yes  77       Golf
    #> 3                 1       Yes  62 Basketball
    #> 4                 1       Yes  77    Reading
    #> 5                 1       Yes  77  Saxophone

The procedure works by using *pretrained text embeddings* from OpenAI to
construct a measure of similarity for each pair of names. These
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
For best performance, I **strongly recommend** purchasing at least \$5
in API credits, which will significantly increase your API rate limits.

Once your account is created, copy-paste your API key into the following
line of R code.

    library(fuzzylink)

    openai_api_key('YOUR API KEY GOES HERE', install = TRUE)

Now you’re all set up!

## Example

Here is some code to reproduce the example above and make sure that
everything is working on your computer.

``` r
library(tidyverse)
library(fuzzylink)

dfA <- tribble(~name, ~age,
               'Joe Biden', 81,
               'Donald Trump', 77,
               'Barack Obama', 62,
               'George W. Bush', 77,
               'Bill Clinton', 77)

dfB <- tribble(~name, ~hobby,
               'Joseph Robinette Biden', 'Football',
               'Donald John Trump ', 'Golf',
               'Barack Hussein Obama', 'Basketball',
               'George Walker Bush', 'Reading',
               'William Jefferson Clinton', 'Saxophone',
               'George Herbert Walker Bush', 'Skydiving',
               'Biff Tannen', 'Bullying',
               'Joe Riley', 'Jogging')

df <- fuzzylink(dfA, dfB, by = 'name', record_type = 'person')

df
```

If the `df` object links all the presidents to their correct name in
`dfB`, everything is running smoothly! (Note that you may see a warning
from `glm.fit`. This is normal. The `stats` package gets suspicious
whenever the model fit is *too* perfect.)

### Arguments

- The `by` argument specifies the name of the fuzzy matching variable
  that you want to use to link records. The dataframes `dfA` and `dfB`
  must both have a column with this name.

- The `record_type` argument should be a singular noun describing the
  type of entity the `by` variable represents (e.g. “person”,
  “organization”, “interest group”, “city”). It is used as part of a
  language model prompt when training the statistical model (see Step 3
  below).

- The `model` argument specifies which OpenAI language model to prompt.
  It defaults to ‘gpt-3.5-turbo-instruct’, but for more difficult
  problems you can try ‘gpt-4’ or ‘gpt-4-turbo-preview’. Note that this
  will typically increase accuracy at the expsense of cost and runtime
  (see “A Note on Cost” below).

- Several parameters—including `p`, `k`, `embedding_dimensions`,
  `max_validations`, and `parallel`—are for advanced users who wish to
  customize the behavior of the algorithm. See the package documentation
  for more details.

- If there are any variables that must match *exactly* in order to link
  two records, you will want to include them in the `blocking.variables`
  argument. As a practical matter, I **strongly recommend** including
  blocking variables wherever possible, as they reduce the time and cost
  necessary to compute pairwise distance metrics. Suppose, for example,
  that our two illustrative datasets have a column called `state`, and
  we want to instruct `fuzzylink()` to only link people who live within
  the same state.

``` r
dfA <- tribble(~name, ~state, ~age,
               'Joe Biden', 'Delaware', 81,
               'Donald Trump', 'New York', 77,
               'Barack Obama', 'Illinois', 62,
               'George W. Bush', 'Texas', 77,
               'Bill Clinton', 'Arkansas', 77)

dfB <- tribble(~name, ~state, ~hobby,
               'Joseph Robinette Biden', 'Delaware', 'Football',
               'Donald John Trump ', 'Florida', 'Golf',
               'Barack Hussein Obama', 'Illinois', 'Basketball',
               'George Walker Bush', 'Texas', 'Reading',
               'William Jefferson Clinton', 'Arkansas', 'Saxophone',
               'George Herbert Walker Bush', 'Texas', 'Skydiving',
               'Biff Tannen', 'California', 'Bullying',
               'Joe Riley', 'South Carolina', 'Jogging')
```

``` r
df <- fuzzylink(dfA, dfB, 
                by = 'name',
                blocking.variables = 'state',
                record_type = 'person')
```

Note that because Donald Trump is listed under two different states—New
York in `dfA` and Florida in `dfB`–the `fuzzylink()` function no longer
returns a match for this record; all blocking variables must match
exactly before the function will link two records together. You can
specify as many blocking variables as needed by inputting their column
names as a vector.

The function returns a few additional columns along with the merged
dataframe. The column `match_probability` reports the model’s estimated
probability that the pair of records refer to the same entity. This
column should be used to aid in validation and can be used for computing
weighted averages if a record in `dfA` is matched to multiple records in
`dFB`. The columns `sim` and `jw` are string distance measures that the
model uses to predict whether two records are a match. And if you
included `blocking.variables` in the function call, there will be a
column called `block` with an ID variable denoting which block the
records belong to.

## Under The Hood

If you’d like to know more details about about how `fuzzylink()` works,
you can read the accompanying [research
paper](https://joeornstein.github.io/publications/fuzzylink.pdf). In
this section, we’ll take a look under the hood at the previous example,
walking through each of the steps that `fuzzylink()` takes to join the
two dataframes.

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
#> [1]  13 256
head(embeddings['Bill Clinton',])
#> [1]  0.08014997  0.07625150 -0.01624639 -0.07962137 -0.09838690 -0.04968902
```

### Step 2: Similarity Scores

Next, we compute the *cosine similarity* between each name pair. This is
our measure of how closely related two pieces of text are, where 0 is
completely unrelated and 1 is identical. If you include
`blocking.variables` in the call to `fuzzylink()`, the function will
only consider *within-block* name pairs (i.e. it will only compute
similarity scores for records with an exact match on each blocking
variable). I **strongly recommend** blocking wherever possible, as it
significantly reduces cost and speeds up computation.

``` r
sim <- get_similarity_matrix(embeddings, strings_A, strings_B)
sim
#>                Joseph Robinette Biden Donald John Trump  Barack Hussein Obama
#> Joe Biden                   0.7667334          0.5534320            0.5310559
#> Donald Trump                0.4316799          0.8389533            0.4479409
#> Barack Obama                0.5171574          0.4755891            0.8457114
#> George W. Bush              0.4941582          0.4877961            0.5680423
#> Bill Clinton                0.4886223          0.5038519            0.5174142
#>                George Walker Bush William Jefferson Clinton
#> Joe Biden               0.5096715                 0.5428332
#> Donald Trump            0.4807049                 0.4464548
#> Barack Obama            0.4853513                 0.5130095
#> George W. Bush          0.8447458                 0.6114500
#> Bill Clinton            0.6232799                 0.8732244
#>                George Herbert Walker Bush Biff Tannen Joe Riley
#> Joe Biden                       0.4703117   0.3014061 0.3906947
#> Donald Trump                    0.3944298   0.3437589 0.2330043
#> Barack Obama                    0.4242685   0.2544581 0.3481904
#> George W. Bush                  0.7334758   0.2457048 0.3605879
#> Bill Clinton                    0.5949622   0.2212121 0.3196084
```

### Step 3: Create a Training Set

We would like to use those cosine similarity scores to predict whether
two names refer to the same entity. In order to do that, we need to
first create a labeled dataset to fit a statistical model. The
`get_training_set()` function selects a sample of name pairs and labels
them using the following prompt to GPT-4 (brackets denote input
variables).

    Decide if the following two names refer to the same {record_type}. Misspellings, alternative names, and acronyms may be acceptable matches. Think carefully. Respond "Yes" or "No".'

    Name A: {A}
    Name B: {B}
    Response:

``` r
train <- get_training_set(list(sim), record_type = 'person')
train
#> # A tibble: 40 × 5
#>    A              B                              sim    jw match
#>    <fct>          <fct>                        <dbl> <dbl> <chr>
#>  1 Barack Obama   "George Herbert Walker Bush" 0.424 0.496 No   
#>  2 Joe Biden      "William Jefferson Clinton"  0.543 0.524 No   
#>  3 Bill Clinton   "George Herbert Walker Bush" 0.595 0.371 No   
#>  4 Joe Biden      "Joseph Robinette Biden"     0.767 0.721 Yes  
#>  5 Donald Trump   "Biff Tannen"                0.344 0.399 No   
#>  6 George W. Bush "William Jefferson Clinton"  0.611 0.450 No   
#>  7 Bill Clinton   "Donald John Trump "         0.504 0.465 No   
#>  8 Barack Obama   "George Walker Bush"         0.485 0.352 No   
#>  9 Joe Biden      "George Walker Bush"         0.510 0.389 No   
#> 10 George W. Bush "Joseph Robinette Biden"     0.494 0.520 No   
#> # ℹ 30 more rows
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
#>                A                      B       sim        jw match_probability
#> 1      Joe Biden Joseph Robinette Biden 0.7667334 0.7208273      1.000000e+00
#> 2   Donald Trump Joseph Robinette Biden 0.4316799 0.4217172      2.220446e-16
#> 3   Barack Obama Joseph Robinette Biden 0.5171574 0.4191919      2.220446e-16
#> 4 George W. Bush Joseph Robinette Biden 0.4941582 0.5200216      2.220446e-16
#> 5   Bill Clinton Joseph Robinette Biden 0.4886223 0.4797980      2.220446e-16
#> 6      Joe Biden     Donald John Trump  0.5534320 0.4444444      2.220446e-16
```

### Step 5: Validate Uncertain Matches

We now have a dataset with estimated match probabilities for each pair
of records in `dfA` and `dfB`. We could stop there and just report the
match probabilities. But for larger datasets we can get better results
if we conduct a final validation step. For each name pair within a range
of estimated match probabilities (by default 0.1 to 0.95), we will use
the GPT-4 prompt above to check whether the name pair is a match. These
labeled pairs are then added to the training dataset, the logistic
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
    # only keep pairs that have been validated or have a match probability > 0.1
    filter((match_probability > 0.1 & is.na(match)) | match == 'Yes') |>
    right_join(dfA, by = c('A' = 'name'),
               relationship = 'many-to-many') |>
    left_join(dfB, by = c('B' = 'name'),
                     relationship = 'many-to-many')

matches
#>                A                         B       sim        jw
#> 1      Joe Biden    Joseph Robinette Biden 0.7667334 0.7208273
#> 2   Donald Trump        Donald John Trump  0.8389533 0.9333333
#> 3   Barack Obama      Barack Hussein Obama 0.8457114 0.9200000
#> 4 George W. Bush        George Walker Bush 0.8447458 0.9301587
#> 5   Bill Clinton William Jefferson Clinton 0.8732244 0.5788889
#>   match_probability match  state.x age  state.y      hobby
#> 1                 1   Yes Delaware  81 Delaware   Football
#> 2                 1   Yes New York  77  Florida       Golf
#> 3                 1   Yes Illinois  62 Illinois Basketball
#> 4                 1   Yes    Texas  77    Texas    Reading
#> 5                 1   Yes Arkansas  77 Arkansas  Saxophone
```

## A Note On Cost

Because the `fuzzylink()` function makes several calls to the OpenAI
API—which charges a [per-token fee](https://openai.com/pricing)—there is
a monetary cost associated with each use. Based on the package defaults
and API pricing as of March 2024, here is a table of approximate costs
for merging datasets of various sizes.

| dfA       | dfB       | Approximate Cost (Default Settings) |
|:----------|:----------|:------------------------------------|
| 10        | 10        | \$0.02                              |
| 10        | 100       | \$0.02                              |
| 10        | 1,000     | \$0.02                              |
| 10        | 10,000    | \$0.02                              |
| 10        | 100,000   | \$0.07                              |
| 10        | 1,000,000 | \$0.6                               |
| 100       | 10        | \$0.15                              |
| 100       | 100       | \$0.15                              |
| 100       | 1,000     | \$0.15                              |
| 100       | 10,000    | \$0.16                              |
| 100       | 100,000   | \$0.21                              |
| 100       | 1,000,000 | \$0.74                              |
| 1,000     | 10        | \$1.5                               |
| 1,000     | 100       | \$1.5                               |
| 1,000     | 1,000     | \$1.5                               |
| 1,000     | 10,000    | \$1.51                              |
| 1,000     | 100,000   | \$1.56                              |
| 1,000     | 1,000,000 | \$2.09                              |
| 10,000    | 10        | \$15.01                             |
| 10,000    | 100       | \$15.01                             |
| 10,000    | 1,000     | \$15.01                             |
| 10,000    | 10,000    | \$15.01                             |
| 10,000    | 100,000   | \$15.06                             |
| 10,000    | 1,000,000 | \$15.59                             |
| 100,000   | 10        | \$30.06                             |
| 100,000   | 100       | \$30.06                             |
| 100,000   | 1,000     | \$30.06                             |
| 100,000   | 10,000    | \$30.06                             |
| 100,000   | 100,000   | \$30.12                             |
| 100,000   | 1,000,000 | \$30.64                             |
| 1,000,000 | 10        | \$30.59                             |
| 1,000,000 | 100       | \$30.59                             |
| 1,000,000 | 1,000     | \$30.59                             |
| 1,000,000 | 10,000    | \$30.59                             |
| 1,000,000 | 100,000   | \$30.64                             |
| 1,000,000 | 1,000,000 | \$31.17                             |

Note that cost scales more quickly with the size of `dfA` than with
`dfB`, because it is more costly to complete LLM prompts for validation
than it is to retrieve embeddings. For particularly large datasets, one
can reduce costs by using GPT-3.5 (`model = 'gpt-3.5-turbo'`), blocking
(`blocking.variables`), or reducing the maximum number of validations
(`max_validations`).
