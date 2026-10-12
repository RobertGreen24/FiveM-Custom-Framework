/* ==========================================================================
   Nexus Framework :: banking
   ========================================================================== */

const $ = (id) => document.getElementById(id);
const RESOURCE = 'nx_banking';

const state = {
    money: { cash: 0, bank: 0, savings: 0 },
    config: {},
    transactions: [],
    depositAccount: 'bank',
    withdrawAccount: 'bank',
    transferAccount: 'bank',
};

const post = (event, payload = {}) =>
    fetch(`https://${RESOURCE}/${event}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload),
    }).catch(() => {});

const money = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');

/* ------------------------------ render ------------------------------ */

function renderBalances() {
    $('bal-cash').textContent = money(state.money.cash);
    $('bal-bank').textContent = money(state.money.bank);
    $('bal-savings').textContent = money(state.money.savings);

    $('deposit-hint').textContent = `Cash on hand: ${money(state.money.cash)}`;
    const fee = state.config.atmFee || 0;
    $('withdraw-hint').textContent = `${fee > 0 ? `ATM fee: ${money(fee)} · ` : ''}ATM limit ${money(state.config.atmMaxWithdraw || 0)}`;
    $('transfer-hint').textContent = `Fee: ${state.config.transferFee || 0}% · min ${money(state.config.minTransfer || 0)}`;
}

function renderHistory() {
    const list = $('history');
    list.innerHTML = '';

    if (!state.transactions.length) {
        list.innerHTML = '<p class="hint">No transactions yet.</p>';
        return;
    }

    state.transactions.forEach((tx) => {
        const row = document.createElement('div');
        row.className = 'tx';
        const amount = Number(tx.amount) || 0;

        row.innerHTML = `
            <div class="tx-left">
                <div class="tx-type"></div>
                <div class="tx-reason"></div>
            </div>
            <div class="tx-right">
                <div class="tx-amount ${amount >= 0 ? 'in' : 'out'}"></div>
                <div class="tx-date"></div>
            </div>`;

        row.querySelector('.tx-type').textContent = String(tx.type || 'transaction').replace(/_/g, ' ');
        row.querySelector('.tx-reason').textContent = tx.reason || '—';
        row.querySelector('.tx-amount').textContent = `${amount >= 0 ? '+' : '-'}${money(Math.abs(amount))}`;
        row.querySelector('.tx-date').textContent = String(tx.created_at || '').slice(0, 16);
        list.appendChild(row);
    });
}

function render() {
    renderBalances();
    renderHistory();

    if (state.finance) {
        $('finance-line').textContent = `Vehicle finance: ${money(state.finance.remaining)} outstanding · ${money(state.finance.payment)} weekly`;
    } else {
        $('finance-line').textContent = 'Nexus Bank · insured deposits';
    }
}

/* ------------------------------ views ------------------------------ */

function showView(name) {
    ['deposit', 'withdraw', 'transfer', 'history'].forEach((view) => {
        $(`view-${view}`).classList.toggle('hidden', view !== name);
    });
    document.querySelectorAll('.tab').forEach((tab) => {
        tab.classList.toggle('selected', tab.dataset.tab === name);
    });
}

document.querySelectorAll('.tab').forEach((tab) => {
    tab.addEventListener('click', () => showView(tab.dataset.tab));
});

/* ------------------------------ inputs ------------------------------ */

document.querySelectorAll('.quick').forEach((button) => {
    button.addEventListener('click', () => {
        const amount = button.dataset.value === 'all' ? 'all' : Number(button.dataset.value);
        const input = $(`${button.dataset.target}-amount`);

        if (amount === 'all') {
            if (button.dataset.target === 'deposit') {
                input.value = state.depositAccount === 'savings' ? state.money.cash : state.money.cash;
            } else {
                input.value = state.withdrawAccount === 'savings' ? state.money.savings : state.money.bank;
            }
        } else {
            input.value = Number(input.value || 0) + amount;
        }
    });
});

function wireSegmented(id, key) {
    document.querySelectorAll(`#${id} .seg`).forEach((seg) => {
        seg.addEventListener('click', () => {
            state[key] = seg.dataset.value;
            document.querySelectorAll(`#${id} .seg`).forEach((other) => other.classList.remove('selected'));
            seg.classList.add('selected');
        });
    });
}

wireSegmented('deposit-account', 'depositAccount');
wireSegmented('withdraw-account', 'withdrawAccount');
wireSegmented('transfer-account', 'transferAccount');

/* ------------------------------ actions ------------------------------ */

$('btn-deposit').addEventListener('click', () => {
    const amount = Number($('deposit-amount').value);
    if (!amount || amount <= 0) return;
    post('nx:deposit', { account: state.depositAccount, amount });
    $('deposit-amount').value = '';
});

$('btn-withdraw').addEventListener('click', () => {
    const amount = Number($('withdraw-amount').value);
    if (!amount || amount <= 0) return;
    post('nx:withdraw', { account: state.withdrawAccount, amount });
    $('withdraw-amount').value = '';
});

$('btn-transfer').addEventListener('click', () => {
    const target = $('transfer-target').value.trim();
    const amount = Number($('transfer-amount').value);
    const note = $('transfer-note').value.trim();
    if (!target || !amount || amount <= 0) return;
    post('nx:transfer', { account: state.transferAccount, target, amount, note });
    $('transfer-amount').value = '';
    $('transfer-note').value = '';
});

$('btn-refresh').addEventListener('click', () => post('nx:refresh'));

$('btn-close').addEventListener('click', () => {
    $('app').classList.add('hidden');
    post('nx:close');
});

/* ------------------------------ bridge ------------------------------ */

window.addEventListener('message', (event) => {
    const payload = event.data || {};
    const data = payload.data || {};

    switch (payload.action) {
        case 'open':
        case 'update':
            if (data.money) {
                state.money = data.money;
                state.config = data.config || {};
                state.transactions = data.transactions || [];
                state.finance = data.finance;
                render();
                $('app').classList.remove('hidden');
            }
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
        $('app').classList.add('hidden');
        post('nx:close');
    }
});
