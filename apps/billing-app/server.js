import express from "express";
import amqp from "amqplib";
import pkg from "pg";
const { Pool } = pkg;

const PORT = process.env.PORT || 8080;
const RABBITMQ_URL = process.env.RABBITMQ_URL || "amqp://user:pass@rabbitmq-svc:5672";
const RABBITMQ_QUEUE = process.env.RABBITMQ_QUEUE || "orders";

const DB_HOST = process.env.DB_HOST || "billing-db";
const DB_PORT = Number(process.env.DB_PORT || "5432");
const DB_NAME = process.env.DB_NAME || "orders";
const DB_USER = process.env.DB_USER || "billing_user";
const DB_PASS = process.env.DB_PASSWORD || "billing_pass";

const app = express();
app.get("/health", (_req, res) => res.json({ ok: true }));
app.listen(PORT, () => console.log(`billing-app health on ${PORT}`));

const pool = new Pool({ host: DB_HOST, port: DB_PORT, database: DB_NAME, user: DB_USER, password: DB_PASS });

async function initDb() {
  const c = await pool.connect();
  try {
    await c.query(`CREATE TABLE IF NOT EXISTS orders (
      id SERIAL PRIMARY KEY,
      user_id INT NOT NULL,
      number_of_items INT NOT NULL,
      total_amount NUMERIC NOT NULL,
      created_at TIMESTAMP DEFAULT NOW()
    );`);
    console.log("[billing] DB ready");
  } finally {
    c.release();
  }
}
initDb().catch(e => { console.error("DB init failed:", e); process.exit(1); });

async function consume() {
  while (true) {
    try {
      const conn = await amqp.connect(RABBITMQ_URL);
      const ch = await conn.createChannel();
      await ch.assertQueue(RABBITMQ_QUEUE, { durable: true });
      console.log("[billing] Connected to RabbitMQ, waiting for messages...");
      ch.consume(RABBITMQ_QUEUE, async (msg) => {
        if (!msg) return;
        try {
          const data = JSON.parse(msg.content.toString());
          const { user_id, number_of_items, total_amount } = data;
          await pool.query(
            "INSERT INTO orders(user_id, number_of_items, total_amount) VALUES ($1,$2,$3)",
            [Number(user_id), Number(number_of_items), Number(total_amount)]
          );
          ch.ack(msg);
        } catch (e) {
          console.error("Processing failed:", e);
          ch.nack(msg, false, true);
        }
      }, { noAck: false });
      return;
    } catch (e) {
      console.error("[billing] RabbitMQ connect failed, retry in 3s:", e.message);
      await new Promise(r => setTimeout(r, 3000));
    }
  }
}
consume();
