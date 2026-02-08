"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
var express_1 = require("express");
var trade_fixed_1 = require("./requests/trade_fixed");
var app = (0, express_1.default)();
var PORT = 8001;
app.use(express_1.default.urlencoded({ extended: true }));
app.use(express_1.default.json());
app.use(trade_fixed_1.default);
app.listen(PORT, function () {
    console.log("\u26A1\uFE0F[TEST SERVER]: Running on http://localhost:".concat(PORT));
    console.log("Test endpoints:");
    console.log("  - GET  http://localhost:".concat(PORT, "/trade"));
    console.log("  - POST http://localhost:".concat(PORT, "/approve"));
    console.log("  - GET  http://localhost:".concat(PORT, "/checkAllowance"));
});
