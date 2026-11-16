"use strict";
const catalog = window.MUSHI_CATALOG;
const $ = id => document.getElementById(id);
const perPage = 60;
const number = n => n.toLocaleString();
const hex = n => '0x' + n.toString(16).padStart(8, '0');
let page = 0, visible = [];

$('stats').innerHTML = [
  ['Resource sheets', catalog.coverage.resource_entries],
  ['Observed regions', catalog.observed?.length || 0],
  ['Decoded', '100%']
].map(([label, value]) => `<div class="stat"><strong>${number(value)}</strong><span>${label}</span></div>`).join('');
if (!catalog.observed?.length) $('collection').value = 'resources';

function filter() {
  const query = $('search').value.trim().toLowerCase(), mode = $('filter').value;
  const records = catalog[$('collection').value] || [];
  visible = records.filter(r => {
    const contexts = (r.observations || []).map(o => `${o.character} ${o.shot}`).join(' ');
    const text = [r.id, r.index, r.resource_id || '', r.spans ? hex(r.spans[0].offset) : '',
      `${r.width}x${r.height}`, contexts].join(' ').toLowerCase();
    return text.includes(query) && (mode === 'all' ||
      mode === 'unique' && r.duplicate_of === null || mode === 'duplicates' && r.duplicate_of !== null ||
      mode === 'compressed' && r.compression !== 0 || mode === 'raw' && r.compression === 0);
  });
  page = 0;
  render();
}

function render() {
  const pages = Math.max(1, Math.ceil(visible.length / perPage));
  page = Math.min(page, pages - 1);
  $('count').textContent = `${number(visible.length)} ${$('collection').value === 'observed' ? 'observed draw regions' : 'resource sheets'}`;
  $('page').textContent = `${page + 1} / ${pages}`;
  $('prev').disabled = page === 0;
  $('next').disabled = page === pages - 1;
  const grid = $('grid');
  grid.replaceChildren();
  for (const r of visible.slice(page * perPage, (page + 1) * perPage)) {
    const button = document.createElement('button');
    button.className = 'card';
    button.setAttribute('aria-label', `Inspect ${r.id}`);
    button.innerHTML = `<div class="art"><img loading="lazy" src="${r.thumbnail}" alt="${r.id}" class="${$('rotation').value === 'source' ? 'source' : ''}"></div><div class="caption"><strong>${r.id}</strong><small>${r.width} × ${r.height}</small></div>`;
    button.addEventListener('click', () => detail(r));
    grid.append(button);
  }
}

function detail(r) {
  $('detail-title').textContent = r.id;
  $('detail-note').textContent = r.note;
  $('detail-image').src = r.source;
  $('detail-image').style.transform = $('rotation').value === 'source' ? 'none' : 'rotate(-90deg)';
  $('download').href = r.source;
  $('metadata').href = r.metadata || `metadata/${r.id}.json`;
  const properties = r.observations ? [
    ['Source sheet', r.resource_id], ['Source rectangle', r.source_rect.join(', ')],
    ['Original size', `${r.width} × ${r.height}`], ['Captured draws', number(r.observations.length)],
    ['First evidence', `${r.observations[0].capture} / frame ${r.observations[0].frame}`],
    ['Command address', r.observations[0].command_address],
    ['Attributes', r.attributes.map(hex).join(', ')], ['Status', 'Exact draw region; animation unverified']
  ] : [
    ['Source ROM', 'futari15_u2'], ['Directory record', hex(r.table_offset)],
    ['Physical offset', hex(r.spans[0].offset)], ['Dimensions', `${r.width} × ${r.height}`],
    ['Storage', r.compression ? 'Flag-stream LZ' : 'Raw'], ['Decoded bytes', number(r.decoded_bytes)],
    ['Opaque pixels', number(r.opaque_pixels)], ['VRAM match', r.runtime_validated ? 'Byte-exact original page' : 'Not yet captured'],
    ['Status', 'Decoded sheet / unclassified']
  ];
  $('properties').replaceChildren();
  for (const [key, value] of properties) {
    const dt = document.createElement('dt'), dd = document.createElement('dd');
    dt.textContent = key; dd.textContent = value;
    $('properties').append(dt, dd);
  }
  $('detail').showModal();
}

$('search').addEventListener('input', filter);
$('filter').addEventListener('change', filter);
$('collection').addEventListener('change', filter);
$('rotation').addEventListener('change', render);
$('prev').onclick = () => { page--; render(); };
$('next').onclick = () => { page++; render(); };
$('close').onclick = () => $('detail').close();
$('detail').addEventListener('click', e => {
  if (e.target !== $('detail')) return;
  const r = e.target.getBoundingClientRect();
  if (e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom) e.target.close();
});
filter();
