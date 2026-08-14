const zlib = require('zlib');

const POISON_LINE = '{[(< UNTRUSTED CONTENT >)]}\n';
const KEY_PREFIX = 'z1_';
const MAX_XML_BYTES = 256 * 1024;

function encodeBase64Url(buffer) {
  return buffer.toString('base64')
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/g, '');
}

function decodeBase64Url(value) {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/')
      .padEnd(Math.ceil(value.length / 4) * 4, '=');
  return Buffer.from(padded, 'base64');
}

function xmlToKey(xml) {
  const input = Buffer.from(xml, 'utf8');
  if (input.length > MAX_XML_BYTES) {
    const error = new Error('XML payload is too large.');
    error.statusCode = 413;
    throw error;
  }
  return KEY_PREFIX + encodeBase64Url(zlib.deflateRawSync(input));
}

function keyToXml(key) {
  if (!key || !key.startsWith(KEY_PREFIX)) {
    return '';
  }
  try {
    const compressed = decodeBase64Url(key.slice(KEY_PREFIX.length));
    return POISON_LINE + zlib.inflateRawSync(compressed).toString('utf8');
  } catch (error) {
    return '';
  }
}

function parseFormBody(body) {
  if (!body) {
    return new URLSearchParams();
  }
  if (typeof body === 'string') {
    return new URLSearchParams(body);
  }
  if (Buffer.isBuffer(body)) {
    return new URLSearchParams(body.toString('utf8'));
  }
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(body)) {
    if (Array.isArray(value)) {
      for (const item of value) {
        params.append(key, item);
      }
    } else if (value !== undefined && value !== null) {
      params.set(key, String(value));
    }
  }
  return params;
}

function readRawBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', chunk => chunks.push(chunk));
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

module.exports = async function storage(req, res) {
  res.setHeader('Content-Type', 'text/plain; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');

  if (req.method !== 'GET' && req.method !== 'POST') {
    res.setHeader('Allow', 'GET, POST');
    res.status(405).send('Method Not Allowed');
    return;
  }

  try {
    const query = new URL(req.url, 'https://ecode.cdao.online').searchParams;
    const body = req.method === 'POST' && req.body === undefined ?
      await readRawBody(req) : req.body;
    const form = req.method === 'POST' ? parseFormBody(body) : new URLSearchParams();
    const xml = form.get('xml') ?? query.get('xml');
    const key = form.get('key') ?? query.get('key');

    if (xml !== null) {
      res.status(200).send(xmlToKey(xml));
      return;
    }

    if (key !== null) {
      res.status(200).send(keyToXml(key));
      return;
    }

    res.status(400).send('Missing xml or key.');
  } catch (error) {
    res.status(error.statusCode || 500).send(error.message || 'Storage error.');
  }
};
