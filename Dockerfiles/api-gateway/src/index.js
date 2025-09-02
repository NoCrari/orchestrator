const express = require('express');
const axios = require('axios');
const bodyParser = require('body-parser');

const app = express();
const PORT = process.env.PORT || 3000;

// Service URLs
const INVENTORY_SERVICE_URL = process.env.INVENTORY_SERVICE_URL || 'http://inventory-app:8080';
const BILLING_SERVICE_URL = process.env.BILLING_SERVICE_URL || 'http://billing-app:8080';

// Middleware
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// Logging middleware
app.use((req, res, next) => {
    console.log(`${new Date().toISOString()} - ${req.method} ${req.path}`);
    next();
});

// Health check endpoint
app.get('/health', (req, res) => {
    res.status(200).json({ status: 'healthy', service: 'api-gateway' });
});

// Ready check endpoint
app.get('/ready', (req, res) => {
    res.status(200).json({ status: 'ready', service: 'api-gateway' });
});

// Root endpoint
app.get('/', (req, res) => {
    res.json({
        service: 'API Gateway',
        version: '1.0.0',
        endpoints: {
            inventory: '/api/movies',
            billing: '/api/billing'
        }
    });
});

// Inventory service proxy
app.use('/api/movies', async (req, res) => {
    try {
        const url = `${INVENTORY_SERVICE_URL}${req.path}`;
        const response = await axios({
            method: req.method,
            url: url,
            data: req.body,
            headers: {
                'Content-Type': 'application/json'
            }
        });
        res.status(response.status).json(response.data);
    } catch (error) {
        console.error('Error forwarding to inventory service:', error.message);
        if (error.response) {
            res.status(error.response.status).json(error.response.data);
        } else {
            res.status(503).json({ error: 'Inventory service unavailable' });
        }
    }
});

// Billing service proxy
app.use('/api/billing', async (req, res) => {
    try {
        const url = `${BILLING_SERVICE_URL}${req.path}`;
        const response = await axios({
            method: req.method,
            url: url,
            data: req.body,
            headers: {
                'Content-Type': 'application/json'
            }
        });
        res.status(response.status).json(response.data);
    } catch (error) {
        console.error('Error forwarding to billing service:', error.message);
        if (error.response) {
            res.status(error.response.status).json(error.response.data);
        } else {
            res.status(503).json({ error: 'Billing service unavailable' });
        }
    }
});

// 404 handler
app.use((req, res) => {
    res.status(404).json({ error: 'Endpoint not found' });
});

// Error handler
app.use((err, req, res, next) => {
    console.error('Error:', err);
    res.status(500).json({ error: 'Internal server error' });
});

// Start server
app.listen(PORT, () => {
    console.log(`API Gateway running on port ${PORT}`);
    console.log(`Inventory service: ${INVENTORY_SERVICE_URL}`);
    console.log(`Billing service: ${BILLING_SERVICE_URL}`);
});