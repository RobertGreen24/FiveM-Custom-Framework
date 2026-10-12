/* ==========================================================================
   Nexus Framework :: HUD
   Pure renderer: the Lua side pushes a payload, we paint it. Values are only
   touched in the DOM when they actually change so the HUD never flickers.
   ========================================================================== */

const $ = (id) => document.getElementById(id);

const RING_LENGTH = 170;      // 2 * PI * r(27)
const prev = {};

const formatMoney = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');

/* ------------------------------ helpers ------------------------------ */

function setText(el, value, key) {
    const text = String(value === undefined || value === null ? '' : value);
    if (el.textContent === text) return;
    el.textContent = text;
    if (key && prev[key] !== undefined && prev[key] !== text) {
        el.classList.remove('bump');
        void el.offsetWidth;
        el.classList.add('bump');
    }
    if (key) prev[key] = text;
}

function setRing(id, percent) {
    const ring = $(id);
    if (!ring) return;
    const clamped = Math.max(0, Math.min(100, Number(percent) || 0));
    ring.style.strokeDashoffset = String(RING_LENGTH * (1 - clamped / 100));
}

function setColour(id, hex) {
    const ring = $(id);
    if (ring && hex) ring.style.stroke = hex;
}

function toggle(el, show) {
    if (el) el.classList.toggle('hidden', !show);
}

const COLOURS = {
    healthLow: '#ef4444',
    healthMid: '#f59e0b',
    healthHigh: '#22c55e',
    armour: '#3b82f6',
    hunger: '#f59e0b',
    thirst: '#22d3ee',
    stress: '#a855f7',
};

/* ------------------------------ main render ------------------------------ */

function render(data) {
    toggle($('hud'), false);

    if (!data.visible) {
        $('hud').classList.add('hidden');
        return;
    }
    $('hud').classList.remove('hidden');

    /* --- vitals --- */
    if (data.vitals) {
        const { health, armour, hunger, thirst, stress } = data.vitals;

        setRing('ring-health', health);
        const colour = health > 60 ? COLOURS.healthHigh : health > 30 ? COLOURS.healthMid : COLOURS.healthLow;
        setColour('ring-health', colour);
        setText($('val-health'), Math.round(health));

        const healthRing = document.querySelector('[data-stat="health"]');
        healthRing.classList.toggle('pulse', health <= 25);

        setRing('ring-armour', armour);
        setRing('ring-hunger', hunger);
        setRing('ring-thirst', thirst);

        const stressWrap = $('ring-stress-wrap');
        stressWrap.classList.toggle('hidden', stress < 8);
        setRing('ring-stress', stress);
    }

    /* --- money --- */
    if (data.money) {
        const cash = $('money-cash');
        const bank = $('money-bank');
        const black = $('money-black');

        const cashText = formatMoney(data.money.cash);
        if (cash.textContent !== cashText) {
            const rose = Number(data.money.cash) > Number(prev.cashRaw || 0);
            cash.textContent = cashText;
            cash.classList.remove('gain', 'loss', 'bump');
            void cash.offsetWidth;
            cash.classList.add('bump');
            if (prev.cashRaw !== undefined) cash.classList.add(rose ? 'gain' : 'loss');
            setTimeout(() => cash.classList.remove('gain', 'loss'), 900);
        }
        prev.cashRaw = data.money.cash;

        setText(bank, formatMoney(data.money.bank));
        toggle($('money-black-row'), Number(data.money.black) > 0);
        setText(black, formatMoney(data.money.black));
    }

    /* --- job --- */
    if (data.job) {
        setText($('job-label'), data.job.label || 'Unemployed');
        setText($('job-grade'), data.job.grade || 'Civilian');
        $('duty-pulse').classList.toggle('on', data.job.onDuty === true);

        const gang = $('job-gang');
        toggle(gang, !!data.job.gang && data.job.gang !== 'No Affiliation' && data.job.gang !== 'none');
        setText(gang, data.job.gang);
    }

    /* --- vehicle --- */
    const vehicle = $('vehicle');
    if (data.vehicle) {
        vehicle.classList.remove('hidden');
        setText($('vehicle-speed'), Math.round(data.vehicle.speed));
        setText($('vehicle-unit'), data.vehicle.unit);
        setText($('fuel-value'), `${data.vehicle.fuel}%`);
        $('fuel-bar').style.width = `${Math.max(0, Math.min(100, data.vehicle.fuel))}%`;
        setText($('body-value'), `${data.vehicle.body}%`);
        $('body-bar').style.width = `${Math.max(0, Math.min(100, data.vehicle.body))}%`;

        const gear = data.vehicle.gear === 0 ? 'R' : String(data.vehicle.gear);
        setText($('tag-gear'), data.vehicle.rpm > 92 ? 'LIMIT' : gear);
        setText($('tag-plate'), data.vehicle.plate || '—');

        toggle($('tag-seatbelt'), data.vehicle.seatbelt === true);
        toggle($('tag-cruise'), data.vehicle.cruise === true);
        toggle($('tag-locked'), data.vehicle.locked === true);
    } else {
        vehicle.classList.add('hidden');
    }

    /* --- ammo --- */
    const ammoBox = $('ammo');
    if (data.ammo) {
        ammoBox.classList.remove('hidden');
        setText($('ammo-clip'), data.ammo.clip);
        setText($('ammo-total'), data.ammo.ammo);
        ammoBox.classList.toggle('low', Number(data.ammo.clip) <= 3);
    } else {
        ammoBox.classList.add('hidden');
    }

    /* --- location --- */
    if (data.location) {
        setText($('street-name'), data.location.street || '—');
        setText($('street-zone'), data.location.zone || '');
    }

    /* --- voice --- */
    if (data.voice) {
        const box = $('voice');
        box.classList.toggle('active', data.voice.talking === true);
        for (let level = 1; level <= 4; level += 1) {
            box.classList.toggle(`level-${level}`, Number(data.voice.level) === level);
        }
        const ranges = { 1: 'Whisper', 2: 'Normal', 3: 'Shout', 4: 'Radio' };
        setText($('voice-label'), data.voice.radio ? `Radio ${data.voice.radio}` : (ranges[Number(data.voice.level)] || 'Normal'));
    }

    /* --- server info --- */
    if (data.players !== undefined) setText($('server-players'), data.players);
    if (data.serverName) setText($('server-name'), data.serverName);

    /* --- downed --- */
    $('downed').classList.toggle('hidden', data.downed !== true);
}

/* ------------------------------ bridge ------------------------------ */

window.addEventListener('message', (event) => {
    const payload = event.data || {};

    switch (payload.action) {
        case 'update':
            render(payload.data || {});
            break;

        case 'toggle':
            if (payload.data && payload.data.visible === false) {
                $('hud').classList.add('hidden');
            } else {
                $('hud').classList.remove('hidden');
            }
            break;

        default:
            break;
    }
});
