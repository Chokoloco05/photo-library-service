/* Shared library: all mutations go to PostgreSQL through the API. */
const $ = selector => document.querySelector(selector);
const BASE_PATH = new URL(document.baseURI).pathname.replace(/\/$/, '');
window.addEventListener('pageshow', event => { if (event.persisted) location.reload(); });
const state = { photos: [], view: 'library', selected: new Set(), groups: [], pairs: [], editing: null, importing: false };
state.auth = { authenticated: false, csrfToken: null, loginAllowed: false };
const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
const bytes = size => size < 1024 ? `${size} o` : size < 1048576 ? `${(size / 1024).toLocaleString('fr', { maximumFractionDigits: 1 })} Ko` : `${(size / 1048576).toLocaleString('fr', { maximumFractionDigits: 1 })} Mo`;
const imageUrl = (photo, thumbnail = true) => `${BASE_PATH}/api/photos/${encodeURIComponent(photo.id)}/image${thumbnail ? '?thumbnail=1' : ''}`;

async function api(url, options) {
  if (options?.method && !['GET', 'HEAD'].includes(options.method)) {
    options = { ...options, headers: { ...options.headers, 'X-CSRF-Token': state.auth.csrfToken || '' } };
  }
  const response = await fetch(`${BASE_PATH}${url}`, options);
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    if (response.status === 401 && url !== '/api/auth/login') {
      state.auth = { ...state.auth, authenticated: false, csrfToken: null };
      location.replace(`${BASE_PATH}/login`);
    }
    throw Object.assign(new Error(body.error || `Le service ne répond pas (${response.status}). Réessaie.`), { status: response.status });
  }
  return response.status === 204 ? null : response.json();
}
function updateAccess() {
  const { authenticated, username } = state.auth;
  $('#access-title').textContent = `Connecté : ${username || 'admin'}`;
  $('#access-description').textContent = 'Vous pouvez ajouter, modifier et supprimer des photos.';
  $('#logout-button').hidden = !authenticated;
  $('#import-button').hidden = !authenticated;
  $('#dropzone').hidden = !authenticated;
}
function askLogin() { location.replace(`${BASE_PATH}/login`); }
function notify(message, error = false) { const el = $('#notice'); el.textContent = message; el.hidden = !message; el.classList.toggle('error', error); }
function empty(title, copy, action = '') {
  return `<div class="empty"><span class="empty-icon" aria-hidden="true">◌</span><h2>${escapeHtml(title)}</h2><p>${escapeHtml(copy)}</p>${action}</div>`;
}
function card(photo) {
  const chosen = state.selected.has(photo.id);
  return `<article class="photo-card${chosen ? ' selected' : ''}"><div class="photo-visual"><input type="checkbox" class="select-photo" data-select="${photo.id}" aria-label="Sélectionner ${escapeHtml(photo.title)}" ${chosen ? 'checked' : ''}><button class="photo-open" data-open="${photo.id}" aria-label="Voir ${escapeHtml(photo.title)}"><img src="${imageUrl(photo)}" alt="${escapeHtml(photo.title)}" loading="lazy"></button><span class="format-badge">${escapeHtml(photo.mime_type.split('/')[1].toUpperCase())}</span></div><div class="card-body"><h3 class="card-title" title="${escapeHtml(photo.title)}">${escapeHtml(photo.title)}</h3><div class="card-meta"><span>${photo.width} × ${photo.height}</span><span>${bytes(photo.size_bytes)}</span></div></div><div class="card-actions"><button class="text-button" data-open="${photo.id}">Voir</button>${state.auth.authenticated ? `<button class="text-button" data-edit="${photo.id}">Modifier</button><button class="text-button delete-button" data-delete="${photo.id}">Supprimer</button>` : ''}</div></article>`;
}
function filtered(photos) {
  const query = $('#search').value.toLocaleLowerCase('fr');
  return photos.filter(p => `${p.title} ${p.filename} ${p.description}`.toLocaleLowerCase('fr').includes(query)).sort((a, b) => {
    if ($('#sort').value === 'size') return b.size_bytes - a.size_bytes;
    if ($('#sort').value === 'name') return a.filename.localeCompare(b.filename, 'fr');
    return new Date(b.created_at) - new Date(a.created_at);
  });
}
function updateSelection() {
  $('#selection-bar').hidden = !state.selected.size;
  $('#selection-count').textContent = `${state.selected.size} / 2 photos sélectionnées`;
  $('#compare-button').disabled = state.selected.size !== 2;
}
function render() {
  const results = $('#results');
  results.setAttribute('aria-busy', 'false');
  results.setAttribute('aria-labelledby', `tab-${state.view}`);
  if (state.view === 'library') {
    const photos = filtered(state.photos);
    results.innerHTML = photos.length ? `<div class="photo-grid">${photos.map(card).join('')}</div>` : state.photos.length
      ? empty('Aucune photo ne correspond.', 'Essayez un autre titre ou un autre nom de fichier.')
      : empty('Votre prochain souvenir commence ici.', 'La bibliothèque est vide. Le compte administrateur peut ajouter des photos.', state.auth.authenticated ? '<button class="button primary" data-import>Ajouter mes premières photos</button>' : '');
  } else if (state.view === 'duplicates') {
    const groups = state.groups.filter(g => filtered(g.photos).length);
    results.innerHTML = groups.length ? groups.map((group, index) => `<section class="group"><div class="group-header"><div><h2>Groupe ${index + 1} · ${group.photos.length} copies identiques</h2><p>Même fichier, mêmes octets. Gardez la copie de votre choix.</p></div><span class="saving">${bytes(group.reclaimable_bytes)} récupérables</span></div><div class="photo-grid">${filtered(group.photos).map(card).join('')}</div></section>`).join('') : empty('Aucun doublon exact à afficher.', 'Les copies sont détectées grâce à l’empreinte SHA-256 du fichier. Les images recompressées peuvent apparaître dans « Images proches ».');
  } else {
    const pairs = state.pairs.filter(pair => filtered([pair.left, pair.right]).length);
    results.innerHTML = pairs.length ? pairs.map(pair => `<section class="group"><div class="group-header"><div><h2>Deux versions à regarder de plus près</h2><p>Distance visuelle : ${pair.distance}/64 · une suggestion, à vérifier avec vos yeux.</p></div><button class="button" data-pair="${pair.left.id},${pair.right.id}">Comparer →</button></div><div class="photo-grid">${[pair.left, pair.right].map(card).join('')}</div></section>`).join('') : empty('Pas d’images proches à afficher.', 'Les suggestions comparent la structure des images. Des cadrages très différents peuvent ne pas être reconnus ; des images simples peuvent se ressembler sans être des doublons.');
  }
  updateSelection();
}
async function load() {
  $('#results').setAttribute('aria-busy', 'true');
  try {
    const [library, stats] = await Promise.all([api('/api/photos'), api('/api/stats')]);
    state.photos = library.photos;
    const ids = new Set(state.photos.map(p => p.id));
    state.selected = new Set([...state.selected].filter(id => ids.has(id)));
    $('#photo-count').textContent = stats.count.toLocaleString('fr');
    $('#library-badge').textContent = stats.count;
    $('#total-bytes').textContent = bytes(stats.bytes);
    $('#reclaimable').textContent = bytes(stats.reclaimable_bytes);
    if (state.view === 'duplicates') state.groups = (await api('/api/duplicates')).groups;
    if (state.view === 'similar') state.pairs = (await api('/api/similar')).pairs;
    render();
  } catch (error) {
    notify(error.message, true);
    $('#results').innerHTML = empty('La bibliothèque est momentanément indisponible.', 'Vos photos ne sont pas stockées dans ce navigateur. Vérifiez la connexion au service puis cliquez sur Actualiser.');
    $('#results').setAttribute('aria-busy', 'false');
  }
}
async function upload(files) {
  if (!state.auth.authenticated) { askLogin(); return; }
  if (state.importing || !files.length) return;
  state.importing = true;
  $('#import-button').disabled = true; $('#browse-button').disabled = true;
  let success = 0; const errors = [];
  try {
    for (const [index, file] of Array.from(files).entries()) {
      notify(`Import de ${index + 1} / ${files.length} : ${file.name}`);
      if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type) || file.size > 10485760) {
        errors.push(`${file.name} : JPEG, PNG ou WebP de 10 Mo maximum.`); continue;
      }
      try {
        await api('/api/photos', { method: 'POST', headers: { 'Content-Type': file.type, 'X-Filename': encodeURIComponent(file.name) }, body: file }); success++;
      } catch (error) { errors.push(`${file.name} : ${error.message}`); }
    }
    await load();
    notify(`${success} photo${success > 1 ? 's' : ''} importée${success > 1 ? 's' : ''}.${errors.length ? '\n' + errors.join('\n') : ' Les originaux sont conservés.'}`, !!errors.length);
  } finally { state.importing = false; $('#import-button').disabled = false; $('#browse-button').disabled = false; $('#file-input').value = ''; }
}
function compare(ids) {
  const photos = ids.map(id => state.photos.find(p => p.id === id)).filter(Boolean);
  if (!photos.length) return;
  $('#compare-title').textContent = photos.length === 2 ? 'Deux photos. À vous de choisir.' : 'Votre photo, en détail.';
  $('#compare-content').innerHTML = photos.map(p => `<section class="compare-panel"><img src="${imageUrl(p, false)}" alt="${escapeHtml(p.title)}"><h3>${escapeHtml(p.title)}</h3><dl><dt>Fichier</dt><dd>${escapeHtml(p.filename)}</dd><dt>Dimensions</dt><dd>${p.width} × ${p.height} px</dd><dt>Poids original</dt><dd>${bytes(p.size_bytes)}</dd><dt>Format</dt><dd>${escapeHtml(p.mime_type.split('/')[1].toUpperCase())}</dd><dt>Ajoutée le</dt><dd>${new Date(p.created_at).toLocaleDateString('fr')}</dd></dl><p class="dialog-note">${escapeHtml(p.description || 'Aucune description pour le moment.')}</p><div class="compare-actions"><a class="button" href="${BASE_PATH}/api/photos/${p.id}/download">Télécharger</a>${state.auth.authenticated ? `<button class="delete-button" data-delete="${p.id}">Supprimer cette copie</button>` : ''}</div></section>`).join('');
  const dialog = $('#compare-dialog'); if (!dialog.open) dialog.showModal();
}
async function removePhoto(id) {
  if (!state.auth.authenticated) { askLogin(); return; }
  const photo = state.photos.find(p => p.id === id);
  if (!photo || !confirm(`Supprimer définitivement « ${photo.title} » (${bytes(photo.size_bytes)}) ? Télécharge l’original avant si tu souhaites le conserver.`)) return;
  try {
    await api(`/api/photos/${id}`, { method: 'DELETE' });
    $('#compare-dialog').close(); state.selected.delete(id);
    await load(); notify(`Photo supprimée. ${bytes(photo.size_bytes)} retirés des originaux de la bibliothèque.`);
  } catch (error) { notify(error.message, true); }
}
function edit(id) {
  if (!state.auth.authenticated) { askLogin(); return; }
  const photo = state.photos.find(p => p.id === id); if (!photo) return;
  state.editing = id; $('#photo-title').value = photo.title; $('#photo-description').value = photo.description || ''; $('#edit-error').textContent = ''; $('#edit-dialog').showModal();
}
document.addEventListener('click', event => {
  const button = event.target.closest('button'); if (!button) return;
  if (button.dataset.import !== undefined) $('#file-input').click();
  if (button.dataset.open) compare([button.dataset.open]);
  if (button.dataset.pair) compare(button.dataset.pair.split(','));
  if (button.dataset.edit) edit(button.dataset.edit);
  if (button.dataset.delete) removePhoto(button.dataset.delete);
  if (button.dataset.close) document.getElementById(button.dataset.close).close();
});
$('#results').addEventListener('change', event => {
  const id = event.target.dataset.select; if (!id) return;
  if (event.target.checked && state.selected.size >= 2) { event.target.checked = false; notify('Sélectionnez deux photos maximum pour la comparaison.'); return; }
  if (event.target.checked) state.selected.add(id); else state.selected.delete(id);
  render();
});
$('#edit-form').addEventListener('submit', async event => {
  event.preventDefault(); const submit = event.submitter; submit.disabled = true;
  try {
    await api(`/api/photos/${state.editing}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ title: $('#photo-title').value, description: $('#photo-description').value }) });
    $('#edit-dialog').close(); await load(); notify('Les détails ont été enregistrés.');
  } catch (error) { $('#edit-error').textContent = error.message; }
  finally { submit.disabled = false; }
});
for (const selector of ['#import-button', '#browse-button']) $(selector).addEventListener('click', () => $('#file-input').click());
$('#file-input').addEventListener('change', event => upload(event.target.files));
for (const name of ['dragenter', 'dragover']) $('#dropzone').addEventListener(name, event => { event.preventDefault(); $('#dropzone').classList.add('dragging'); });
for (const name of ['dragleave', 'drop']) $('#dropzone').addEventListener(name, event => { event.preventDefault(); $('#dropzone').classList.remove('dragging'); });
$('#dropzone').addEventListener('drop', event => upload(event.dataTransfer.files));
document.querySelectorAll('[role=tab]').forEach(tab => {
  tab.addEventListener('click', async () => {
    state.view = tab.dataset.view;
    document.querySelectorAll('[role=tab]').forEach(other => { other.setAttribute('aria-selected', String(other === tab)); other.tabIndex = other === tab ? 0 : -1; });
    $('#view-description').textContent = state.view === 'library' ? 'Vos originaux, au même endroit. Sélectionnez deux photos pour les comparer.' : state.view === 'duplicates' ? 'Des fichiers strictement identiques. L’espace récupérable conserve toujours une copie de chaque groupe.' : 'Des ressemblances visuelles, pas une certitude. Comparez avant de supprimer. Les 100 premières paires sont affichées.';
    await load();
  });
  tab.addEventListener('keydown', event => {
    if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
    event.preventDefault(); const tabs = [...document.querySelectorAll('[role=tab]')]; const index = tabs.indexOf(tab);
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? tabs.length - 1 : (index + (event.key === 'ArrowRight' ? 1 : -1) + tabs.length) % tabs.length;
    tabs[next].focus(); tabs[next].click();
  });
});
$('#search').addEventListener('input', render); $('#sort').addEventListener('change', render);
$('#clear-selection').addEventListener('click', () => { state.selected.clear(); render(); });
$('#compare-button').addEventListener('click', () => compare([...state.selected]));
$('#refresh').addEventListener('click', () => { notify(''); load(); });
$('#logout-button').addEventListener('click', async () => {
  try {
    await api('/api/auth/logout', { method: 'POST' });
    location.replace(`${BASE_PATH}/login`);
  } catch (error) { notify(error.message, true); }
});
api('/api/info').then(info => { $('#environment').textContent = info.environment.toUpperCase(); $('#version').textContent = `${info.version} · ${info.pod}`; }).catch(() => { $('#environment').textContent = 'Hors ligne'; });
api('/api/auth/session').then(session => {
  if (!session.authenticated) { location.replace(`${BASE_PATH}/login`); return; }
  state.auth = session; updateAccess(); load();
}).catch(() => location.replace(`${BASE_PATH}/login`));
