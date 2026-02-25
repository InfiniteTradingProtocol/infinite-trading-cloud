require(dotenv)
load_dot_env("~/infinitetrading/src/api/.env")


db_connect = function(user,hostname,port,password,dbname){
        default_authentication_plugin=password
        con = dbConnect(RMariaDB::MariaDB(),user = user, password = password, dbname = dbname,hostname = hostname)
        return(con)
}
db_con = function() {
        con = db_connect(Sys.getenv("db_user"),Sys.getenv("db_ip"),Sys.getenv("db_port"),Sys.getenv("db_password"),dbname=Sys.getenv("db_schema"))
        return(con)
}
print_table_contents(conn,"dhedge_polygon_sides")
conn = db_con()

test = FALSE
if (test) {
        print("deleting all tables")
        tables = c("coins","uniV3Fees","pairs","networks","protocols","polygon_dhedge_sides","polygon_dhedge_gas_wallets")
        for (table in tables) { delete_table(table) }
        print("listing all tables") 
	source("~/infinitetrading/src/api/mySQL/listAllTables.R")

	print("creating tables")
        source("~/infinitetrading/src/api/mySQL/createAllTables.R")

        print("networks table structure"); print_table_structure(conn, "networks")
        print("protcols table structure"); print_table_structure(conn, "protocols")
        print("pairs table structure"); print_table_structure(conn, "pairs")
        print("platforms table structure"); print_table_structure(conn, "platforms")
        print("fees table structure"); print_table_structure(conn, "uniV3Fees")
        print("coins table structure"); print_table_structure(conn, "coins")
	source("~/infinitetrading/src/api/mySQL/addNetworks.R")
        print("adding all networks"); add_networks(conn, c("optimism", "polygon", "arbitrum","base"))
        print("table content for networks"); print_table_contents(conn,"networks")
        print("removing base arbitrum and optimism"); remove_networks(conn, c("base", "arbitrum","optimism"))
        print("table content for networks"); print_table_contents(conn,"networks")
        print("adding all networks"); add_networks(conn, c("optimism", "polygon", "arbitrum","base"))

        print("adding all coins from the csv"); updateCoins()

        print("table content for coins"); print_table_contents(conn,"coins")
        print("readable table content for coins"); print(getCoins(conn))

        print("adding all protocols"); add_protocols(conn, c("dhedge", "defund","enzyme","valio"))

        print("adding all pairs for optimism")
        add_pairs(conn, "optimism", c("WBTC-USDC","WSTETH-USDC","WETH-USDC","VELO-USDC","OP-USDC","SNX-USDC"))

        print("adding all pairs for polygon")
        add_pairs(conn, "polygon", c("WBTC-USDC","WETH-USDC","wMATIC-USDC","STMATIC-USDC","SNX-USDC","LINK-USDC","GNS-USDC","LDO-USDC"))

        print("adding all pairs for arbitrum")
        add_pairs(conn, "arbitrum", c("WBTC-USDC","WETH-USDC","WSTETH-USDC","ARB-USDC"))

        print("adding all pairs for base")
        add_pairs(conn, "base", c("WBTC-USDC","WETH-USDC","WSTETH-USDC","AERO-USDC"))

        print("adding uniswapV3 platform"); add_platforms(conn,"uniswapv3")

        print("adding uniswapV3 fees for polygon")
        add_fees(conn, network="polygon", pairs=c("WETH-USDC","WBTC-USDC","WMATIC-USDC","STMATIC-USDC","LINK-USDC","SNX-USDC","GNS-USDC","LDO-USDC"),fees=c(500,500,3000,3000,3000,3000,3000,3000))
        print("Adding uniswapV3 Fees for optimism")
        add_fees(conn, network="optimism", pairs=c("WETH-USDC","WBTC-USDC","SNX-USDC","OP-USDC"),fees=c(500,500,3000,3000))

        print("removing enzyme and valio"); remove_protocols(conn, c("enzyme", "valio"))

        print("printing table content for networks"); print_table_contents(conn, "networks")
        print("printing table content for protocols"); print_table_contents(conn, "protocols")
        print("printing table content for pairs"); print_table_contents(conn, "pairs")
        print("printing table content for platforms"); print_table_contents(conn, "platforms")

        print("is valid network base?(NO)"); print(is_valid_network("base"))
        #initial = Sys.time()
        #print("is valid network fetched polygon (YES)"); print(is_valid_network_fetched("polygon"))
        #final = Sys.time()
        #print(paste0("execution time: ",final - initial))
        #initial = Sys.time()
        #print("is valid network fetched polygon (YES)"); print(is_valid_network_fetched("polygon"))
        #final = Sys.time()
        #print(paste0("execution time: ",final - initial))
        #print("cache data"); print(fetch_data)
        print("is valid network polygon?(YES)"); print(is_valid_network("polygon"))
        print("is valid protocol dhedge(YES)"); print(is_valid_protocol("dhedge"))
        print("is valid protocol enzyme?(NO)"); print(is_valid_protocol("enzyme"))
        print("is valid platform uniswapV3?(YES)"); print(is_valid_platform("uniswapV3"))
        print("is valid platform 1inch?(NO)"); print(is_valid_platform("1inch"))
        print("is valid network polygon pair wmatic-usdc?(YES)"); print(is_valid_pair("polygon","wmatic-usdc"))
        print("is valid network polygon link-weth?(NO)"); print(is_valid_pair("polygon","link"))

        print("getting univ3 WETH-USDC polygon fee"); print(getUniV3Fee(network="polygon",pair="WETH-USDC"))
        print("getting univ3 WBTC-USDC polygon fee"); print(getUniV3Fee(network="polygon",pair="WBTC-USDC"))
        print("getting univ3 WETH-USDC optimism fee"); print(getUniV3Fee(network="optimism",pair="WETH-USDC"))
        print("getting univ3 WBTC-USDC LINEA fee (invalid network)"); print(getUniV3Fee(network="linea",pair="WBTC-USDC"))
        print("getting univ3 OP-USDC polygon fee (invalid pair)"); print(getUniV3Fee(network="polygon",pair="OP-USDC"))

        print("getting contract for WBTC on polygon"); contract = getContract(conn, network="polygon", symbol="WBTC"); print(contract)
        print("getting symbol for WBTC contract on polygon"); print(getSymbol(conn,network="polygon",contract=contract))
}
