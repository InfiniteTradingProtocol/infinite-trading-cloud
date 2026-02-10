import { ethers, Network } from "@dhedge/v2-sdk";
import { Router } from "express";

const investRouter = Router();
import { Request, Response } from "express";
import { dhedge } from "../dhedge";

// Error response helper
function sendErrorResponse(res: Response, statusCode: number, errorCode: number, message: string, errorType: string, details?: any) {
  const response: any = {
    status: "fail",
    status_code: errorCode,
    message: message,
    error_type: errorType
  };
  if (details) {
    response.details = details;
  }
  res.status(statusCode).send(response);
}

investRouter.post("/approveDeposit", async (req: Request, res: Response) => {
  try {
    let network = Network.POLYGON;
    if (req.query.network) network = req.query.network as Network;
    const poolAddress = req.query.pool as string;
    const pool = await dhedge(network).loadPool(poolAddress);
    const tx = await pool.approveDeposit(
      req.body.asset,
      ethers.constants.MaxUint256
    );
    res.status(200).send({ status: "success", msg: tx.hash });
  } catch (err) {
    const message = (err instanceof Error) ? err.message : String(err);
    sendErrorResponse(res, 400, 4001, message, "approve_deposit_failed");
  }
});

investRouter.post("/deposit", async (req: Request, res: Response) => {
  try {
    let network = Network.POLYGON;
    if (req.query.network) network = req.query.network as Network;
    const poolAddress = req.query.pool as string;
    const pool = await dhedge(network).loadPool(poolAddress);
    const tx = await pool.deposit(req.body.asset, req.body.amount);
    res.status(200).send({ status: "success", msg: tx.hash });
  } catch (err) {
    const message = (err instanceof Error) ? err.message : String(err);
    sendErrorResponse(res, 400, 4002, message, "deposit_failed");
  }
});

export default investRouter;
