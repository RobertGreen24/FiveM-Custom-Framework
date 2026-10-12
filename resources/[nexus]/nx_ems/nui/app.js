/* ==========================================================================
   Nexus Framework :: EMS charts
   ========================================================================== */

const $ = (id) => document.getElementById(id);
const RESOURCE = 'nx_ems';

let data = null;
let results = { patients: [] };
let alertCount = 0;

const post = (event, payload = {}) =>
    fetch(`https://${RESOURCE}/${event}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload),
    }).catch(() => {});

const esc = (value) => String(value == null ? '' : value);

const el = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
};

function row({ title, sub, tags = [], actions = [], onClick }) {
    const node = el('div', 'row' + (onClick ? ' clickable' : ''));
    const main = el('div');
    main.append(el('div', 'title', title), el('div', 'sub', sub));
    const side = el('div', 'side');
    tags.forEach((tag) => side.appendChild(el('span', `tag ${tag.tone || ''}`, tag.label)));
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

/* ------------------------------ views ------------------------------ */

function renderDispatch() {
    $('stat-calls').textContent = (data.calls || []).length;
    $('stat-medics').textContent = (data.medics || []).length;
    $('stat-alerts').textContent = alertCount;

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
                    try {
                        const coords = JSON.parse(call.coords || 'null');
                        if (coords) {
                            post('nx:waypoint', { coords: [coords.x, coords.y, coords.z] });
                        }
                    } catch (error) { /* ignore */ }
                    post('nx:call', { id: call.id });
                },
            }],
        }));
    });
}

function renderRecent() {
    const list = $('recent');
    list.innerHTML = '';
    const recent = data.recent || [];
    if (!recent.length) {
        list.appendChild(el('p', 'muted', 'No charts yet.'));
        return;
    }

    recent.forEach((record) => {
        const name = record.first_name ? `${record.first_name} ${record.last_name}` : `Character #${record.char_id}`;
        list.appendChild(row({
            title: `${record.title} · ${name}`,
            sub: `${record.medic} · ${String(record.created_at).slice(0, 16)}`,
            tags: [{ label: record.type, tone: record.type === 'death' ? 'danger' : 'info' }],
            onClick: record.char_id ? () => post('nx:chart', { charId: record.char_id }) : undefined,
        }));
    });
}

function renderPatients() {
    const list = $('patients');
    list.innerHTML = '';
    if (!results.patients.length) {
        list.appendChild(el('p', 'muted', 'Search for a patient to open their chart.'));
        return;
    }

    results.patients.forEach((patient) => {
        list.appendChild(row({
            title: `${patient.first_name} ${patient.last_name}`,
            sub: `ID ${patient.state_id} · ${patient.phone || 'no phone'} · ${patient.job}`,
            tags: [{ label: 'Chart', tone: 'info' }],
            onClick: () => post('nx:chart', { charId: patient.id }),
        }));
    });
}

function renderHospitals() {
    const list = $('hospitals');
    list.innerHTML = '';
    (data.hospitals || []).forEach((hospital) => {
        list.appendChild(row({
            title: hospital.label,
            sub: `Bed at ${Math.round(hospital.bed.x)}, ${Math.round(hospital.bed.y)}`,
            tags: [{ label: 'Hospital', tone: 'ok' }],
            actions: [{
                label: 'Route',
                onClick: () => post('nx:waypoint', {
                    coords: [hospital.coords.x, hospital.coords.y, hospital.coords.z],
                }),
            }],
        }));
    });
}

function switchTab(name) {
    document.querySelectorAll('.tab').forEach((tab) => tab.classList.toggle('selected', tab.dataset.tab === name));
    ['dispatch', 'recent', 'patients', 'hospitals'].forEach((tab) => {
        $(`view-${tab}`).classList.toggle('hidden', tab !== name);
    });
}

document.querySelectorAll('.tab').forEach((tab) => {
    tab.addEventListener('click', () => switchTab(tab.dataset.tab));
});

