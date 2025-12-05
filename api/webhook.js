import crypto from 'crypto';

// Environment variables yang perlu diset di Vercel:
// WEBHOOK_SECRET = Secret key untuk validasi request dari Roblox
// SAWERIA_SECRET = Secret key untuk validasi webhook dari Saweria (opsional, untuk extra security)
// RATE_LIMIT_WINDOW = 60000 (1 menit dalam ms)
// MAX_REQUESTS_PER_WINDOW = 10

// In-memory storage untuk rate limiting (gunakan Redis untuk production)
const rateLimitStore = new Map();
const recentDonations = new Map();

// Fungsi untuk verifikasi signature dari Saweria (opsional)
function verifySaweriaSignature(body, signature, secret) {
  if (!secret || !signature) {
    // Jika tidak ada secret atau signature, skip verification
    return true;
  }
  
  try {
    const hmac = crypto.createHmac('sha256', secret);
    hmac.update(JSON.stringify(body));
    const calculatedSignature = hmac.digest('hex');
    return crypto.timingSafeEqual(
      Buffer.from(signature),
      Buffer.from(calculatedSignature)
    );
  } catch (error) {
    console.error('Signature verification error:', error);
    return false;
  }
}

// Validasi IP Saweria (extra layer security - opsional)
function isValidSaweriaIP(ip) {
  // Saweria menggunakan beberapa IP range
  // Ini adalah contoh, sesuaikan dengan IP actual dari Saweria
  const allowedIPs = [
    '127.0.0.1', // Localhost untuk testing
    // Tambahkan IP Saweria di sini jika diperlukan
  ];
  
  // Jika list kosong, allow all (untuk development)
  if (allowedIPs.length === 1 && allowedIPs[0] === '127.0.0.1') {
    return true;
  }
  
  return allowedIPs.includes(ip);
}

// Rate limiting
function checkRateLimit(identifier) {
  const now = Date.now();
  const windowMs = parseInt(process.env.RATE_LIMIT_WINDOW || '60000');
  const maxRequests = parseInt(process.env.MAX_REQUESTS_PER_WINDOW || '10');
  
  if (!rateLimitStore.has(identifier)) {
    rateLimitStore.set(identifier, []);
  }
  
  const requests = rateLimitStore.get(identifier);
  const recentRequests = requests.filter(time => now - time < windowMs);
  
  if (recentRequests.length >= maxRequests) {
    return false;
  }
  
  recentRequests.push(now);
  rateLimitStore.set(identifier, recentRequests);
  
  // Cleanup old entries
  if (rateLimitStore.size > 1000) {
    const oldestKey = rateLimitStore.keys().next().value;
    rateLimitStore.delete(oldestKey);
  }
  
  return true;
}

// Anti duplicate donation
function isDuplicateDonation(donationId) {
  const now = Date.now();
  const fiveMinutes = 5 * 60 * 1000;
  
  // Cleanup old donations (lebih dari 5 menit)
  for (const [id, timestamp] of recentDonations.entries()) {
    if (now - timestamp > fiveMinutes) {
      recentDonations.delete(id);
    }
  }
  
  if (recentDonations.has(donationId)) {
    return true;
  }
  
  recentDonations.set(donationId, now);
  return false;
}

// Validasi struktur data donation dari Saweria
function validateDonationData(donation) {
  // Field yang wajib ada dari Saweria webhook
  const requiredFields = ['id', 'amount_raw', 'type'];
  
  for (const field of requiredFields) {
    if (!donation[field]) {
      return false;
    }
  }
  
  // Validasi tipe harus donation
  if (donation.type !== 'donation') {
    return false;
  }
  
  // Validasi amount harus number dan positif
  if (typeof donation.amount_raw !== 'number' || donation.amount_raw <= 0) {
    return false;
  }
  
  return true;
}

// Storage untuk pending notifications
const pendingNotifications = [];

