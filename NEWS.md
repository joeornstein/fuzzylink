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
