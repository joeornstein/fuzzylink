
<!-- README.md is generated from README.Rmd. Please edit that file -->

# fuzzylink

<!-- badges: start -->
<!-- badges: end -->

The goal of the `fuzzylink` package is to allow users to merge datasets
with fuzzy matches on identifying variables. Suppose, for example, you
have the following two datasets:

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

The procedure works by using *pretrained text embeddings* from OpenAI’s
GPT-3 to construct a measure of similarity for each pair of names. These
similarity measures are then used as predictors in a statistical model
to estimate the probability that two name pairs represent the same
entity. In the guide below, I will walk step-by-step through what’s
going on under the hood when we call the `fuzzylink()` function.

## Installation

You can install the development version of `fuzzylink` from
[GitHub](https://github.com/) with:

``` r
# install.packages("devtools")
devtools::install_github("joeornstein/fuzzylink")
```

You will also need an account with OpenAI. You can sign up
[here](https://beta.openai.com/signup), after which you’ll need generate
an API key [here](https://platform.openai.com/account/api-keys). I
recommend adding this API key as a variable in your operating system
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
1,536-dimensional vector called an *embedding*. You can learn more about
embeddings
[here](https://platform.openai.com/docs/guides/embeddings/embedding-models),
but the basic idea is to represent text using a vector of real-valued
numbers, such that vectors that are close to one another in space have
similar meaning.

``` r
library(fuzzylink)

strings_A <- unique(dfA$name)
strings_B <- unique(dfB$name)
embeddings <- get_embeddings(unique(c(strings_A, strings_B)))

dim(embeddings)
#> [1]    6 3072
rownames(embeddings)
#> [1] "Timothy B. Ryan"    "James J. Pointer"   "Jennifer C. Reilly"
#> [4] "Tim Ryan"           "Jimmy Pointer"      "Jessica Renny"
```

### Step 2: Similarity Scores

``` r
sim <- get_similarity_matrix(embeddings, strings_A, strings_B)
sim
#>                     Tim Ryan Jimmy Pointer Jessica Renny
#> Timothy B. Ryan    0.6916803     0.2901356     0.2536269
#> James J. Pointer   0.2539563     0.7673960     0.2220962
#> Jennifer C. Reilly 0.3384956     0.1969335     0.4228717
```

### Step 3: Create a Training Set

``` r
train <- get_training_set(sim)
train
#> # A tibble: 9 × 4
#>   A                  B               sim match
#>   <fct>              <fct>         <dbl> <chr>
#> 1 Jennifer C. Reilly Jimmy Pointer 0.197 No   
#> 2 James J. Pointer   Jessica Renny 0.222 No   
#> 3 James J. Pointer   Tim Ryan      0.254 Yes  
#> 4 Timothy B. Ryan    Jessica Renny 0.254 No   
#> 5 Timothy B. Ryan    Jimmy Pointer 0.290 Yes  
#> 6 Jennifer C. Reilly Tim Ryan      0.338 No   
#> 7 Jennifer C. Reilly Jessica Renny 0.423 No   
#> 8 Timothy B. Ryan    Tim Ryan      0.692 Yes  
#> 9 James J. Pointer   Jimmy Pointer 0.767 Yes
```

### Step 4: Fit Model

``` r
model <- glm(as.numeric(match == 'Yes') ~ sim, data = train)
train$match_prob <- predict(model, train, type = 'response')
train
#> # A tibble: 9 × 5
#>   A                  B               sim match match_prob
#>   <fct>              <fct>         <dbl> <chr>      <dbl>
#> 1 Jennifer C. Reilly Jimmy Pointer 0.197 No         0.192
#> 2 James J. Pointer   Jessica Renny 0.222 No         0.227
#> 3 James J. Pointer   Tim Ryan      0.254 Yes        0.270
#> 4 Timothy B. Ryan    Jessica Renny 0.254 No         0.270
#> 5 Timothy B. Ryan    Jimmy Pointer 0.290 Yes        0.319
#> 6 Jennifer C. Reilly Tim Ryan      0.338 No         0.385
#> 7 Jennifer C. Reilly Jessica Renny 0.423 No         0.500
#> 8 Timothy B. Ryan    Tim Ryan      0.692 Yes        0.866
#> 9 James J. Pointer   Jimmy Pointer 0.767 Yes        0.969
```

### Step 5: Create Matched Dataset

``` r
df <- sim |> 
  reshape2::melt() |> 
  set_names(c('A', 'B', 'sim'))

df$match_probability <- predict(model, df, type = 'response')

df |> 
  filter(match_probability > 0.5) |> 
  right_join(dfA, by = c('A' = 'name')) |> 
  left_join(dfB, by = c('B' = 'name'))
#>                    A             B       sim match_probability age       hobby
#> 1    Timothy B. Ryan      Tim Ryan 0.6916803         0.8663648  28 Woodworking
#> 2   James J. Pointer Jimmy Pointer 0.7673960         0.9694929  40      Guitar
#> 3 Jennifer C. Reilly Jessica Renny 0.4228717         0.5002357  32     Camping
```
