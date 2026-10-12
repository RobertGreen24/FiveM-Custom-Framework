/* ==========================================================================
   Nexus Framework :: MDT
   ========================================================================== */

const $ = (id) => document.getElementById(id);
const RESOURCE = 'nx_police';

let data = null;
let results = { people: [], vehicles: [] };
let profile = null;

const post = (event, payload = {}) =>
    fetch(`https://${RESOURCE}/${event}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload),
    }).catch(() => {});

const money = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');

let toastTimer = 0;

function toast(kind, head, body, duration = 7000) {
    const holder = $('toasts');
    if (!holder) return;

    const node = el('div', `toast ${kind || ''}`);
    node.appendChild(el('div', 't-head', head));
    if (body) node.appendChild(el('div', 't-body', body));
    holder.appendChild(node);

    const id = ++toastTimer;
    setTimeout(() => {
        if (id !== toastTimer && holder.childElementCount > 3) {
            node.remove();
            return;
        }
        node.classList.add('out');
        setTimeout(() => node.remove(), 220);
    }, duration);
}

function renderJail(data) {
    const banner = $('jail-banner');
    if (!banner) return;

    if (!data || !data.active) {
        banner.classList.add('hidden');
        return;
    }

    $('jail-title').textContent = `Jailed · ${data.minutes || 0} minute(s)`;
    $('jail-sub').textContent = data.reason || 'No reason given';
    banner.classList.remove('hidden');
}
const esc = (value) => String(value == null ? '' : value);

const el = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
};

/* ------------------------------ helpers ------------------------------ */

function row({ title, sub, tags = [], onClick, actions = [] }) {
    const node = el('div', 'row' + (onClick ? ' clickable' : ''));
    const main = el('div', 'main');
    main.appendChild(el('div', 'title', title));
    if (sub) main.appendChild(el('div', 'sub', sub));

    const side = el('div', 'side');
    tags.forEach((tag) => {
        const pill = el('span', `tag ${tag.tone || ''}`, tag.label);
        side.appendChild(pill);
    });
    actions.forEach((action) => {
        const button = el('button', 'btn small', action.label);
        button.addEventListener('click', (event) => {
            event.stopPropagation();
            action.onClick();
        });
        side.appendChild(button);
    });

    node.append(main, side);
    if (onClick) node.addEventListener('click', onClick);
    return node;
}

function coordsCoords(value) {
    if (!value) return null;
    if (Array.isArray(value)) return value;
    try {
        return JSON.parse(value);
    } catch (error) {
        return null;
    }
}

/* ------------------------------ dashboard ------------------------------ */

function renderDashboard() {
    const incidents = (data.incidents || []).filter((incident) => incident.status !== 'closed');
    $('stat-incidents').textContent = incidents.length;
    $('stat-warrants').textContent = (data.warrants || []).length;
    $('stat-bolos').textContent = (data.bolos || []).length;
    $('stat-calls').textContent = (data.calls || []).length;

    $('pill-warrants').textContent = (data.warrants || []).length;
    $('pill-bolos').textContent = (data.bolos || []).length;
    $('pill-calls').textContent = (data.calls || []).length;

    const feed = $('feed');
    feed.innerHTML = '';

    const entries = [
        ...(data.incidents || []).map((incident) => ({
            code: incident.code, priority: incident.priority,
            text: incident.title, meta: `${incident.created_by} · ${String(incident.created_at).slice(5, 16)}`,
            status: incident.status,
        })),
        ...(data.calls || []).map((call) => ({
            code: '911', priority: 'high', text: call.message, meta: `${call.caller || 'unknown'} · ${call.number || '—'}`,
            status: 'open',
        })),
    ].slice(0, 24);

    if (!entries.length) {
        feed.appendChild(el('p', 'muted', 'Nothing to report.'));
        return;
    }

    entries.forEach((entry) => {
        const node = el('div', 'feed-row');
        const code = el('span', `code ${entry.priority === 'high' ? 'high' : entry.priority === 'low' ? 'low' : ''} ${entry.status === 'closed' ? 'done' : ''}`, entry.code || '—');
        node.append(code, el('div', null, entry.text), el('div', 'muted', entry.meta));
        feed.appendChild(node);
    });
}

/* ------------------------------ tabs ------------------------------ */

function renderPeople() {
    const list = $('people');
    list.innerHTML = '';
    if (!results.people.length) {
        list.appendChild(el('p', 'muted', 'Search for a person to see their record.'));
        return;
    }
    results.people.forEach((person) => {
        list.appendChild(row({
            title: `${person.first_name} ${person.last_name}`,
            sub: `ID ${person.state_id} · ${person.job} · ${person.phone || 'no phone'} · last seen ${String(person.last_seen || '—').slice(0, 16)}`,
            tags: [{ label: 'Profile', tone: 'info' }],
            onClick: () => post('nx:profile', { charId: person.id }),
        }));
    });
}

function renderVehicles() {
    const list = $('vehicles');
    list.innerHTML = '';
    if (!results.vehicles.length) {
        list.appendChild(el('p', 'muted', 'Search or run a plate.'));
        return;
    }
    results.vehicles.forEach((vehicle) => {
        const owner = vehicle.first_name ? `${vehicle.first_name} ${vehicle.last_name}` : 'Unregistered';
        list.appendChild(row({
            title: vehicle.plate,
            sub: `${vehicle.label || vehicle.model} · ${vehicle.vtype || 'vehicle'} · ${owner} · ${vehicle.mileage || 0} km`,
            tags: [{ label: vehicle.state == 1 ? 'Out' : 'Stored', tone: vehicle.state == 1 ? 'ok' : '' }],
            onClick: () => post('nx:plate', { plate: vehicle.plate }),
        }));
    });
}

function renderWarrants() {
    const list = $('warrants');
    list.innerHTML = '';
    if (!(data.warrants || []).length) {
        list.appendChild(el('p', 'muted', 'No active warrants.'));
        return;
    }
    data.warrants.forEach((warrant) => {
        const name = warrant.first_name ? `${warrant.first_name} ${warrant.last_name}` : `Character #${warrant.char_id}`;
        list.appendChild(row({
            title: name,
            sub: `${warrant.reason}${warrant.fine > 0 ? ` · ${money(warrant.fine)}` : ''} · by ${warrant.issued_by}`,
            tags: [{ label: warrant.priority || 'normal', tone: warrant.priority === 'high' ? 'danger' : 'warn' }],
            actions: [{ label: 'Clear', onClick: () => post('nx:clearWarrant', { id: warrant.id }) }],
        }));
    });
}

