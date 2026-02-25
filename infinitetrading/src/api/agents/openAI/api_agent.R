# api.R
library(plumber)
library(httr)
library(jsonlite)

# ---- Config
Sys.setenv(OPENAI_API_KEY = "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")
library(digest)

# ========= Config & Globals =========
if (!nzchar(OPENAI_API_KEY)) stop("Set OPENAI_API_KEY")

OPENAI_RESP_URL    <- "https://api.openai.com/v1/responses"
OPENAI_EMB_URL     <- "https://api.openai.com/v1/embeddings"
MODEL              <- "gpt-5"                 # pick your best reasoning model
EMBEDDINGS_MODEL   <- "text-embedding-3-large"

CMC_API_KEY        <- Sys.getenv("CMC_API_KEY")            # optional
CRYPTOPANIC_TOKEN  <- Sys.getenv("CRYPTOPANIC_TOKEN")      # optional
ETHERSCAN_API_KEY  <- Sys.getenv("ETHERSCAN_API_KEY")      # optional
COVALENT_API_KEY   <- Sys.getenv("COVALENT_API_KEY")       # optional

USER_DISCLAIMER <- paste(
  "Educational content only; not investment, legal, or tax advice.",
  "Crypto is highly volatile and carries risk, including loss of principal."
)

SYSTEM <- paste(
  "You are a crypto-focused financial education agent.",
  "- Educational only; no personalized advice or execution.",
  "- Ask for: objective, horizon, liquidity needs, general tax situation, risk tolerance.",
  "- Prefer fresh data via tools (prices, news, on-chain) then enrich with RAG snippets.",
  "- Always note risks: volatility, drawdown, concentration, smart-contract risk, fees, taxes.",
  "- If asked for specific trades/suitability, refuse gently and provide frameworks instead.",
  sep = "\n"
)

# In-memory RAG store (persist to .rds)
RAG_PATH <- "rag_store.rds"
rag_store <- if (file.exists(RAG_PATH)) readRDS(RAG_PATH) else data.frame(
  id=character(), text=character(), metadata=I(list()), embedding=I(list()), stringsAsFactors=FALSE
)

save_rag <- function() saveRDS(rag_store, RAG_PATH)

# ========= Small Utility Layer =========
http_get_json <- function(url, headers=list(), query=list(), tries=3, sleep_secs=0.5) {
  for (i in seq_len(tries)) {
    resp <- GET(url, add_headers(.headers = headers), query = query)
    if (!http_error(resp)) {
      return(content(resp, as="parsed", type="application/json", simplifyVector=FALSE))
    }
    Sys.sleep(sleep_secs * i)
  }
  stop("GET failed: ", url, "\n", content(resp, "text", encoding="UTF-8"))
}

http_post_json <- function(url, headers=list(), body=list(), tries=3, sleep_secs=0.5) {
  for (i in seq_len(tries)) {
    resp <- POST(url, add_headers(.headers = headers),
                 body = body, encode="json")
    if (!http_error(resp)) {
      return(content(resp, as="parsed", type="application/json", simplifyVector=FALSE))
    }
    Sys.sleep(sleep_secs * i)
  }
  stop("POST failed: ", url, "\n", content(resp, "text", encoding="UTF-8"))
}

cosine_sim <- function(a, b) {
  ax <- sqrt(sum(a*a)); bx <- sqrt(sum(b*b))
  if (ax==0 || bx==0) return(0)
  sum(a*b)/(ax*bx)
}

`%||%` <- function(x, y) if (is.null(x)) y else x

# ========= OpenAI Helpers =========
openai_responses <- function(body_list) {
  http_post_json(
    OPENAI_RESP_URL,
    headers=list(
      Authorization = paste("Bearer", OPENAI_API_KEY),
      "Content-Type" = "application/json"
    ),
    body = body_list
  )
}

openai_embed <- function(texts) {
  res <- http_post_json(
    OPENAI_EMB_URL,
    headers=list(
      Authorization = paste("Bearer", OPENAI_API_KEY),
      "Content-Type" = "application/json"
    ),
    body=list(model=EMBEDDINGS_MODEL, input=texts)
  )
  # return list of numeric vectors
  lapply(res$data, function(d) unlist(d$embedding))
}

# ========= Providers: Prices =========

