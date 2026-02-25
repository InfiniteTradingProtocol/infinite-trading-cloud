# openapi_async.R

library(plumber)
library(jsonlite)

# Load your asynchronous Plumber API
pr <- plumb("/home/ubuntu/infinitetrading/src/api/gateway.R")

# Generate the OpenAPI specification
openapi_spec <- pr$getApiSpec()

# Save the specification to a file
output_path <- "/home/ubuntu/infinitetrading/src/api/openapi_spec.json"

# Ensure the directory exists and is writable
output_dir <- dirname(output_path)
if (!dir.exists(output_dir)) {
  stop(paste("Directory does not exist:", output_dir))
}

if (file.access(output_dir, 2) != 0) {
  stop(paste("Directory is not writable:", output_dir))
}

# Save the specification to a file with error handling
tryCatch({
  write_json(openapi_spec, output_path, pretty = TRUE)
  cat("OpenAPI specification saved successfully to", output_path, "\n")
}, error = function(e) {
  cat("Error saving OpenAPI specification:", e$message, "\n")
})
write_json(openapi_spec, "/home/ubuntu/infinitetrading/src/api/openapi_spec.json", pretty = TRUE)

