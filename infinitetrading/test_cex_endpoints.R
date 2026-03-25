##########################################################################
# CEX API Endpoints Test Script
# 
# Fill in your credentials below and run each test section
##########################################################################

require(httr)
require(jsonlite)

# ============================================================
# CONFIGURATION - FILL IN YOUR VALUES
# ============================================================

# API Endpoint
API_URL <- "http://localhost:8003"  # or "https://api.infinitetrading.io"

# Your Manager Wallet (Ethereum address)
MANAGER_WALLET <- "0x..."  # TODO: Fill in your wallet address

# Your Gas Wallet API Key (from associated_gas_wallets)
GAS_WALLET_API_KEY <- "0x..."  # TODO: Fill in your gas wallet API key (private key)

# Your Signature (sign the message below with your wallet)
# Message to sign: "Sign this message to authenticate with dHEDGE Gas Wallet Manager.\n\nThis signature will be used to verify your identity for secure operations."
SIGNATURE <- "0x..."  # TODO: Fill in your signature

# CEX Credentials (for registration only)
CEX_EXCHANGE <- "coinbase"  # or "binance", "okx", etc.
CEX_SUBACCOUNT_NAME <- "test_account_1"
CEX_API_KEY <- ""  # TODO: Fill in your CEX API key
CEX_SECRET <- ""  # TODO: Fill in your CEX secret
CEX_PASSPHRASE <- ""  # Optional, for exchanges that require it (e.g., Coinbase Pro)

# Trading Parameters
TEST_PAIR <- "BTC-USD"
TEST_SIDE <- "long"  # or "neutral"
TEST_MAX_USD <- 100
TEST_SHARE <- 1.0
TEST_STRATEGY <- "custom"  # or name of automated strategy

# ============================================================
# HELPER FUNCTIONS
# ============================================================

signature_message <- "Sign this message to authenticate with dHEDGE Gas Wallet Manager.\n\nThis signature will be used to verify your identity for secure operations."

print_response <- function(response_name, response) {
    cat("\n")
    cat("================================================================================\n")
    cat(sprintf("TEST: %s\n", response_name))
    cat("================================================================================\n")
    cat(sprintf("Status Code: %d\n", status_code(response)))
    content <- content(response, as = "text", encoding = "UTF-8")
    parsed <- tryCatch(fromJSON(content), error = function(e) list(raw = content))
    cat("Response:\n")
    print(parsed)
    cat("\n")
    return(parsed)
}

# ============================================================
# TEST 1: Register CEX Subaccount (One-time setup)
# ============================================================

test_register_subaccount <- function() {
    url <- paste0(
        API_URL, "/registerCEXSubaccount",
        "?manager=", URLencode(MANAGER_WALLET, reserved = TRUE),
        "&gas_wallet_api_key=", URLencode(GAS_WALLET_API_KEY, reserved = TRUE),
        "&exchange=", CEX_EXCHANGE,
        "&subaccount_name=", URLencode(CEX_SUBACCOUNT_NAME, reserved = TRUE),
        "&cex_api_key=", URLencode(CEX_API_KEY, reserved = TRUE),
        "&cex_secret=", URLencode(CEX_SECRET, reserved = TRUE),
        "&cex_passphrase=", URLencode(CEX_PASSPHRASE, reserved = TRUE),
        "&signature=", URLencode(SIGNATURE, reserved = TRUE)
    )
    
    response <- POST(url)
    result <- print_response("Register CEX Subaccount", response)
    
    if (!is.null(result$subaccount_id)) {
        cat(sprintf("✅ SUCCESS: Subaccount registered with ID: %d\n", result$subaccount_id))
        cat(sprintf("   Gas Balance: $%.2f\n", result$gas_balance_usd))
    } else {
        cat(sprintf("❌ FAILED: %s\n", result$message))
    }
    
    return(result)
}

# ============================================================
# TEST 2: Set CEX Side (Create/Update Bot)
# ============================================================

