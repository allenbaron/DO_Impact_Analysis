# Conducts literature searches for papers referring to the Human Disease
# Ontology by one of various identifiers.

# Setup -------------------------------------------------------------------

library(here)
library(tidyverse)
library(europepmc)
library(rentrez)
library(DO.utils)
library(ggupset)
library(ggvenn)
library(hues)


# Define Output Location & Searches ---------------------------------------
data_dir <- here::here("data/lit_search")
graphics_dir <- here::here("graphics/lit_search")

search_terms <- c(
  ns_id = 'doid',
  full_name = '"human disease ontology"',
  generic_name = '"disease ontology"',
  lynn_custom = '"disease ontology" NOT IDO',
  website = '"disease-ontology.org"',
  ncbo = 'bioportal.bioontology.org/ontologies/doid',
  embl_ols = 'ebi.ac.uk/ols/ontologies/doid',
  iri = 'purl.obolibrary.org/obo/doid.owl',
  iri_no_ext = 'purl.obolibrary.org/obo/doid' ,
  ontobee = 'ontobee.org/ontology/doid',
  github = 'github.com/diseaseontology/humandiseaseontology',
  do_wiki = 'do-wiki.nubic.northwestern.edu/do-wiki/index.php/main_page',
  sourceforge = 'sourceforge.net/p/diseaseontology',
  wikipedia = 'en.wikipedia.org/wiki/disease_ontology'
)



# Support -----------------------------------------------------------------
if (!dir.exists(data_dir)) {
  dir.create(data_dir, recursive = TRUE)
}

if (!dir.exists(graphics_dir)) {
  dir.create(graphics_dir, recursive = TRUE)
}

# make functions safe --> to keep code running if errors
search_pm_safely <- purrr::safely(DO.utils::search_pubmed)
search_pmc_safely <- purrr::safely(DO.utils::search_pmc)
search_epmc_safely <- purrr::safely(europepmc::epmc_search)

search_blank <- tibble::tibble(
  name = names(search_terms),
  term = search_terms
)


# GET Europe PMC search results -------------------------------------------
epmc_raw_file <- file.path(data_dir, "epmc_search_raw.RData")
epmc_df_file <- file.path(data_dir, "epmc_search_results.csv")

if (!file.exists(epmc_raw_file)) {
  # Using with synonyms to match web results
  epmc_res <- purrr::map(
    search_terms,
    ~ search_epmc_safely(.x, limit = 10000, synonym = TRUE)
  ) %>%
    purrr::set_names(names(search_terms)) %>%
    purrr::transpose() %>%
    purrr::simplify_all()

  save(epmc_res, file = epmc_raw_file)
} else {
  load(epmc_raw_file)
}

if (!file.exists(epmc_df_file)) {
  epmc_df <- dplyr::bind_rows(epmc_res$result, .id = "search_id") %>%
    dplyr::mutate(pmid = as.character(pmid))
  readr::write_csv(epmc_df, epmc_df_file)
} else {
  epmc_df <- readr::read_csv(epmc_df_file)
}


# GET PubMed search results -----------------------------------------------
pm_raw_file <- file.path(data_dir, "pubmed_search_raw.RData")
pm_id_raw_file <- file.path(data_dir, "pm_search_raw-IDs.RData")

pm_df_file <- file.path(data_dir, "pubmed_search_results.csv")

if (!file.exists(pm_raw_file)) {
  # pubmed splits URLs replacing / with AND (probably close to the same in essence)
  pm_res <- purrr::map(
    search_terms,
    ~ search_pm_safely(.x, retmax = 10000)
  ) %>%
    purrr::set_names(names(search_terms)) %>%
    purrr::transpose() %>%
    purrr::simplify_all()

  save(pm_res, file = pm_raw_file)
} else {
  load(pm_raw_file)
}

# Get more IDs for matching
if (!file.exists(pm_id_raw_file)) {
  pm_uniq <- purrr::map(pm_res$result, DO.utils::extract_pmid) %>%
    unlist() %>%
    unique()

  pm_id2 <- DO.utils::batch_id_converter(pm_uniq) %>%
    tibble::as_tibble()

  save(pm_id2, file = pm_id_raw_file)
} else {
  load(pm_id_raw_file)
}

