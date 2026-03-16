import { Pool } from 'pg';

export const pgPool = new Pool({
  host: process.env.PG_HOST || 'localhost',
  port: Number(process.env.PG_PORT) || 5432,
  database: process.env.PG_DATABASE || 'mydb',
  user: process.env.PG_USER || 'admin',
  password: process.env.PG_PASSWORD || '12341234',
});