function renderBolos() {
    const list = $('bolos');
    list.innerHTML = '';
    if (!(data.bolos || []).length) {
        list.appendChild(el('p', 'muted', 'No active BOLOs.'));
        return;
    }
    data.bolos.forEach((bolo) => {
        list.appendChild(row({
            title: bolo.plate || bolo.model || 'Unidentified',
            sub: `${bolo.reason}${bolo.details ? ` · ${bolo.details}` : ''} · by ${bolo.issued_by}`,
            tags: [{ label: bolo.priority || 'normal', tone: bolo.priority === 'high' ? 'danger' : 'warn' }],
            actions: [{ label: 'Clear', onClick: () => post('nx:clearBolo', { id: bolo.id }) }],
        }));
    });
}

function renderIncidents() {
    const list = $('incidents');
    list.innerHTML = '';
    if (!(data.incidents || []).length) {
        list.appendChild(el('p', 'muted', 'No incidents logged.'));
        return;
    }
    data.incidents.forEach((incident) => {
        list.appendChild(row({
            title: `${incident.code} · ${incident.title}`,
            sub: `${incident.created_by} · ${String(incident.created_at).slice(0, 16)}`,
            tags: [{ label: incident.status, tone: incident.status === 'closed' ? 'ok' : 'warn' }],
            actions: incident.status === 'closed'
                ? []
                : [{ label: 'Close', onClick: () => {
                    const note = window.prompt('Closing note (optional):') || '';
                    post('nx:closeIncident', { id: incident.id, note });
                } }],
        }));
    });
}

function renderCalls() {
    const list = $('calls');
    list.innerHTML = '';
    if (!(data.calls || []).length) {
        list.appendChild(el('p', 'muted', 'No pending calls.'));
        return;
    }
    data.calls.forEach((call) => {
        list.appendChild(row({
            title: call.message,
            sub: `${call.caller || 'unknown'} · ${call.number || '—'} · ${String(call.created_at).slice(0, 16)}`,
            tags: [{ label: '911', tone: 'danger' }],
            actions: [{
                label: 'Respond',
                onClick: () => {
                    const coords = coordsCoords(call.coords);
                    if (coords) {
                        fetch(`https://${RESOURCE}/nx:waypoint`, {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                            body: JSON.stringify({ coords }),
                        }).catch(() => {});
                    }
                    post('nx:call', { id: call.id });
                },
            }],
        }));
    });
}

function switchTab(name) {
    document.querySelectorAll('.nav-item').forEach((item) => {
        item.classList.toggle('selected', item.dataset.tab === name);
    });
    ['dashboard', 'people', 'vehicles', 'warrants', 'bolos', 'incidents', 'calls', 'actions'].forEach((tab) => {
        $(`tab-${tab}`).classList.toggle('hidden', tab !== name);
    });
}