test_set_cex_side <- function() {
    url <- paste0(
        API_URL, "/setCEXSide",
        "?gas_wallet_api_key=", URLencode(GAS_WALLET_API_KEY, reserved = TRUE),
        "&subaccount_name=", URLencode(CEX_SUBACCOUNT_NAME, reserved = TRUE),
        "&pair=", TEST_PAIR,
        "&side=", TEST_SIDE,
        "&max_usd=", TEST_MAX_USD,
        "&share=", TEST_SHARE,
        "&strategy=", TEST_STRATEGY
    )
    
    response <- POST(url)
    result <- print_response("Set CEX Side", response)
    
    if (!is.null(result$bot_id)) {
        cat(sprintf("✅ SUCCESS: Bot %s with ID: %d\n", 
                   ifelse(result$side_changed, "updated", "created"), 
                   result$bot_id))
        cat(sprintf("   Side: %s\n", result$side))
        if (!is.null(result$previous_side)) {
            cat(sprintf("   Previous Side: %s\n", result$previous_side))
        }
    } else {
        cat(sprintf("❌ FAILED: %s\n", result$message))
    }
    
    return(result)
}

# ============================================================
# TEST 3: Set CEX Strategy (Switch to automated strategy)
# ============================================================

test_set_cex_strategy <- function() {
    url <- paste0(
        API_URL, "/setCEXStrategy",
        "?gas_wallet_api_key=", URLencode(GAS_WALLET_API_KEY, reserved = TRUE),
        "&subaccount_name=", URLencode(CEX_SUBACCOUNT_NAME, reserved = TRUE),
        "&pair=", TEST_PAIR,
        "&strategy=", "ema_rsi"  # Example strategy name
    )
    
    response <- POST(url)
    result <- print_response("Set CEX Strategy", response)
    
    if (result$status == "success") {
        cat("✅ SUCCESS: Strategy updated\n")
    } else {
        cat(sprintf("❌ FAILED: %s\n", result$message))
    }
    
    return(result)
}

# ============================================================
# TEST 4: Get All CEX Subaccounts (View with signature)
# ============================================================

test_get_all_subaccounts <- function() {
    url <- paste0(
        API_URL, "/getAllCEXSubaccounts",
        "?manager=", URLencode(MANAGER_WALLET, reserved = TRUE),
        "&signature=", URLencode(SIGNATURE, reserved = TRUE)
    )
    
    response <- GET(url)
    result <- print_response("Get All CEX Subaccounts", response)
    
    if (!is.null(result$subaccounts)) {
        cat(sprintf("✅ SUCCESS: Found %d subaccount(s)\n", length(result$subaccounts)))
        for (i in seq_along(result$subaccounts)) {
            sub <- result$subaccounts[[i]]
            cat(sprintf("\n   Subaccount %d:\n", i))
            cat(sprintf("   - Name: %s\n", sub$subaccount_name))
            cat(sprintf("   - Exchange: %s\n", sub$exchange))
            cat(sprintf("   - Active: %s\n", sub$is_active))
            cat(sprintf("   - Balance: $%.2f\n", sub$total_balance_usd))
            cat(sprintf("   - Gas Balance: $%.2f\n", sub$gas_balance_usd))
            cat(sprintf("   - Total Bots: %d\n", sub$total_bots))
            cat(sprintf("   - Active Bots: %d\n", sub$active_bots))
        }
    } else {
        cat(sprintf("❌ FAILED: %s\n", result$message))
    }
    
    return(result)
}

# ============================================================
# TEST 5: Deactivate CEX Bot
# ============================================================

test_deactivate_bot <- function() {
    url <- paste0(
        API_URL, "/deactivateCEXBot",
        "?gas_wallet_api_key=", URLencode(GAS_WALLET_API_KEY, reserved = TRUE),
        "&subaccount_name=", URLencode(CEX_SUBACCOUNT_NAME, reserved = TRUE),
        "&pair=", TEST_PAIR
    )
    
    response <- POST(url)
    result <- print_response("Deactivate CEX Bot", response)
    
    if (result$status == "success") {
        cat("✅ SUCCESS: Bot deactivated\n")
    } else {
        cat(sprintf("❌ FAILED: %s\n", result$message))
    }
    
    return(result)
}

# ============================================================
# TEST 6: Delete CEX Bot
# ============================================================

test_delete_bot <- function() {
    url <- paste0(
        API_URL, "/deleteCEXBot",
        "?gas_wallet_api_key=", URLencode(GAS_WALLET_API_KEY, reserved = TRUE),
        "&subaccount_name=", URLencode(CEX_SUBACCOUNT_NAME, reserved = TRUE),
        "&pair=", TEST_PAIR
    )
    
    response <- DELETE(url)
    result <- print_response("Delete CEX Bot", response)
    
    if (result$status == "success") {
        cat("✅ SUCCESS: Bot deleted\n")
    } else {
        cat(sprintf("❌ FAILED: %s\n", result$message))
    }
    
    return(result)
}

