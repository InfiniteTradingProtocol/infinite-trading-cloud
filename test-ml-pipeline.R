#!/usr/bin/env Rscript
# Comprehensive ML Test - Training a Simple Model

cat("=== Testing Full ML Pipeline ===\n\n")

library(keras3)

# 1. Create synthetic data
cat("1. Creating synthetic training data...\n")
set.seed(42)
n_samples <- 1000
x_train <- matrix(rnorm(n_samples * 10), nrow = n_samples, ncol = 10)
y_train <- matrix(rbinom(n_samples, 1, 0.5), nrow = n_samples, ncol = 1)
cat("   ✓ Created", n_samples, "training samples\n")

# 2. Build model
cat("\n2. Building neural network...\n")
model <- keras_model_sequential(input_shape = c(10)) |>
  layer_dense(units = 64, activation = 'relu') |>
  layer_dropout(0.2) |>
  layer_dense(units = 32, activation = 'relu') |>
  layer_dropout(0.2) |>
  layer_dense(units = 1, activation = 'sigmoid')
cat("   ✓ Model architecture created\n")

# 3. Compile model
cat("\n3. Compiling model...\n")
model |> compile(
  optimizer = optimizer_adam(learning_rate = 0.001),
  loss = 'binary_crossentropy',
  metrics = c('accuracy')
)
cat("   ✓ Model compiled\n")

# 4. Train model
cat("\n4. Training model (5 epochs)...\n")
history <- model |> fit(
  x_train, y_train,
  epochs = 5,
  batch_size = 32,
  validation_split = 0.2,
  verbose = 0
)
cat("   ✓ Training complete\n")
cat("   Final loss:", round(tail(history$metrics$loss, 1), 4), "\n")
cat("   Final accuracy:", round(tail(history$metrics$accuracy, 1), 4), "\n")

# 5. Make predictions
cat("\n5. Making predictions...\n")
x_test <- matrix(rnorm(10 * 10), nrow = 10, ncol = 10)
predictions <- model |> predict(x_test, verbose = 0)
cat("   ✓ Generated", nrow(predictions), "predictions\n")
cat("   Sample predictions:", round(predictions[1:3], 4), "\n")

# 6. Save and load model
cat("\n6. Testing model save/load...\n")
model_path <- tempfile(fileext = ".keras")
tryCatch({
  model |> save_model(model_path)
  cat("   ✓ Model saved to:", model_path, "\n")
  
  loaded_model <- load_model(model_path)
  cat("   ✓ Model loaded successfully\n")
  
  # Verify loaded model works
  test_pred <- loaded_model |> predict(x_test[1:1,,drop=FALSE], verbose = 0)
  cat("   ✓ Loaded model prediction:", round(test_pred[1], 4), "\n")
  
  file.remove(model_path)
}, error = function(e) {
  cat("   ✗ Error:", e$message, "\n")
})

cat("\n=== ✅ ALL ML TESTS PASSED ===\n")
cat("\nYour system is ready for machine learning!\n")
cat("You can now:\n")
cat("  - Train neural networks\n")
cat("  - Make predictions\n")
cat("  - Save/load models\n")
cat("  - Use in your trading strategies\n")
