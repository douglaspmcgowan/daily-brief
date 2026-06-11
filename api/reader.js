const { Readability } = require('@mozilla/readability');
const { JSDOM } = require('jsdom');

// Block SSRF — refuse internal/localhost targets
function isSafeUrl(raw) {
  try {
    const { hostname, protocol } = new URL(raw);
    if (!['http:', 'https:'].includes(protocol)) return false;
    const blocked = ['localhost', '127.0.0.1', '0.0.0.0', '::1', '169.254.169.254'];
    if (blocked.includes(hostname)) return false;
    // RFC-1918 ranges
    if (/^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.)/.test(hostname)) return false;
    return true;
  } catch {
    return false;
  }
}

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  if (req.method === 'OPTIONS') return res.status(204).end();

  const url = req.query?.url;
  if (!url) return res.status(400).json({ error: 'Missing ?url= parameter' });
  if (!isSafeUrl(url)) return res.status(400).json({ error: 'URL not permitted' });

  let response;
  try {
    response = await fetch(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
      },
      redirect: 'follow',
      signal: AbortSignal.timeout(8000),
    });
  } catch (err) {
    const msg = err.name === 'TimeoutError' ? 'Request timed out after 8s' : `Fetch failed: ${err.message}`;
    return res.status(502).json({ error: msg });
  }

  if (!response.ok) {
    return res.status(502).json({ error: `Upstream returned HTTP ${response.status}` });
  }

  const ct = response.headers.get('content-type') || '';
  if (!ct.includes('html') && !ct.includes('xml')) {
    return res.status(422).json({ error: `URL returns ${ct}, not HTML` });
  }

  let html;
  try { html = await response.text(); }
  catch (err) { return res.status(502).json({ error: `Could not read response: ${err.message}` }); }

  let article;
  try {
    const dom = new JSDOM(html, { url });
    article = new Readability(dom.window.document).parse();
  } catch (err) {
    return res.status(500).json({ error: `Parse error: ${err.message}` });
  }

  if (!article) {
    return res.status(422).json({ error: 'Could not extract readable content from this page' });
  }

  res.setHeader('Cache-Control', 's-maxage=3600, stale-while-revalidate=86400');
  return res.status(200).json({
    title:    article.title    || '',
    content:  article.content  || '',
    excerpt:  article.excerpt  || '',
    byline:   article.byline   || '',
    siteName: article.siteName || new URL(url).hostname,
    length:   article.length   || 0,
  });
};
