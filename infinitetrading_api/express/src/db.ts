/**
 * db.ts — MySQL connection pool for Express API
 *
 * Loads config from process.env (populated from express/.env via dotenv in index.ts).
 * Variables expected: db_host, db_port, db_user, db_password, db_name
 */
// eslint-disable-next-line @typescript-eslint/no-var-requires
const mysql = require('mysql');

// Pool is created lazily on first use; dotenv must already be loaded.
let _pool: any = null;

function getPool(): any {
    if (!_pool) {
        _pool = mysql.createPool({
            host: process.env.db_host || 'localhost',
            port: Number(process.env.db_port) || 3306,
            user: process.env.db_user || 'admin',
            password: process.env.db_password || '',
            database: process.env.db_name || 'infinitetrading',
            connectionLimit: 5,
            connectTimeout: 10000,
        });
    }
    return _pool;
}

/** Run a SELECT query, returns rows as an array. */
export function dbQuery(sql: string, params: any[] = []): Promise<any[]> {
    return new Promise((resolve, reject) => {
    getPool().query(sql, params, (err: any, results: any) => {
            if (err) reject(err);
            else resolve(results as any[]);
        });
    });
}

/** Run an INSERT / UPDATE / DELETE, returns affectedRows. */
export function dbExecute(sql: string, params: any[] = []): Promise<number> {
    return new Promise((resolve, reject) => {
        getPool().query(sql, params, (err: any, results: any) => {
            if (err) reject(err);
            else resolve((results.affectedRows as number) ?? 0);
        });
    });
}
