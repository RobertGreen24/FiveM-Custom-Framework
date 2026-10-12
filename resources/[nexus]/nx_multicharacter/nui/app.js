/* ==========================================================================
   Nexus Framework :: character select (vanilla JS)
   ========================================================================== */

const $ = (id) => document.getElementById(id);
const RESOURCE = 'nx_multicharacter';

let characters = [];
let maxSlots = 4;
let selectedGender = 0;

const post = (event, data = {}) =>
    fetch(`https://${RESOURCE}/${event}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    }).catch(() => {});

/* ============================== formatting ============================== */

function money(value) {
    const n = Math.floor(Number(value) || 0);
    return '$' + n.toLocaleString('en-US');
}

function playtime(seconds) {
    const s = Math.floor(Number(seconds) || 0);
    const hours = Math.floor(s / 3600);
    const minutes = Math.floor((s % 3600) / 60);
    if (hours <= 0) return `${minutes}m`;
    return `${hours}h ${minutes}m`;
}

function dateOnly(value) {
    if (!value) return '—';
    return String(value).slice(0, 10);
}

function age(value) {
    if (!value) return '';
    const birth = new Date(String(value).slice(0, 10));
    if (Number.isNaN(birth.getTime())) return '';
    const now = new Date();
    let years = now.getFullYear() - birth.getFullYear();
    const m = now.getMonth() - birth.getMonth();
    if (m < 0 || (m === 0 && now.getDate() < birth.getDate())) years -= 1;
    return `${years} yrs`;
}

/* ============================== rendering ============================== */

function renderCharacters() {
    const list = $('character-list');
    list.innerHTML = '';

    const free = Math.max(0, maxSlots - characters.length);
    $('slot-count').textContent = `${characters.length} / ${maxSlots} slots used`;
    $('stat-characters').textContent = String(characters.length);
    $('btn-new').disabled = free <= 0;
    $('btn-new').textContent = free <= 0 ? 'All slots in use' : '+ Create character';

    if (!characters.length) {
        const empty = document.createElement('div');
        empty.className = 'card';
        empty.innerHTML = `<h3>No characters yet</h3>
            <p class="muted">Create your first character to enter the city. You can hold up to
            ${maxSlots} characters on this account.</p>`;
        list.appendChild(empty);
        return;
    }

    characters
        .slice()
        .sort((a, b) => Number(a.slot) - Number(b.slot))
        .forEach((character) => {
            const card = document.createElement('div');
            card.className = 'character';

            const head = document.createElement('div');
            head.className = 'character-head';

            const nameWrap = document.createElement('div');
            const name = document.createElement('div');
            name.className = 'character-name';
            name.textContent = `${character.first_name} ${character.last_name}`;
            const meta = document.createElement('div');
            meta.className = 'character-meta';
            const gender = Number(character.gender) === 1 ? 'Female' : 'Male';
            meta.textContent = `${gender} · ${age(character.birth_date)} · ${character.nationality || 'American'}`;
            nameWrap.appendChild(name);
            nameWrap.appendChild(meta);

            const slot = document.createElement('span');
            slot.className = 'character-slot';
            slot.textContent = `Slot ${character.slot}`;

            head.appendChild(nameWrap);
            head.appendChild(slot);

            const stats = document.createElement('div');
            stats.className = 'character-stats';
            const rows = [
                ['Cash', money(character.cash)],
                ['Bank', money(character.bank)],
                ['Job', character.job ? character.job.replace(/_/g, ' ') : 'unemployed'],
                ['Playtime', playtime(character.playtime)],
            ];
            rows.forEach(([label, value]) => {
                const line = document.createElement('div');
                line.className = 'stat-line';
                line.innerHTML = `<span>${label}</span><strong></strong>`;
                line.querySelector('strong').textContent = value;
                stats.appendChild(line);
            });

            const actions = document.createElement('div');
            actions.className = 'character-actions';

            const play = document.createElement('button');
            play.className = 'btn primary';
            play.textContent = 'Play';
            play.addEventListener('click', (event) => {
                event.stopPropagation();
                play.textContent = 'Loading…';
                post('nx:select', { charId: character.id });
            });

            const remove = document.createElement('button');
            remove.className = 'btn danger';
            remove.textContent = 'Delete';
            remove.addEventListener('click', (event) => {
                event.stopPropagation();
                if (window.confirm(`Delete ${character.first_name} ${character.last_name} permanently?`)) {
                    post('nx:delete', { charId: character.id });
                }
            });

            actions.appendChild(play);
            actions.appendChild(remove);

            card.appendChild(head);
            card.appendChild(stats);
            card.appendChild(actions);
            card.addEventListener('click', () => post('nx:select', { charId: character.id }));

            list.appendChild(card);
        });
}

/* ============================== views ============================== */

function showView(view) {
    $('view-actions').classList.toggle('hidden', view !== 'actions');
    $('view-create').classList.toggle('hidden', view !== 'create');
    $('create-error').classList.add('hidden');
}

function buildNationalities(list) {
    const select = $('nationality');
    select.innerHTML = '';
    (list && list.length ? list : ['American']).forEach((nationality) => {
        const option = document.createElement('option');
        option.value = nationality;
        option.textContent = nationality;
        select.appendChild(option);
    });
}

/* ============================== events ============================== */

$('btn-new').addEventListener('click', () => {
    // default the birth date to 25 years ago
    const date = new Date();
    date.setFullYear(date.getFullYear() - 25);
    $('birth-date').value = date.toISOString().slice(0, 10);
    showView('create');
    setTimeout(() => $('first-name').focus(), 60);
});

$('btn-cancel-create').addEventListener('click', () => showView('actions'));

$('btn-refresh').addEventListener('click', () => post('nx:refresh'));

document.querySelectorAll('#gender-group .seg').forEach((button) => {
    button.addEventListener('click', () => {
        document.querySelectorAll('#gender-group .seg').forEach((other) => other.classList.remove('selected'));
        button.classList.add('selected');
        selectedGender = Number(button.dataset.value);
    });
});

$('view-create').addEventListener('submit', (event) => {
    event.preventDefault();
    const payload = {
        firstName: $('first-name').value.trim(),
        lastName: $('last-name').value.trim(),
        gender: selectedGender,
        birthDate: $('birth-date').value,
        nationality: $('nationality').value,
    };

    if (!payload.firstName || !payload.lastName) {
        return showError('Enter a first and last name.');
    }
    if (!payload.birthDate) {
        return showError('Choose a date of birth.');
    }

    post('nx:create', payload);
    return undefined;
});

function showError(message) {
    const box = $('create-error');
    box.textContent = message;
    box.classList.remove('hidden');
}

/* ============================== bridge ============================== */

window.addEventListener('message', (event) => {
    const payload = event.data || {};
    const data = payload.data || {};

    switch (payload.action) {
        case 'open':
            characters = data.characters || [];
            maxSlots = data.maxSlots || 4;
            buildNationalities(data.nationalities);
            $('account-line').textContent = data.account && data.account.name
                ? `Signed in as ${data.account.name}`
                : 'Welcome to the city';
            showView('actions');
            renderCharacters();
            $('app').classList.remove('hidden');
            break;

        case 'update':
            characters = data.characters || characters;
            maxSlots = data.maxSlots || maxSlots;
            showView('actions');
            renderCharacters();
            break;

        case 'createFailed':
            showView('create');
            showError(data.message || 'Could not create that character.');
            break;

        case 'close':
            $('app').classList.add('hidden');
            break;

        default:
            break;
    }
});

document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
        post('nx:close');
    }
});
