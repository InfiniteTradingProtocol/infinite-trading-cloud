/// sudo npm install mysql
//import { wallet } from "../wallet";
//const network = 'polygon' as Network
//const signer = wallet(network,'infinitetrading')

import { ethers, Network } from "@dhedge/v2-sdk";
import { dhedge } from "../../dhedge";
require("dotenv").config({ path: '../../../.env' });
import * as mysql from "mysql";
import * as crypto from "crypto";

const db_username: string = process.env.db_username!;
const db_password: string = process.env.db_password!;
const db_host: string = process.env.db_host!;
const db_port: string = process.env.db_port!;
const connection = mysql.createConnection({host: db_host, user: db_username, password: db_password, database: 'infinitetrading'});

async function createWallet() {
    try {
        const wallet = ethers.Wallet.createRandom();
        console.log("Wallet created successfully:", wallet.address);
        return {
            status: "success", 
	    address: wallet.address,
            privateKey: wallet.privateKey
        };
    } catch (err) {
        console.error("Error creating wallet:", err);
        return {
            status: "fail",
	    message: err
        };
    }
}
