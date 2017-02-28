utils::globalVariables("role")

#' @importFrom utils head tail
#' @importFrom tibble data_frame
#' @importFrom stringr str_split str_match
#' @import ggplot2

# The actual graphing functions are created dynamically.
#  See the functions at the bottom of this file

# These are unexported helper functions to create the gf_ functions. The gf_ functions
# themselves are at the end of this file....

# traverse a formula and return a nested list of "nodes"
formula_slots <- function(x) {
  if (length(x) == 2L && deparse(x[[1]]) == "~") {
    formula_slots(x[[2]])
  } else if (length(x) == 3L && deparse(x[[1]]) %in% c(":")) {
    list(x)
  } else if (length(x) <= 2L) {
    list(x)
  } else {
    list(formula_slots(x[[2]]), formula_slots(x[[3]]))
  }
}

# add quotes to character elements of list x and returns a vector of character
.quotify <- function(x) {
  as.character(
    lapply(x, function(e) if(is.character(e)) paste0('"', e, '"') else e)
  )
}

.add_arg_list_to_function_string <- function(S, extras) {
  empty <- grepl("\\(\\s?\\)$", S)
  res <- if (length(extras) == 0 ) {
    S
  } else {
    more <- paste0(names(extras), " = ", .quotify(extras), collapse = ", ")
    S <- gsub("\\)$", "", S)
    paste0(S, ifelse(empty, "", ", "), more, ")")
  }

  res
}

# This doen't appear to be used anywhere.

gf_generic <- function(object = NULL, formula = NULL, data = NULL,
                       extras = list(), geom = "point", aes_form = y ~ x,
                       ... ) {
  data_name <- deparse(substitute(data))
  if (inherits(object, c("gg", "ggplot"))) {
    # things are already set up
    add <- TRUE
  } else if (inherits(object, "formula")) {
    formula <- object
    object <- NULL
    add <- FALSE
  }

  gg_string <- gf_master(formula = formula, data = data, add = add,
                         geom = geom, gg_object = object,
                         extras = extras, aes_form = aes_form,
                         data_name = data_name)
  gg_string
}

gf_factory <- function(type, extras = NULL, aes_form = y ~ x) {
  # this is a copy of the body of gf_generic() with some of the
  # arguments Curried.
  function(object = NULL, formula = NULL,
           data = NULL, geom = type, verbose = FALSE,
           add = inherits(object, c("gg", "ggplot")),
           ...) {
    extras <- c(list(...), extras)
    data_name <- deparse(substitute(data))

    if (inherits(object, "formula")) {
      formula <- object
      object <- NULL
    }


    if (!inherits(object, c("gg", "ggplot"))) {
      add <- FALSE  # can't add if we don't have a plot to add to
    }
    gg_string <- gf_master(formula = formula, data = data,
                           geom = geom, gg_object = object,
                           add = add, extras = extras,
                           aes_form = aes_form,
                           data_name = data_name)
    if (verbose) cat(gsub("geom", "\n  geom", gg_string, fixed = TRUE), "\n")

    P <- eval(parse(text = gg_string))
    if (add)  #  don't need this part: && inherits(object, c("gg", "ggplot")))
      return(object + P)
    else
      return(P)
  }
}

gf_master <- function(formula = NULL, data = NULL,
                      add = FALSE,
                      data_name = NULL,
                      geom = "geom_point", extras = list(),
                      gg_object = NULL,
                      aes_form = y ~ x) {

  data_string <-
    if (is.null(data)) ""
  else paste("data =", data_name)

  if ( (! add) && is.null(data) )
    stop("Must provide a frame or a data argument for a frame.")

  var_names <-
    if (is.null(data)) {
      if (is.null(gg_object)) {
        character(0)
      } else {
        names(gg_object$data)
      }
    } else {
      names(data)
    }

  # arguments for the frame or, if add == TRUE, for the geom
  main_arguments <-
    formula_to_aesthetics(formula, var_names,
                          prefix = data_string,
                          aes_form = aes_form)

  from_formula <- formula_to_df(formula, var_names, aes_form = aes_form)


  main_arguments <-
    df_to_aesthetics(
      from_formula, var_names,
      prefix = if (add) data_string else "")

  gg_string <-
    .add_arg_list_to_function_string(
      paste0("geom_", geom, main_arguments),
      extras)

  if (! add) gg_string <-   # need ggplot() call, too
    paste0("ggplot(", data_string, ") + ", gg_string)

  gg_string
}

