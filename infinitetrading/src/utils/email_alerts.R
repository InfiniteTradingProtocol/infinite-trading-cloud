# ==============================================================================
# Email alert helpers — Resend API
# Requires: RESEND_API_KEY in environment, httr + jsonlite already loaded.
# ==============================================================================

`%||%` <- function(a, b) if (!is.null(a)) a else b

# Send an HTML email via Resend. Returns TRUE on success, never throws.
send_resend_email <- function(subject, html_body) {
  api_key <- Sys.getenv("RESEND_API_KEY")
  if (nchar(api_key) == 0) {
    cat("  ⚠️  RESEND_API_KEY not set — cannot send email\n")
    return(invisible(FALSE))
  }
  tryCatch({
    resp <- POST(
      url  = "https://api.resend.com/emails",
      add_headers(
        Authorization  = paste("Bearer", api_key),
        `Content-Type` = "application/json"
      ),
      body   = toJSON(list(
        from    = "alerts@infinitetrading.io",
        to      = list("admin@infinitetrading.io"),
        subject = subject,
        html    = html_body
      ), auto_unbox = TRUE),
      encode = "raw"
    )
    if (status_code(resp) %in% c(200L, 201L)) {
      cat(sprintf("  📧 Email sent: %s\n", subject))
      return(invisible(TRUE))
    }
    result <- tryCatch(fromJSON(content(resp, "text", encoding = "UTF-8")),
                       error = function(e) list())
    cat(sprintf("  ⚠️  Resend error (%d): %s\n", status_code(resp),
                result$message %||% "unknown"))
    return(invisible(FALSE))
  }, error = function(e) {
    cat(sprintf("  ⚠️  Email send failed: %s\n", e$message))
    return(invisible(FALSE))
  })
}

# Check daily limit for an alert.
# alert_state is an environment with $count (integer) and $date (Date).
# Initialise:
#   my_alert <- new.env(parent = emptyenv())
#   my_alert$count <- 0L
#   my_alert$date  <- Sys.Date()
# Usage:
#   if (can_send_alert(my_alert)) { send_resend_email(...); my_alert$count <- my_alert$count + 1L }
can_send_alert <- function(alert_state, max_per_day = 2L) {
  today <- Sys.Date()
  if (!isTRUE(alert_state$date == today)) {
    alert_state$count <- 0L
    alert_state$date  <- today
  }
  alert_state$count < max_per_day
}
