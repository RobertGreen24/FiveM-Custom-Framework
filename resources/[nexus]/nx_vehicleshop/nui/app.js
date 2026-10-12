/* ==========================================================================
   Nexus Framework :: dealership
   ========================================================================== */

const $ = (id) => document.getElementById(id);
const RESOURCE = 'nx_vehicleshop';

const state = {
    data: null,
    category: null,
    selected: null,
    payment: 'bank',
};

const post = (event, payload = {}) =>
    fetch(`https://${RESOURCE}/${event}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload),
    }).catch(() => {});

const money = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');

/* ------------------------------ categories ------------------------------ */

function renderCategories() {
    const data = state.data;
    const nav = $('categories');
    nav.innerHTML = '';

    (data.shop.categories || []).forEach((id) => {
        const label = (data.categoryLabels.find((entry) => entry.id === id) || {}).label || id;
        const count = data.vehicles.filter((v) => v.category === id).length;

        const row = document.createElement('div');
        row.className = 'category' + (id === state.category ? ' selected' : '');
        row.innerHTML = `<span class="cat-label"></span><span>${count}</span>`;
        row.querySelector('.cat-label').textContent = label;
        row.addEventListener('click', () => {
            state.category = id;
            renderCategories();
            renderVehicles();
        });
        nav.appendChild(row);
    });

    $('categories').classList.remove('hidden');
}

/* ------------------------------ vehicles ------------------------------ */

function renderVehicles() {
    const data = state.data;
    const grid = $('vehicles');
    grid.innerHTML = '';

    const label = (data.categoryLabels.find((entry) => entry.id === state.category) || {}).label || 'Vehicles';
    $('category-label').textContent = label;

    const list = data.vehicles.filter((v) => v.category === state.category);
    if (!list.length) {
        grid.innerHTML = '<div class="muted" style="padding:20px">Nothing in this category.</div>';
        return;
    }

    const ownedModels = new Set((data.myVehicles || []).map((v) => v.model));

    list.forEach((vehicle) => {
        const card = document.createElement('div');
        card.className = 'vehicle-card' + (ownedModels.has(vehicle.model) ? ' owned' : '');

        const total = vehicle.price + (data.fee || 0);

        card.innerHTML = `
            <div class="vc-head">
                <div class="vc-name"></div>
                <div class="vc-price"></div>
            </div>
            <div class="vc-meta"><span></span><span></span></div>`;

        card.querySelector('.vc-name').textContent = vehicle.label;
        card.querySelector('.vc-price').textContent = money(total);
        card.querySelector('.vc-meta').children[0].textContent = label;
        card.querySelector('.vc-meta').children[1].textContent = `Registration ${money(data.fee || 0)}`;

        if (ownedModels.has(vehicle.model)) {
            const badge = document.createElement('div');
            badge.className = 'vc-badge';
            badge.textContent = 'You own one';
            card.appendChild(badge);
        }

        card.addEventListener('mouseenter', () => post('nx:preview', { model: vehicle.model }));
        card.addEventListener('click', () => openDetail(vehicle));
        grid.appendChild(card);
    });
}

function renderOwned() {
    const data = state.data;
    const list = $('owned-list');
    list.innerHTML = '';

    $('owned-count').textContent = `${data.owned}/${data.maxOwned}`;

    (data.myVehicles || []).forEach((vehicle) => {
        const row = document.createElement('div');
        row.className = 'owned-item';
        row.innerHTML = `<span></span><button>Sell</button>`;
        row.querySelector('span').textContent = `${vehicle.label || vehicle.model} · ${vehicle.plate}`;
        row.querySelector('button').addEventListener('click', (event) => {
            event.stopPropagation();
            if (window.confirm(`Sell ${vehicle.label || vehicle.model} (${vehicle.plate}) to this dealership?`)) {
                post('nx:sell', { plate: vehicle.plate });
            }
        });
        list.appendChild(row);
    });

    if (!(data.myVehicles || []).length) {
        const empty = document.createElement('div');
        empty.className = 'muted small';
        empty.textContent = 'No vehicles yet.';
        list.appendChild(empty);
    }
}

function renderMoney() {
    $('money-cash').textContent = money(state.data.money.cash);
    $('money-bank').textContent = money(state.data.money.bank);
}

/* ------------------------------ detail ------------------------------ */

function openDetail(vehicle) {
    state.selected = vehicle;
    const data = state.data;

    const fee = data.fee || 0;
    const total = vehicle.price + fee;

    $('detail-category').textContent = (data.categoryLabels.find((entry) => entry.id === vehicle.category) || {}).label || '';
    $('detail-name').textContent = vehicle.label;
    $('detail-price').textContent = money(total);
    $('detail-fee').textContent = `includes ${money(fee)} registration`;

    // finance availability
    const financeEnabled = data.finance && data.finance.enabled;
    $('seg-finance').disabled = !financeEnabled;
    if (!financeEnabled && state.payment === 'finance') state.payment = 'bank';

    if (financeEnabled) {
        const deposit = Math.floor(total * data.finance.minDeposit);
        const financed = Math.floor((total - deposit) * (1 + data.finance.rate));
        const weekly = Math.ceil(financed / 2);
        $('credit-score').textContent = data.finance.score;
        $('finance-deposit').textContent = money(deposit);
        $('finance-rate').textContent = `${Math.round(data.finance.rate * 100)}%`;
        $('finance-weekly').textContent = money(weekly);
    }

    document.querySelectorAll('#payment-group .seg').forEach((seg) => {
        seg.classList.toggle('selected', seg.dataset.value === state.payment);
    });
    $('finance-box').classList.toggle('hidden', state.payment !== 'finance');
    $('detail-error').classList.add('hidden');

    $('detail').classList.remove('hidden');
    post('nx:preview', { model: vehicle.model });
}

function closeDetail() {
    $('detail').classList.add('hidden');
    state.selected = null;
}

/* ------------------------------ bridge ------------------------------ */

window.addEventListener('message', (event) => {
    const payload = event.data || {};
    const data = payload.data || {};

    switch (payload.action) {
        case 'open':
        case 'update':
            if (!data.shop) break;
            state.data = data;
            if (!state.category) state.category = (data.shop.categories || [])[0];
            $('shop-label').textContent = data.shop.label;
            $('shop-sub').textContent = 'Showroom';
            renderCategories();
            renderVehicles();
            renderOwned();
            renderMoney();
            $('app').classList.remove('hidden');
            break;

        case 'close':
            $('app').classList.add('hidden');
            closeDetail();
            break;

        default:
            break;
    }
});

/* ------------------------------ events ------------------------------ */

document.querySelectorAll('#payment-group .seg').forEach((seg) => {
    seg.addEventListener('click', () => {
        if (seg.disabled) return;
        state.payment = seg.dataset.value;
        document.querySelectorAll('#payment-group .seg').forEach((other) => other.classList.remove('selected'));
        seg.classList.add('selected');
        $('finance-box').classList.toggle('hidden', state.payment !== 'finance');
    });
});

$('btn-buy').addEventListener('click', () => {
    if (!state.selected || !state.data) return;
    const total = state.selected.price + (state.data.fee || 0);

    if (state.payment === 'finance') {
        post('nx:buy', { model: state.selected.model, finance: { terms: 14 } });
    } else {
        const balance = state.payment === 'cash' ? state.data.money.cash : state.data.money.bank;
        if (balance < total) {
            const error = $('detail-error');
            error.textContent = `Not enough money in your ${state.payment} — you need ${money(total)}.`;
            error.classList.remove('hidden');
            return;
        }
        post('nx:buy', { model: state.selected.model, payment: state.payment });
    }
    closeDetail();
});

$('btn-test').addEventListener('click', () => {
    if (!state.selected) return;
    post('nx:testDrive', { model: state.selected.model });
    closeDetail();
});

$('btn-preview').addEventListener('click', () => {
    if (state.selected) post('nx:preview', { model: state.selected.model });
});

$('btn-cancel').addEventListener('click', closeDetail);

$('btn-close').addEventListener('click', () => {
    $('app').classList.add('hidden');
    closeDetail();
    post('nx:close');
});

document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return;
    if (!$('detail').classList.contains('hidden')) {
        closeDetail();
        return;
    }
    $('app').classList.add('hidden');
    post('nx:close');
});
