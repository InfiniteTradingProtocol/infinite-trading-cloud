#!/usr/bin/env Rscript
# Test script to verify CEX subaccounts endpoint updates
# Tests: 1) payment_network field present, 2) balances showing correctly

library(httr)
library(jsonlite)

API_URL <- "https://api.infinitetrading.io"

# Replace with your actual credentials
MANAGER_WALLET <- readline(prompt = "Enter manager wallet address: ")
SIGNATURE <- readline(prompt = "Enter signature: ")

cat("\n=== Testing getAllCEXSubaccounts Endpoint ===\n")

# Test getAllCEXSubaccounts
response <- GET(
    paste0(API_URL, "/getAllCEXSubaccounts"),
    query = list(
        manager = MANAGER_WALLET,
        signature = SIGNATURE
    )
)

cat(sprintf("\nStatus Code: %d\n", status_code(response)))

if (status_code(response) == 200) {
    result <- fromJSON(content(response, "text"))
    
    cat(sprintf("\nStatus: %s\n", result$status))
    cat(sprintf("Message: %s\n", result$message))
    
    if (!is.null(result$subaccounts) && length(result$subaccounts) > 0) {
        cat(sprintf("\n✅ Found %d subaccount(s)\n", length(result$subaccounts)))
        
        # Check each subaccount
        for (i in seq_along(result$subaccounts)) {
            sub <- result$subaccounts[[i]]
            cat(sprintf("\n--- Subaccount #%d: %s ---\n", i, sub$subaccount_name))
            cat(sprintf("Exchange: %s\n", sub$exchange))
            cat(sprintf("Gas Wallet: %s\n", sub$gas_wallet))
            
            # CHECK 1: payment_network field present
            if (!is.null(sub$payment_network)) {
                cat(sprintf("✅ Payment Network: %s\n", sub$payment_network))
            } else {
                cat("❌ Payment Network: MISSING!\n")
            }
            
            cat(sprintf("Active: %s\n", sub$is_active))
            
            # CHECK 2: Balance showing correctly
            if (!is.null(sub$total_balance_usd)) {
                balance <- as.numeric(sub$total_balance_usd)
                if (balance > 0) {
                    cat(sprintf("✅ Total Balance: $%.2f USD\n", balance))
                } else {
                    cat(sprintf("⚠️  Total Balance: $%.2f USD (might be zero or issue fetching)\n", balance))
                }
            } else {
                cat("❌ Total Balance: MISSING!\n")
            }
            
            # Show assets if available
            if (!is.null(sub$assets) && length(sub$assets) > 0) {
                cat(sprintf("\nAssets (%d):\n", length(sub$assets)))
                for (j in seq_along(sub$assets)) {
                    asset <- sub$assets[[j]]
                    cat(sprintf("  - %s: %.8f (≈ $%.2f)\n", 
                               asset$currency, 
                               as.numeric(asset$total),
                               as.numeric(asset$usd_value)))
                }
            } else {
                cat("\n⚠️  No assets found (balance might be zero)\n")
            }
            
            cat(sprintf("\nBots: %d total, %d active\n", 
                       sub$total_bots, sub$active_bots))
        }
        
        cat("\n=== Summary ===\n")
        cat("✅ All tests passed if you see payment_network and correct balances above\n")
        
    } else {
        cat("\n⚠️  No subaccounts found for this manager\n")
    }
    
} else {
    cat("\n❌ Request failed\n")
    cat(content(response, "text"), "\n")
}

cat("\nDone!\n")
