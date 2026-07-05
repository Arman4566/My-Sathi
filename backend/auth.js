// Cloud authentication: signup, login, forgot-password, reset-password,
// and a `requireAuth` middleware that other routers (see medicines.js)
// use to identify which user a request belongs to.
//
// SECURITY NOTES:
// - Passwords are hashed with bcrypt (never stored or logged in plain
//   text). Never switch this back to a fast hash like SHA-256/MD5 for
//   passwords — bcrypt's deliberate slowness is what makes brute-forcing
//   leaked hashes impractical.
// - JWTs are signed with JWT_SECRET (see .env.example) — pick a long,
//   random value in production and never commit it.
// - Forgot-password responses are identical whether or not the email
//   exists, so attackers can't use this endpoint to discover which
//   emails are registered.

const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const nodemailer = require('nodemailer');
const pool = require('./db');

const router = express.Router();
const JWT_SECRET = process.env.JWT_SECRET;
const TOKEN_EXPIRY = '30d';

function toProfileJson(row) {
  return {
    id: row.id,
    name: row.name,
    email: row.email,
    age: row.age,
    weightKg: row.weight_kg,
    heightCm: row.height_cm,
    gender: row.gender,
    bio: row.bio,
    photoPath: row.photo_path,
  };
}

// ---------------------------------------------------------------------
// Middleware: verifies the Authorization: Bearer <token> header and
// attaches req.userId. Used by any route that needs to know "who is
// asking" — e.g. medicines.js.
// ---------------------------------------------------------------------
function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'missing_token' });

  try {
    const payload = jwt.verify(token, JWT_SECRET);
    req.userId = payload.sub;
    next();
  } catch (err) {
    return res.status(401).json({ error: 'invalid_token' });
  }
}

// ---------------------------------------------------------------------
// POST /api/auth/signup
// ---------------------------------------------------------------------
router.post('/signup', async (req, res) => {
  try {
    const { name, email, password } = req.body;
    if (!name || !email || !password || password.length < 4) {
      return res.status(400).json({ error: 'invalid_input' });
    }

    const existing = await pool.query('SELECT id FROM users WHERE email = $1', [
      email.toLowerCase(),
    ]);
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'email_taken' });
    }

    const passwordHash = await bcrypt.hash(password, 10);
    const result = await pool.query(
      `INSERT INTO users (name, email, password_hash)
       VALUES ($1, $2, $3) RETURNING *`,
      [name, email.toLowerCase(), passwordHash]
    );

    const user = result.rows[0];
    const token = jwt.sign({ sub: user.id }, JWT_SECRET, { expiresIn: TOKEN_EXPIRY });
    res.json({ token, profile: toProfileJson(user) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'signup_failed' });
  }
});

// ---------------------------------------------------------------------
// POST /api/auth/login
// ---------------------------------------------------------------------
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    const result = await pool.query('SELECT * FROM users WHERE email = $1', [
      (email || '').toLowerCase(),
    ]);
    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'invalid_credentials' });
    }

    const user = result.rows[0];
    const matches = await bcrypt.compare(password || '', user.password_hash);
    if (!matches) {
      return res.status(401).json({ error: 'invalid_credentials' });
    }

    const token = jwt.sign({ sub: user.id }, JWT_SECRET, { expiresIn: TOKEN_EXPIRY });
    res.json({ token, profile: toProfileJson(user) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'login_failed' });
  }
});

// ---------------------------------------------------------------------
// GET /api/auth/me — fetch the current profile from a stored token
// ---------------------------------------------------------------------
router.get('/me', requireAuth, async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM users WHERE id = $1', [req.userId]);
    if (result.rows.length === 0) return res.status(404).json({ error: 'not_found' });
    res.json({ profile: toProfileJson(result.rows[0]) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'fetch_failed' });
  }
});

// ---------------------------------------------------------------------
// PUT /api/auth/me — update profile fields (age, weight, height, etc.)
// ---------------------------------------------------------------------
router.put('/me', requireAuth, async (req, res) => {
  try {
    const { name, age, weightKg, heightCm, gender, bio, photoPath } = req.body;
    const result = await pool.query(
      `UPDATE users SET
         name = COALESCE($1, name),
         age = COALESCE($2, age),
         weight_kg = COALESCE($3, weight_kg),
         height_cm = COALESCE($4, height_cm),
         gender = COALESCE($5, gender),
         bio = COALESCE($6, bio),
         photo_path = COALESCE($7, photo_path)
       WHERE id = $8 RETURNING *`,
      [name, age, weightKg, heightCm, gender, bio, photoPath, req.userId]
    );
    res.json({ profile: toProfileJson(result.rows[0]) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'update_failed' });
  }
});

// ---------------------------------------------------------------------
// Forgot / reset password
// ---------------------------------------------------------------------
const transporter = process.env.EMAIL_USER
  ? nodemailer.createTransport({
      service: 'gmail', // swap for your provider, or use a transactional
      auth: {            // email API (Resend/SendGrid) instead — see README
        user: process.env.EMAIL_USER,
        pass: process.env.EMAIL_PASS,
      },
    })
  : null;

router.post('/forgot-password', async (req, res) => {
  const { email } = req.body;
  // Always respond the same way whether or not the email exists, so this
  // endpoint can't be used to discover registered emails.
  const genericResponse = {
    message: 'If that email is registered, a reset code has been sent.',
  };

  try {
    const result = await pool.query('SELECT id FROM users WHERE email = $1', [
      (email || '').toLowerCase(),
    ]);
    if (result.rows.length === 0) return res.json(genericResponse);

    const userId = result.rows[0].id;
    const token = crypto.randomInt(100000, 999999).toString(); // 6-digit code
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000); // 15 minutes

    await pool.query(
      'INSERT INTO password_reset_tokens (token, user_id, expires_at) VALUES ($1, $2, $3)',
      [token, userId, expiresAt]
    );

    if (transporter) {
      await transporter.sendMail({
        from: process.env.EMAIL_USER,
        to: email,
        subject: 'Your Sathi password reset code',
        text: `Your password reset code is ${token}. It expires in 15 minutes. If you didn't request this, you can ignore this email.`,
      });
    } else {
      // No email configured — log it so you can still test the flow
      // during development. Remove this in production.
      console.log(`[DEV ONLY] Password reset code for ${email}: ${token}`);
    }

    res.json(genericResponse);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'forgot_password_failed' });
  }
});

router.post('/reset-password', async (req, res) => {
  try {
    const { token, newPassword } = req.body;
    if (!token || !newPassword || newPassword.length < 4) {
      return res.status(400).json({ error: 'invalid_input' });
    }

    const result = await pool.query(
      `SELECT * FROM password_reset_tokens
       WHERE token = $1 AND used = false AND expires_at > now()`,
      [token]
    );
    if (result.rows.length === 0) {
      return res.status(400).json({ error: 'invalid_or_expired_token' });
    }

    const record = result.rows[0];
    const passwordHash = await bcrypt.hash(newPassword, 10);

    await pool.query('UPDATE users SET password_hash = $1 WHERE id = $2', [
      passwordHash,
      record.user_id,
    ]);
    await pool.query('UPDATE password_reset_tokens SET used = true WHERE token = $1', [
      token,
    ]);

    res.json({ message: 'Password updated. You can now log in.' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'reset_password_failed' });
  }
});

module.exports = { router, requireAuth };
