/* ==========================================================================
   Nexus Framework :: inventory grid
   Two panels (self + container), drag & drop, right-click actions, hotbar.
   The Lua side is authoritative: this file only ever *requests* changes.
   ========================================================================== */

const $ = (id) => document.getElementById(id);
const RESOURCE = 'nx_inventory';

const ICONS = {
    weapon: '🔫',
    ammo: '📦',
    food: '🍔',
    drink: '🥤',
    medical: '💊',
    tool: '🔧',
    clothing: '👕',
    key: '🔑',
    money: '💵',
    misc: '📦',
    item: '◆',
};

const state = {
    self: null,
    other: null,
    money: { cash: 0, bank: 0, black: 0 },
    hotbar: 5,
    context: null,      // { owner, slot, item }
    drag: null,         // { owner, slot, item, offsetX, offsetY }
};

const post = (event, payload = {}) =>
    fetch(`https://${RESOURCE}/${event}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload),
    }).then((res) => res.json()).catch(() => ({}));

const money = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');
const kg = (grams) => (Math.round((Number(grams) || 0) / 100) / 10).toFixed(1) + ' kg';

/* ============================== rendering ============================== */

function iconFor(item) {
    if (item.name && item.name.startsWith('weapon_')) return ICONS.weapon;
    return ICONS[item.type] || ICONS.item;
}

function buildSlot(container, slotNumber) {
    const item = (container.items || []).find((entry) => Number(entry.slot) === slotNumber);

    const slot = document.createElement('div');
    slot.className = 'slot' + (item ? '' : ' empty');
    slot.dataset.owner = container.owner;
    slot.dataset.slot = slotNumber;

    if (container.hotbarFrom && slotNumber >= container.hotbarFrom && slotNumber < container.hotbarFrom + state.hotbar) {
        slot.classList.add('hotbar');
        slot.dataset.hotkey = String(slotNumber - container.hotbarFrom + 1);
    }

    if (!item) {
        slot.addEventListener('dragover', (event) => event.preventDefault());
        return slot;
    }

    slot.dataset.rarity = item.rarity || 'common';

    const icon = document.createElement('div');
    icon.className = 'slot-icon';
    icon.textContent = iconFor(item);

    const name = document.createElement('div');
    name.className = 'slot-name';
    name.textContent = item.label || item.name;

    slot.appendChild(icon);
    slot.appendChild(name);

    if (item.amount > 1) {
        const amount = document.createElement('div');
        amount.className = 'slot-amount';
        amount.textContent = item.amount;
        slot.appendChild(amount);
    }

    // durability / battery strip from metadata
    const meta = item.metadata || {};
    if (typeof meta.durability === 'number') {
        const bar = document.createElement('div');
        bar.className = 'slot-meta';
        const fill = document.createElement('span');
        const pct = Math.max(0, Math.min(100, meta.durability));
        fill.style.width = `${pct}%`;
        fill.style.background = pct > 50 ? '#22c55e' : pct > 20 ? '#f59e0b' : '#ef4444';
        bar.appendChild(fill);
        slot.appendChild(bar);
    } else if (typeof meta.battery === 'number') {
        const bar = document.createElement('div');
        bar.className = 'slot-meta';
        const fill = document.createElement('span');
        fill.style.width = `${Math.max(0, Math.min(100, meta.battery))}%`;
        fill.style.background = '#22d3ee';
        bar.appendChild(fill);
        slot.appendChild(bar);
    }

    /* ---------------- interactions ---------------- */

    slot.addEventListener('mousedown', (event) => {
        if (event.button !== 0) return;
        event.preventDefault();
        startDrag(container, item, event);
    });

    slot.addEventListener('contextmenu', (event) => {
        event.preventDefault();
        openContext(container, item, event.clientX, event.clientY);
    });

    slot.addEventListener('dblclick', () => {
        post('nx:use', { owner: container.owner, slot: item.slot });
    });

    slot.addEventListener('mouseenter', (event) => showTooltip(item, event));
    slot.addEventListener('mousemove', (event) => moveTooltip(event));
    slot.addEventListener('mouseleave', hideTooltip);

    return slot;
}

function renderContainer(kind) {
    const container = kind === 'self' ? state.self : state.other;
    const panel = kind === 'self' ? $('panel-self') : $('panel-other');
    const grid = kind === 'self' ? $('grid-self') : $('grid-other');

    if (!container) {
        panel.classList.add('hidden');
        return;
    }
    panel.classList.remove('hidden');

    $(`${kind}-label`).textContent = container.label || (kind === 'self' ? 'Inventory' : 'Container');

    const used = (container.items || []).length;
    $(`${kind}-slots`).textContent = `${used}/${container.slots}`;

    const pct = container.maxWeight > 0 ? (container.weight / container.maxWeight) * 100 : 0;
    const bar = $(`${kind}-weight-bar`);
    bar.style.width = `${Math.min(100, pct)}%`;
    bar.classList.toggle('heavy', pct > 85);
    $(`${kind}-weight`).textContent = `${kg(container.weight)} / ${kg(container.maxWeight)}`;

    grid.innerHTML = '';
    const hotbarFrom = kind === 'self' ? 1 : null;
    const view = Object.assign({}, container, { hotbarFrom });
    for (let slot = 1; slot <= container.slots; slot += 1) {
        grid.appendChild(buildSlot(view, slot));
    }
}

function renderMoney() {
    $('money-cash').textContent = money(state.money.cash);
    $('money-bank').textContent = money(state.money.bank);
    $('money-dirty').textContent = money(state.money.black);
    $('money-dirty-wrap').classList.toggle('hidden', !(Number(state.money.black) > 0));
}

function render(payload) {
    state.self = payload.self;
    state.other = payload.other;
    state.money = payload.money || state.money;
    state.hotbar = payload.hotbar || state.hotbar;

    renderMoney();
    renderContainer('self');
    renderContainer('other');

    $('app').classList.remove('hidden');
}

/* ============================== drag & drop ============================== */

function startDrag(container, item, event) {
    state.drag = { owner: container.owner, slot: item.slot, item };

    const ghost = $('drag-ghost');
    ghost.textContent = iconFor(item);
    ghost.classList.remove('hidden');
    moveGhost(event);

    document.addEventListener('mousemove', onDragMove);
    document.addEventListener('mouseup', onDragEnd);
}

function moveGhost(event) {
    const ghost = $('drag-ghost');
    if (ghost.classList.contains('hidden')) return;
    ghost.style.left = `${event.clientX - 27}px`;
    ghost.style.top = `${event.clientY - 27}px`;
}

function onDragMove(event) {
    moveGhost(event);

    document.querySelectorAll('.slot.drag-over').forEach((el) => el.classList.remove('drag-over'));
    const el = document.elementFromPoint(event.clientX, event.clientY);
    const slot = el && el.closest ? el.closest('.slot') : null;
    if (slot && slot.dataset.owner) slot.classList.add('drag-over');
}

function onDragEnd(event) {
    document.removeEventListener('mousemove', onDragMove);
    document.removeEventListener('mouseup', onDragEnd);

    const el = document.elementFromPoint(event.clientX, event.clientY);
    const slot = el && el.closest ? el.closest('.slot') : null;

    if (slot && slot.dataset.owner && state.drag) {
        finishDrag(
            { owner: slot.dataset.owner },
            Number(slot.dataset.slot),
            event.shiftKey
        );
    } else {
        cancelDrag();
    }
}

function finishDrag(targetContainer, targetSlot, split) {
    const drag = state.drag;
    cancelDrag();
    if (!drag) return;

    if (drag.owner === targetContainer.owner && drag.slot === targetSlot) return;

    if (split) {
        post('nx:split', { owner: drag.owner, slot: drag.slot, amount: Math.max(1, Math.floor(drag.item.amount / 2)) });
        return;
    }

    post('nx:move', {
        from: drag.owner,
        fromSlot: drag.slot,
        to: targetContainer.owner,
        toSlot: targetSlot,
        amount: drag.item.amount,
    });
}

function cancelDrag() {
    state.drag = null;
    $('drag-ghost').classList.add('hidden');
    document.querySelectorAll('.slot.drag-over').forEach((el) => el.classList.remove('drag-over'));
}

/* ============================== context menu ============================== */

function openContext(container, item, x, y) {
    state.context = { owner: container.owner, slot: item.slot, item };

    const menu = $('context');
    menu.classList.remove('hidden');

    const isSelf = state.self && container.owner === state.self.owner;
    menu.querySelector('[data-action="give"]').classList.toggle('disabled', !isSelf);
    menu.querySelector('[data-action="use"]').classList.toggle('disabled', !item.usable && item.type !== 'weapon');
    menu.querySelector('[data-action="split"]').classList.toggle('disabled', !(item.amount > 1));
    menu.querySelector('[data-action="drop"]').classList.toggle('disabled', !isSelf);
    menu.querySelector('[data-action="dropAll"]').classList.toggle('disabled', !isSelf || !(item.amount > 1));

    // keep the menu on screen
    const width = 180;
    const height = 210;
    menu.style.left = `${Math.min(x, window.innerWidth - width - 8)}px`;
    menu.style.top = `${Math.min(y, window.innerHeight - height - 8)}px`;

    hideTooltip();
}

function closeContext() {
    state.context = null;
    $('context').classList.add('hidden');
}

$('context').addEventListener('click', (event) => {
    const option = event.target.closest('.context-item');
    if (!option || !state.context) return;
    const action = option.dataset.action;
    const { owner, slot, item } = state.context;
    closeContext();

    switch (action) {
        case 'use':
            post('nx:use', { owner, slot });
            break;
        case 'give':
            openGiveModal(item);
            break;
        case 'split':
            post('nx:split', { owner, slot, amount: Math.max(1, Math.floor(item.amount / 2)) });
            break;
        case 'drop':
            post('nx:drop', { owner, slot, amount: item.amount });
            break;
        case 'dropAll':
            post('nx:drop', { owner, slot, amount: item.amount });
            break;
        default:
            break;
    }
});

/* ============================== give modal ============================== */

function openGiveModal(item) {
    state.giveItem = item;
    $('give-subtitle').textContent = `Give ${item.label}${item.amount > 1 ? ` x${item.amount}` : ''} to...`;

    post('nx:giveList').then((result) => {
        const list = $('give-players');
        list.innerHTML = '';

        const players = (result && result.players) || [];
        if (!players.length) {
            const empty = document.createElement('p');
            empty.className = 'muted';
            empty.textContent = 'Nobody is close enough.';
            list.appendChild(empty);
        }

        players.forEach((player) => {
            const row = document.createElement('div');
            row.className = 'player-option';
            row.innerHTML = `<span></span><span class="muted"></span>`;
            row.children[0].textContent = `${player.name} (${player.stateId})`;
            row.children[1].textContent = `${player.distance.toFixed(1)}m`;
            row.addEventListener('click', () => {
                post('nx:give', { slot: item.slot, amount: item.amount, target: player.source });
                $('give-modal').classList.add('hidden');
            });
            list.appendChild(row);
        });

        $('give-modal').classList.remove('hidden');
    });
}

$('give-cancel').addEventListener('click', () => $('give-modal').classList.add('hidden'));

/* ============================== tooltip ============================== */

function showTooltip(item, event) {
    const tooltip = $('tooltip');
    $('tt-title').textContent = item.label || item.name;
    $('tt-desc').textContent = item.description || '';

    const meta = $('tt-meta');
    meta.innerHTML = '';
    const rows = [];

    if (typeof item.metadata?.durability === 'number') rows.push(['Durability', `${Math.round(item.metadata.durability)}%`]);
    if (item.metadata?.ammo !== undefined) rows.push(['Ammo', item.metadata.ammo]);
    if (item.metadata?.serial) rows.push(['Serial', item.metadata.serial]);
    if (item.metadata?.registered) rows.push(['Registered', 'Yes']);
    rows.push(['Weight', `${(item.weight / 1000).toFixed(2)} kg`]);
    rows.push(['Type', item.type]);

    rows.forEach(([label, value]) => {
        const line = document.createElement('div');
        line.innerHTML = `${label}: <b></b>`;
        line.querySelector('b').textContent = value;
        meta.appendChild(line);
    });

    tooltip.classList.remove('hidden');
    moveTooltip(event);
}

function moveTooltip(event) {
    const tooltip = $('tooltip');
    if (tooltip.classList.contains('hidden')) return;
    const x = Math.min(event.clientX + 16, window.innerWidth - 270);
    const y = Math.min(event.clientY + 14, window.innerHeight - 150);
    tooltip.style.left = `${x}px`;
    tooltip.style.top = `${y}px`;
}

function hideTooltip() {
    $('tooltip').classList.add('hidden');
}

/* ============================== buttons ============================== */

$('btn-pickup-all').addEventListener('click', () => {
    if (!state.other) return;
    const owner = state.other.owner;
    if (!owner.startsWith('drop:')) return;
    post('nx:pickup', { dropId: owner.slice(5) });
});

/* ============================== bridge ============================== */

window.addEventListener('message', (event) => {
    const payload = event.data || {};

    switch (payload.action) {
        case 'open':
            if (payload.data) render(payload.data);
            break;
        case 'update':
            if (payload.data) render(payload.data);
            break;
        case 'close':
            $('app').classList.add('hidden');
            closeContext();
            hideTooltip();
            $('give-modal').classList.add('hidden');
            break;
        default:
            break;
    }
});

document.addEventListener('mousedown', (event) => {
    if (!event.target.closest('.context')) closeContext();
});

document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
        closeContext();
        hideTooltip();
        $('give-modal').classList.add('hidden');
        post('nx:close', {});
    }
});
