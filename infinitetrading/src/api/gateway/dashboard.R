require(shiny); require(DBI); require(RSQLite); require(bslib); require(dotenv);
load_dot_env("~/infinitetrading/src/api/.env")

#admin credentials
username = Sys.getenv("dashboard_username")
password = Sys.getenv("dashboard_password")

#Connection to RSQLite
db <- dbConnect(SQLite(), "api_logs.sqlite")
if (dbExistsTable(db, "api_logs")) {
  print("Connection successful, and table exists.")
} else {
  stop("Table does not exist or database file is invalid.")
}
ui <- fluidPage(
  theme = bs_theme(
    bg = "#F9F9FB",  # Light background
    fg = "#4E2A84",  # Purple for text
    primary = "#6E5DE7",  # Bright purple for buttons/headers
    secondary = "#D6CFFF"  # Light purple for accents
  ),
  
  # Title Panel
  #titlePanel("Infinite Trading API v1"),
   tags$div(
    h1("API v1 Analytics", style = "color: #6E5DE7;"),
    style = "text-align: center; margin-bottom: 30px; margin-top:10px;"
  ), 
  
  # Sidebar Layout
  sidebarLayout(
    sidebarPanel(
         tags$div(
          tags$img(
            src="https://github.com/InfiniteTradingProtocol/infinite-trading-protocol/blob/main/logos/InfiniteTradingBlackLettersTransparentBG.png?raw=true", height = "150px",
            alt = "Infinite Trading Protocol"
          ),
          style = "display: flex; justify-content: center; margin-bottom: 20px;"
        ),
      h3("Endpoints", style = "color: #6E5DE7;"),  # Sidebar text color
      selectInput("endpoint", "Select Endpoint:", choices = NULL, selected = NULL),
      tags$div(actionButton("admin_btn", "Admin Login", class = "btn-primary"),style = "display: flex; justify-content: center; align-items: center; margin-top: 10px;"),
      tags$div(
    tableOutput("top_ips"),
    style = "display: flex; justify-content: center; align-items: center; margin-top: 20px;"
  )
      ),
    mainPanel(
      #h1("Main Panel", style = "color: #4E2A84;"),  # Header color
      plotOutput("tx_plot"),
      plotOutput("ip_requests_plot")
      #tableOutput("top_ips")
    )
  )
)

