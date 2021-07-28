# modified from:
# https://github.com/sol-eng/plumber-logging/blob/0f41e1c95b/R/shiny/app.R

pkgs <- c(
  "dplyr",
  "fs",
  "forcats",
  "glue",
  "ggplot2",
  "grDevices",
  "memoise",
  "readr",
  "shiny",
  "shinydashboard"
)

for (pkg in pkgs) {

  suppressPackageStartupMessages(
    library(pkg, quietly = TRUE, character.only = TRUE)
  )

}

log_dir <- "~/logs"

read_plumber_log <- function(log_file) {
  readr::read_log(
    file = log_file,
    col_names = c(
      "log_level", "timestamp", "remote_addr",  "user_agent", "host", "method",
      "endpoint", "status", "execution_time"
    )
  )
}

ui <- dashboardPage(
  dashboardHeader(title = Sys.getenv("PAGE_TITLE")),
  dashboardSidebar(disable = TRUE),
  dashboardBody(
    tags$head(tags$style(type="text/css", ".recalculating { opacity: 1.0; }")),
    fluidRow(
      valueBoxOutput("total_requests", width = 6L),
      valueBoxOutput("requests_per_second", width = 6L)
    ),
    fluidRow(
      valueBoxOutput("percent_success", width = 6L),
      valueBoxOutput("average_execution", width = 6L)
    ),
    fluidRow(
      valueBoxOutput("top_ep", width = 6L),
      valueBoxOutput("highest_user", width = 6L)
    ),
    fluidRow(
      box(
        imageOutput("requests_plot"),
        title = "Requests Overview",
        width = 12L,
        collapsible = TRUE
      )
    ),
    fluidRow(
      box(
        imageOutput("status_plot"),
        title = "Response Status Overview",
        width = 6L
      ),
      box(
        imageOutput("endpoints_plot"), title = "Endpoints Overview", width = 6L
      )
    ),
    fluidRow(
      box(
        imageOutput("users_plot"),
        title = "User-agents Overview",
        width = 12L,
        collapsible = TRUE
      )
    )
  )
)

