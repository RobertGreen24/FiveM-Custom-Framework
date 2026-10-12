/* Nexus :: nx_chat — NUI controller */
(() => {
    'use strict';

    const chat = document.getElementById('chat');
    const messagesEl = document.getElementById('messages');
    const composer = document.getElementById('composer');
    const channelsEl = document.getElementById('channels');
    const input = document.getElementById('input');
    const prefixEl = document.getElementById('prefix');
    const counter = document.getElementById('counter');
    const suggestionsEl = document.getElementById('suggestions');

    let channels = [];
    let suggestions = [];
    let activeChannel = 'local';
    let maxLength = 200;
    let suggestionIndex = -1;
    let history = [];
    let historyIndex = 0;

    const resource = (name) => `https://${GetParentResourceName()}/${name}`;
    const post = (name, data) =>
        fetch(resource(name), {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data || {}),
        }).catch(() => {});

    const CHANNEL_LABELS = {
        local: 'Local',
        me: 'Me',
        do: 'Do',
        whisper: 'Whisper',
        shout: 'Shout',
        ooc: 'OOC',
        ad: 'Advert',
        twt: 'Twitter',
        dispatch: 'Dispatch',
        staff: 'Staff',
        system: 'System',
    };

    /* --------------------------- message render --------------------------- */

    const MAX_LINES = 220;

    function addMessage(data) {
        if (!data) return;

        const line = document.createElement('div');
        const channel = (data.channel || 'local').toLowerCase();
        line.className = `line ${channel}`;
        if (data.kind === 'announce') line.classList.add('system');

        const time = document.createElement('span');
        time.className = 'time';
        if (data.time) time.textContent = `[${data.time}]`;

        const author = document.createElement('span');
        author.className = 'author';
        author.textContent = data.author ? `${data.author}: ` : '';

        const body = document.createElement('span');
        body.className = 'body';
        body.textContent = data.text === undefined ? '' : String(data.text);
        if (data.multiline) body.style.whiteSpace = 'pre-wrap';

        if (data.colour) {
            line.style.borderLeftColor = data.colour.startsWith('#') ? data.colour : `#${data.colour}`;
        }

        line.append(time, author, body);
        messagesEl.appendChild(line);

        while (messagesEl.childElementCount > MAX_LINES) {
            messagesEl.removeChild(messagesEl.firstChild);
        }

        messagesEl.scrollTop = messagesEl.scrollHeight;
    }

    function clearMessages() {
        messagesEl.innerHTML = '';
    }

    /* ------------------------------ channels ------------------------------ */

    function renderChannels() {
        channelsEl.innerHTML = '';
        channels.forEach((channel) => {
            const button = document.createElement('button');
            button.className = `channel${channel.id === activeChannel ? ' selected' : ''}`;
            button.textContent = channel.label;
            button.dataset.id = channel.id;
            button.addEventListener('click', () => {
                selectChannel(channel.id);
                input.focus();
            });
            channelsEl.appendChild(button);
        });
    }

    function selectChannel(id) {
        activeChannel = id;
        const channel = channels.find((entry) => entry.id === id);
        const command = channel && channel.command;
        prefixEl.textContent = command ? `/${command}` : '/local';
        renderChannels();
        post('nx:channel', { channel: id });
    }

    /* ---------------------------- command hints ---------------------------- */

    function updateSuggestions() {
        const value = input.value.trim();

        if (!value.startsWith('/')) {
            suggestionsEl.classList.remove('show');
            suggestionIndex = -1;
            return;
        }

        const query = value.slice(1).toLowerCase();
        const matches = suggestions
            .filter((entry) => entry.name.replace('/', '').startsWith(query))
            .slice(0, 8);

        if (!matches.length) {
            suggestionsEl.classList.remove('show');
            return;
        }

        suggestionsEl.innerHTML = '';
        matches.forEach((entry, index) => {
            const row = document.createElement('div');
            row.className = `suggestion${index === suggestionIndex ? ' selected' : ''}`;

            const name = document.createElement('span');
            name.className = 'name';
            name.textContent = entry.name;

            const desc = document.createElement('span');
            desc.className = 'desc';
            desc.textContent = entry.description;

            row.append(name, desc);
            row.addEventListener('click', () => {
                input.value = `${entry.name} `;
                suggestionsEl.classList.remove('show');
                input.focus();
            });
            suggestionsEl.appendChild(row);
        });

        suggestionsEl.classList.add('show');
    }

    /* ------------------------------- sending ------------------------------- */

    function send() {
        const text = input.value.trim();
        if (!text) {
            close();
            return;
        }

        // a leading /command switches the channel on the fly
        const slash = text.match(/^\/(\w+)\s*(.*)$/);
        let channel = activeChannel;
        let body = text;

        if (slash) {
            const command = slash[1].toLowerCase();
            const known = channels.find((entry) => entry.command === command);
            if (known) {
                channel = known.id;
                body = slash[2];
                if (command === '911' || command === '311') {
                    post('nx:emergency', { service: command, message: slash[2] });
                    input.value = '';
                    close();
                    return;
                }
            } else if (command === '911' || command === '311') {
                post('nx:emergency', { service: command, message: slash[2] });
                input.value = '';
                close();
                return;
            }
        }

        post('nx:send', { text: body, channel });
        history.push(text);
        if (history.length > 60) history.shift();
        historyIndex = history.length;
        input.value = '';
    }

    /* -------------------------------- window -------------------------------- */

    function open() {
        chat.classList.add('open');
        setTimeout(() => input.focus(), 30);
    }

    function close() {
        chat.classList.remove('open');
        suggestionsEl.classList.remove('show');
        input.value = '';
        input.blur();
        post('nx:close');
    }

    /* -------------------------------- events -------------------------------- */

    input.addEventListener('input', () => {
        counter.textContent = `${input.value.length}/${maxLength}`;
        updateSuggestions();
    });

    input.addEventListener('keydown', (event) => {
        if (event.key === 'Escape') {
            event.preventDefault();
            close();
            return;
        }

        if (event.key === 'Tab') {
            event.preventDefault();
            if (!channels.length) return;
            const index = channels.findIndex((entry) => entry.id === activeChannel);
            const next = channels[(index + 1) % channels.length];
            selectChannel(next.id);
            return;
        }

        if (event.key === 'ArrowUp') {
            if (suggestionsEl.classList.contains('show')) return;
            event.preventDefault();
            if (historyIndex > 0) {
                historyIndex -= 1;
                input.value = history[historyIndex] || '';
            }
            return;
        }

        if (event.key === 'ArrowDown') {
            if (suggestionsEl.classList.contains('show')) return;
            event.preventDefault();
            if (historyIndex < history.length - 1) {
                historyIndex += 1;
                input.value = history[historyIndex];
            } else {
                historyIndex = history.length;
                input.value = '';
            }
            return;
        }

        if (event.key === 'Enter') {
            event.preventDefault();
            send();
        }
    });

    window.addEventListener('message', (event) => {
        const payload = event.data || {};

        switch (payload.action) {
            case 'open': {
                const data = payload.data || {};
                channels = data.channels || [];
                suggestions = data.suggestions || [];
                maxLength = data.maxLength || 200;
                history = data.history || [];
                historyIndex = history.length;
                activeChannel = data.channel || 'local';
                counter.textContent = `0/${maxLength}`;
                input.maxLength = maxLength;
                renderChannels();
                selectChannel(activeChannel);
                open();
                if (data.browsing) input.value = '';
                break;
            }
            case 'close':
                chat.classList.remove('open');
                input.blur();
                break;
            case 'message':
                addMessage(payload.data);
                break;
            case 'clear':
                clearMessages();
                break;
        }
    });
})();
