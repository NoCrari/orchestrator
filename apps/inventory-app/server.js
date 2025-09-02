import express from "express";
import pkg from "pg";
const { Pool } = pkg;

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 8080;
const DB_HOST = process.env.DB_HOST || "inventory-db";
const DB_PORT = Number(process.env.DB_PORT || "5432");
const DB_NAME = process.env.DB_NAME || "inventory";
const DB_USER = process.env.DB_USER || "inventory_user";
const DB_PASS = process.env.DB_PASSWORD || "inventory_pass";

const pool = new Pool({
  host: DB_HOST, port: DB_PORT, database: DB_NAME, user: DB_USER, password: DB_PASS
});

async function init() {
  const client = await pool.connect();
  try {
    await client.query(`CREATE TABLE IF NOT EXISTS movies (
      id SERIAL PRIMARY KEY,
      title TEXT NOT NULL,
      description TEXT,
      created_at TIMESTAMP DEFAULT NOW()
    );`);
    console.log("[inventory] DB ready");
  } finally {
    client.release();
  }
}
init().catch(err => {
  console.error("DB init failed:", err);
  process.exit(1);
});

app.post("/api/movies", async (req, res) => {
  const { title, description } = req.body || {};
  if (!title) return res.status(400).json({ error: "title required" });
  try {
    const r = await pool.query("INSERT INTO movies(title, description) VALUES ($1,$2) RETURNING *",
      [title, description || null]);
    res.json(r.rows[0]);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: "db error" });
  }
});

app.get("/api/movies", async (_req, res) => {
  try {
    const r = await pool.query("SELECT * FROM movies ORDER BY id DESC LIMIT 10");
    res.json(r.rows);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: "db error" });
  }
});

app.get("/health", (_req, res) => res.json({ ok: true }));

app.listen(PORT, () => console.log(`inventory-app listening on ${PORT}`));