# CoinGecko (no key): ids like "bitcoin,ethereum", vs_currencies="usd"
coingecko_prices <- function(ids, vs="usd") {
  url <- "https://api.coingecko.com/api/v3/simple/price"
  q <- list(ids=paste(ids, collapse=","), vs_currencies=vs,
            include_24hr_change="true", include_last_updated_at="true")
  r <- http_get_json(url, query=q)
  now <- as.integer(Sys.time())
  out <- list()
  for (id in ids) {
    rec <- r[[id]]
    if (!is.null(rec)) {
      out[[id]] <- list(
        price = as.numeric(rec[[vs]] %||% NA),
        change_24h = as.numeric(rec[[paste0(vs,"_24h_change")]] %||% NA),
        provider = "coingecko",
        asOf = rec$last_updated_at %||% now
      )
    }
  }
  out
}

# CoinMarketCap (needs CMC_API_KEY): symbols "BTC,ETH"
cmc_prices <- function(symbols, convert="USD") {
  if (!nzchar(CMC_API_KEY)) return(NULL)
  url <- "https://pro-api.coinmarketcap.com/v2/cryptocurrency/quotes/latest"
  r <- http_get_json(url,
                     headers=list("X-CMC_PRO_API_KEY"=CMC_API_KEY),
                     query=list(symbol=paste(symbols, collapse=","), convert=convert))
  out <- list()
  data <- r$data %||% list()
  for (sym in symbols) {
    d <- data[[sym]]
    if (is.null(d) || length(d)<1) next
    q <- d[[1]]$quote[[convert]]
    out[[sym]] <- list(
      price = as.numeric(q$price %||% NA),
      change_24h = as.numeric(q$percent_change_24h %||% NA),
      provider = "coinmarketcap",
      asOf = q$last_updated %||% ""
    )
  }
  out
}

# Coinbase Exchange public (no key): product like "BTC-USD"
coinbase_ticker <- function(product_id) {
  url <- paste0("https://api.exchange.coinbase.com/products/", product_id, "/ticker")
  r <- http_get_json(url, headers=list("User-Agent"="plumber-agent"))
  list(
    price = as.numeric(r$price %||% NA),
    provider = "coinbase",
    asOf = r$time %||% ""
  )
}

# Unified price fetcher: accepts symbols (BTC, ETH) and/or coingecko ids
get_crypto_quotes <- function(symbols = NULL, ids = NULL) {
  res <- list()

  # 1) Try CoinMarketCap by symbols (if key)
  if (!is.null(symbols) && nzchar(CMC_API_KEY)) {
    res$cmc <- cmc_prices(symbols)
  }

  # 2) Try CoinGecko by ids (no key). If only symbols provided, map common cases
  if (!is.null(ids)) {
    res$cgecko <- coingecko_prices(ids)
  } else if (!is.null(symbols)) {
    # naive symbol->id map for common majors; expand as needed
    map <- c(BTC="bitcoin", ETH="ethereum", SOL="solana", MATIC="matic-network",
             BNB="binancecoin", XRP="ripple", ADA="cardano", DOGE="dogecoin",
             AVAX="avalanche-2", DOT="polkadot")
    ids2 <- unname(na.omit(map[symbols]))
    if (length(ids2)) res$cgecko <- coingecko_prices(ids2)
  }

  # 3) Also fetch Coinbase public tickers for provided symbols (USD pairs)
  if (!is.null(symbols)) {
    cb <- list()
    for (sym in symbols) {
      pid <- paste0(sym, "-USD")
      cb[[sym]] <- coinbase_ticker(pid)
    }
    res$coinbase <- cb
  }

  res
}

# ========= News: CryptoPanic (optional) =========
cryptopanic_news <- function(currencies=NULL, public=TRUE, kind=c("news","media"),
                             regions=NULL, limit=20) {
  if (!nzchar(CRYPTOPANIC_TOKEN)) return(list())
  url <- "https://cryptopanic.com/api/v1/posts/"
  q <- list(auth_token=CRYPTOPANIC_TOKEN,
            filter=if (public) "rising" else "hot",
            kind=paste(kind, collapse=","),
            currencies=if (is.null(currencies)) NULL else paste(currencies, collapse=","),
            regions=if (is.null(regions)) NULL else paste(regions, collapse=","),
            public="true",
            page=1)
  r <- http_get_json(url, query=q)
  posts <- r$results %||% list()
  out <- lapply(head(posts, limit), function(p) {
    list(
      title = p$title %||% "",
      source = p$source$domain %||% "",
      published = p$published_at %||% "",
      url = p$url %||% "",
      currencies = vapply(p$currencies %||% list(), function(x) x$code, ""),
      domain = p$domain %||% ""
    )
  })
  out
}

# ========= On-chain (optional) =========

