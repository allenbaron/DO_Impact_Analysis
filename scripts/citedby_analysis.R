# Analysis of publications citing/using the Human Disease Ontology

# Setup -------------------------------------------------------------------
library(here)
library(tidyverse)
library(googlesheets4)
library(DO.utils)
library(hues)
library(ggrepel)



# SET output ---------------------------------------------------------
data_dir <- here::here("data/citedby/analysis")
graphics_dir <- here::here("graphics/citedby/analysis")


if (!dir.exists(data_dir)) {
  dir.create(data_dir, recursive = TRUE)
}

if (!dir.exists(graphics_dir)) {
  dir.create(graphics_dir, recursive = TRUE)
}



# Google sheet ------------------------------------------------------------
gs <- "1wG-d0wt-9YbwhQTaelxqRzbm4qnu11WDM2rv3THy5mY"
cb_sheet <- "cited_by"


cb_data <- googlesheets4::read_sheet(gs, sheet = cb_sheet, col_type = "c") %>%
  dplyr::mutate(
    dplyr::across(dplyr::matches("_(dt|date)$"), readr::parse_guess)
  )




# Plot cited by counts over time ------------------------------------------

g_cb <- DO.utils::plot_citedby(
  data_file = here::here("data/citedby/DO_citedby.csv"),
  out_dir = NULL,
  w = 8,
  h = 5.6
) +
  scale_fill_manual(
    name = "Type",
    values = hues::iwanthue(6),
    guide = ggplot2::guide_legend(reverse = TRUE)
  ) +
  theme_minimal() +
  labs(x = "Year", y = "Publications")

ggsave(
  plot = g_cb,
  filename = file.path(graphics_dir, "DO_cited_by_count.png"),
  width = 5,
  height = 3.5,
  dpi = 600
)


# Analysis: 2021-09 to 2022-09 --------------------------------------------

cb_tidy <- cb_data %>%
  dplyr::filter(
    pub_date > as.Date("2021-08-31"),
    pub_date < as.Date("2022-10-01")
  ) %>%
  dplyr::mutate(
    status = dplyr::case_when(
      !is.na(uses_DO) ~ "reviewed",
      stringr::str_detect(review, "paywall") ~ "inaccessible",
      TRUE ~ "not reviewed"
    ),
    uses_DO = dplyr::case_when(
      is.na(uses_DO) ~ NA_character_,
      stringr::str_detect(uses_DO, "^(minimal|supplement|indirect)") ~ "minor",
      TRUE ~ stringr::str_remove(uses_DO, ",.*")
    ),
    source = stringr::str_replace_all(source, "(ncbi_col)-[^ ;]", "\\1"),
    cites_DO = stringr::str_detect(source, "pubmed|scopus")
  )

# save review status
cb_tidy %>%
  dplyr::count(status, sort = TRUE) %>%
  readr::write_csv(file.path(data_dir, "status.csv"))

cb_reviewed <- cb_tidy %>%
  dplyr::filter(!status %in% c("inaccessible", "not reviewed"))

cb_reviewed %>%
  dplyr::count(uses_DO, sort = TRUE) %>%
  readr::write_csv(file.path(data_dir, "uses_DO.csv"))

cb_use <- cb_reviewed %>%
  dplyr::filter(uses_DO %in% c("yes", "minor"))

cb_use %>%
  DO.utils::count_delim(role, delim = "|", sort = TRUE) %>%
  readr::write_csv(file.path(data_dir, "roles.csv"))

cb_use %>%
  DO.utils::count_delim(research_area, delim = "|", sort = TRUE) %>%
  readr::write_csv(file.path(data_dir, "research_area.csv"))

# summarize use cases (all time)
use_case <- googlesheets4::read_sheet(
  gs,
  "DO_website_user_list",
  col_types = "c"
)

use_case %>%
  dplyr::filter(added == "TRUE") %>%
  dplyr::count(type) %>%
  readr::write_csv(file.path(data_dir, "use_cases-all_time.csv"))