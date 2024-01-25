
<!-- README.md is generated from README.Rmd. Please edit that file -->

# fuzzylink

<!-- badges: start -->
<!-- badges: end -->

The goal of the `fuzzylink` package is to allow users to merge datasets
with fuzzy matches on identifying variables. Suppose, for example, you
have the following two datasets:

    #> ── Attaching core tidyverse packages ──────────────────────── tidyverse 2.0.0 ──
    #> ✔ dplyr     1.1.4     ✔ readr     2.1.4
    #> ✔ forcats   1.0.0     ✔ stringr   1.5.1
    #> ✔ ggplot2   3.4.4     ✔ tibble    3.2.1
    #> ✔ lubridate 1.9.3     ✔ tidyr     1.3.0
    #> ✔ purrr     1.0.2     
    #> ── Conflicts ────────────────────────────────────────── tidyverse_conflicts() ──
    #> ✖ dplyr::filter() masks stats::filter()
    #> ✖ dplyr::lag()    masks stats::lag()
    #> ℹ Use the conflicted package (<http://conflicted.r-lib.org/>) to force all conflicts to become errors

``` r
dfA
#> # A tibble: 3 × 2
#>   name                 age
#>   <chr>              <dbl>
#> 1 Timothy B. Ryan       28
#> 2 James J. Pointer      40
#> 3 Jennifer C. Reilly    32
dfB
#> # A tibble: 3 × 2
#>   name          hobby      
#>   <chr>         <chr>      
#> 1 Tim Ryan      Woodworking
#> 2 Jimmy Pointer Guitar     
#> 3 Jessica Renny Camping
```

We would like a procedure that correctly identifies that the first two
rows of `dfA` and `dfB` are likely to be matches, but not the third row.
The `fuzzylink()` function can do so.

``` r
df <- fuzzylink(dfA, dfB, by = 'name')
df
```

The procedure works by taking *pretrained text embeddings* from OpenAI’s
GPT-3 and constructing a measure of similarity for each pair of names.
These similarity metrics are then used as predictors in a statistical
model estimating the probability that two name pairs represent the same
entity.

## Installation

You can install the development version of `fuzzylink` from
[GitHub](https://github.com/) with:

``` r
# install.packages("devtools")
devtools::install_github("joeornstein/fuzzylink")
```

## Example

This is a basic example which shows you how to solve a common problem:

``` r
library(fuzzylink)
## basic example code
```

Under the hood, the `fuzzylink()` function takes the following steps:

### Step 1: Embedding

``` r
strings_A <- unique(dfA$name)
strings_B <- unique(dfB$name)
embeddings <- get_embeddings(unique(c(strings_A, strings_B)))

dim(embeddings)
#> [1]    6 1536
rownames(embeddings)
#> [1] "Timothy B. Ryan"    "James J. Pointer"   "Jennifer C. Reilly"
#> [4] "Tim Ryan"           "Jimmy Pointer"      "Jessica Renny"
```

### Step 2: Similarity Scores

``` r
sim <- get_similarity_matrix(embeddings, strings_A, strings_B)
sim
#>                     Tim Ryan Jimmy Pointer Jessica Renny
#> Timothy B. Ryan    0.9412603     0.7919442     0.8174883
#> James J. Pointer   0.7941938     0.8974922     0.8085944
#> Jennifer C. Reilly 0.8277412     0.8144514     0.8787375
```

### Step 3: Create a Training Set

``` r
train <- get_training_set(sim)
train
#> # A tibble: 9 × 4
#>   A                  B               sim match
#>   <fct>              <fct>         <dbl> <chr>
#> 1 Timothy B. Ryan    Jimmy Pointer 0.792 No   
#> 2 James J. Pointer   Tim Ryan      0.794 Yes  
#> 3 James J. Pointer   Jessica Renny 0.809 No   
#> 4 Jennifer C. Reilly Jimmy Pointer 0.814 No   
#> 5 Timothy B. Ryan    Jessica Renny 0.817 No   
#> 6 Jennifer C. Reilly Tim Ryan      0.828 Yes  
#> 7 Jennifer C. Reilly Jessica Renny 0.879 No   
#> 8 James J. Pointer   Jimmy Pointer 0.897 Yes  
#> 9 Timothy B. Ryan    Tim Ryan      0.941 Yes
```

### Step 4: Fit Model

``` r
model <- glm(as.numeric(match == 'Yes') ~ sim, data = train)
train$match_prob <- predict(model, train, type = 'response')
train
#> # A tibble: 9 × 5
#>   A                  B               sim match match_prob
#>   <fct>              <fct>         <dbl> <chr>      <dbl>
#> 1 Timothy B. Ryan    Jimmy Pointer 0.792 No         0.228
#> 2 James J. Pointer   Tim Ryan      0.794 Yes        0.238
#> 3 James J. Pointer   Jessica Renny 0.809 No         0.301
#> 4 Jennifer C. Reilly Jimmy Pointer 0.814 No         0.327
#> 5 Timothy B. Ryan    Jessica Renny 0.817 No         0.340
#> 6 Jennifer C. Reilly Tim Ryan      0.828 Yes        0.385
#> 7 Jennifer C. Reilly Jessica Renny 0.879 No         0.609
#> 8 James J. Pointer   Jimmy Pointer 0.897 Yes        0.691
#> 9 Timothy B. Ryan    Tim Ryan      0.941 Yes        0.883
```

### Step 5: Create Matched Dataset

``` r
df <- sim |> 
  reshape2::melt() |> 
  set_names(c('A', 'B', 'sim'))

df$match_probability <- predict(model, df, type = 'response')

df |> 
  filter(match_probability > 0.65) |> 
  select(-sim) |> 
  right_join(dfA, by = c('A' = 'name')) |> 
  left_join(dfB, by = c('B' = 'name'))
#>                    A             B match_probability age       hobby
#> 1    Timothy B. Ryan      Tim Ryan         0.8828290  28 Woodworking
#> 2   James J. Pointer Jimmy Pointer         0.6908369  40      Guitar
#> 3 Jennifer C. Reilly          <NA>                NA  32        <NA>
```