# ============================================================
# TEST 7: Delete CEX Subaccount (with signature)
# ============================================================

test_delete_subaccount <- function() {
    url <- paste0(
        API_URL, "/deleteCEXSubaccount",
        "?manager=", URLencode(MANAGER_WALLET, reserved = TRUE),
        "&subaccount_name=", URLencode(CEX_SUBACCOUNT_NAME, reserved = TRUE),
        "&signature=", URLencode(SIGNATURE, reserved = TRUE)
    )
    
    response <- DELETE(url)
    result <- print_response("Delete CEX Subaccount", response)
    
    if (result$status == "success") {
        cat("✅ SUCCESS: Subaccount deleted (all bots removed)\n")
    } else {
        cat(sprintf("❌ FAILED: %s\n", result$message))
    }
    
    return(result)
}

# ============================================================
# RUN ALL TESTS
# ============================================================

run_all_tests <- function() {
    cat("\n")
    cat("################################################################################\n")
    cat("# CEX API ENDPOINT TESTS\n")
    cat("################################################################################\n")
    cat("\n")
    cat("Configuration:\n")
    cat(sprintf("  API URL: %s\n", API_URL))
    cat(sprintf("  Manager Wallet: %s\n", MANAGER_WALLET))
    cat(sprintf("  Gas Wallet API Key: %s...\n", substr(GAS_WALLET_API_KEY, 1, 10)))
    cat(sprintf("  Subaccount Name: %s\n", CEX_SUBACCOUNT_NAME))
    cat(sprintf("  Exchange: %s\n", CEX_EXCHANGE))
    cat("\n")
    
    # Test sequence
    cat("Starting tests...\n\n")
    
    # 1. Register subaccount
    test_register_subaccount()
    Sys.sleep(1)
    
    # 2. Set bot side
    test_set_cex_side()
    Sys.sleep(1)
    
    # 3. View all subaccounts
    test_get_all_subaccounts()
    Sys.sleep(1)
    
    # 4. Deactivate bot
    test_deactivate_bot()
    Sys.sleep(1)
    
    # 5. View again to confirm deactivation
    test_get_all_subaccounts()
    
    cat("\n")
    cat("################################################################################\n")
    cat("# ALL TESTS COMPLETE\n")
    cat("################################################################################\n")
    cat("\n")
    cat("To clean up, uncomment and run:\n")
    cat("# test_delete_bot()  # Delete specific bot\n")
    cat("# test_delete_subaccount()  # Delete entire subaccount\n")
    cat("\n")
}

# ============================================================
# INSTRUCTIONS
# ============================================================

cat("\n")
cat("################################################################################\n")
cat("# CEX API Test Script\n")
cat("################################################################################\n")
cat("\n")
cat("1. Fill in your credentials at the top of this file\n")
cat("2. Run individual tests:\n")
cat("   - test_register_subaccount()    # Register new subaccount\n")
cat("   - test_set_cex_side()          # Create/update bot\n")
cat("   - test_set_cex_strategy()      # Switch to automated strategy\n")
cat("   - test_get_all_subaccounts()   # View all subaccounts\n")
cat("   - test_deactivate_bot()        # Pause a bot\n")
cat("   - test_delete_bot()            # Delete a bot\n")
cat("   - test_delete_subaccount()     # Delete subaccount (CASCADE)\n")
cat("\n")
cat("3. Or run all tests in sequence:\n")
cat("   - run_all_tests()\n")
cat("\n")
cat("To get your signature:\n")
cat("  Message: Sign this message to authenticate with dHEDGE Gas Wallet Manager.\n\n")
cat("           This signature will be used to verify your identity for secure operations.\n")
cat("\n")
cat("  Use MetaMask or web3.js to sign this message with your wallet.\n")
cat("################################################################################\n")
cat("\n")

# Example signature from testing
# manager="0x8893Ca7295Dfb55260Ee0db7FAa03AC8dCD8F5f5"
# signature="0xbb386c636b399080d73841476fed1bf353383ff5b30967f7e22ba977f116846e22266a6281a8ea01768c119b9fd97cbf6d5b47692f1bad2ea149f049fee5cad01c"
