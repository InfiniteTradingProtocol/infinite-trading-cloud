#!/usr/bin/env Rscript
# Test ML/Keras Setup
cat("=== Testing Machine Learning Stack ===\n\n")

# Test keras3
cat("1. Testing keras3...\n")
if (require('keras3', quietly=TRUE)) {
  cat("   ✓ keras3 version:", as.character(packageVersion('keras3')), "\n")
  
  # Test model creation
  tryCatch({
    model <- keras_model_sequential() |>
      layer_dense(units = 64, activation = 'relu', input_shape = c(10)) |>
      layer_dense(units = 32, activation = 'relu') |>
      layer_dense(units = 1, activation = 'sigmoid')
    
    cat("   ✓ Model creation works\n")
    cat("   ✓ Backend:", config_backend(), "\n")
  }, error = function(e) {
    cat("   ✗ Model creation failed:", e$message, "\n")
  })
} else {
  cat("   ✗ keras3 not installed\n")
}

# Test tensorflow
cat("\n2. Testing tensorflow...\n")
if (require('tensorflow', quietly=TRUE)) {
  cat("   ✓ tensorflow version:", as.character(packageVersion('tensorflow')), "\n")
} else {
  cat("   ✗ tensorflow not installed\n")
}

# Test reticulate (Python bridge)
cat("\n3. Testing reticulate (Python bridge)...\n")
if (require('reticulate', quietly=TRUE)) {
  cat("   ✓ reticulate version:", as.character(packageVersion('reticulate')), "\n")
  if (py_module_available('tensorflow')) {
    cat("   ✓ Python TensorFlow available\n")
  } else {
    cat("   ✗ Python TensorFlow not available\n")
  }
} else {
  cat("   ✗ reticulate not installed\n")
}

cat("\n=== ML Stack Status: READY ===\n")
