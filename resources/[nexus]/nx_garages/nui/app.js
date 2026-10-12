/* ==========================================================================
   Nexus Framework :: garages
   ========================================================================== */

const $ = (id) => document.getElementById(id);
const RESOURCE = 'nx_garages';

const state = {
    data: null,
    filter: 'all',
};

const post = (event, payload = {}) =>
    fetch(`https://${RESOURCE}/${event}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload),
    }).catch(() => {});

const money = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');

const el = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
};

/* ------------------------------ filters ------------------------------ */

function renderFilters() {
    const host = $('filters');
    host.innerHTML = '';

    const types = [{ id: 'all', label: 'All' }, ...(state.data.types || [])];
    types.forEach((type) => {
        const chip = el('button', 'chip' + (state.filter === type.id ? ' selected' : ''), type.label);
        chip.addEventListener('click', () => {
            state.filter = type.id;
            renderFilters();
            renderVehicles();
        });
        host.appendChild(chip);
    });
}

/* ------------------------------ list ------------------------------ */

function stateLabel(vehicle) {
    if (vehicle.state === 0) return 'out';
    if (vehicle.state === 2) return 'impounded';
    return 'stored';
}

function renderVehicles() {
    const host = $('vehicles');
    host.innerHTML = '';

    const vehicles = (state.data.vehicles || []).filter((vehicle) => {
        if (state.filter === 'all') return true;
        return (vehicle.vtype || 'automobile') === state.filter;
    });

    if (!vehicles.length) {
        host.appendChild(el('p', 'hint', state.data.garage.impound
            ? 'Nothing has been impounded.'
            : 'No vehicles here yet.'));
        return;
    }

    vehicles.forEach((vehicle) => {
        const status = stateLabel(vehicle);
        const node = el('div', 'vehicle' + (status === 'out' ? ' out' : ''));

        const left = el('div', 'left');
        left.appendChild(el('div', 'name', `${vehicle.label || vehicle.model} · ${vehicle.plate}`));

        const sub = el('div', 'sub');
        sub.append(
            el('span', null, `${Math.round(vehicle.fuel || 0)}% fuel`),
            el('span', null, `${Math.round(vehicle.mileage || 0)} km`),
            el('span', null, `${Math.round(((vehicle.engine_health || 1000) / 1000) * 100)}% engine`)
        );
        left.appendChild(sub);

        const right = el('div', 'right');
        const tag = el('span', `tag ${status}`, status);
        right.appendChild(tag);

        if (status === 'impounded') {
            right.appendChild(el('span', 'fee', money(vehicle.fee || 0)));
        }

        node.append(left, right);
        node.addEventListener('click', () => {
            post('nx:retrieve', { plate: vehicle.plate, model: vehicle.model });
            $('app').classList.add('hidden');
            post('nx:close');
        });

        host.appendChild(node);
    });
}

/* ------------------------------ bridge ------------------------------ */

window.addEventListener('message', (event) => {
    const payload = event.data || {};
    const data = payload.data || {};

    switch (payload.action) {
        case 'open':
        case 'update':
            if (!data.garage) break;
            state.data = data;
            state.filter = 'all';

            $('garage-label').textContent = data.garage.label;
            $('garage-type').textContent = data.garage.impound
                ? 'Impound lot'
                : data.garage.fleet ? 'Department fleet' : 'Garage';

            $('cash').textContent = money(data.money.cash);
            $('bank').textContent = money(data.money.bank);
            $('hint').textContent = data.garage.impound
                ? 'Impound fees must be paid before the vehicle is released.'
                : data.garage.fleet
                    ? 'Fleet vehicles are returned, not owned.'
                    : 'Choose a vehicle to bring it out.';

            $('btn-store').classList.toggle('hidden', data.garage.impound === true);
            renderFilters();
            renderVehicles();
            $('app').classList.remove('hidden');
            break;

        case 'close':
            $('app').classList.add('hidden');
            break;

        default:
            break;
    }
});

$('btn-close').addEventListener('click', () => {
    $('app').classList.add('hidden');
    post('nx:close');
});

$('btn-store').addEventListener('click', () => post('nx:store', {}));
$('btn-refresh').addEventListener('click', () => post('nx:refresh'));

document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return;
    $('app').classList.add('hidden');
    post('nx:close');
});