server <- function(input, output, session) {

  mem_read_plumber_log <- memoise::memoise(

    function(file, timestamp) {

      read_plumber_log(file)

    }

  )

  observe({

    invalidateLater(30L * 60L * 1000L)

    memoise::forget(mem_read_plumber_log)

  })

  log_data <- reactivePoll(
    1000,
    checkFunc = function() {

      files <- fs::dir_ls(log_dir)

      fs::file_info(files)$modification_time

    },
    valueFunc = function() {

      files <- fs::dir_ls(log_dir)

      purrr::map2_df(
        files, fs::file_info(files)$modification_time, mem_read_plumber_log
      )

    },
    session = session
  )

  filtered_log <- reactive({

    log_data()

  })

  output$total_requests <- renderValueBox({

    valueBox(value = nrow(filtered_log()), subtitle = "Total Requests")

  })

  output$requests_per_second <- renderValueBox({

    data <- filtered_log()

    n_requests <- nrow(data)

    seconds <- dplyr::n_distinct(data$timestamp)

    valueBox(
      value = round(n_requests / seconds, 2L), subtitle = "Requests per Second"
    )

  })

  output$percent_success <- renderValueBox({

    p <- filtered_log() %>%
      dplyr::count(status, name = "count") %>%
      dplyr::mutate(p = count / sum(count)) %>%
      dplyr::filter(status < 400L) %>%
      dplyr::pull(p) %>%
      round(4L)

    valueBox(
      value = glue::glue("{p*100}%"),
      subtitle = "Request Success Rate",
      color = ifelse(p >= .9, "green", "red")
    )

  })

  output$average_execution <- renderValueBox({

    avg_execution <-
      filtered_log()$execution_time %>%
      mean(na.rm = TRUE) %>%
      round(4L)

    valueBox(value = avg_execution, subtitle = "Average Execution Time (S)")

  })

  output$top_ep <- renderValueBox({

    top_ep <-
      filtered_log() %>%
      dplyr::count(host, method, endpoint, name = "count") %>%
      dplyr::slice_max(count, n = 1L, with_ties = FALSE)

    valueBox(
      value = top_ep$count,
      subtitle = glue::glue(
        "Top Endpoint: {top_ep$method} {top_ep$host}{top_ep$endpoint}"
      )
    )

  })

  output$highest_user <- renderValueBox({

    highest_user <-
      filtered_log() %>%
      dplyr::count(user_agent, name = "count") %>%
      dplyr::slice_max(count, n = 1L, with_ties = FALSE)

    valueBox(
      value = highest_user$count,
      subtitle = glue::glue(
        "Top User-agent: {highest_user$user_agent}"
      )
    )

  })

  output$requests_plot <- renderImage({

    tmp <- tempfile(tmpdir = "~/plots", fileext = ".svg")

    grDevices::svg(
      tmp,
      session$clientData$output_requests_plot_width *
        session$clientData$pixelratio / 96L,
      session$clientData$output_requests_plot_height *
        session$clientData$pixelratio / 96L
    )

    gg <- filtered_log() %>%
      dplyr::count(timestamp, name = "count") %>%
      ggplot2::ggplot() +
        ggplot2::aes(x = timestamp, y = count) +
        ggplot2::geom_point() +
        ggplot2::labs(x = "Time", y = "Requests") +
        ggplot2::scale_x_datetime(labels = scales::date_format("%H:%M:%S")) +
        ggplot2::theme_bw()

    print(gg)

    dev.off()

    list(src = tmp, contentType = "image/svg+xml")

    },
    deleteFile = TRUE
  )

  output$status_plot <- renderImage({

    tmp <- tempfile(tmpdir = "~/plots", fileext = ".svg")

    grDevices::svg(
      tmp,
      session$clientData$output_status_plot_width *
        session$clientData$pixelratio / 96L,
      session$clientData$output_status_plot_height *
        session$clientData$pixelratio / 96L
    )

    gg <- filtered_log() %>%
      dplyr::count(status = as.factor(status), name = "count") %>%
      ggplot2::ggplot() +
        ggplot2::aes(x = forcats::fct_reorder(status, count), y = count) +
        ggplot2::geom_col() +
        ggplot2::theme_bw() +
        ggplot2::coord_flip() +
        ggplot2::labs(x = "Response Status", y = "Requests")

    print(gg)

    dev.off()

    list(src = tmp, contentType = "image/svg+xml")

    },
    deleteFile = TRUE
  )

  output$endpoints_plot <- renderImage({

    tmp <- tempfile(tmpdir = "~/plots", fileext = ".svg")

    grDevices::svg(
      tmp,
      session$clientData$output_endpoints_plot_width *
        session$clientData$pixelratio / 96L,
      session$clientData$output_endpoints_plot_height *
        session$clientData$pixelratio / 96L
    )

    gg <- filtered_log() %>%
      dplyr::count(method, host, endpoint, name = "count") %>%
      tidyr::unite(method, method, host, sep = " ") %>%
      tidyr::unite(endpoint, method, endpoint, sep = "") %>%
      dplyr::slice_max(count, n = 10L, with_ties = FALSE) %>%
      ggplot2::ggplot() +
        ggplot2::aes(x = forcats::fct_reorder(endpoint, count), y = count) +
        ggplot2::geom_col() +
        ggplot2::theme_bw() +
        ggplot2::coord_flip() +
        ggplot2::labs(x = "Endpoint", y = "Requests")

    print(gg)

    dev.off()

    list(src = tmp, contentType = "image/svg+xml")

    },
    deleteFile = TRUE
  )

  output$users_plot <- renderImage({

    tmp <- tempfile(tmpdir = "~/plots", fileext = ".svg")

    grDevices::svg(
      tmp,
      session$clientData$output_users_plot_width *
        session$clientData$pixelratio / 96L,
      session$clientData$output_users_plot_height *
        session$clientData$pixelratio / 96L
    )

    gg <- filtered_log() %>%
      dplyr::count(user_agent, name = "count") %>%
      dplyr::slice_max(count, n = 10L, with_ties = FALSE) %>%
      ggplot2::ggplot() +
        ggplot2::aes(x = user_agent, y = count) +
        ggplot2::geom_col() +
        ggplot2::theme_bw() +
        ggplot2::coord_flip() +
        ggplot2::labs(x = "User-agents", y = "Requests")

    print(gg)

    dev.off()

    list(src = tmp, contentType = "image/svg+xml")

    },
    deleteFile = TRUE
  )

  addResourcePath("robots.txt", "~/shiny/robots.txt")
  addResourcePath("status", "~/shiny/healthz")
  addResourcePath("favicon.ico", "~/shiny/favicon.ico")

}

shinyApp(ui = ui, server = server)
