import express from "express";
import axios from "axios";
import amqp from "amqplib";

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3000;
const INVENTORY_URL = process.env.INVENTORY_URL || "http://inventory-svc:8080";
const RABBITMQ_URL = process.env.RABBITMQ_URL || "amqp://user:pass@rabbitmq-svc:5672";
const RABBITMQ_QUEUE = process.env.RABBITMQ_QUEUE || "orders";

// --- Inventory proxy endpoints ---
app.post("/api/movies", async (req, res) => {
  try {
    const r = await axios.post(`${INVENTORY_URL}/api/movies`, req.body, { timeout: 5000 });
    res.status(r.status).json(r.data);
  } catch (err) {
    console.error("Error forwarding to inventory:", err.message);
    res.status(502).json({ error: "inventory unavailable" });
  }
});

app.get("/api/movies", async (_req, res) => {
  try {
    const r = await axios.get(`${INVENTORY_URL}/api/movies`, { timeout: 5000 });
    res.status(r.status).json(r.data);
  } catch (err) {
    console.error("Error forwarding to inventory:", err.message);
    res.status(502).json({ error: "inventory unavailable" });
  }
});

// --- Billing: publish to RabbitMQ and ACK immediately
let channel;
async function initRabbit() {
  try {
    const conn = await amqp.connect(RABBITMQ_URL);
    channel = await conn.createChannel();
    await channel.assertQueue(RABBITMQ_QUEUE, { durable: true });
    console.log("[gateway] Connected to RabbitMQ");
  } catch (e) {
    console.error("[gateway] RabbitMQ connect failed, retrying in 3s:", e.message);
    setTimeout(initRabbit, 3000);
  }
}
initRabbit();

app.post("/api/billing", async (req, res) => {
  if (!channel) return res.status(503).json({ error: "queue unavailable" });
  try {
    const payload = Buffer.from(JSON.stringify(req.body));
    channel.sendToQueue(RABBITMQ_QUEUE, payload, { persistent: true });
    res.status(200).json({ status: "queued" });
  } catch (e) {
    console.error("Publish failed:", e);
    res.status(500).json({ error: "publish failed" });
  }
});

app.get("/health", (_req, res) => res.json({ ok: true }));

app.listen(PORT, () => console.log(`api-gateway listening on ${PORT}`));