if (!file.exists(pm_df_file)) {
  pm_df <- pm_res$result %>%
    purrr::map(DO.utils::extract_pmid) %>%
    unlist() %>%
    tibble::tibble(
      search_id = names(.),
      pmid = .
    ) %>%
    dplyr::mutate(search_id = stringr::str_remove(search_id, "[0-9]+$")) %>%
    dplyr::left_join(dplyr::select(pm_id2, pmcid:doi), by = "pmid")

  readr::write_csv(pm_df, pm_df_file)
} else {
  pm_df <- readr::read_csv(pm_df_file)
}


# GET PMC search results --------------------------------------------------
pmc_raw_file <- file.path(data_dir, "pmc_search_raw.RData")
pmc_id_raw_file <- file.path(data_dir, "pmc_search_raw-IDs.RData")

pmc_df_file <- file.path(data_dir, "pmc_search_results.csv")

if (!file.exists(pmc_raw_file)) {
  pmc_res <- purrr::map(
    search_terms,
    ~ search_pmc_safely(.x, retmax = 10000, pmid = TRUE)
  ) %>%
    purrr::set_names(names(search_terms)) %>%
    purrr::transpose() %>%
    purrr::simplify_all()

  save(pmc_res, file = pmc_raw_file)
} else {
  load(pmc_raw_file)
}

# Get PubMed IDs for matching -- search results have PMIDs but they are not
# ordered to match the PMCIDs and must be obtained separately.
if (!file.exists(pmc_id_raw_file)) {
  pmc_uniq <- purrr::map(pmc_res$result, ~ .x$ids) %>%
    unlist() %>%
    unique()

  pmc_id2 <- DO.utils::batch_id_converter(pmc_uniq, type = "pmcid") %>%
    tibble::as_tibble()

  save(pmc_id2, file = pmc_id_raw_file)
} else {
  load(pmc_id_raw_file)
}


if (!file.exists(pmc_df_file)) {
  pmc_df <- purrr::map2_dfr(
    .x = pmc_res$result,
    .y = names(pmc_res$result),
    function(res, nm) {
        if (rlang::is_empty(res$ids)) {
          NULL
        } else {
          tibble::tibble(
            pmcid = res$ids,
            search_id = nm
          )
        }
    }
  ) %>%
    dplyr::left_join(dplyr::select(pmc_id2, -versions), by = "pmcid") %>%
    dplyr::select(search_id, pmid, pmcid, doi)

  readr::write_csv(pmc_df, pmc_df_file)
} else {
  pmc_df <- readr::read_csv(pmc_df_file)
}


# Count Results -----------------------------------------------------------
search_n <- dplyr::bind_rows(
  pm = dplyr::count(pm_df, search_id),
  pmc = dplyr::count(pmc_df, search_id),
  epmc = dplyr::count(epmc_df, search_id),
  .id = "db"
) %>%
  tidyr::pivot_wider(
    names_from = db,
    values_from = n
  ) %>%
  dplyr::left_join(search_blank, by = c("search_id" = "name"))

readr::write_csv(search_n, file.path(data_dir, "search_res_n.csv"), na = "0")


# Actual searches performed -----------------------------------------------
actual_search <- tibble::tibble(
  search_id = names(search_terms),
  search_term = unlist(search_terms),
  pm = purrr::map_chr(pm_res$result, ~.x$QueryTranslation),
  pmc = purrr::map_chr(pmc_res$result, ~.x$QueryTranslation)
)

readr::write_csv(actual_search, file.path(data_dir, "actual_search_terms.csv"))


# Identify overlap in searches --------------------------------------------
plot_upset <- function(df, id_col, overlap_col, min_count = 0, ...) {
  overlap_df <- df %>%
    # drop category if < min_count
    dplyr::add_count({{ overlap_col }}, name = "n") %>%
    dplyr::filter(n >= min_count) %>%
    # format for ggupset
    dplyr::select({{ overlap_col }}, {{ id_col }}) %>%
    dplyr::group_by({{ id_col }}) %>%
    dplyr::summarize(
      {{ overlap_col }} := list({{ overlap_col }}),
      str = paste({{ overlap_col }}, collapse = "|")
    ) %>%
    dplyr::ungroup() %>%
    dplyr::add_count(str, name = "n")

  g <- ggplot(overlap_df, aes(x = {{ overlap_col }})) +
    theme_minimal() +
    geom_bar() +
    scale_x_upset() +
    labs(...)

  g
}

# Searches are too long to display for full EPMC plot, number searches instead
# and output csv of search with numbers to identify them
search_num_rc <- c(
  generic_name = '#1', lynn_custom = '#2', ns_id = '#3', full_name = '#4',
  website = '#5', ncbo = '#6', iri_no_ext = '#7', github = '#8', iri = '#9',
  embl_ols = '#10', sourceforge = '#11', wikipedia = '#12', do_wiki = '#13',
  ontobee = '#14' # no hits
)

