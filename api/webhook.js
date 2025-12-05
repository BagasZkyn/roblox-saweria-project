import crypto from 'crypto';

// Storage & memory structures
const rateLimitStore = new Map();
const recentDonations = new Map();
const pendingNotifications = [];

// Validate Saweria signature
function verifySaweriaSignature(body, signature, secret) {
  if (!secret || !signature) return true;

  try {
    const hmac = crypto.createHmac('sha256', secret);
    hmac.update(JSON.stringify(body));
    const calculatedSignature = hmac.digest('hex');

    return crypto.timingSafeEqual(
      Buffer.from(signature),
      Buffer.from(calculatedSignature)
    );
  } catch (err) {
    console.error('Signature verification error:', err);
    return false;
  }
}

// Rate limit basic
function checkRateLimit(id) {
  const now = Date.now();
  const windowMs = Number(process.env.RATE_LIMIT_WINDOW || 60000);
  const maxReq = Number(process.env.MAX_REQUESTS_PER_WINDOW || 10);

  if (!rateLimitStore.has(id)) rateLimitStore.set(id, []);

  const list = rateLimitStore.get(id).filter(t => now - t < windowMs);

  if (list.length >= maxReq) return false;

  list.push(now);
  rateLimitStore.set(id, list);
  return true;
}

// Duplicate donation prevention
function isDuplicateDonation(id) {
  const now = Date.now();
  const ttl = 5 * 60 * 1000;

  for (const [key, ts] of recentDonations.entries()) {
    if (now - ts > ttl) recentDonations.delete(key);
  }

  if (recentDonations.has(id)) return true;

  recentDonations.set(id, now);
  return false;
}

// Validate Saweria payload
function validateDonationData(d) {
  if (!d || typeof d !== 'object') return false;
  if (!d.id || !d.amount_raw || !d.type) return false;
  if (d.type !== 'donation') return false;
  if (typeof d.amount_raw !== 'number' || d.amount_raw <= 0) return false;
  return true;
}

export default async function handler(req, res) {
  // CORS
  res.setHeader('Access-Control-Allow-Credentials', true);
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'X-CSRF-Token, X-Requested-With, Accept, Accept-Version, Content-Length, Content-MD5, Content-Type, Date, X-Api-Version, Saweria-Callback-Signature, X-Webhook-Secret'
  );

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const path = req.url; // Vercel strips "/api/webhook"
  // console.log("DEBUG PATH:", path, "METHOD:", req.method);

  // -----------------------------
  // POST /api/webhook  → path "/"
  // -----------------------------
  if (req.method === 'POST' && path === '/') {
    try {
      const donation = req.body;

      if (!validateDonationData(donation)) {
        return res.status(400).json({ error: 'Invalid donation structure' });
      }

      // Verify signature if secret enabled
      const signature = req.headers['saweria-callback-signature'];
      const seSecret = process.env.SAWERIA_SECRET;

      if (seSecret && signature) {
        if (!verifySaweriaSignature(donation, signature, seSecret)) {
          return res.status(401).json({ error: 'Invalid signature' });
        }
      }

      // Duplicate donation check
      if (isDuplicateDonation(donation.id)) {
        return res.status(200).json({
          message: 'Duplicate donation ignored',
          cached: true
        });
      }

      // Rate limit (donation + IP)
      const ip = req.headers['x-forwarded-for']?.split(',')[0] || 'unknown';
      if (!checkRateLimit(`${donation.id}_${ip}`)) {
        return res.status(429).json({ error: 'Rate limit exceeded' });
      }

      // Build notification
      const notif = {
        id: donation.id,
        donatorName: donation.donator_name || 'Anonymous',
        amount: donation.amount_raw,
        message: donation.message || '',
        timestamp: donation.created_at
          ? new Date(donation.created_at).getTime()
          : Date.now(),
        verified: true
      };

      // Push into queue
      pendingNotifications.push(notif);
      if (pendingNotifications.length > 50) pendingNotifications.shift();

      return res.status(200).json({
        success: true,
        message: 'Donation received',
        donationId: donation.id
      });
    } catch (err) {
      console.error('Webhook error:', err);
      return res.status(500).json({ error: err.message });
    }
  }

  // --------------------------------
  // GET /api/webhook/poll → path "/poll"
  // --------------------------------
  if (req.method === 'GET' && path.startsWith('/poll')) {
    try {
      const secret = req.headers['x-webhook-secret'];
      const expected = process.env.WEBHOOK_SECRET;

      if (!expected) {
        return res
          .status(500)
          .json({ error: 'WEBHOOK_SECRET not configured' });
      }

      if (secret !== expected) {
        return res.status(401).json({ error: 'Invalid webhook secret' });
      }

      // Rate limit poll
      const ip = req.headers['x-forwarded-for']?.split(',')[0] || 'unknown';
      if (!checkRateLimit(`poll_${ip}`)) {
        return res
          .status(429)
          .json({ error: 'Rate limit exceeded. Too frequent polling.' });
      }

      const data = [...pendingNotifications];
      pendingNotifications.length = 0;

      return res.status(200).json({
        success: true,
        count: data.length,
        notifications: data
      });
    } catch (err) {
      console.error('Poll error:', err);
      return res.status(500).json({ error: err.message });
    }
  }

  // ----------------------------------
  // GET /api/webhook/health → path "/health"
  // ----------------------------------
  if (req.method === 'GET' && path === '/health') {
    return res.status(200).json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      pendingNotifications: pendingNotifications.length,
      rateLimitEntries: rateLimitStore.size,
      cachedDonations: recentDonations.size
    });
  }

  // Default
  return res.status(404).json({ error: 'Not found' });
}
