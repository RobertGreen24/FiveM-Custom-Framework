/* ==========================================================================
   Nexus Framework :: shared UI kit (vanilla JS, no build step)
   Handles: toasts, progress, text UI, input forms, confirms, context menus.
   ========================================================================== */

const RESOURCE = 'nx_core';
const MAX_TOASTS = 5;

const ICONS = {
    info: '◆',
    success: '✓',
    warning: '!',
    error: '✕',
    police: '★',
    ems: '✚',
    money: '$',
};

const $ = (id) => document.getElementById(id);

/** Talk back to the Lua side. */
function respond(id, value) {
    fetch(`https://${RESOURCE}/nx:response`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify({ id, value }),
    }).catch(() => {});
}

/* ============================== notifications ============================== */

function createToast(data) {
    const container = $('notifications');

    const toast = document.createElement('div');
    toast.className = `toast ${data.type || 'info'}`;

    const icon = document.createElement('div');
    icon.className = 'toast-icon';
    icon.textContent = data.icon || ICONS[data.type] || ICONS.info;

    const content = document.createElement('div');
    content.className = 'toast-content';

    if (data.title) {
        const title = document.createElement('div');
        title.className = 'toast-title';
        title.textContent = data.title;
        content.appendChild(title);
    }

    const message = document.createElement('div');
    message.className = 'toast-message';
    message.textContent = data.message || '';
    content.appendChild(message);

    const timer = document.createElement('div');
    timer.className = 'toast-timer';
    const duration = Math.max(1200, Number(data.duration) || 5000);
    timer.style.animationDuration = `${duration}ms`;

    toast.appendChild(icon);
    toast.appendChild(content);
    toast.appendChild(timer);

    container.appendChild(toast);

    // cap the stack
    while (container.children.length > MAX_TOASTS) {
        container.removeChild(container.firstChild);
    }

    const remove = () => {
        if (!toast.parentNode) return;
        toast.classList.add('out');
        setTimeout(() => toast.remove(), 200);
    };

    setTimeout(remove, duration);
    toast.addEventListener('click', remove);

    return toast;
}

/* ============================== progress ============================== */

const RING_LENGTH = 264;
let progressTimer = null;

function startProgress(data) {
    const wrap = $('progress');
    const fill = $('progress-ring-fill');
    const bar = $('progress-bar-fill');
    const label = $('progress-label');
    const icon = $('progress-icon');
    const hint = $('progress-hint');

    label.textContent = data.label || 'Working';
    icon.textContent = data.icon || '◆';
    hint.textContent = data.hint || 'Hold on…';
    if (data.colour) {
        fill.style.stroke = data.colour;
        bar.style.background = data.colour;
    }
    wrap.classList.remove('hidden');

    const duration = Math.max(250, Number(data.duration) || 3000);
    const started = performance.now();

    clearInterval(progressTimer);
    progressTimer = setInterval(() => {
        const elapsed = performance.now() - started;
        const pct = Math.min(1, elapsed / duration);
        fill.style.strokeDashoffset = String(RING_LENGTH * (1 - pct));
        bar.style.width = `${pct * 100}%`;
        if (pct >= 1) clearInterval(progressTimer);
    }, 60);
}

function endProgress() {
    clearInterval(progressTimer);
    $('progress').classList.add('hidden');
    $('progress-ring-fill').style.strokeDashoffset = String(RING_LENGTH);
    $('progress-bar-fill').style.width = '0%';
}

/* ============================== text UI ============================== */

function setTextUI(data) {
    const el = $('textui');
    if (!data.show) {
        el.classList.add('hidden');
        return;
    }
    $('textui-key').textContent = data.key || 'E';
    $('textui-label').textContent = data.label || 'Interact';
    el.classList.remove('hidden');
}

/* ============================== modal layer ============================== */

let activeInputId = null;
let activeConfirmId = null;
let activeMenuId = null;

const modalLayer = () => $('modal-layer');

function showModal(panelId) {
    modalLayer().classList.remove('hidden');
    ['input-panel', 'confirm-panel', 'menu-panel'].forEach((id) => {
        $(id).classList.toggle('hidden', id !== panelId);
    });
}

function hideModals() {
    modalLayer().classList.add('hidden');
    ['input-panel', 'confirm-panel', 'menu-panel'].forEach((id) => $(id).classList.add('hidden'));
    activeInputId = null;
    activeConfirmId = null;
    activeMenuId = null;
}

/* -------- input -------- */

function openInput(data) {
    activeInputId = data.id;
    $('input-title').textContent = data.title || 'Input';
    $('input-desc').textContent = data.description || '';
    $('input-desc').style.display = data.description ? 'block' : 'none';
    $('input-submit').textContent = data.submitLabel || 'Confirm';

    const container = $('input-fields');
    container.innerHTML = '';

    (data.fields || []).forEach((field, index) => {
        const wrapper = document.createElement('div');
        wrapper.className = 'field';

        const label = document.createElement('label');
        label.setAttribute('for', `field-${index}`);
        label.textContent = field.label || field.name;
        wrapper.appendChild(label);

        let input;
        if (field.type === 'select' && Array.isArray(field.options)) {
            input = document.createElement('select');
            field.options.forEach((opt) => {
                const option = document.createElement('option');
                option.value = opt.value !== undefined ? opt.value : opt;
                option.textContent = opt.label !== undefined ? opt.label : opt;
                input.appendChild(option);
            });
        } else if (field.type === 'textarea') {
            input = document.createElement('textarea');
        } else {
            input = document.createElement('input');
            input.type = field.type || 'text';
        }

        input.id = `field-${index}`;
        input.dataset.name = field.name;
        if (field.placeholder) input.placeholder = field.placeholder;
        if (field.value !== undefined && field.value !== null) input.value = field.value;
        if (field.min !== undefined) input.min = field.min;
        if (field.max !== undefined) input.max = field.max;
        if (field.maxLength) input.maxLength = field.maxLength;

        wrapper.appendChild(input);
        container.appendChild(wrapper);
    });

    showModal('input-panel');
    const first = container.querySelector('input, select, textarea');
    if (first) setTimeout(() => first.focus(), 60);
}