document.querySelectorAll('.nav-item').forEach((item) => {
    item.addEventListener('click', () => switchTab(item.dataset.tab));
});

/* ------------------------------ profile modal ------------------------------ */

function openProfile(person) {
    profile = person;
    const card = $('modal-card');
    card.innerHTML = '';

    const head = el('div', 'modal-head');
    const left = el('div');
    left.append(el('h2', null, person.name), el('div', 'sub', `Character #${person.id} · state id ${person.state_id || '—'}`));
    const close = el('button', 'btn ghost', 'Close');
    close.addEventListener('click', () => $('modal').classList.add('hidden'));
    head.append(left, close);

    const grid = el('div', 'modal-grid');
    const fields = [
        ['Date of birth', person.birth_date],
        ['Phone', person.phone],
        ['Employment', `${person.job} (${person.job_grade})`],
        ['Gang', person.gang && person.gang !== 'none' ? `${person.gang} (${person.gang_grade})` : 'None'],
        ['Unpaid fines', money(person.unpaidFines)],
        ['Last seen', String(person.last_seen || '—').slice(0, 16)],
    ];
    fields.forEach(([label, value]) => {
        const field = el('div', 'field');
        field.append(el('span', null, label), el('b', null, esc(value || '—')));
        grid.appendChild(field);
    });

    card.append(head, grid);

    // licences
    card.append(el('h3', null, 'Licences'));
    const licences = el('div', 'results');
    (person.licences || []).forEach((licence) => {
        licences.appendChild(row({
            title: licence.name.replace(/_/g, ' '),
            sub: `Issued by ${licence.issued_by || 'system'}`,
            tags: [
                { label: `${licence.points || 0} pts`, tone: '' },
                { label: licence.revoked == 1 ? 'Revoked' : 'Valid', tone: licence.revoked == 1 ? 'danger' : 'ok' },
            ],
        }));
    });
    if (!(person.licences || []).length) licences.appendChild(el('p', 'muted', 'No licences on file.'));
    card.appendChild(licences);

    // vehicles
    card.append(el('h3', null, 'Registered vehicles'));
    const vehicles = el('div', 'results');
    (person.vehicles || []).forEach((vehicle) => {
        vehicles.appendChild(row({
            title: vehicle.plate,
            sub: `${vehicle.label || vehicle.model} · ${vehicle.garage || 'unknown garage'}`,
            tags: [{ label: vehicle.state == 1 ? 'Out' : 'Stored', tone: vehicle.state == 1 ? 'ok' : '' }],
        }));
    });
    if (!(person.vehicles || []).length) vehicles.appendChild(el('p', 'muted', 'No vehicles registered.'));
    card.appendChild(vehicles);

    // warrants
    card.append(el('h3', null, 'Warrant history'));
    const warrants = el('div', 'results');
    (person.warrants || []).forEach((warrant) => {
        warrants.appendChild(row({
            title: warrant.reason,
            sub: `By ${warrant.issued_by} · ${String(warrant.issued_at).slice(0, 16)}`,
            tags: [{ label: warrant.active == 1 ? 'Active' : 'Cleared', tone: warrant.active == 1 ? 'danger' : 'ok' }],
            actions: warrant.active == 1 ? [{ label: 'Clear', onClick: () => post('nx:clearWarrant', { id: warrant.id }) }] : [],
        }));
    });
    if (!(person.warrants || []).length) warrants.appendChild(el('p', 'muted', 'No warrants.'));
    card.appendChild(warrants);

    // new warrant form
    card.append(el('h3', null, 'Issue a warrant'));
    const form = el('div', 'form');
    const reason = el('input'); reason.placeholder = 'Reason';
    const charges = el('input'); charges.placeholder = 'Charges (optional)';
    const fine = el('input'); fine.type = 'number'; fine.placeholder = 'Fine (optional)';
    const priority = el('select');
    ['low', 'normal', 'high'].forEach((value) => {
        const option = document.createElement('option');
        option.value = value; option.textContent = value; priority.appendChild(option);
    });
    priority.value = 'normal';
    const submit = el('button', 'btn primary', 'File warrant');
    submit.addEventListener('click', () => {
        if (!reason.value.trim()) return;
        post('nx:warrant', {
            charId: person.id, reason: reason.value, charges: charges.value,
            fine: Number(fine.value) || 0, priority: priority.value,
        });
        reason.value = ''; charges.value = ''; fine.value = '';
    });
    form.append(reason, charges, fine, priority, submit);
    card.appendChild(form);

    $('modal').classList.remove('hidden');
}

