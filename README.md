
<!-- README.md is generated from README.Rmd. Please edit that file -->

# fuzzylink

<!-- badges: start -->

<!-- badges: end -->

The R package `fuzzylink` implements a probabilistic record linkage
procedure proposed in [Ornstein
(2025)](https://doi.org/10.1017/pan.2025.10016). This method allows
users to merge datasets with fuzzy matches on a key identifying
variable. Suppose, for example, you have the following two datasets:

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
    #> 1      Joe Biden    Joseph Robinette Biden 0.7661285 0.7673401   Yes
    #> 2   Donald Trump        Donald John Trump  0.8388663 0.9333333   Yes
    #> 3   Barack Obama      Barack Hussein Obama 0.8457284 0.9200000   Yes
    #> 4 George W. Bush        George Walker Bush 0.8445312 0.9301587   Yes
    #> 5   Bill Clinton William Jefferson Clinton 0.8730800 0.5788889   Yes
    #>   match_probability age      hobby
    #> 1                 1  81   Football
    #> 2                 1  77       Golf
    #> 3                 1  62 Basketball
    #> 4                 1  77    Reading
    #> 5                 1  77  Saxophone

The procedure works by using *pretrained text embeddings* to construct a
measure of similarity for each pair of names. These similarity measures
are then used as predictors in a statistical model to estimate the
probability that two name pairs represent the same entity. See [Ornstein
(2025)](https://doi.org/10.1017/pan.2025.10016) for technical details.

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
  language model prompt when training the statistical model.

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
    #> 1      Joe Biden    Joseph Robinette Biden 0.7660565     1 0.7673401   Yes
    #> 2   Barack Obama      Barack Hussein Obama 0.8457001     3 0.9200000   Yes
    #> 3 George W. Bush        George Walker Bush 0.8447794     4 0.9301587   Yes
    #> 4   Bill Clinton William Jefferson Clinton 0.8732311     5 0.5788889   Yes
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

## A Note On Cost

Because the `fuzzylink()` function makes several calls to the OpenAI
API—which charges a per-token fee—there is a monetary cost associated
with each use. Based on the package defaults and API pricing as of
August 2025, here is a table of approximate costs for merging datasets
of various sizes.

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
than it is to retrieve embeddings. With particularly large datasets, one
can reduce costs by using GPT-3.5 (`model = 'gpt-3.5-turbo-instruct'`),
blocking (`blocking.variables`), or reducing the maximum number of pairs
labeled by the LLM (`max_labels`).