# also excluding results where actual search tokens were converted to non-DO
# identifiers
epmc_plot_df <- epmc_df %>%
  dplyr::mutate(
    search_num = dplyr::recode(search_id, !!!search_num_rc),
    search_id = dplyr::recode(search_id, !!!search_terms)
  )

# full EPMC plot
g_epmc <- plot_upset(
  epmc_plot_df,
  id,
  search_num,
  x = "Search",
  y = "Hits"
) +
  ggupset::theme_combmatrix(
    combmatrix.label.text = element_text(size = 8),
    combmatrix.label.extra_spacing = 0,
    combmatrix.label.total_extra_spacing = unit(0, "pt"),
    combmatrix.panel.line.size = 1,
    combmatrix.panel.point.size = 2.5
  )

ggsave(
  filename = file.path(graphics_dir, "epmc_search_overlap.png"),
  plot = g_epmc,
  device = "png",
  width = 6.6,
  height = 3.5,
  dpi = 600,
  bg = "white"
)

tibble::tibble(
  search_num = search_num_rc,
  search = dplyr::recode(names(search_num_rc), !!!search_terms)
) %>%
  readr::write_csv(file.path(data_dir, "epmc_search_num.csv"))


# EMPC plot, searches with < 10 hits dropped
g_epmc10 <- plot_upset(
  epmc_plot_df,
  id,
  search_id,
  min_count = 10,
  x = "Search",
  y = "Hits"
) +
  ggupset::theme_combmatrix(
    combmatrix.panel.point.size = 2,
    combmatrix.panel.line.size = 0.8,
    combmatrix.label.text = element_text(size = 8),
    combmatrix.label.extra_spacing = 1.5,
    combmatrix.label.total_extra_spacing = unit(0, "pt")
  )

ggsave(
  filename = file.path(graphics_dir, "epmc_search_overlap-min10.png"),
  plot = g_epmc10,
  device = "png",
  width = 6.6,
  height = 3,
  dpi = 600,
  bg = "white"
)


# PMC plot
g_pmc <- pmc_df %>%
  dplyr::filter(search_id != "do_wiki") %>%
  dplyr::mutate(search_id = dplyr::recode(search_id, !!!search_terms)) %>%
  plot_upset(
    pmcid,
    search_id,
    x = "Search",
    y = "Hits"
  )

ggsave(
  filename = file.path(graphics_dir, "pmc_search_overlap.png"),
  plot = g_pmc,
  device = "png",
  dpi = 600,
  bg = "white"
)


# PubMed plot
g_pm <- pm_df %>%
  dplyr::filter(!search_id %in% c("iri", "do_wiki")) %>%
  dplyr::mutate(search_id = dplyr::recode(search_id, !!!search_terms)) %>%
  plot_upset(
    pmid,
    search_id,
    x = "Search",
    y = "Hits"
  )

ggsave(
  filename = file.path(graphics_dir, "pm_search_overlap.png"),
  plot = g_pm,
  device = "png",
  dpi = 600,
  bg = "white"
)


# Identify overlap across sources -----------------------------------------
best_search <- c("ns_id", "generic_name", "website")
epmc_match <- epmc_df %>%
  # limit to meaningful searches
  dplyr::filter(search_id %in% best_search) %>%
  dplyr::select(epmc_id = id, pmid:doi) %>%
  unique() %>%
  dplyr::mutate(
    src = "epmc",
    id = dplyr::row_number()
  ) %>%
  dplyr::select(id, src, pmid:doi, epmc_id)

# requires matching by all available identifiers
pmc_compare <- pmc_df %>%
  dplyr::filter(search_id %in% best_search) %>%
  dplyr::select(-search_id) %>%
  unique() %>%
  # position matches row number so no need for replacement
  DO.utils::match_citations(epmc_match, add_col = "id") %>%
  dplyr::arrange(id) %>%
  dplyr::mutate(src = "pmc")

pmc_uniq <- pmc_compare %>%
  dplyr::filter(is.na(id)) %>%
  dplyr::mutate(id = max(epmc_match$id) + dplyr::row_number())
pmc_match <- pmc_compare %>%
  dplyr::filter(!is.na(id))

