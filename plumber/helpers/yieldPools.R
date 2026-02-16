pool_mapping <- function(pool) {
        map = c()
        map$pool = pool
        map$price = NULL
        map$date = NULL
        map$benchmark = NULL
        map$name = NULL
        if (pool == "0xa2ffe6ed599e8f7aac8047f5ee0de3d83de1b320") {
                map$price = 1890
                map$date = "2023-04-27 11:38:50 AM"
                map$benchmark = "ETH-USD"
                map$name = "Ethereum Savings Account"
                map$network = "Optimism"
        }
        else if (pool == "0xe51af0ba747b9c464057b9099040f4df0b29a7de") {
                map$price = 58297.57
                map$date = "2024-05-01 09:14:31 AM"
                map$benchmark = "BTC-USD"
                map$name = "Bitcoin Yield"
                map$network = "Optimism"
        }
        else if (pool == "0x54db076bfac96c02e9a2a66410d69f35ac481fe6") {
                map$price = 3340
                map$date = "2024-04-02 10:45:01 AM"
                map$benchmark = "ETH-USD"
                map$name = "Ethereum Yield"
                map$network="Base"
        }
        else if (pool == "0x37acdfc02b78b53c9a0e21a58746cc71e23a8f05") {
                map$price = 2588.77
                map$date = "2024-01-10 02:56:15 AM"
                map$benchmark = "ETH-USD"
                map$name = "Ethereum Savings Account"
                map$network="Arbitrum"
        }
        else if (pool == "0x948720ff3f5f26f889b42e22ee8d1c23da5063a3") {
                map$price = 0.74
                map$date = "2023-07-12 01:03:33 PM"
                map$benchmark = "POL-USD"
                map$name = "Matic Yield"
                map$network="Polygon"
        }
        else if (pool == "0x08837d4bc031b9f7641e25cc901d91424081a176") {
                map$price = 1
                map$date = "2023-07-03 10:31:11 PM"
                map$benchmark = "USD"
                map$name = "USD Savings Account"
                map$network = "Optimism"
        }
        else if (pool == "0x423582afb8e8693a427bf67d76adf9f6a8e33124") {
                map$price = 1
                map$date = "2024-06-17 06:30:33 PM"
                map$benchmark = "USD"
                map$name = "USD Stablecoins Velodrome Yield"
                map$network = "Optimism"
        }
        else if (pool == "0xd770898671f6d73c6206a4517d7c92d392ce4b9f") {
                map$price = 1
                map$date = "2024-03-20 04:30:47 PM"
                map$benchmark = "USD"
                map$name = "USD Yield"
                map$network = "Base"
        }
        else if (pool == "0xc3ffa8d537e31ebf83e7f5f43b481c8101545352") {
                map$price = 1
                map$date = "2023-07-10 02:16:16 AM"
                map$benchmark = "USD"
                map$name = "USD Delta Neutral Yield"
                map$network = "Polygon"
        }
        else if (pool == "0xb1569ec05aba57fd9256ba3816ae9221f23306ee") {
                map$price = 97900
                map$date = "2024-11-24 4:21:29 PM"
                map$benchmark = "BTC-USD"
                map$name = "BTC Yield"
                map$network = "Base"
        }
        return(map)
}

pools = c("0xb1569ec05aba57fd9256ba3816ae9221f23306ee","0xc3ffa8d537e31ebf83e7f5f43b481c8101545352","0x08837d4bc031b9f7641e25cc901d91424081a176","0x423582afb8e8693a427bf67d76adf9f6a8e33124","0xd770898671f6d73c6206a4517d7c92d392ce4b9f","0xa2ffe6ed599e8f7aac8047f5ee0de3d83de1b320","0x948720ff3f5f26f889b42e22ee8d1c23da5063a3","0x37acdfc02b78b53c9a0e21a58746cc71e23a8f05","0xe51af0ba747b9c464057b9099040f4df0b29a7de","0x54db076bfac96c02e9a2a66410d69f35ac481fe6")
