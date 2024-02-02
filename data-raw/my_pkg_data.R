## code to prepare `my_pkg_data` dataset goes here

library(tidyverse)


# convert lower case names to title case full names
dfA <- fastLink::dfA |>
  mutate(firstname = firstname |>
           as.character() |>
           replace_na('') |>
           str_to_title(),
         middlename = middlename |>
           as.character() |>
           replace_na('') |>
           str_to_title(),
         lastname = lastname |>
           as.character() |>
           replace_na('') |>
           str_to_title()) |>
  mutate(full_name = paste(firstname, middlename, lastname)) |>
  # replace double spaces with single spaces
  mutate(full_name = str_replace_all(full_name, '  ', ' ')) |>
  select(full_name, housenum, streetname, city, birthyear)

dfB <- fastLink::dfB |>
  mutate(firstname = firstname |>
           as.character() |>
           replace_na('') |>
           str_to_title(),
         middlename = middlename |>
           as.character() |>
           replace_na('') |>
           str_to_title(),
         lastname = lastname |>
           as.character() |>
           replace_na('') |>
           str_to_title()) |>
  mutate(full_name = paste(firstname, middlename, lastname)) |>
  # replace double spaces with single spaces
  mutate(full_name = str_replace_all(full_name, '  ', ' ')) |>
  select(full_name, housenum, streetname, city, birthyear)





usethis::use_data(my_pkg_data, overwrite = TRUE)