server <- function(input, output, session) {
  credentials <- reactiveValues(logged_in = FALSE)
# Reactive expression for query data
query_data_reactive <- reactive({
  req(input$endpoint)
  invalidateLater(300000, session)
  if (input$endpoint == "ALL") {
    dbGetQuery(db, "
      SELECT timestamp, ip, COUNT(*) AS tx_count
      FROM api_logs
      WHERE timestamp >= strftime('%s', 'now') - 86400
      GROUP BY timestamp, ip
      ORDER BY timestamp DESC
    ")
  } else {
    dbGetQuery(db, "
      SELECT timestamp, ip, COUNT(*) AS tx_count
      FROM api_logs
      WHERE endpoint = ? AND timestamp >= strftime('%s', 'now') - 86400
      GROUP BY timestamp, ip
      ORDER BY timestamp DESC
    ", params = list(input$endpoint))
  }
})
  # Handle "View as Admin" button
  observeEvent(input$admin_btn, {
    showModal(modalDialog(
      title = "Admin Login",
      textInput("username", "Username:"),
      passwordInput("password", "Password:"),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("login_btn", "Login")
      )
    ))
  })
    observeEvent(input$login_btn, {
    # Replace with your username and password
    if (input$username == username && input$password == password) {
      credentials$logged_in <- TRUE
      removeModal()
    } else {
      showModal(modalDialog(
        title = "Error",
        "Incorrect username or password. Please try again.",
        easyClose = TRUE
      ))
    }
  })
  # Update endpoint choices dynamically, including "ALL"
  updateSelectInput(session, "endpoint", choices = {
  endpoints <- dbGetQuery(db, "SELECT DISTINCT endpoint FROM api_logs WHERE timestamp >= strftime('%s', 'now') - 86400")$endpoint
  c("ALL", endpoints)  # Add "ALL" option at the beginning
}, selected = "ALL")  # Default to "ALL"


  # Plot transactions per hour
  output$tx_plot <- renderPlot({
    query_data <- query_data_reactive()

    # Check if query_data is empty
    if (nrow(query_data) == 0 || all(is.na(query_data$tx_count))) {
      plot.new()  # Create an empty plot
      text(0.5, 0.5, "No data available for the selected option", cex = 1.2)
      return()
    }
    total_transactions <- sum(as.numeric(query_data$tx_count), na.rm = TRUE)
    total_transactions_formatted <- formatC(total_transactions, format = "f", big.mark = ",", digits = 0)
    unique_ip_count <- length(unique(query_data$ip))
    # Parse and format the timestamp
    query_data$hour <- as.POSIXct(as.numeric(query_data$timestamp), origin = "1970-01-01", tz = "UTC")
    query_data$hour <- format(query_data$hour, "%Y-%m-%d %H:00:00")  # Group by hour

    # Aggregate by hour
    query_data <- aggregate(tx_count ~ hour, data = query_data, sum)

    # Create the barplot
    # Generate gradient colors based on tx_count

    max_tx <- max(query_data$tx_count)
    min_tx <- min(query_data$tx_count)

    # Normalize transaction counts to range 0–1 for gradient mapping
    normalized_tx <- (query_data$tx_count - min_tx) / (max_tx - min_tx)

    # Define the gradient: light purple (#D6CFFF) to strong purple (#6E5DE7)
    gradient_palette <- colorRampPalette(c("#D6CFFF", "#6E5DE7"))
    colors <- gradient_palette(100)[floor(normalized_tx * 99) + 1]  # Map normalized values to gradient

    #colors <- colorRampPalette(c("#6E5DE7", "#867ABF", "#D6CFFF"))(nrow(query_data))
    par(bg = "#F9F9FB")  # Set the background color
    barplot(query_data$tx_count, names.arg = query_data$hour, las = 2, main="Transactions Per Hour",xlab = "Hour", ylab = "Count", col = colors)
    mtext(paste0("Last 24h Total: ", total_transactions_formatted), side = 3, line = 0.5, cex = 0.9, col = "#4E2A84")
  })
  # Plot requests by IP
  output$ip_requests_plot <- renderPlot({
    query_data <- query_data_reactive()
    unique_ip_count <- length(unique(query_data$ip))
    if (input$endpoint == "ALL") {
      ip_data <- dbGetQuery(db, "
        SELECT timestamp, ip, COUNT(*) AS request_count
        FROM api_logs
	WHERE timestamp >= strftime('%s', 'now') - 86400
        GROUP BY ip
        ORDER BY request_count DESC
      ")
    } else {
      ip_data <- dbGetQuery(db, "
        SELECT timestamp, ip, COUNT(*) AS request_count
        FROM api_logs
	WHERE endpoint = ? AND timestamp >= strftime('%s', 'now') - 86400
        GROUP BY ip
        ORDER BY request_count DESC
      ", params = list(input$endpoint))
    }

    if (nrow(ip_data) == 0 || all(is.na(ip_data$request_count))) {
      plot.new()
      text(0.5, 0.5, "No data available for the selected option", cex = 1.2)
      return()
    }
  # Calculate gradient colors for request_count
  #unique_ip_count <- length(unique(ip_data$ip))
  max_requests <- max(ip_data$request_count)
  min_requests <- min(ip_data$request_count)

  # Normalize request counts to range 0–1 for gradient mapping
  normalized_requests <- (ip_data$request_count - min_requests) / (max_requests - min_requests)

  # Define the gradient: light purple (#D6CFFF) to strong purple (#6E5DE7)
  gradient_palette <- colorRampPalette(c("#D6CFFF", "#6E5DE7"))
    if (!credentials$logged_in) {
	        ip_data$ip <- sub("(\\d+\\.\\d+)\\.\\d+\\.\\d+", "\\1.***.***", ip_data$ip)
    }
  colors <- gradient_palette(100)[floor(normalized_requests * 99) + 1]
    barplot(
      ip_data$request_count,
      names.arg = ip_data$ip,
      las = 1,  # Rotate IP addresses vertically
      col = colors,
      main = "Requests by IP",
      xlab = "IP Address",
      ylab = "Count"
    )
      mtext(paste0("Last 24h Unique IP's: ", unique_ip_count), side = 3, line = 0.5, cex = 0.9, col = "#4E2A84")
  })
  # Display top IPs
  output$top_ips <- renderTable({
    # SQL query for "ALL" or specific endpoint
    if (input$endpoint == "ALL") {
      query_data <- dbGetQuery(db, "
        SELECT timestamp, ip, COUNT(*) AS tx_count
        FROM api_logs
	WHERE timestamp >= strftime('%s', 'now') - 86400
        GROUP BY ip
        ORDER BY tx_count DESC
      ")
    } else {
      query_data <- dbGetQuery(db, "
        SELECT timestamp, ip, COUNT(*) AS tx_count
        FROM api_logs
        WHERE endpoint = ? AND timestamp >= strftime('%s', 'now') - 86400
        GROUP BY ip
        ORDER BY tx_count DESC
      ", params = list(input$endpoint))
    }

    # If no data, return an empty data frame
    if (nrow(query_data) == 0) {
      return(data.frame(ip = character(), tx_count = numeric()))
    }
    query_data$timestamp <- as.POSIXct(floor(as.numeric(query_data$timestamp)), origin = "1970-01-01", tz = "UTC")
    query_data$timestamp <- format(query_data$timestamp, "%Y-%m-%d %H:00:00")  # Group by hour
    # Hide IPs if not logged in
    if (!credentials$logged_in) query_data$ip <- sub("(\\d+\\.\\d+)\\.\\d+\\.\\d+", "\\1.***.***", query_data$ip)
    # Return the query result
    query_data
  })
}

# Run the Shiny app
shinyApp(ui = ui, server = server, options = list(host = "0.0.0.0", port = 5299))

