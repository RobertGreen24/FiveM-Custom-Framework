/* ==========================================================================
   Nexus Framework :: appearance
   ========================================================================== */

const $ = (id) => document.getElementById(id);
const RESOURCE = 'nx_appearance';

const state = {
    data: null,
    view: 'identity',
    gender: 'male',
};

const post = (event, payload = {}) =>
    fetch(`https://${RESOURCE}/${event}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload),
    }).catch(() => {});

const el = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
};

/* ------------------------------ sliders ------------------------------ */

function slider({ label, value, min = -1, max = 1, step = 0.05, onInput, format }) {
    const wrap = el('div', 'slider');
    const head = el('label');
    const name = el('span', null, label);
    const readout = el('span', null, format ? format(value) : Number(value).toFixed(2));
    head.append(name, readout);

    const input = document.createElement('input');
    input.type = 'range';
    input.min = String(min);
    input.max = String(max);
    input.step = String(step);
    input.value = String(value);
    input.addEventListener('input', () => {
        const next = Number(input.value);
        readout.textContent = format ? format(next) : next.toFixed(2);
        onInput(next);
    });

    wrap.append(head, input);
    return wrap;
}

/* ------------------------------ views ------------------------------ */

function renderBlend() {
    const face = state.data.appearance.face || {};
    const host = $('blend');
    host.innerHTML = '';

    host.appendChild(slider({
        label: 'Father', value: face.shapeFirst ?? 0, min: 0, max: 45, step: 1,
        format: (value) => `#${value}`,
        onInput: (value) => post('nx:blend', { face: { shapeFirst: value } }),
    }));

    host.appendChild(slider({
        label: 'Mother', value: face.shapeSecond ?? 0, min: 0, max: 45, step: 1,
        format: (value) => `#${value}`,
        onInput: (value) => post('nx:blend', { face: { shapeSecond: value } }),
    }));

    host.appendChild(slider({
        label: 'Resemblance', value: face.shapeMix ?? 0.5, min: 0, max: 1,
        onInput: (value) => post('nx:blend', { face: { shapeMix: value } }),
    }));

    host.appendChild(slider({
        label: 'Skin father', value: face.skinFirst ?? 0, min: 0, max: 45, step: 1,
        format: (value) => `#${value}`,
        onInput: (value) => post('nx:blend', { face: { skinFirst: value } }),
    }));

    host.appendChild(slider({
        label: 'Skin mother', value: face.skinSecond ?? 0, min: 0, max: 45, step: 1,
        format: (value) => `#${value}`,
        onInput: (value) => post('nx:blend', { face: { skinSecond: value } }),
    }));

    host.appendChild(slider({
        label: 'Skin tone', value: face.skinMix ?? 0.5, min: 0, max: 1,
        onInput: (value) => post('nx:blend', { face: { skinMix: value } }),
    }));
}

function renderFeatures() {
    const face = state.data.appearance.face || {};
    const host = $('features');
    host.innerHTML = '';

    (state.data.features || []).forEach((feature) => {
        host.appendChild(slider({
            label: feature.label,
            value: face[feature.key] ?? 0,
            min: -1,
            max: feature.max || 1,
            onInput: (value) => post('nx:feature', { key: feature.key, value }),
        }));
    });
}

function renderHair() {
    const hair = $('hair-options');
    hair.innerHTML = '';
    const appearance = state.data.appearance;

    [
        { label: 'Hair style', key: 'hair', max: 74 },
        { label: 'Beard', key: 'beard', max: 28 },
        { label: 'Eyebrows', key: 'eyebrows', max: 33 },
        { label: 'Make-up', key: 'makeup', max: 74 },
        { label: 'Blush', key: 'blush', max: 6 },
        { label: 'Lipstick', key: 'lipstick', max: 9 },
    ].forEach((entry) => {
        hair.appendChild(slider({
            label: entry.label,
            value: appearance[entry.key] ?? 0,
            min: 0,
            max: entry.max,
            step: 1,
            format: (value) => `#${value}`,
            onInput: (value) => post('nx:style', { [entry.key]: value }),
        }));
    });

    const colours = $('colours');
    colours.innerHTML = '';

    const palette = el('div');
    palette.className = 'colours';
    (state.data.hairColours || []).slice(0, 64).forEach((index, position) => {
        const swatch = el('div', 'swatch');
        swatch.style.background = `hsl(${(position * 7) % 360}, ${35 + (position % 4) * 12}%, ${18 + (position % 6) * 9}%)`;
        swatch.title = `Hair colour ${index}`;
        swatch.addEventListener('click', () => {
            document.querySelectorAll('#colours .swatch').forEach((other) => other.classList.remove('selected'));
            swatch.classList.add('selected');
            post('nx:style', { hairColour: index, hairHighlight: index });
        });
        palette.appendChild(swatch);
    });
    colours.appendChild(palette);

    const eyes = el('div');
    eyes.className = 'colours';
    (state.data.eyeColours || []).forEach((index) => {
        const swatch = el('div', 'swatch');
        swatch.style.background = `hsl(${190 + index * 3}, 45%, ${25 + (index % 5) * 10}%)`;
        swatch.title = `Eye colour ${index}`;
        swatch.addEventListener('click', () => post('nx:style', { eyeColour: index }));
        eyes.appendChild(swatch);
    });
    $('hair-options').appendChild(el('h2', null, 'Eye colour'));
    $('hair-options').appendChild(eyes);
}