pm_compare <- pm_df %>%
  dplyr::filter(search_id %in% best_search) %>%
  dplyr::select(-search_id) %>%
  unique() %>%
  DO.utils::match_citations(epmc_match, add_col = "id1") %>%
  DO.utils::match_citations(pmc_uniq, add_col = "id2") %>%
  dplyr::mutate(
    id2 = pmc_uniq$id[id2],
    id = dplyr::if_else(!is.na(id1), id1, id2),
    src = "pm"
  ) %>%
  dplyr::select(-id1, -id2) %>%
  dplyr::arrange(id)

pm_uniq <- pm_compare %>%
  dplyr::filter(is.na(id)) %>%
  dplyr::mutate(id = max(pmc_uniq$id) + dplyr::row_number())
pm_match <- pm_compare %>%
  dplyr::filter(!is.na(id))

src_match <- dplyr::bind_rows(
  epmc_match,
  pmc_match,
  pmc_uniq,
  pm_match,
  pm_uniq
)

# save source comparison data
readr::write_csv(src_match, file.path(data_dir, "src_comparison.csv"))


# create & save plots
src <- unique(src_match$src)
g_src_venn <- purrr::map(
  src,
  ~ src_match$id[src_match$src == .x]
  ) %>%
  purrr::set_names(nm = dplyr::recode(
      src,
      pmc = "PubMed Central",
      pm = "PubMed",
      epmc = "Europe PMC"
    )
  ) %>%
  ggvenn(fill_color = hues::iwanthue(3, random = TRUE))

ggsave(
  filename = file.path(graphics_dir, "search_src_overlap-venn.png"),
  plot = g_src_venn,
  device = "png",
  width = 6,
  height = 6,
  dpi = 600,
  bg = "white"
)


g_src_upset <- src_match %>%
  dplyr::mutate(
    src = dplyr::recode(
      src,
      pmc = "PubMed Central",
      pm = "PubMed",
      epmc = "Europe PMC"
    )
  ) %>%
  plot_upset(id_col = id, overlap_col = src, x = "Source", y = "Hits")

ggsave(
  filename = file.path(graphics_dir, "search_src_overlap-upset.png"),
  plot = g_src_upset,
  device = "png",
  dpi = 600,
  bg = "white"
)


# Plot unique results for DOID & "disease ontology" -----------------------

all_search <- dplyr::bind_rows(epmc_df, pmc_df, pm_df, .id = "src") %>%
  dplyr::filter(search_id %in% best_search) %>%
  dplyr::mutate(
    src = dplyr::recode(
      src,
      "1" = "Europe PMC",
      "2" = "PubMed Central",
      "3" = "PubMed"
    ),
    src = factor(src, levels = c("PubMed", "PubMed Central", "Europe PMC")),
    search_id = dplyr::recode(search_id, !!!search_terms),
    search_id = factor(
      search_id,
      levels = c("doid", "\"disease-ontology.org\"", "\"disease ontology\"")
    )
  )

g_total <- ggplot(all_search, aes(x = src)) +
  geom_bar(
    aes(fill = search_id), width = 0.8,
    size = 0.2, color = "black"
  ) +
  scale_fill_manual(
    name = "Search",
    values = c("grey20", "grey50", "grey80")
  ) +
  geom_text(aes(x = src, y = 350, label = src), angle = 90, hjust = 0) +
  labs(x = "Database", y = "Search Hits") +
  scale_y_continuous(expand = expansion(mult = 0.01)) +
  theme_minimal() +
  theme(
    axis.text.x = element_blank(),
    legend.text = element_text(size = 10, color = "black")
  )

# save without legend (to get right size)
ggsave(
  g_total + theme(legend.position = "none"),
  filename = file.path(graphics_dir, "total_hits-graph.png"),
  device = "png",
  dpi = 600,
  width = 1.47,
  height = 3.35,
  bg = "white"
)


# save only for legend (crop)
ggsave(
  # may not like left position (also printed without guides adjustment)
  g_total + guides(fill = guide_legend(title.position = "left")),
  filename = file.path(graphics_dir, "total_hits-legend.png"),
  device = "png",
  dpi = 600,
  width = 3,
  height = 3.35,
  bg = "white"
)


# save complete
ggsave(
  # may not like left position (also printed without guides adjustment)
  g_total + guides(fill = guide_legend(title.position = "top")),
  filename = file.path(graphics_dir, "total_hits-complete.png"),
  device = "png",
  dpi = 600,
  width = 3.5,
  height = 3.35,
  bg = "white"
)