export default async function handler(req, res) {
  // CORS headers
  res.setHeader('Access-Control-Allow-Credentials', true);
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 
    'X-CSRF-Token, X-Requested-With, Accept, Accept-Version, Content-Length, Content-MD5, Content-Type, Date, X-Api-Version, Saweria-Callback-Signature, X-Webhook-Secret'
  );

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  // Endpoint untuk menerima webhook dari Saweria
  if (req.method === 'POST' && req.url === '/api/webhook') {
    try {
      // Get IP address
      const clientIp = req.headers['x-forwarded-for']?.split(',')[0].trim() || 
                       req.headers['x-real-ip'] || 
                       'unknown';
      
      console.log('Webhook received from IP:', clientIp);

      const donation = req.body;

      // Validasi struktur data
      if (!validateDonationData(donation)) {
        console.error('Invalid donation data:', donation);
        return res.status(400).json({ 
          error: 'Invalid donation data structure' 
        });
      }

      // Verifikasi signature (opsional)
      const signature = req.headers['saweria-callback-signature'];
      const saweriaSecret = process.env.SAWERIA_SECRET;
      
      if (saweriaSecret && signature) {
        const isValid = verifySaweriaSignature(donation, signature, saweriaSecret);
        if (!isValid) {
          console.error('Invalid signature for donation:', donation.id);
          return res.status(401).json({ 
            error: 'Invalid signature' 
          });
        }
        console.log('Signature verified for donation:', donation.id);
      }

      // Anti duplicate donation
      if (isDuplicateDonation(donation.id)) {
        console.log(`Duplicate donation detected: ${donation.id}`);
        return res.status(200).json({ 
          message: 'Duplicate donation ignored',
          cached: true 
        });
      }

      // Rate limiting berdasarkan donation ID + IP
      const rateLimitKey = `${donation.id}_${clientIp}`;
      if (!checkRateLimit(rateLimitKey)) {
        console.warn('Rate limit exceeded for:', rateLimitKey);
        return res.status(429).json({ 
          error: 'Rate limit exceeded' 
        });
      }

      // Format data untuk Roblox
      const notificationData = {
        id: donation.id,
        donatorName: donation.donator_name || 'Anonymous',
        amount: donation.amount_raw,
        message: donation.message || '',
        timestamp: donation.created_at ? new Date(donation.created_at).getTime() : Date.now(),
        verified: true
      };

      // Simpan ke pending notifications
      pendingNotifications.push(notificationData);
      
      // Keep only last 50 notifications
      if (pendingNotifications.length > 50) {
        pendingNotifications.shift();
      }

      console.log('New donation received:', {
        id: notificationData.id,
        donator: notificationData.donatorName,
        amount: notificationData.amount
      });

      return res.status(200).json({ 
        success: true,
        message: 'Donation received and queued',
        donationId: donation.id
      });

    } catch (error) {
      console.error('Webhook error:', error);
      return res.status(500).json({ 
        error: 'Internal server error',
        message: error.message 
      });
    }
  }

  // Endpoint untuk Roblox mengambil notifikasi
  if (req.method === 'GET' && req.url.startsWith('/api/webhook/poll')) {
    try {
      const secret = req.headers['x-webhook-secret'];
      const expectedSecret = process.env.WEBHOOK_SECRET;

      if (!expectedSecret) {
        return res.status(500).json({ 
          error: 'Server configuration error: WEBHOOK_SECRET not set' 
        });
      }

      if (secret !== expectedSecret) {
        return res.status(401).json({ 
          error: 'Invalid webhook secret' 
        });
      }

      // Rate limiting untuk polling
      const clientIp = req.headers['x-forwarded-for']?.split(',')[0].trim() || 
                       req.headers['x-real-ip'] || 
                       'unknown';
      
      if (!checkRateLimit(`poll_${clientIp}`)) {
        return res.status(429).json({ 
          error: 'Rate limit exceeded. Please slow down polling.' 
        });
      }

      // Return all pending notifications dan clear
      const notifications = [...pendingNotifications];
      pendingNotifications.length = 0;

      return res.status(200).json({
        success: true,
        count: notifications.length,
        notifications: notifications
      });

    } catch (error) {
      console.error('Poll error:', error);
      return res.status(500).json({ 
        error: 'Internal server error',
        message: error.message 
      });
    }
  }

  // Health check endpoint
  if (req.method === 'GET' && req.url === '/api/webhook/health') {
    return res.status(200).json({ 
      status: 'healthy',
      timestamp: new Date().toISOString(),
      pendingNotifications: pendingNotifications.length,
      rateLimitEntries: rateLimitStore.size,
      cachedDonations: recentDonations.size
    });
  }

  return res.status(404).json({ error: 'Not found' });
}
