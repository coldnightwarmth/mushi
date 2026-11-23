'use strict';
(() => {
  const data = window.MUSHI_ANIMATIONS, root = document.getElementById('sequences');
  function element(tag, text, className) {
    const node = document.createElement(tag);
    if (text) node.textContent = text;
    if (className) node.className = className;
    return node;
  }
  for (const sequence of data.sequences) {
    const card = element('article', null, 'sequence'), top = element('div', null, 'sequence-top');
    const canvas = element('canvas'); canvas.width = canvas.height = 192;
    canvas.setAttribute('aria-label', sequence.label + ' preview');
    const content = element('div'), title = element('h3', sequence.label), description = element('p');
    const controls = element('div', null, 'sequence-controls');
    const play = element('button', 'Play'), step = element('button', 'Next frame');
    const speedLabel = element('label', 'Preview speed '), speed = element('select');
    speed.setAttribute('aria-label', sequence.label + ' preview speed');
    for (const value of [4, 15, 60]) {
      const option = element('option', value + ' ticks/s'); option.value = value; speed.append(option);
    }
    speedLabel.append(speed);
    const status = element('span', 'Loading frames…', 'sequence-status'); status.setAttribute('aria-live', 'polite');
    controls.append(play, step, speedLabel); play.disabled = step.disabled = true;
    const links = element('div', null, 'sequence-links'), metadata = element('a', 'Sequence metadata ↗');
    metadata.href = sequence.metadata; links.append(metadata);
    const strip = element('div', null, 'frame-strip');
    const context = canvas.getContext('2d'); context.imageSmoothingEnabled = false;
    const images = new Map();
    for (const frame of sequence.frames) {
      const image = new Image(); image.src = frame.source; image.alt = frame.id; images.set(frame.id, image);
    }
    let profile = sequence, index = 0, playing = false, next = 0, request = 0, ready = false, cells = [];
    const scale = Math.max(1, Math.floor(160 / Math.max(...sequence.frames.flatMap(frame => [frame.width, frame.height]))));
    function draw() {
      const frame = profile.frames[index], image = images.get(frame.id);
      context.clearRect(0, 0, 192, 192);
      context.drawImage(image, (192 - image.naturalWidth * scale) / 2, (192 - image.naturalHeight * scale) / 2,
        image.naturalWidth * scale, image.naturalHeight * scale);
      status.textContent = 'Frame ' + (index + 1) + ' / ' + profile.frames.length + ' · ' + frame.ticks + ' tick' + (frame.ticks === 1 ? '' : 's');
      cells.forEach((cell, i) => cell.classList.toggle('current', i === index));
    }
    function stop() {
      playing = false; cancelAnimationFrame(request);
      play.textContent = index === profile.frames.length - 1 ? 'Replay' : 'Play';
    }
    function selectProfile(selected) {
      stop(); profile = selected; index = 0; play.textContent = 'Play'; strip.replaceChildren(); cells = [];
      for (const frame of profile.frames) {
        const link = element('a'); link.href = frame.metadata; link.title = 'Inspect ' + frame.id;
        const image = element('img'); image.src = frame.source; image.alt = frame.id;
        link.append(image, element('span', frame.id), element('span', frame.ticks + ' tick' + (frame.ticks === 1 ? '' : 's')));
        strip.append(link); cells.push(link);
      }
      description.textContent = 'Primary layer · ' + profile.frames.length + ' frames · ' + profile.ticks +
        ' update ticks · ' + (sequence.particle_type !== undefined ? 'particle type ' + sequence.particle_type : 'variants ' + sequence.variants.join(', '));
      if (ready) draw();
    }
    if (sequence.profiles) {
      const fadeLabel = element('label', 'Initial fade '), fade = element('select');
      fade.setAttribute('aria-label', sequence.label + ' initial fade');
      for (const entry of [...sequence.profiles].reverse()) {
        const option = element('option', String(entry.initial_fade)); option.value = entry.initial_fade; fade.append(option);
      }
      fade.value = sequence.default_initial_fade;
      fade.addEventListener('change', () => selectProfile(sequence.profiles.find(entry => entry.initial_fade === Number(fade.value))));
      fadeLabel.append(fade); controls.append(fadeLabel);
      profile = sequence.profiles.find(entry => entry.initial_fade === sequence.default_initial_fade);
    }
    controls.append(status);
    content.append(title, description, controls, links); top.append(canvas, content);
    card.append(top, strip, element('p', sequence.note, 'sequence-note')); root.append(card);
    function tick(time) {
      if (!playing) return;
      if (time >= next) {
        if (index === profile.frames.length - 1) { stop(); return; }
        index++; draw(); next = time + profile.frames[index].ticks * 1000 / Number(speed.value);
      }
      request = requestAnimationFrame(tick);
    }
    play.addEventListener('click', () => {
      if (playing) { stop(); return; }
      index = 0; draw(); playing = true; play.textContent = 'Pause';
      next = performance.now() + profile.frames[0].ticks * 1000 / Number(speed.value);
      request = requestAnimationFrame(tick);
    });
    step.addEventListener('click', () => { stop(); index = (index + 1) % profile.frames.length; draw(); stop(); });
    speed.addEventListener('change', () => { if (playing) next = performance.now() + profile.frames[index].ticks * 1000 / Number(speed.value); });
    selectProfile(profile);
    Promise.all([...images.values()].map(image => image.decode())).then(() => {
      ready = true; draw(); play.disabled = step.disabled = false;
    }).catch(() => { status.textContent = 'Frame images could not load'; });
  }
})();
