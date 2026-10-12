/* ==========================================================================
   Nexus Framework :: spawn selector
   ========================================================================== */

const $ = (id) => document.getElementById(id);
const RESOURCE = 'nx_spawn';

let spawns = [];
let selected = 0;
let data = {};

const post = (event, payload = {}) =>
    fetch(`https://${RESOURCE}/${event}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload),
    }).catch(() => {});

function render() {
    const grid = $('spawn-grid');
    grid.innerHTML = '';

    spawns.forEach((spawn, index) => {
        const card = document.createElement('div');
        card.className = 'spawn' + (index === selected ? ' selected' : '');

        const badge = document.createElement('span');
        badge.className = 'spawn-badge' + (spawn.reason === 'last' ? ' last' : spawn.reason === 'job' ? ' job' : '');
        badge.textContent = spawn.reason === 'last' ? 'Last location' : spawn.reason === 'job' ? 'Job' : 'City';

        const name = document.createElement('div');
        name.className = 'spawn-name';
        name.textContent = spawn.label;

        const coords = document.createElement('div');
        coords.className = 'spawn-coords';
        coords.textContent = `${Number(spawn.coords[0]).toFixed(1)}, ${Number(spawn.coords[1]).toFixed(1)}, ${Number(spawn.coords[2]).toFixed(1)}`;

        const glow = document.createElement('div');
        glow.className = 'spawn-glow';

        card.appendChild(badge);
        card.appendChild(name);
        card.appendChild(coords);
        card.appendChild(glow);

        card.addEventListener('click', () => choose(index));
        card.addEventListener('mouseenter', () => {
            selected = index;
            highlight();
        });

        grid.appendChild(card);
    });
}

function highlight() {
    Array.from($('spawn-grid').children).forEach((child, index) => {
        child.classList.toggle('selected', index === selected);
    });
}

function choose(index) {
    const spawn = spawns[index];
    if (!spawn) return;
    post('nx:spawn', { key: spawn.key, useLastPosition: spawn.reason === 'last' });
    $('app').classList.add('hidden');
}

/* ------------------------------ countdown ------------------------------ */

let timerHandle = null;

function startCountdown(seconds) {
    clearInterval(timerHandle);
    let remaining = seconds;
    const el = $('timer');

    const tick = () => {
        el.textContent = `Auto-spawning in ${remaining}s`;
        if (remaining <= 0) {
            clearInterval(timerHandle);
            post('nx:spawnDefault');
        }
        remaining -= 1;
    };

    tick();
    timerHandle = setInterval(tick, 1000);
}

/* ------------------------------ bridge ------------------------------ */

window.addEventListener('message', (event) => {
    const payload = event.data || {};
    const incoming = payload.data || {};

    switch (payload.action) {
        case 'open': {
            data = incoming;
            spawns = incoming.spawns || [];
            selected = 0;

            $('player-name').textContent = incoming.name || 'Citizen';
            $('player-job').textContent = incoming.job
                ? `${incoming.job} · choose your starting location`
                : 'Choose your starting location';

            const resume = $('resume');
            if (incoming.lastCoords && incoming.lastLocation) {
                resume.classList.remove('hidden');
            } else {
                resume.classList.add('hidden');
            }

            render();
            $('app').classList.remove('hidden');
            startCountdown(Math.max(5, Math.round((incoming.timeout || 45000) / 1000)));
            break;
        }

        case 'close':
            clearInterval(timerHandle);
            $('app').classList.add('hidden');
            break;

        default:
            break;
    }
});

$('btn-resume').addEventListener('click', () => {
    clearInterval(timerHandle);
    post('nx:spawnDefault');
    $('app').classList.add('hidden');
});

document.addEventListener('keydown', (event) => {
    if ($('app').classList.contains('hidden')) return;

    if (event.key === 'ArrowDown' || event.key === 'ArrowRight') {
        event.preventDefault();
        selected = Math.min(spawns.length - 1, selected + 1);
        highlight();
    } else if (event.key === 'ArrowUp' || event.key === 'ArrowLeft') {
        event.preventDefault();
        selected = Math.max(0, selected - 1);
        highlight();
    } else if (event.key === 'Enter') {
        event.preventDefault();
        choose(selected);
    }
});