/* ------------------------------ chart modal ------------------------------ */

function openChart(chart) {
    const node = $('chart');
    node.innerHTML = '';

    const card = el('div', 'chart-card');
    const head = el('div', 'chart-head');
    const left = el('div');
    left.append(
        el('h2', null, `${chart.first_name} ${chart.last_name}`),
        el('div', 'sub', `Character #${chart.id} · state id ${chart.state_id || '—'} · ${chart.online ? 'in the city' : 'offline'}`)
    );
    const close = el('button', 'btn ghost', 'Close');
    close.addEventListener('click', () => node.classList.add('hidden'));
    head.append(left, close);
    card.appendChild(head);

    const grid = el('div', 'chart-grid');
    [
        ['Date of birth', chart.birth_date],
        ['Blood type', chart.bloodType],
        ['Allergies', chart.allergies],
        ['Phone', chart.phone],
        ['Unpaid medical', `$${Number(chart.unpaid || 0).toLocaleString('en-US')}`],
    ].forEach(([label, value]) => {
        const field = el('div', 'field');
        field.append(el('span', null, label), el('b', null, esc(value || '—')));
        grid.appendChild(field);
    });
    card.appendChild(grid);

    card.appendChild(el('h3', null, 'Medical history'));
    const history = el('div', 'list');
    if (!(chart.records || []).length) {
        history.appendChild(el('p', 'muted', 'No history on file.'));
    }
    (chart.records || []).forEach((record) => {
        history.appendChild(row({
            title: record.title,
            sub: `${record.medic} · ${String(record.created_at).slice(0, 16)}${record.details ? ` · ${record.details}` : ''}`,
            tags: [{ label: record.type, tone: record.type === 'death' ? 'danger' : 'info' }],
        }));
    });
    card.appendChild(history);

    card.appendChild(el('h3', null, 'Add chart entry'));
    const form = el('div', 'form');
    const title = el('input'); title.placeholder = 'Title';
    const details = el('input'); details.placeholder = 'Details';
    const submit = el('button', 'btn primary', 'Save entry');
    submit.addEventListener('click', () => {
        if (!title.value.trim()) return;
        post('nx:note', { charId: chart.id, title: title.value, details: details.value });
        title.value = ''; details.value = '';
    });
    form.append(title, details, submit);
    card.appendChild(form);

    node.appendChild(card);
    node.classList.remove('hidden');
}

/* ------------------------------ bridge ------------------------------ */

window.addEventListener('message', (event) => {
    const payload = event.data || {};
    const payloadData = payload.data || {};

    switch (payload.action) {
        case 'open':
        case 'update':
            if (!payloadData.medic) break;
            data = payloadData;
            results = { patients: results.patients };
            renderDispatch();
            renderRecent();
            renderHospitals();
            renderPatients();
            $('app').classList.remove('hidden');
            break;

        case 'results':
            results = { patients: payloadData.patients || [] };
            switchTab('patients');
            renderPatients();
            break;

        case 'chart':
            openChart(payloadData);
            break;

        case 'alert':
            alertCount += 1;
            $('stat-alerts').textContent = alertCount;
            break;

        case 'close':
            $('app').classList.add('hidden');
            $('chart').classList.add('hidden');
            break;

        default:
            break;
    }
});

$('btn-search').addEventListener('click', () => {
    const query = $('search').value.trim();
    if (query.length >= 2) post('nx:search', { query });
});

$('search').addEventListener('keydown', (event) => {
    if (event.key === 'Enter') $('btn-search').click();
});

$('btn-refresh').addEventListener('click', () => post('nx:refresh'));

$('btn-close').addEventListener('click', () => {
    $('app').classList.add('hidden');
    $('chart').classList.add('hidden');
    post('nx:close');
});

document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return;
    if (!$('chart').classList.contains('hidden')) {
        $('chart').classList.add('hidden');
        return;
    }
    $('app').classList.add('hidden');
    post('nx:close');
});
