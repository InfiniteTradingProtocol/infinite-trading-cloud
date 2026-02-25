source_function <- function(file, func_name) {
  # Create a temporary environment
  env <- new.env()
  
  # Source the file into the temporary environment
  source(file, local = env)
  
  # Check if the function exists in the environment
  if (exists(func_name, envir = env)) {
    # Assign the function to the global environment
    assign(func_name, get(func_name, envir = env), envir = .GlobalEnv)
  } else {
    stop(paste("Function", func_name, "not found in", file))
  }
  
  # Remove the temporary environment
  rm(env)
  
  # Optional: Run garbage collection
  gc()
}

# Usage
source_function('/path/to/functions.R', 'add')
result <- add(3, 5)
print(result)  # Output: 8