# Etherscan quick stats
etherscan_eth_stats <- function() {
  if (!nzchar(ETHERSCAN_API_KEY)) return(NULL)
  base <- "https://api.etherscan.io/api"
  price <- http_get_json(base, query=list(module="stats", action="ethprice", apikey=ETHERSCAN_API_KEY))
  gas   <- http_get_json(base, query=list(module="gastracker", action="gasoracle", apikey=ETHERSCAN_API_KEY))
  list(
    eth_price_usd = as.numeric(price$result$ethusd %||% NA),
    gas_fast_gwei = as.numeric(gas$result$FastGasPrice %||% NA),
    updated = as.character(Sys.time())
  )
}

# Covalent: token holders count example (chain_id 1 = Ethereum)
covalent_token_holders <- function(chain_id=1, token_address) {
  if (!nzchar(COVALENT_API_KEY)) return(NULL)
  url <- sprintf("https://api.covalenthq.com/v1/%s/tokens/%s/token_holders/", chain_id, token_address)
  r <- http_get_json(url, query=list(key=COVALENT_API_KEY, page_size=1))
  list(holders = as.integer(r$data$pagination$total_count %||% NA))
}

# ========= RAG =========

rag_ingest <- function(id, text, metadata=list()) {
  emb <- openai_embed(text)
  row <- data.frame(
    id=id, text=text, metadata=I(list(metadata)), embedding=I(list(emb[[1]])),
    stringsAsFactors = FALSE
  )
  exists_idx <- which(rag_store$id == id)
  if (length(exists_idx)) {
    rag_store[exists_idx,] <<- row
  } else {
    rag_store <<- rbind(rag_store, row)
  }
  save_rag()
  TRUE
}

rag_search <- function(query, top_k=5) {
  if (nrow(rag_store) == 0) return(list())
  q_emb <- openai_embed(query)[[1]]
  sims <- sapply(rag_store$embedding, function(e) cosine_sim(q_emb, unlist(e)))
  idx <- order(sims, decreasing=TRUE)[seq_len(min(top_k, length(sims)))]
  lapply(idx, function(i) {
    list(id=rag_store$id[i], text=rag_store$text[i],
         metadata=rag_store$metadata[[i]], score = unname(sims[i]))
  })
}

# ========= Tool Schemas (NOTE: "function" keys are QUOTED) =========
TOOLS <- list(
  list(
    type="function",
    "function"=list(
      name="get_crypto_quotes",
      description="Get crypto quotes from multiple providers (CoinGecko, CoinMarketCap, Coinbase).",
      parameters=list(
        type="object",
        properties=list(
          symbols=list(type="array", items=list(type="string"),
                       description="e.g., ['BTC','ETH']"),
          ids=list(type="array", items=list(type="string"),
                   description="CoinGecko ids e.g., ['bitcoin','ethereum']")
        )
      )
    )
  ),
  list(
    type="function",
    "function"=list(
      name="get_crypto_news",
      description="Fetch recent crypto headlines via CryptoPanic (if token set).",
      parameters=list(
        type="object",
        properties=list(
          currencies=list(type="array", items=list(type="string"),
                          description="e.g., ['BTC','ETH']"),
          limit=list(type="integer", default=20)
        )
      )
    )
  ),
  list(
    type="function",
    "function"=list(
      name="get_onchain_stats",
      description="Basic on-chain stats (ETH price & gas via Etherscan; token holders via Covalent).",
      parameters=list(
        type="object",
        properties=list(
          token_address=list(type="string", description="ERC-20 token address for holders count (Covalent)"),
          chain_id=list(type="integer", default=1)
        )
      )
    )
  ),
  list(
    type="function",
    "function"=list(
      name="rag_search",
      description="Search previously ingested documents; returns top-K snippets.",
      parameters=list(
        type="object",
        properties=list(
          query=list(type="string"),
          top_k=list(type="integer", default=5)
        ),
        required=list("query")
      )
    )
  )
)

# ========= Structured Output Schema =========
AdviceItem <- list(
  type="object",
  properties=list(
    title=list(type="string"),
    summary=list(type="string"),
    tickers=list(type="array", items=list(type="string"), default=list()),
    data=list(type="object", description="Optional raw data used for the analysis")
  ),
  required=list("title","summary")
)

AdvisorReplySchema <- list(
  type="object",
  properties=list(
    intent=list(type="string", enum=list("education","portfolio_question","macro_view","risk_warning")),
    disclaimer=list(type="string"),
    items=list(type="array", items=AdviceItem, default=list()),
    followups=list(type="array", items=list(type="string"), default=list())
  ),
  required=list("intent","disclaimer")
)

