const express = require('express');
const bodyParser = require('body-parser');
const pool = require('./database');
const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);

const app = express();
const port = 3000;

app.use(bodyParser.urlencoded({ extended: true }));
app.use(bodyParser.json());

app.post('/subscribe', async (req, res) => {
  const { email } = req.body;

  if (!email) {
    return res.status(400).send('Email is required');
  }

  try {
    await pool.query('INSERT INTO subscribers (email) VALUES ($1)', [email]);
    res.status(200).send('Thank you for subscribing!');
  } catch (error) {
    console.error(error);
    res.status(500).send('Something went wrong.');
  }
});

app.post('/preorder', async (req, res) => {
  const { email, product_id, dedication } = req.body;

  if (!email || !product_id) {
    return res.status(400).send('Email and product ID are required');
  }

  const lineItems = [
    {
      price_data: {
        currency: 'usd',
        product_data: {
          name: 'Aether Hardcover',
        },
        unit_amount: 2499,
      },
      quantity: 1,
    },
  ];

  if (dedication) {
    lineItems.push({
      price_data: {
        currency: 'usd',
        product_data: {
          name: 'Personalized Dedication',
        },
        unit_amount: 500,
      },
      quantity: 1,
    });
  }

  try {
    const session = await stripe.checkout.sessions.create({
      payment_method_types: ['card'],
      line_items: lineItems,
      mode: 'payment',
      success_url: `https://brycefalcon.com/success.html`,
      cancel_url: `https://brycefalcon.com/cancel.html`,
      customer_email: email,
    });

    await pool.query(
      'INSERT INTO presale_customers (email, stripe_session_id, status) VALUES ($1, $2, $3)',
      [email, session.id, 'pending']
    );

    res.redirect(303, session.url);
  } catch (error) {
    console.error(error);
    res.status(500).send('Something went wrong.');
  }
});

app.post('/stripe-webhook', bodyParser.raw({type: 'application/json'}), async (req, res) => {
  const sig = req.headers['stripe-signature'];

  let event;

  try {
    event = stripe.webhooks.constructEvent(req.body, sig, process.env.STRIPE_WEBHOOK_SECRET);
  } catch (err) {
    res.status(400).send(`Webhook Error: ${err.message}`);
    return;
  }

  if (event.type === 'checkout.session.completed') {
    const session = event.data.object;

    try {
      await pool.query(
        'UPDATE presale_customers SET status = $1 WHERE stripe_session_id = $2',
        ['paid', session.id]
      );
    } catch (error) {
      console.error(error);
      return res.status(500).send('Something went wrong.');
    }
  }

  res.json({received: true});
});

app.listen(port, () => {
  console.log(`Server is running on port ${port}`);
});
