const express = require('express');
const { Pool } = require('pg');
const amqp = require('amqplib');
const bodyParser = require('body-parser');

const app = express();
const PORT = process.env.PORT || 8080;

// Database configuration
const pool = new Pool({
    host: process.env.DB_HOST || 'billing-db',
    port: process.env.DB_PORT || 5432,
    database: process.env.DB_NAME || 'billing',
    user: process.env.DB_USER || 'billing_user',
    password: process.env.DB_PASSWORD || 'bill123',
    max: 20,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 2000,
});

// RabbitMQ configuration
const RABBITMQ_URL = `amqp://${process.env.RABBITMQ_USER || 'admin'}:${process.env.RABBITMQ_PASSWORD || 'rabbitmq123'}@${process.env.RABBITMQ_HOST || 'rabbitmq'}:${process.env.RABBITMQ_PORT || 5672}`;
const QUEUE_NAME = process.env.RABBITMQ_QUEUE || 'billing_queue';

let channel = null;

// Middleware
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// Initialize database
async function initDatabase() {
    try {
        await pool.query(`
            CREATE TABLE IF NOT EXISTS orders (
                id SERIAL PRIMARY KEY,
                user_id VARCHAR(255) NOT NULL,
                number_of_items INTEGER NOT NULL,
                total_amount DECIMAL(10, 2) NOT NULL,
                status VARCHAR(50) DEFAULT 'pending',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        `);
        console.log('Database initialized');
    } catch (error) {
        console.error('Error initializing database:', error);
    }
}

// Connect to RabbitMQ
async function connectRabbitMQ() {
    try {
        const connection = await amqp.connect(RABBITMQ_URL);
        channel = await connection.createChannel();
        await channel.assertQueue(QUEUE_NAME, { durable: true });

        console.log('Connected to RabbitMQ');

        // Start consuming messages
        channel.consume(QUEUE_NAME, async (msg) => {
            if (msg !== null) {
                try {
                    const order = JSON.parse(msg.content.toString());
                    console.log('Processing order from queue:', order);

                    // Save to database
                    await pool.query(
                        'INSERT INTO orders (user_id, number_of_items, total_amount, status) VALUES ($1, $2, $3, $4)',
                        [order.user_id, order.number_of_items, order.total_amount, 'processed']
                    );

                    channel.ack(msg);
                    console.log('Order processed successfully');
                } catch (error) {
                    console.error('Error processing message:', error);
                    channel.nack(msg, false, true);
                }
            }
        });

        connection.on('error', (err) => {
            console.error('RabbitMQ connection error:', err);
            setTimeout(connectRabbitMQ, 5000);
        });

    } catch (error) {
        console.error('Failed to connect to RabbitMQ:', error);
        setTimeout(connectRabbitMQ, 5000);
    }
}

// Health check endpoint
app.get('/health', async (req, res) => {
    try {
        await pool.query('SELECT 1');
        const rabbitHealthy = channel !== null;
        if (rabbitHealthy) {
            res.status(200).json({ status: 'healthy', service: 'billing-app', database: 'connected', rabbitmq: 'connected' });
        } else {
            res.status(503).json({ status: 'degraded', service: 'billing-app', database: 'connected', rabbitmq: 'disconnected' });
        }
    } catch (error) {
        res.status(503).json({ status: 'unhealthy', service: 'billing-app', error: error.message });
    }
});

// Ready check endpoint
app.get('/ready', async (req, res) => {
    try {
        await pool.query('SELECT 1');
        res.status(200).json({ status: 'ready', service: 'billing-app' });
    } catch (error) {
        res.status(503).json({ status: 'not ready', service: 'billing-app' });
    }
});

// Get all orders
app.get('/', async (req, res) => {
    try {
        const result = await pool.query('SELECT * FROM orders ORDER BY created_at DESC');
        res.json(result.rows);
    } catch (error) {
        console.error('Error fetching orders:', error);
        res.status(500).json({ error: 'Failed to fetch orders' });
    }
});

// Get order by ID
app.get('/:id', async (req, res) => {
    try {
        const { id } = req.params;
        const result = await pool.query('SELECT * FROM orders WHERE id = $1', [id]);
        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Order not found' });
        }
        res.json(result.rows[0]);
    } catch (error) {
        console.error('Error fetching order:', error);
        res.status(500).json({ error: 'Failed to fetch order' });
    }
});

// Create new order (publishes to RabbitMQ)
app.post('/', async (req, res) => {
    try {
        const { user_id, number_of_items, total_amount } = req.body;

        if (!user_id || !number_of_items || !total_amount) {
            return res.status(400).json({ error: 'Missing required fields' });
        }

        const order = {
            user_id,
            number_of_items: parseInt(number_of_items),
            total_amount: parseFloat(total_amount),
            timestamp: new Date().toISOString()
        };

        if (channel) {
            // Send to RabbitMQ queue
            channel.sendToQueue(QUEUE_NAME, Buffer.from(JSON.stringify(order)), { persistent: true });
            res.status(200).json({ message: 'Order queued for processing', order });
        } else {
            // Fallback: save directly to database if RabbitMQ is not available
            const result = await pool.query(
                'INSERT INTO orders (user_id, number_of_items, total_amount, status) VALUES ($1, $2, $3, $4) RETURNING *',
                [user_id, number_of_items, total_amount, 'direct']
            );
            res.status(201).json(result.rows[0]);
        }
    } catch (error) {
        console.error('Error creating order:', error);
        res.status(500).json({ error: 'Failed to create order' });
    }
});

// Start server
app.listen(PORT, async () => {
    console.log(`Billing app running on port ${PORT}`);
    await initDatabase();
    await connectRabbitMQ();
});