function renderComponents() {
    const host = $('components');
    host.innerHTML = '';

    const components = (state.data.appearance.components || []);
    (state.data.components || []).forEach((slot) => {
        const current = components.find((component) => Number(component.id) === slot.id) || { drawable: 0, texture: 0 };

        const card = el('div', 'component');
        const head = el('div', 'head');
        head.append(
            el('span', 'name', slot.name),
            el('span', 'value', `Drawable ${current.drawable} · Tex ${current.texture}`)
        );

        const buttons = el('div', 'buttons');
        const tweak = (deltaDrawable, deltaTexture) => {
            const drawable = Math.max(0, Number(current.drawable) + deltaDrawable);
            const texture = Math.max(0, Number(current.texture) + deltaTexture);
            current.drawable = drawable;
            current.texture = texture;
            head.lastChild.textContent = `Drawable ${drawable} · Tex ${texture}`;
            post('nx:component', { id: slot.id, drawable, texture });
        };

        [
            { label: '◄◄', action: () => tweak(-1, 0) },
            { label: '►►', action: () => tweak(1, 0) },
            { label: 'Tex ◄', action: () => tweak(0, -1) },
            { label: 'Tex ►', action: () => tweak(0, 1) },
        ].forEach((entry) => {
            const button = el('button', 'mini', entry.label);
            button.addEventListener('click', entry.action);
            buttons.appendChild(button);
        });

        const controls = el('div', 'controls');
        controls.appendChild(buttons);
        card.append(head, controls);
        host.appendChild(card);
    });
}

function renderProps() {
    const host = $('props');
    host.innerHTML = '';

    const props = state.data.appearance.props || [];
    (state.data.props || []).forEach((slot) => {
        let current = props.find((prop) => Number(prop.id) === slot.id);

        const card = el('div', 'component');
        const head = el('div', 'head');
        head.append(
            el('span', 'name', slot.name),
            el('span', 'value', current ? `Drawable ${current.drawable}` : 'None')
        );

        const buttons = el('div', 'buttons');
        const step = (delta) => {
            if (!current && delta > 0) {
                current = { id: slot.id, drawable: 0, texture: 0 };
                props.push(current);
            }
            if (!current) return;
            current.drawable = Math.max(0, Number(current.drawable) + delta);
            head.lastChild.textContent = `Drawable ${current.drawable}`;
            post('nx:prop', { id: slot.id, drawable: current.drawable, texture: current.texture || 0 });
        };

        [
            { label: '◄', action: () => step(-1) },
            { label: '►', action: () => step(1) },
            { label: 'None', action: () => {
                head.lastChild.textContent = 'None';
                post('nx:prop', { id: slot.id, drawable: -1 });
            } },
        ].forEach((entry) => {
            const button = el('button', 'mini', entry.label);
            button.addEventListener('click', entry.action);
            buttons.appendChild(button);
        });

        card.append(head, buttons);
        host.appendChild(card);
    });
}

function renderOutfits(outfits) {
    const host = $('outfits');
    host.innerHTML = '';

    if (!outfits || !outfits.length) {
        host.appendChild(el('p', 'hint', 'No outfits saved yet.'));
        return;
    }

    outfits.forEach((outfit) => {
        const node = el('div', 'outfit');
        node.append(el('span', null, outfit.name));

        const actions = el('div', 'buttons');
        const wear = el('button', 'mini', 'Wear');
        wear.addEventListener('click', () => post('nx:wearOutfit', { id: outfit.id }));
        const remove = el('button', 'mini off', 'Delete');
        remove.addEventListener('click', () => post('nx:deleteOutfit', { id: outfit.id }));
        actions.append(wear, remove);

        node.appendChild(actions);
        host.appendChild(node);
    });
}

function switchView(view) {
    state.view = view;
    document.querySelectorAll('.nav-item').forEach((item) => item.classList.toggle('selected', item.dataset.view === view));
    ['identity', 'face', 'hair', 'clothes', 'accessories', 'wardrobe'].forEach((name) => {
        $(`view-${name}`).classList.toggle('hidden', name !== view);
    });
}

document.querySelectorAll('.nav-item').forEach((item) => {
    item.addEventListener('click', () => switchView(item.dataset.view));
});

/* ------------------------------ messages ------------------------------ */

window.addEventListener('message', (event) => {
    const payload = event.data || {};
    const data = payload.data || {};

    switch (payload.action) {
        case 'open':
        case 'update':
            if (!data.components) break;
            state.data = data;
            state.gender = data.gender || 'male';

            document.querySelectorAll('[data-gender]').forEach((button) => {
                button.classList.toggle('selected', button.dataset.gender === state.gender);
            });

            $('subtitle').textContent = data.creation ? 'Design your character' : `Editing · ${data.mode}`;
            renderBlend();
            renderFeatures();
            renderHair();
            renderComponents();
            renderProps();
            $('app').classList.remove('hidden');
            break;

        case 'outfits':
            renderOutfits(data);
            switchView('wardrobe');
            break;

        case 'close':
            $('app').classList.add('hidden');
            break;

        default:
            break;
    }
});

/* ------------------------------ controls ------------------------------ */

document.querySelectorAll('[data-gender]').forEach((button) => {
    button.addEventListener('click', () => post('nx:gender', { gender: button.dataset.gender }));
});

$('btn-random').addEventListener('click', () => post('nx:random'));

$('btn-capture').addEventListener('click', () => post('nx:save', { capture: true }));

$('btn-save').addEventListener('click', () => post('nx:save', {}));

$('btn-cancel').addEventListener('click', () => {
    $('app').classList.add('hidden');
    post('nx:close');
});

$('btn-save-outfit').addEventListener('click', () => {
    const name = $('outfit-name').value.trim();
    post('nx:saveOutfit', { name });
    $('outfit-name').value = '';
});

document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return;
    $('app').classList.add('hidden');
    post('nx:close');
});
