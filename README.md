
<!-- README.md is generated from README.Rmd. Please edit that file -->

# fuzzylink

<!-- badges: start -->
<!-- badges: end -->

The R package `fuzzylink` implements a probabilistic record linkage
procedure proposed in [Ornstein
(2025)](https://joeornstein.github.io/publications/fuzzylink.pdf). This
method allows users to merge datasets with fuzzy matches on a key
identifying variable. Suppose, for example, you have the following two
datasets:

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

    #>                A                         B       sim        jw match
    #> 1      Joe Biden    Joseph Robinette Biden 0.7661541 0.7673401   Yes
    #> 2   Donald Trump        Donald John Trump  0.8388798 0.9333333   Yes
    #> 3   Barack Obama      Barack Hussein Obama 0.8456864 0.9200000   Yes
    #> 4 George W. Bush        George Walker Bush 0.8447156 0.9301587   Yes
    #> 5   Bill Clinton William Jefferson Clinton 0.8732390 0.5788889   Yes
    #>   match_probability age      hobby
    #> 1                 1  81   Football
    #> 2                 1  77       Golf
    #> 3                 1  62 Basketball
    #> 4                 1  77    Reading
    #> 5                 1  77  Saxophone

The procedure works by using *pretrained text embeddings* to construct a
measure of similarity for each pair of names. These similarity measures
are then used as predictors in a statistical model to estimate the
probability that two name pairs represent the same entity. In the guide
below, I will walk step-by-step through what’s happening under the hood
when we call the `fuzzylink()` function. See [Ornstein
(2025)](https://joeornstein.github.io/publications/fuzzylink.pdf) for
technical details.

## Installation

You can install `fuzzylink` from CRAN with:

``` r
install.packages('fuzzylink')
```

Or you can install the development version from
[GitHub](https://github.com/) with:

``` r
# install.packages("devtools")
devtools::install_github("joeornstein/fuzzylink")
```

You will also need API access to a large language model (LLM). The
`fuzzylink` package currently supports both OpenAI and Mistral LLMs, but
will default to using OpenAI unless specified by the user.

### OpenAI

You will need to create a developer account with OpenAI, and create an
API key through their developer platform. For best performance, I
**strongly recommend** purchasing at least \$5 in API credits, which
will significantly increase your API rate limits.

Once your account is created, copy-paste your API key into the following
line of R code.

    library(fuzzylink)

    openai_api_key('YOUR API KEY GOES HERE', install = TRUE)

### Mistral

If you prefer to use language models from Mistral, you can sign up for
an account [here](https://mistral.ai/). As of writing, Mistral requires
you to purchase prepaid credits before you can access their language
models through the API.

Once you have a paid account, you can create an API key
[here](https://console.mistral.ai/api-keys/), and copy-paste the API key
into the following line of R code:

    library(fuzzylink)

    mistral_api_key('YOUR API KEY GOES HERE', install = TRUE)

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

- The `instructions` argument should be a string containing additional
  instructions to include in the language model prompt. Format these
  like you would format instructions to a human research assistant,
  including any relevant information that you think would help the model
  make accurate classifications.

- The `model` argument specifies which language model to prompt. It
  defaults to OpenAI’s ‘gpt-4o’, but for simpler problems, you can try
  ‘gpt-3.5-turbo-instruct’, which will significantly reduce cost and
  runtime. If you prefer an open-source language model, try
  ‘open-mixtral-8x22b’.

- The `embedding_model` argument specifies which pretrained text
  embeddings to use when modeling match probability. It defaults to
  OpenAI’s ‘text-embedding-3-large’, but will also accept
  ‘text-embedding-3-small’ or Mistral’s ‘mistral-embed’.

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
df
```

    #>                A                         B       sim block        jw match
    #> 1      Joe Biden    Joseph Robinette Biden 0.7661946     1 0.7673401   Yes
    #> 2   Barack Obama      Barack Hussein Obama 0.8457494     3 0.9200000   Yes
    #> 3 George W. Bush        George Walker Bush 0.8446584     4 0.9301587   Yes
    #> 4   Bill Clinton William Jefferson Clinton 0.8732175     5 0.5788889   Yes
    #> 5   Donald Trump                      <NA>        NA    NA        NA  <NA>
    #>   match_probability    state age      hobby
    #> 1                 1 Delaware  81   Football
    #> 2                 1 Illinois  62 Basketball
    #> 3                 1    Texas  77    Reading
    #> 4                 1 Arkansas  77  Saxophone
    #> 5                NA New York  77       <NA>

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
256-dimensional vector called an *embedding*. The basic idea is to
represent text using a vector of real-valued numbers, such that two
vectors close to one another in space have similar meanings.

``` r
library(tidyverse)

strings_A <- unique(dfA$name)
strings_B <- unique(dfB$name)
all_strings <- unique( c(strings_A, strings_B) )
embeddings <- get_embeddings(all_strings)

dim(embeddings)
#> [1]  13 256
head(embeddings['Bill Clinton',])
#> [1]  0.08017124  0.07613955 -0.01628375 -0.07957640 -0.09821473 -0.04966916
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
#> Joe Biden                   0.7661285          0.5531430            0.5262673
#> Donald Trump                0.4315020          0.8388663            0.4477866
#> Barack Obama                0.5170260          0.4756605            0.8457284
#> George W. Bush              0.4940132          0.4877906            0.5680539
#> Bill Clinton                0.4885266          0.5039268            0.5174566
#>                George Walker Bush William Jefferson Clinton
#> Joe Biden               0.5029197                 0.5407695
#> Donald Trump            0.4805455                 0.4463142
#> Barack Obama            0.4851386                 0.5128536
#> George W. Bush          0.8445312                 0.6113071
#> Bill Clinton            0.6231014                 0.8730800
#>                George Herbert Walker Bush Biff Tannen Joe Riley
#> Joe Biden                       0.4659178   0.3023257 0.3797427
#> Donald Trump                    0.3943302   0.3437970 0.2331483
#> Barack Obama                    0.4241720   0.2545664 0.3481560
#> George W. Bush                  0.7333917   0.2458818 0.3609610
#> Bill Clinton                    0.5950848   0.2213021 0.3196283
```

### Step 3: Create a Training Set

We would like to use those cosine similarity scores to predict whether
two names refer to the same entity. In order to do that, we need to
first create a labeled dataset to fit a statistical model. To do so,
`fuzzylink()` selects a sample of name pairs and labels them using the
following prompt to GPT-4o (brackets denote input variables).

    Decide if the following two names refer to the same {record_type}. {instructions} Think carefully. Respond "Yes" or "No".'

    Name A: {A}
    Name B: {B}
    Response:

``` r
# convert the distance matrix to a dataframe
df <- reshape2::melt(sim)
names(df) <- c('A', 'B', 'sim')
# add lexical similarity
df$jw <- stringdist::stringsim(tolower(df$A), tolower(df$B),
                                 method = 'jw', p = 0.1)

# label training set
df$match <- check_match(
    df$A,
    df$B,
    record_type = 'person'
  )

df
#>                 A                          B       sim        jw match
#> 1       Joe Biden     Joseph Robinette Biden 0.7661285 0.7673401   Yes
#> 2    Donald Trump     Joseph Robinette Biden 0.4315020 0.4797980    No
#> 3    Barack Obama     Joseph Robinette Biden 0.5170260 0.4146465    No
#> 4  George W. Bush     Joseph Robinette Biden 0.4940132 0.5543531    No
#> 5    Bill Clinton     Joseph Robinette Biden 0.4885266 0.4909812    No
#> 6       Joe Biden         Donald John Trump  0.5531430 0.4777778    No
#> 7    Donald Trump         Donald John Trump  0.8388663 0.9333333   Yes
#> 8    Barack Obama         Donald John Trump  0.4756605 0.3935185    No
#> 9  George W. Bush         Donald John Trump  0.4877906 0.4449735    No
#> 10   Bill Clinton         Donald John Trump  0.5039268 0.4444444    No
#> 11      Joe Biden       Barack Hussein Obama 0.5262673 0.5351852    No
#> 12   Donald Trump       Barack Hussein Obama 0.4477866 0.4888889    No
#> 13   Barack Obama       Barack Hussein Obama 0.8457284 0.9200000   Yes
#> 14 George W. Bush       Barack Hussein Obama 0.5680539 0.5113095    No
#> 15   Bill Clinton       Barack Hussein Obama 0.5174566 0.5900000    No
#> 16      Joe Biden         George Walker Bush 0.5029197 0.3888889    No
#> 17   Donald Trump         George Walker Bush 0.4805455 0.5000000    No
#> 18   Barack Obama         George Walker Bush 0.4851386 0.5000000    No
#> 19 George W. Bush         George Walker Bush 0.8445312 0.9301587   Yes
#> 20   Bill Clinton         George Walker Bush 0.6231014 0.3611111    No
#> 21      Joe Biden  William Jefferson Clinton 0.5407695 0.5244444    No
#> 22   Donald Trump  William Jefferson Clinton 0.4463142 0.3722222    No
#> 23   Barack Obama  William Jefferson Clinton 0.5128536 0.4388889    No
#> 24 George W. Bush  William Jefferson Clinton 0.6113071 0.4504762    No
#> 25   Bill Clinton  William Jefferson Clinton 0.8730800 0.5788889   Yes
#> 26      Joe Biden George Herbert Walker Bush 0.4659178 0.4159544    No
#> 27   Donald Trump George Herbert Walker Bush 0.3943302 0.3707265    No
#> 28   Barack Obama George Herbert Walker Bush 0.4241720 0.4696581    No
#> 29 George W. Bush George Herbert Walker Bush 0.7333917 0.8395604    No
#> 30   Bill Clinton George Herbert Walker Bush 0.5950848 0.4363248    No
#> 31      Joe Biden                Biff Tannen 0.3023257 0.5033670    No
#> 32   Donald Trump                Biff Tannen 0.3437970 0.3989899    No
#> 33   Barack Obama                Biff Tannen 0.2545664 0.4568182    No
#> 34 George W. Bush                Biff Tannen 0.2458818 0.2748918    No
#> 35   Bill Clinton                Biff Tannen 0.2213021 0.7010101    No
#> 36      Joe Biden                  Joe Riley 0.3797427 0.8666667    No
#> 37   Donald Trump                  Joe Riley 0.2331483 0.4675926    No
#> 38   Barack Obama                  Joe Riley 0.3481560 0.2962963    No
#> 39 George W. Bush                  Joe Riley 0.3609610 0.4708995    No
#> 40   Bill Clinton                  Joe Riley 0.3196283 0.3611111    No
```

### Step 4: Fit Model

Next, we fit a logistic regression model on the labeled dataset, so that
we can map similarity scores onto a probability that two records match.
We use both the cosine similarity (`sim`) and a measure of lexical
similarity (`jw`) as predictors in this model.

``` r
model <- glm(as.numeric(match == 'Yes') ~ sim + jw, 
             data = df,
             family = 'binomial')
```

Append these predictions to each name pair in `dfA` and `dfB`.

``` r
# create a dataframe with each name pair
df$match_probability <- predict(model, df, type = 'response')

head(df)
#>                A                      B       sim        jw match
#> 1      Joe Biden Joseph Robinette Biden 0.7661285 0.7673401   Yes
#> 2   Donald Trump Joseph Robinette Biden 0.4315020 0.4797980    No
#> 3   Barack Obama Joseph Robinette Biden 0.5170260 0.4146465    No
#> 4 George W. Bush Joseph Robinette Biden 0.4940132 0.5543531    No
#> 5   Bill Clinton Joseph Robinette Biden 0.4885266 0.4909812    No
#> 6      Joe Biden     Donald John Trump  0.5531430 0.4777778    No
#>   match_probability
#> 1      1.000000e+00
#> 2      2.220446e-16
#> 3      2.220446e-16
#> 4      2.220446e-16
#> 5      2.220446e-16
#> 6      2.220446e-16
```

### Step 5: Labeling Uncertain Matches

We now have a dataset with estimated match probabilities for each pair
of records in `dfA` and `dfB`. We could stop there and just report the
match probabilities. But for larger datasets we can get better results
if we conduct a final validation step. For name pairs that the model is
uncertain about match status, we will use the GPT-4o prompt above to
check whether the name pair is a match. The `fuzzylink()` procedure uses
a variant of uncertainty sampling, so that name pairs with match
probability closest to 50% are most likely to be selected for labeling.
These labeled pairs are then added to the training dataset, the logistic
regression model is refined, and we repeat this process until there are
no matches left to validate. At that point, every record in `dfA` is
either linked to a record in `dfB` or there are no candidate matches in
`dfB` with an estimated probability higher than the threshold.

Note that, by default, the `fuzzylink()` function will label at most
10,000 name pairs during this step. This setting reduces both cost and
runtime (see “A Note On Cost” below), but users who wish to validate
more name pairs within larger datasets can increase the cap using the
`max_labels` argument.

### Step 6: Link Datasets

Finally, the function returns all name pairs if their match probability
is higher than a cutoff that balances false positive and false negatives
in the resulting dataset.

``` r
matches <- df |>
    # only keep pairs that have been labeled Yes or have a match probability > cutoff
    filter((match_probability > 0.1 & is.na(match)) | match == 'Yes') |>
    right_join(dfA, by = c('A' = 'name'),
               relationship = 'many-to-many') |>
    left_join(dfB, by = c('B' = 'name'),
                     relationship = 'many-to-many')

matches
#>                A                         B       sim        jw match
#> 1      Joe Biden    Joseph Robinette Biden 0.7661285 0.7673401   Yes
#> 2   Donald Trump        Donald John Trump  0.8388663 0.9333333   Yes
#> 3   Barack Obama      Barack Hussein Obama 0.8457284 0.9200000   Yes
#> 4 George W. Bush        George Walker Bush 0.8445312 0.9301587   Yes
#> 5   Bill Clinton William Jefferson Clinton 0.8730800 0.5788889   Yes
#>   match_probability  state.x age  state.y      hobby
#> 1                 1 Delaware  81 Delaware   Football
#> 2                 1 New York  77  Florida       Golf
#> 3                 1 Illinois  62 Illinois Basketball
#> 4                 1    Texas  77    Texas    Reading
#> 5                 1 Arkansas  77 Arkansas  Saxophone
```

## A Note On Cost

Because the `fuzzylink()` function makes several calls to the OpenAI
API—which charges a per-token fee—there is a monetary cost associated
with each use. Based on the package defaults and API pricing as of May
2025, here is a table of approximate costs for merging datasets of
various sizes.

| dfA       | dfB       | Approximate Cost (Default Settings) |
|:----------|:----------|:------------------------------------|
| 10        | 10        | \$0                                 |
| 10        | 100       | \$0                                 |
| 10        | 1,000     | \$0                                 |
| 10        | 10,000    | \$0.01                              |
| 10        | 100,000   | \$0.06                              |
| 10        | 1,000,000 | \$0.59                              |
| 100       | 10        | \$0.04                              |
| 100       | 100       | \$0.04                              |
| 100       | 1,000     | \$0.04                              |
| 100       | 10,000    | \$0.04                              |
| 100       | 100,000   | \$0.1                               |
| 100       | 1,000,000 | \$0.62                              |
| 1,000     | 10        | \$0.38                              |
| 1,000     | 100       | \$0.38                              |
| 1,000     | 1,000     | \$0.38                              |
| 1,000     | 10,000    | \$0.38                              |
| 1,000     | 100,000   | \$0.43                              |
| 1,000     | 1,000,000 | \$0.96                              |
| 10,000    | 10        | \$0.76                              |
| 10,000    | 100       | \$0.76                              |
| 10,000    | 1,000     | \$0.76                              |
| 10,000    | 10,000    | \$0.76                              |
| 10,000    | 100,000   | \$0.81                              |
| 10,000    | 1,000,000 | \$1.34                              |
| 100,000   | 10        | \$0.81                              |
| 100,000   | 100       | \$0.81                              |
| 100,000   | 1,000     | \$0.81                              |
| 100,000   | 10,000    | \$0.81                              |
| 100,000   | 100,000   | \$0.87                              |
| 100,000   | 1,000,000 | \$1.39                              |
| 1,000,000 | 10        | \$1.34                              |
| 1,000,000 | 100       | \$1.34                              |
| 1,000,000 | 1,000     | \$1.34                              |
| 1,000,000 | 10,000    | \$1.34                              |
| 1,000,000 | 100,000   | \$1.39                              |
| 1,000,000 | 1,000,000 | \$1.92                              |

Note that cost scales more quickly with the size of `dfA` than with
`dfB`, because it is more costly to complete LLM prompts for validation
than it is to retrieve embeddings. For particularly large datasets, one
can reduce costs by using GPT-3.5 (`model = 'gpt-3.5-turbo-instruct'`),
blocking (`blocking.variables`), or reducing the maximum number of pairs
labeled by the LLM (`max_labels`).