/* ------------------------------ bridges ------------------------------ */

window.addEventListener('message', (event) => {
    const payload = event.data || {};
    const payloadData = payload.data || {};

    switch (payload.action) {
        case 'open':
        case 'update':
            if (!payloadData.officer) break;
            data = payloadData;
            $('officer-name').textContent = data.officer.name;
            $('officer-meta').textContent = `${data.officer.gradeName || 'Officer'}${data.officer.callsign ? ` · ${data.officer.callsign}` : ''}`;
            renderDashboard();
            renderWarrants();
            renderBolos();
            renderIncidents();
            renderCalls();
            $('app').classList.remove('hidden');
            break;

        case 'results':
            results = { people: payloadData.people || [], vehicles: payloadData.vehicles || [] };
            renderPeople();
            renderVehicles();
            switchTab(results.people.length ? 'people' : 'vehicles');
            break;

        case 'profile':
            openProfile(payloadData);
            break;

        case 'plate':
            if (!payloadData.found) {
                window.alert(`Plate ${payloadData.plate} is not registered.`);
                break;
            }
            results.vehicles = [payloadData];
            renderVehicles();
            switchTab('vehicles');
            break;

        case 'search':
            window.alert(`Search of ${payloadData.name}: ${(payloadData.items || []).length} item(s), ${money(payloadData.cash)} cash.`);
            break;

        case 'dispatch':
            toast('dispatch', payloadData.code ? `Dispatch · ${payloadData.code}` : 'Dispatch',
                payloadData.message || 'New incident reported.');
            break;

        case 'fine':
            toast('cash', 'Fine issued', `${money(payloadData.amount)} · ${payloadData.reason || 'No reason given'}`);
            break;

        case 'jail':
            renderJail(payloadData);
            break;

        case 'close':
            $('app').classList.add('hidden');
            $('modal').classList.add('hidden');
            break;

        default:
            break;
    }
});

/* ------------------------------ events ------------------------------ */

$('btn-search').addEventListener('click', () => {
    const query = $('search').value.trim();
    if (query.length >= 2) post('nx:search', { query });
});

$('search').addEventListener('keydown', (event) => {
    if (event.key === 'Enter') $('btn-search').click();
});

$('btn-plate').addEventListener('click', () => {
    const plate = $('plate').value.trim();
    if (plate) post('nx:plate', { plate });
});

$('plate').addEventListener('keydown', (event) => {
    if (event.key === 'Enter') $('btn-plate').click();
});

$('btn-close').addEventListener('click', () => {
    $('app').classList.add('hidden');
    $('modal').classList.add('hidden');
    post('nx:close');
});

$('btn-new-warrant').addEventListener('click', () => {
    const id = window.prompt('Character id for the warrant:');
    if (!id) return;
    const reason = window.prompt('Reason:');
    if (!reason) return;
    const fine = Number(window.prompt('Fine (0 for none):', '0')) || 0;
    post('nx:warrant', { charId: Number(id), reason, fine, priority: 'normal' });
});

$('btn-new-bolo').addEventListener('click', () => {
    const plate = window.prompt('Plate (leave empty for a model BOLO):') || '';
    const model = plate ? '' : (window.prompt('Vehicle model:') || '');
    const reason = window.prompt('Reason:');
    if (!reason) return;
    post('nx:bolo', { plate, model, reason, priority: 'normal' });
});

$('btn-new-incident').addEventListener('click', () => {
    const code = window.prompt('Code (e.g. 10-31):', '10-31') || '10-31';
    const title = window.prompt('Title:');
    if (!title) return;
    const details = window.prompt('Details (optional):') || '';
    post('nx:incident', { code, title, details, priority: 'normal' });
});

$('btn-action-fine').addEventListener('click', () => {
    post('nx:fine', {
        target: Number($('action-fine-target').value),
        amount: Number($('action-fine-amount').value),
        reason: $('action-fine-reason').value,
    });
});

$('btn-action-jail').addEventListener('click', () => {
    post('nx:jail', {
        target: Number($('action-jail-target').value),
        minutes: Number($('action-jail-minutes').value) || 5,
        reason: $('action-jail-reason').value,
    });
});

$('btn-action-impound').addEventListener('click', () => {
    post('nx:impound', {
        plate: $('action-impound-plate').value,
        reason: $('action-impound-reason').value,
    });
});

document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return;
    if (!$('modal').classList.contains('hidden')) {
        $('modal').classList.add('hidden');
        return;
    }
    $('app').classList.add('hidden');
    post('nx:close');
});
