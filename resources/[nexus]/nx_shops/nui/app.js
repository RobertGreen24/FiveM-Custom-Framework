/* ==========================================================================
   Nexus Framework :: shops
   ========================================================================== */

const $ = (id) => document.getElementById(id);
const RESOURCE = 'nx_shops';

const state = {
    data: null,
    basket: new Map(),   // item name -> amount
    payment: 'cash',
    search: '',
};

const post = (event, payload = {}) =>
    fetch(`https://${RESOURCE}/${event}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload),
    }).catch(() => {});

const money = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');

/* ------------------------------ catalogue ------------------------------ */

function renderItems() {
    const grid = $('items');
    grid.innerHTML = '';

    const data = state.data;
    const sellMode = data.mode === 'sell';
    const term = state.search.toLowerCase();

    const items = (data.items || []).filter(
        (item) => !term || (item.label || '').toLowerCase().includes(term)
    );

    if (!items.length) {
        grid.innerHTML = '<p class="hint">Nothing here.</p>';
        return;
    }

    items.forEach((item) => {
        const row = document.createElement('div');
        row.className = 'item' + (item.illegal ? ' illegal' : '');

        const icon = document.createElement('div');
        icon.className = 'item-icon';
        icon.textContent = sellMode ? '\u{1F4B0}' : '\u{1F6D2}';

        const body = document.createElement('div');
        body.className = 'item-body';
        const name = document.createElement('div');
        name.className = 'item-name';
        name.textContent = item.label + (sellMode ? ` (${item.count})` : '');
        const meta = document.createElement('div');
        meta.className = 'item-meta';
        meta.textContent = sellMode
            ? 'Sell price'
            : [item.type, item.weight ? `${item.weight} kg` : '', item.illegal ? 'illicit' : '']
                  .filter(Boolean).join(' · ');
        body.append(name, meta);

        const price = document.createElement('div');
        price.className = 'item-price';
        price.textContent = money(item.price);

        row.append(icon, body, price);
        row.addEventListener('click', () => (sellMode ? sellItem(item) : addToBasket(item)));
        grid.appendChild(row);
    });
}

/* ------------------------------ basket ------------------------------ */

function addToBasket(item) {
    const current = state.basket.get(item.name) || 0;
    const limit = state.data.max || 50;
    state.basket.set(item.name, Math.min(current + 1, limit));
    renderBasket();
}

function changeQuantity(name, delta) {
    const next = (state.basket.get(name) || 0) + delta;
    if (next <= 0) state.basket.delete(name);
    else state.basket.set(name, Math.min(next, state.data.max || 50));
    renderBasket();
}

function basketTotal() {
    let total = 0;
    state.basket.forEach((amount, name) => {
        const item = (state.data.items || []).find((entry) => entry.name === name);
        if (item) total += item.price * amount;
    });
    return total;
}

function renderBasket() {
    const list = $('cart-items');
    list.innerHTML = '';

    if (!state.basket.size) {
        list.innerHTML = '<p class="hint">Your basket is empty.</p>';
    }

    state.basket.forEach((amount, name) => {
        const item = (state.data.items || []).find((entry) => entry.name === name) || { label: name, price: 0 };

        const row = document.createElement('div');
        row.className = 'cart-row';
        row.innerHTML = `
            <span class="name"></span>
            <div class="qty">
                <button data-delta="-1">−</button>
                <span>${amount}</span>
                <button data-delta="1">+</button>
            </div>
            <strong>${money(item.price * amount)}</strong>`;

        row.querySelector('.name').textContent = item.label;
        row.querySelectorAll('button').forEach((button) => {
            button.addEventListener('click', () => changeQuantity(name, Number(button.dataset.delta)));
        });
        list.appendChild(row);
    });

    $('cart-total').textContent = money(basketTotal());
    $('bal-cash').textContent = money(state.data.money.cash);
    $('bal-bank').textContent = money(state.data.money.bank);

    const total = basketTotal();
    const balance = state.payment === 'cash' ? state.data.money.cash : state.data.money.bank;
    const hint = $('cart-hint');

    if (state.data.shop && state.data.shop.requiresLicence && !state.data.licenceHeld) {
        hint.textContent = 'This shop requires a licence you do not hold.';
    } else if (total > balance) {
        hint.textContent = `Not enough ${state.payment}. Short by ${money(total - balance)}.`;
    } else {
        hint.textContent = '';
    }
}

/* ------------------------------ selling ------------------------------ */

function sellItem(item) {
    const raw = window.prompt(`How many ${item.label} do you want to sell?`, '1');
    if (raw === null) return;
    const amount = Math.max(1, Math.min(Number(raw) || 0, item.count));
    if (!amount) return;
    post('nx:sell', { item: item.name, amount });
}

/* ------------------------------ checkout ------------------------------ */

function checkout() {
    if (!state.data || state.data.mode === 'sell' || !state.basket.size) return;

    const entries = [...state.basket.entries()];
    entries.forEach(([name, amount]) => post('nx:buy', { item: name, amount, payment: state.payment }));

    state.basket.clear();
    $('app').classList.add('hidden');
    post('nx:close');
}

$('btn-checkout').addEventListener('click', checkout);

$('btn-close').addEventListener('click', () => {
    $('app').classList.add('hidden');
    state.basket.clear();
    post('nx:close');
});

$('search').addEventListener('input', (event) => {
    state.search = event.target.value;
    renderItems();
});

document.querySelectorAll('#payment-group .seg').forEach((seg) => {
    seg.addEventListener('click', () => {
        state.payment = seg.dataset.value;
        document.querySelectorAll('#payment-group .seg').forEach((other) => other.classList.remove('selected'));
        seg.classList.add('selected');
        renderBasket();
    });
});

/* ------------------------------ bridge ------------------------------ */

window.addEventListener('message', (event) => {
    const payload = event.data || {};
    const data = payload.data || {};

    switch (payload.action) {
        case 'open':
        case 'update':
            if (!data.mode) break;
            state.data = data;
            state.search = '';
            $('search').value = '';
            document.querySelector('.cart').classList.toggle('hidden', data.mode === 'sell');

            if (data.mode === 'sell') {
                $('shop-type').textContent = 'Sell point';
                $('shop-label').textContent = data.point.label;
                $('shop-hint').textContent = 'Click an item to sell it.';
            } else {
                $('shop-type').textContent = data.shop.type;
                $('shop-label').textContent = data.shop.label;
                $('shop-hint').textContent = data.shop.illegal
                    ? 'No receipts. No questions.'
                    : 'Prices include tax.';
            }

            renderItems();
            renderBasket();
            $('app').classList.remove('hidden');
            break;

        case 'close':
            $('app').classList.add('hidden');
            break;

        default:
            break;
    }
});

document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return;
    $('app').classList.add('hidden');
    state.basket.clear();
    post('nx:close');
});
