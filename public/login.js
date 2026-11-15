const base = new URL(document.baseURI).pathname.replace(/\/$/, '');
window.addEventListener('pageshow', event => { if (event.persisted) location.reload(); });
const form = document.querySelector('#login-form');
const button = document.querySelector('#login-submit');
const message = document.querySelector('#login-error');
const status = document.querySelector('#login-status');
async function initialize() {
  try {
    const response = await fetch(`${base}/api/auth/session`);
    if (!response.ok) throw new Error('Service indisponible. Réessayez dans quelques instants.');
    const session = await response.json();
    if (session.authenticated) { location.replace(`${base}/dashboard`); return; }
    button.disabled = !session.loginAllowed;
    status.textContent = !session.configured ? 'Le compte administrateur doit être configuré.'
      : !session.loginAllowed ? 'Une connexion HTTPS est nécessaire.'
      : session.demoHttp ? 'Démonstration en HTTP. Utilisez le mot de passe réservé à ce projet.' : '';
  } catch (error) { status.textContent = error.message; }
}
form.addEventListener('submit', async event => {
  event.preventDefault(); button.disabled = true; message.textContent = '';
  try {
    const response = await fetch(`${base}/api/auth/login`, { method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: form.elements.username.value, password: form.elements.password.value }) });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || 'Connexion impossible.');
    location.replace(`${base}/dashboard`);
  } catch (error) { message.textContent = error.message; button.disabled = false; }
  finally { form.elements.password.value = ''; }
});
initialize();
