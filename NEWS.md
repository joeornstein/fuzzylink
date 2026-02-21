# fuzzylink 0.4.0

* `fuzzylink()` now supports Anthropic Claude (e.g. `'claude-sonnet-4-5-20250929'`) and Mistral (e.g. `'mistral-large-latest'`) models in addition to OpenAI.
* Updated default model to `gpt-5.2`.
* Active learning loop now reports rolling gradient and stopping threshold in real time.
* Fixed a potential edge case in `get_cutoff()` where NaN F1 scores could cause silent failures on datasets with no true matches.
* Removed unused internal functions (`get_training_set()`, `hand_label()`, `estimate_tokens()`).
* Fixed a bug in `check_match()` where verbose LLM responses (e.g. from Claude or Mistral) could cause match labels to be parsed incorrectly. Labels are now normalized by extracting the first word of each response.

# fuzzylink 0.3.1

* Patched `check_match()` to return labels from legacy OpenAI models.

# fuzzylink 0.3.0

* API calls for language model prompts are now passed through the `ellmer` package, improving speed, error handling, and rate limits.

# fuzzylink 0.2.5

* Updated documentation with publication DOI

# fuzzylink 0.2.4

* Patched a bug introduced in 0.2.3, crashing the algorithm when there are no exact matches.

# fuzzylink 0.2.3

* The algorithm now omits exact matches from the training set during the active learning loop. This avoids the superfluous step of labeling exact matches with the language model, and patches a bug wherein too many exact matches caused the loop to terminate prematurely.

# fuzzylink 0.2.2

* The algorithm now drops missing observations from `dfA` and `dfB` with a warning.

# fuzzylink 0.2.1

* Updated package documentation and console messages. 

# fuzzylink 0.2.0

* Initial CRAN submission.
