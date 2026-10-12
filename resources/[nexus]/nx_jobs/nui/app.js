/* ==========================================================================
   Nexus Framework :: employment office
   ========================================================================== */

const $ = (id) => document.getElementById(id);
const RESOURCE = 'nx_jobs';

let data = null;

const post = (event, payload = {}) =>
    fetch(`https://${RESOURCE}/${event}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload),
    }).catch(() => {});

const money = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');

function render() {
    if (!data) return;

    const current = $('current');
    current.innerHTML = '';
    const title = document.createElement('b');
    title.textContent = data.job.label;
    const grade = document.createElement('span');
    grade.textContent = data.job.gradeName || '';
    current.append(title, grade);

    if (data.duty) {
        const duty = document.createElement('span');
        duty.className = 'duty';
        duty.textContent = 'On duty';
        current.appendChild(duty);
    }

    const grid = $('jobs');
    grid.innerHTML = '';

    (data.jobs || []).forEach((job) => {
        const card = document.createElement('div');
        card.className = 'job' + (job.current ? ' current' : '');

        const top = document.createElement('div');
        top.className = 'job-top';
        const name = document.createElement('div');
        name.className = 'job-name';
        name.textContent = job.label;
        const pay = document.createElement('div');
        pay.className = 'job-pay';
        pay.textContent = `${money(job.salary)} / payday`;
        top.append(name, pay);

        const desc = document.createElement('div');
        desc.className = 'job-desc';
        desc.textContent = job.description || 'No description provided.';

        const meta = document.createElement('div');
        meta.className = 'job-meta';
        const grades = document.createElement('span');
        grades.textContent = `${job.grades} rank${job.grades === 1 ? '' : 's'}`;
        meta.appendChild(grades);

        card.append(top, desc, meta);

        if (job.current) {
            const badge = document.createElement('span');
            badge.className = 'job-badge';
            badge.textContent = 'Current job';
            card.appendChild(badge);
        } else {
            card.addEventListener('click', () => {
                post('nx:take', { job: job.name });
                $('app').classList.add('hidden');
                post('nx:close');
            });
        }

        grid.appendChild(card);
    });
}

$('btn-close').addEventListener('click', () => {
    $('app').classList.add('hidden');
    post('nx:close');
});

$('btn-refresh').addEventListener('click', () => post('nx:refresh'));

$('btn-quit').addEventListener('click', () => {
    if (!window.confirm('Resign from your current job?')) return;
    post('nx:quit');
    $('app').classList.add('hidden');
    post('nx:close');
});

window.addEventListener('message', (event) => {
    const payload = event.data || {};

    switch (payload.action) {
        case 'open':
        case 'update':
            if (!payload.data || !payload.data.jobs) break;
            data = payload.data;
            render();
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
    post('nx:close');
});