formula_to_df <- function(formula = NULL, data_names = character(0),
                          aes_form = y ~ x) {
  if (is.null(formula))
    return(data.frame(role = character(0),
                      expr = character(0),
                      map = logical(0)))
  parts <- formula_slots(formula) %>% rapply(deparse, how = "replace") %>% unlist()
  aes_names <- formula_slots(aes_form) %>% rapply(deparse, how = "replace") %>% unlist()

  # trim leading blanks
  parts <- gsub("^\\s+|\\s+$", "", parts)

  # split into pairs/nonpairs
  pairs <- parts[grepl(":+", parts)]
  nonpairs <- parts[ ! grepl(":+", parts)]

  pair_list <- list()
  mapped_pairs <- character(0)
  for (pair in pairs) {
    this_pair <- stringr::str_split(pair, ":+", n = 2)[[1]]
    pair_list[this_pair[1]] <- this_pair[2]
    if (stringr::str_match(pair, ":+") == "::")
      mapped_pairs <- c(mapped_pairs, this_pair[1])
  }

  nonpair_list <- nonpairs
  # remove items specified explicitly
  aes_names <- setdiff(all.vars(aes_form), names(pair_list))
  names(nonpair_list) <- head(aes_names, length(nonpair_list))

  if (length(nonpair_list) > length(aes_names)) {
    stop("Formula too large.  I'm looking for ", format(aes_form),
         call. = FALSE)
  }
  if (length(nonpair_list) < length(aes_names)) {
    stop("Formula too small.  I'm looking for ", format(aes_form),
         call. = FALSE)
  }

  res <- c(nonpair_list, pair_list)

  res <-
    tibble::data_frame(
      role = names(res),
      expr = unlist(res),
      map = unlist(res) %in% c(data_names) | role %in% aes_names | role %in% mapped_pairs)
  row.names(res) <- NULL
  res
}

df_to_aesthetics <- function(formula_df, data_names = NULL, prefix = "") {
  aes_substr <-
    if (is.null(data_names) || nrow(formula_df) == 0) {
      ""
    } else {
      paste0("aes(",
             with(subset(formula_df, formula_df$map),
                  paste(role, expr, sep = " = ", collapse = ", ")),
             ")",
             ifelse(any( ! formula_df$map), ", ", "") # prepare for more args
      )
    }
  S <- paste0("(", prefix,
              ifelse(nchar(prefix) > 0, ", ", ""),
              aes_substr,
              with(subset(formula_df, ! formula_df$map),
                   paste(role, expr, sep = " = ", collapse = ", ")),
              ")")
  S
}


formula_to_aesthetics <- function(formula,
                                  data_names = NULL,
                                  prefix = "",
                                  aes_form = y ~ x) {
  df <- formula_to_df(formula, data_names, aes_form = aes_form)
  df_to_aesthetics(df, data_names = data_names, prefix = prefix)
}

# pull out the pairs from a formula like color::red + alpha:0.5
# return them as a named list
pairs_in_formula <- function(formula) {
  fc <- as.character(formula)
  parts <- unlist(strsplit(fc, "+", fixed = TRUE))
  # trim leading blanks
  parts <- gsub("^\\s+|\\s+$", "", parts)
  # identify the pairs
  pairs <- parts[grep(":+", parts)]
  xy <- parts[ ! grepl(":", parts)][-1] # logic for x:, y: explicit
  res <- list()
  for (pair in pairs) {
    this_pair <- stringr::str_split(pair, ":+", n = 2)
    res[this_pair[1] ] <- this_pair[2]
  }
  # more logic for x:, y: explicit.
  stop("Haven't yet updated logic in frame_string. See comment.")
  # BUT ... not yet replaced explicit "x" and "y" arguments in
  # frame_string()
  if (length(xy) == 2) {
    if ("y" %in% names(res))
      warning("duplicate specification of y aesthetic")
    else res["y"] <- xy[1]


    if ("x" %in% names(res))
      warning("duplicate specification of x aesthetic")
    else res["x"] <- xy[2]
  } else if (length(xy) == 1) {
    if ("y" %in% names(res)) {
      if ("x" %in% names(res))
        warning("duplicate specification of x aesthetic")
      else res["x"] <- xy
    } else if ("x" %in% names(res)) {
      if ("y" %in% names(res))
        warning("duplicate specification of y aesthetic")
      else res["y"] <- xy
    }
  }

  res
}