RESPONSE_FORMAT <- list(
  type="json_schema",
  json_schema=list(name="AdvisorReply", schema=AdvisorReplySchema)
)

# ========= Orchestration =========
make_messages <- function(system, user) {
  list(list(role="system", content=system),
       list(role="user",   content=user))
}

extract_tool_calls <- function(rsp) {
  out <- rsp$output
  if (is.null(out) || !is.list(out)) return(list())
  Filter(function(x) is.list(x) && identical(x$type,"tool_call"), out)
}

append_tool_messages <- function(base_msgs, tool_calls, tool_results) {
  msgs <- base_msgs
  for (tc in tool_calls) {
    if (!is.null(tool_results[[tc$id]])) {
      msgs <- append(msgs, list(list(
        role="tool",
        name=tc$name,
        content=jsonlite::toJSON(tool_results[[tc$id]], auto_unbox=TRUE),
        tool_call_id=tc$id
      )))
    }
  }
  msgs
}

# ========= Endpoints =========

#* Health
#* @get /ping
function() list(ok=TRUE, time=as.character(Sys.time()))

#* Ingest document for RAG
#* @post /ingest
function(req, res) {
  body <- tryCatch(fromJSON(req$postBody, simplifyVector=TRUE), error=function(e) NULL)
  if (is.null(body$id) || is.null(body$text)) {
    res$status <- 400; return(list(error="Required: id, text. Optional: metadata"))
  }
  metadata <- body$metadata %||% list()
  ok <- rag_ingest(body$id, body$text, metadata)
  list(ok=ok)
}

#* Advise (POST JSON: {"q":"..."} )
#* @post /advise
function(req, res) {
  body <- tryCatch(fromJSON(req$postBody, simplifyVector=TRUE), error=function(e) NULL)
  q <- if (!is.null(body$q)) body$q else "What are current crypto market risks for a 2–3 year horizon?"

  base_messages <- make_messages(SYSTEM, q)

  first <- openai_responses(list(
    model = MODEL,
    input = base_messages,
    tools = TOOLS,
    tool_choice = "auto",
    response_format = RESPONSE_FORMAT
  ))

  tool_calls <- extract_tool_calls(first)
  final <- first

  if (length(tool_calls) > 0) {
    tool_results <- list()

    for (tc in tool_calls) {
      nm <- tc$name
      args <- tc$arguments %||% list()

      if (identical(nm, "get_crypto_quotes")) {
        syms <- args$symbols %||% NULL
        ids  <- args$ids %||% NULL
        tool_results[[tc$id]] <- get_crypto_quotes(syms, ids)

      } else if (identical(nm, "get_crypto_news")) {
        currs <- args$currencies %||% NULL
        lim   <- args$limit %||% 20
        tool_results[[tc$id]] <- cryptopanic_news(currs, limit=lim)

      } else if (identical(nm, "get_onchain_stats")) {
        token_address <- args$token_address %||% NULL
        chain_id      <- args$chain_id %||% 1
        stats <- list(etherscan = etherscan_eth_stats())
        if (!is.null(token_address)) {
          stats$covalent <- covalent_token_holders(chain_id, token_address)
        }
        tool_results[[tc$id]] <- stats

      } else if (identical(nm, "rag_search")) {
        query <- args$query %||% ""
        k     <- args$top_k %||% 5
        tool_results[[tc$id]] <- rag_search(query, k)
      }
    }

    messages2 <- append_tool_messages(base_messages, tool_calls, tool_results)

    final <- openai_responses(list(
      model = MODEL,
      input = messages2,
      tools = TOOLS,
      response_format = RESPONSE_FORMAT
    ))
  }

  payload <- final$output_parsed
  if (is.null(payload)) {
    # fallback plain text
    text <- tryCatch({
      pieces <- final$output
      paste(vapply(pieces, function(p) if (!is.null(p$text)) p$text else "", character(1)), collapse="\n")
    }, error=function(e) "No structured output.")
    payload <- list(
      intent="education",
      disclaimer=USER_DISCLAIMER,
      items=list(list(title="Response", summary=text, tickers=list())),
      followups=list("Provide your objective, horizon, and risk tolerance to refine the analysis.")
    )
  }

  if (is.null(payload$disclaimer) || !nzchar(payload$disclaimer)) {
    payload$disclaimer <- USER_DISCLAIMER
  }

  res$status <- 200
  res$body <- toJSON(payload, auto_unbox=TRUE, pretty=TRUE)
  res
}

