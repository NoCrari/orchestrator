// Dockerfiles/inventory-app/src/index.js

const express = require('express');
const { Pool } = require('pg');

const PORT = Number(process.env.PORT || 8080);

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// --- DB Pool (avec keepAlive) ---
const pool = new Pool({
    host: process.env.DB_HOST || 'inventory-db',
    port: Number(process.env.DB_PORT || 5432),
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME || 'inventory',
    max: 10,
    ssl: false,
    idleTimeoutMillis: 30000,
    allowExitOnIdle: false
});

// --- état de readiness applicatif ---
let ready = false;

// --- util: retry avec backoff expo ---
async function withRetry(fn, { retries = 10, baseMs = 500 } = {}) {
    let attempt = 0;
    for (; ;) {
        try { return await fn(); }
        catch (err) {
            attempt++;
            if (attempt > retries) throw err;
            const delay = Math.min(10000, baseMs * Math.pow(2, attempt)); // cap à 10s
            console.warn(`[init] tentative ${attempt}/${retries} échouée: ${err.code || err.message}. Retry dans ${delay}ms`);
            await new Promise(r => setTimeout(r, delay));
        }
    }
}

// --- Init DB (création table de démo) ---
async function initDatabase() {
    await withRetry(async () => {
        await pool.query('SELECT 1'); // test connectivité
    }, { retries: 12, baseMs: 500 });

    await pool.query(`
    CREATE TABLE IF NOT EXISTS movies (
      id SERIAL PRIMARY KEY,
      title VARCHAR(255) NOT NULL,
      description TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `);

    console.log('Database initialized ✅');
}

// --- Probes ---
app.get('/health', (_req, res) => {
    // liveness: juste prouver que le process répond
    res.status(200).json({ status: 'healthy', service: 'inventory-app' });
});

app.get('/ready', async (_req, res) => {
    // readiness: vérifie DB
    try {
        await pool.query('SELECT 1');
        ready = true;
        res.status(200).json({ status: 'ready', service: 'inventory-app' });
    } catch {
        ready = false;
        res.status(503).json({ status: 'not ready', service: 'inventory-app' });
    }
});

// --- Routes CRUD minimalistes ---
app.get('/', async (_req, res) => {
    try {
        const r = await pool.query('SELECT * FROM movies ORDER BY created_at DESC');
        res.json(r.rows);
    } catch (err) {
        console.error('Error fetching movies:', err);
        res.status(500).json({ error: 'Failed to fetch movies' });
    }
});

app.post('/', async (req, res) => {
    try {
        const { title, description } = req.body || {};
        if (!title) return res.status(400).json({ error: 'Title is required' });
        const r = await pool.query(
            'INSERT INTO movies (title, description) VALUES ($1, $2) RETURNING *',
            [title, description]
        );
        res.status(201).json(r.rows[0]);
    } catch (err) {
        console.error('Error creating movie:', err);
        res.status(500).json({ error: 'Failed to create movie' });
    }
});

// --- Start server d'abord, puis init en arrière-plan ---
app.listen(PORT, () => {
    console.log(`Inventory app running on port ${PORT}`);
    // on n'arrête PAS le process en cas d'échec, on log & on retry
    initDatabase()
        .then(() => { ready = true; })
        .catch(err => {
            ready = false;
            console.error('DB init failed after retries:', err);
            // on ne fait PAS process.exit(1) -> laisse K8s retries via readiness
        });
});

// Sécurité: ne jamais quitter silencieusement
process.on('unhandledRejection', (r) => console.error('unhandledRejection:', r));
process.on('uncaughtException', (e) => console.error('uncaughtException:', e));
process.on('SIGTERM', async () => {
    console.log('SIGTERM received, closing DB pool...');
    await pool.end().catch(() => { });
    process.exit(0);
});