function submitInput() {
    if (!activeInputId) return;
    const values = {};
    $('input-fields').querySelectorAll('[data-name]').forEach((el) => {
        values[el.dataset.name] = el.value;
    });
    const id = activeInputId;
    hideModals();
    respond(id, values);
}

/* -------- confirm -------- */

function openConfirm(data) {
    activeConfirmId = data.id;
    $('confirm-title').textContent = data.title || 'Are you sure?';
    $('confirm-message').textContent = data.message || '';
    $('confirm-ok').textContent = data.confirmLabel || 'Confirm';
    $('confirm-cancel').textContent = data.cancelLabel || 'Cancel';
    $('confirm-ok').className = data.danger ? 'btn danger' : 'btn primary';
    showModal('confirm-panel');
}

function answerConfirm(value) {
    if (!activeConfirmId) return;
    const id = activeConfirmId;
    hideModals();
    respond(id, value);
}

/* -------- menu -------- */

let menuIndex = 0;

function openMenu(data) {
    activeMenuId = data.id;
    menuIndex = 0;
    window.__nxMenuOptions = data.options || [];
    $('menu-title').textContent = data.title || 'Menu';
    $('menu-subtitle').textContent = data.subtitle || '';
    $('menu-subtitle').style.display = data.subtitle ? 'block' : 'none';

    const container = $('menu-options');
    container.innerHTML = '';

    (data.options || []).forEach((opt, index) => {
        const row = document.createElement('div');
        row.className = 'menu-option' + (opt.disabled ? ' disabled' : '') + (index === 0 ? ' selected' : '');

        if (opt.icon) {
            const icon = document.createElement('div');
            icon.className = 'opt-icon';
            icon.textContent = opt.icon;
            row.appendChild(icon);
        }

        const text = document.createElement('div');
        text.className = 'opt-text';

        const label = document.createElement('div');
        label.className = 'opt-label';
        label.textContent = opt.label || '';
        text.appendChild(label);

        if (opt.description) {
            const desc = document.createElement('div');
            desc.className = 'opt-desc';
            desc.textContent = opt.description;
            text.appendChild(desc);
        }

        row.appendChild(text);

        if (!opt.disabled) {
            row.addEventListener('click', () => chooseMenu(index, opt));
        }

        container.appendChild(row);
    });

    showModal('menu-panel');
}

function chooseMenu(index, opt) {
    if (!activeMenuId || !opt || opt.disabled) return;
    const id = activeMenuId;
    hideModals();
    respond(id, opt.value !== undefined ? opt.value : index);
}

function updateMenuSelection(delta) {
    const rows = Array.from($('menu-options').children);
    if (!rows.length) return;
    let next = menuIndex;
    for (let step = 0; step < rows.length; step += 1) {
        next = (next + delta + rows.length) % rows.length;
        if (!rows[next].classList.contains('disabled')) break;
    }
    rows[menuIndex].classList.remove('selected');
    menuIndex = next;
    rows[menuIndex].classList.add('selected');
    rows[menuIndex].scrollIntoView({ block: 'nearest' });
}

/* ============================== message bus ============================== */

window.addEventListener('message', (event) => {
    const payload = event.data || {};
    const data = payload.data || {};

    switch (payload.action) {
        case 'notify':
            createToast(data);
            break;

        case 'progress':
            startProgress(data);
            break;

        case 'progressEnd':
            endProgress();
            break;

        case 'textui':
            setTextUI(data);
            break;

        case 'input':
            openInput(data);
            break;

        case 'confirm':
            openConfirm(data);
            break;

        case 'menu':
            openMenu(data);
            break;

        case 'closeAll':
            hideModals();
            $('notifications').innerHTML = '';
            endProgress();
            setTextUI({ show: false });
            break;

        default:
            break;
    }
});

/* ============================== keyboard ============================== */

document.addEventListener('keydown', (event) => {
    const modalOpen = !modalLayer().classList.contains('hidden');

    if (event.key === 'Escape') {
        if (activeInputId) { const id = activeInputId; hideModals(); respond(id, null); }
        else if (activeConfirmId) answerConfirm(false);
        else if (activeMenuId) { const id = activeMenuId; hideModals(); respond(id, null); }
        return;
    }

    if (!modalOpen) return;

    if (activeInputId && event.key === 'Enter' && event.target.tagName !== 'TEXTAREA') {
        event.preventDefault();
        submitInput();
        return;
    }

    if (activeMenuId) {
        if (event.key === 'ArrowDown') { event.preventDefault(); updateMenuSelection(1); }
        else if (event.key === 'ArrowUp') { event.preventDefault(); updateMenuSelection(-1); }
        else if (event.key === 'Enter') {
            event.preventDefault();
            const opt = (window.__nxMenuOptions || [])[menuIndex];
            if (opt) chooseMenu(menuIndex, opt);
        }
    }
});

/* buttons */
$('input-submit').addEventListener('click', submitInput);
$('input-cancel').addEventListener('click', () => {
    const id = activeInputId;
    hideModals();
    respond(id, null);
});
$('confirm-ok').addEventListener('click', () => answerConfirm(true));
$('confirm-cancel').addEventListener('click', () => answerConfirm(false));
