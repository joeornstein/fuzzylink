# training dataset of hand-coded organization names is from Kaufman & Klevs (2022)

train <- read.csv('evaluation_set.csv')

library(ranger)
library(stringdist)
library(openai)

# compute string distance metrics
train$jw = RecordLinkage::jarowinkler(str1 = train$amicus,
                                     str2 = train$bonica,
                                     r = 0.1)

train$jaccard <- stringdist::stringsim(train$amicus,
                                      train$bonica,
                                      method = 'jaccard')

train$cosine <- stringdist::stringsim(train$amicus,
                                     train$bonica,
                                     method = 'cosine')

train$levenshtein <- stringdist::stringdist(train$amicus,
                                           train$bonica,
                                           method = 'lv')

train$lcsstr <- stringdist::stringdist(train$amicus,
                                      train$bonica,
                                      method = 'lcs')



# create list of unique strings from each list of organizations
organization_names <- unique(c(train$amicus, train$bonica))

# get text embeddings
embeddings <- get_embeddings(organization_names)

# compute cosine similarity for each pair in train
train$embedding_score <- NA
for(i in 1:nrow(train)){
  print(i)
  train$embedding_score[i] <- dot(embeddings[[train$amicus[i]]],
                                  embeddings[[train$bonica[i]]])
}

# fit random forest model
base_model <- ranger(label ~ embedding_score + jw + jaccard + cosine + levenshtein + lcsstr,
                     data = train,
                     importance = 'impurity')

save(train, file = 'train.rda')

usethis::use_data(base_model)

