## Resubmission

This is a resubmission. Changes since 0.3.1:

* `fuzzylink()` and `check_match()` now support Anthropic Claude and Mistral
  models in addition to OpenAI, via the `ellmer` package.
* Updated default model to `gpt-5.2`.
* Fixed a bug in `check_match()` where verbose LLM responses (e.g. from Claude)
  could cause match labels to be parsed incorrectly. Labels are now normalized
  by extracting the first word of each response.
* Active learning loop now reports rolling gradient and stopping threshold in
  real time.
* Fixed a potential edge case in the internal `get_cutoff()` function where NaN
  F1 scores could cause silent failures on datasets with no true matches.
* Removed unused internal functions (`get_training_set()`, `hand_label()`,
  `estimate_tokens()`).

## R CMD check results

0 errors | 0 warnings | 0 notes
