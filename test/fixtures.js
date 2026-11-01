const sharp = require('sharp');
const artwork = '<svg width="160" height="120" xmlns="http://www.w3.org/2000/svg"><defs><linearGradient id="g"><stop stop-color="#173f36"/><stop offset="1" stop-color="#b4cc7d"/></linearGradient></defs><rect width="160" height="120" fill="url(#g)"/><circle cx="115" cy="32" r="18" fill="#f8de93"/><path d="M0 120L55 36L100 100L130 70L160 120" fill="#4e7968"/></svg>';
async function fixture(format = 'png') {
  return sharp(Buffer.from(artwork))[format]().toBuffer();
}
module.exports = { fixture };
