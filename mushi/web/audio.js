"use strict";
const sounds = window.MUSHI_AUDIO.phrases;
const soundGrid = document.getElementById('audio-grid');
const search = document.getElementById('audio-search');
const lengthFilter = document.getElementById('audio-length');
function filterSounds() {
  for (const player of soundGrid.querySelectorAll('audio')) player.pause();
  soundGrid.replaceChildren();
  let count = 0;
  for (const sound of sounds.filter(s => s.source && s.duplicate_of === null)) {
    const aliases = sounds.filter(s => s.duplicate_of === sound.id).map(s => s.id);
    if (![sound.id, ...aliases].join(' ').includes(search.value.trim().toLowerCase())) continue;
    const seconds = sound.duration_seconds, kind = lengthFilter.value;
    if (kind === 'short' && seconds >= 2 || kind === 'medium' && (seconds < 2 || seconds > 10) || kind === 'long' && seconds <= 10) continue;
    count++;
    const card = document.createElement('article'); card.className = 'sound';
    const title = document.createElement('h3'); title.textContent = sound.id;
    const info = document.createElement('p'); info.textContent = `${seconds.toFixed(2)} seconds · ${sound.samples.toLocaleString()} samples`;
    const alias = document.createElement('p'); alias.className = 'aliases'; alias.textContent = aliases.length ? `Also used by ${aliases.join(', ')}` : 'Unique directory entry';
    const audio = document.createElement('audio'); audio.controls = true; audio.preload = 'none'; audio.src = sound.source; audio.setAttribute('aria-label', `Play ${sound.id}`);
    audio.addEventListener('play', () => { for (const other of soundGrid.querySelectorAll('audio')) if (other !== audio) other.pause(); });
    const links = document.createElement('div'); links.className = 'sound-links';
    const download = document.createElement('a'); download.href = sound.source; download.download = ''; download.textContent = 'Download WAV';
    const metadata = document.createElement('a'); metadata.href = sound.metadata; metadata.textContent = 'Source metadata';
    links.append(download, metadata); card.append(title, info, alias, audio, links); soundGrid.append(card);
  }
  document.getElementById('audio-count').textContent = `${count} sound ${count === 1 ? 'phrase' : 'phrases'}`;
}
search.addEventListener('input', filterSounds);
lengthFilter.addEventListener('change', filterSounds);
filterSounds();
