(() => {
	"use strict";

	const resource = typeof GetParentResourceName === "function" ? GetParentResourceName() : "banho_dormir";
	const panel = document.getElementById("panel");
	const progress = document.getElementById("progress");

	let locations = [];
	let selected = null;
	let currentType = "bath";
	let rainSound = null;

	const post = async (action, data = {}) => {
		const response = await fetch(`https://${resource}/${action}`, {
			method: "POST",
			headers: { "Content-Type": "application/json; charset=UTF-8" },
			body: JSON.stringify(data)
		});

		return response.json().catch(() => false);
	};

	const esc = value => String(value ?? "").replace(/[&<>"']/g, char => ({
		"&": "&amp;",
		"<": "&lt;",
		">": "&gt;",
		'"': "&quot;",
		"'": "&#39;"
	}[char]));

	const blankLocation = type => ({
		Id: "",
		Type: type,
		Name: type === "bath" ? "Banho" : "Dormir",
		Coords: { x: 0, y: 0, z: 0, w: 0 },
		Duration: type === "bath" ? 12000 : 18000,
		Price: 0,
		Reward: 0,
		Effects: type === "bath" ? { Health: 5, Hunger: 0, Thirst: 0, Stress: 25 } : { Health: 25, Hunger: 10, Thirst: 10, Stress: 35 },
		Enabled: true
	});

	const fillForm = location => {
		selected = location ? JSON.parse(JSON.stringify(location)) : blankLocation(currentType);
		currentType = selected.Type || currentType;

		for (const element of panel.querySelectorAll("[data-tab-type]")) {
			element.classList.toggle("active", element.dataset.tabType === currentType);
		}

		const coords = selected.Coords || {};
		const effects = selected.Effects || {};
		const values = {
			id: selected.Id || "",
			name: selected.Name || "",
			type: currentType,
			x: coords.x || 0,
			y: coords.y || 0,
			z: coords.z || 0,
			w: coords.w || 0,
			duration: selected.Duration || 10000,
			price: selected.Price || 0,
			reward: selected.Reward || 0,
			health: effects.Health || 0,
			hunger: effects.Hunger || 0,
			thirst: effects.Thirst || 0,
			stress: effects.Stress || 0,
			enabled: selected.Enabled !== false ? "true" : "false"
		};

		for (const [id,value] of Object.entries(values)) {
			const input = panel.querySelector(`#${id}`);
			if (input) input.value = value;
		}

		renderRows();
	};

	const readForm = () => ({
		Id: panel.querySelector("#id")?.value || "",
		Type: currentType,
		Name: panel.querySelector("#name")?.value || "",
		Coords: {
			x: Number(panel.querySelector("#x")?.value || 0),
			y: Number(panel.querySelector("#y")?.value || 0),
			z: Number(panel.querySelector("#z")?.value || 0),
			w: Number(panel.querySelector("#w")?.value || 0)
		},
		Duration: Number(panel.querySelector("#duration")?.value || 10000),
		Price: Number(panel.querySelector("#price")?.value || 0),
		Reward: Number(panel.querySelector("#reward")?.value || 0),
		Effects: {
			Health: Number(panel.querySelector("#health")?.value || 0),
			Hunger: Number(panel.querySelector("#hunger")?.value || 0),
			Thirst: Number(panel.querySelector("#thirst")?.value || 0),
			Stress: Number(panel.querySelector("#stress")?.value || 0)
		},
		Enabled: panel.querySelector("#enabled")?.value !== "false"
	});

	const renderRows = () => {
		const rows = panel.querySelector(".rows");
		if (!rows) return;

		rows.innerHTML = locations.map(location => {
			const type = location.Type === "sleep" ? "Dormir" : "Banho";
			const coords = location.Coords || {};
			const active = selected && selected.Id && selected.Id === location.Id ? "active" : "";
			const reward = Number(location.Reward || 0);

			return `
				<button class="row ${active}" data-id="${esc(location.Id)}">
					<span>
						<b>${esc(location.Name)}</b>
						<small>${Number(coords.x || 0).toFixed(2)}, ${Number(coords.y || 0).toFixed(2)}, ${Number(coords.z || 0).toFixed(2)}${reward > 0 ? ` | paga $${reward}` : ""}</small>
					</span>
					<span class="pill ${location.Type === "sleep" ? "sleep" : ""}">${type}</span>
					<span class="status">${location.Enabled === false ? "off" : "on"}</span>
				</button>
			`;
		}).join("") || `<div class="row"><span><b>Nenhum local criado</b><small>Use sua posicao atual e salve.</small></span></div>`;
	};

	const renderPanel = () => {
		panel.innerHTML = `
			<div class="panel-shell">
				<header class="panel-head">
					<div>
						<small>Configurar pontos da cidade</small>
						<b>Criar local</b>
					</div>
					<button class="close" data-action="close">X</button>
				</header>
				<main class="panel-content">
					<section class="card creator">
						<div class="tabs">
							<button data-tab-type="bath">Banho</button>
							<button data-tab-type="sleep">Dormir</button>
						</div>
						<div class="preview"><div class="marker"></div></div>
						<div class="form-grid">
							<input id="id" type="hidden">
							<label class="wide">Nome do local<input id="name"></label>
							<label>Tempo (ms)<input id="duration" type="number" min="3000"></label>
							<label>Cobrar valor<input id="price" type="number" min="0"></label>
							<label>Dinheiro ganho<input id="reward" type="number" min="0"></label>
							<label>Status<select id="enabled"><option value="true">Ativo</option><option value="false">Desativado</option></select></label>
							<div class="coords">
								<label>X<input id="x" type="number" step="0.01"></label>
								<label>Y<input id="y" type="number" step="0.01"></label>
								<label>Z<input id="z" type="number" step="0.01"></label>
								<label>H<input id="w" type="number" step="0.01"></label>
							</div>
							<label>Vida<input id="health" type="number" min="0" max="100"></label>
							<label>Fome<input id="hunger" type="number" min="0" max="100"></label>
							<label>Sede<input id="thirst" type="number" min="0" max="100"></label>
							<label>Stress<input id="stress" type="number" min="0" max="100"></label>
						</div>
						<div class="actions">
							<button class="btn soft" data-action="position">Usar posicao</button>
							<button class="btn green" data-action="save">Salvar local</button>
							<button class="btn red" data-action="delete">Remover</button>
						</div>
					</section>
					<section class="card list">
						<div class="list-title">
							<b>Locais criados</b>
							<button class="btn soft" data-action="new">Novo</button>
						</div>
						<div class="rows"></div>
					</section>
				</main>
			</div>
		`;

		fillForm(selected || blankLocation(currentType));
	};

	const openPanel = payload => {
		locations = payload.Locations || [];
		selected = locations[0] ? JSON.parse(JSON.stringify(locations[0])) : blankLocation(currentType);
		currentType = selected.Type || "bath";
		panel.classList.remove("hidden");
		renderPanel();
	};

	const closePanel = () => {
		panel.classList.add("hidden");
		panel.innerHTML = "";
	};

	const renderProgress = payload => {
		const duration = Number(payload.Duration || 10000);
		progress.innerHTML = `
			<div class="progress-label"><span>${esc(payload.Label || "Aguarde")}</span><span>X cancela</span></div>
			<div class="bar"><span style="animation-duration:${duration}ms"></span></div>
		`;
		progress.classList.remove("hidden");
	};

	const stopRainSound = () => {
		if (!rainSound) return;

		const { context, source, gain } = rainSound;
		rainSound = null;

		try {
			gain.gain.cancelScheduledValues(context.currentTime);
			gain.gain.linearRampToValueAtTime(0, context.currentTime + 0.25);
			setTimeout(() => {
				try { source.stop(); } catch (error) {}
				try { context.close(); } catch (error) {}
			}, 300);
		} catch (error) {
			try { source.stop(); } catch (stopError) {}
			try { context.close(); } catch (closeError) {}
		}
	};

	const startRainSound = async payload => {
		if ((payload.Name || "rain") !== "rain") return;
		stopRainSound();

		try {
			const AudioContext = window.AudioContext || window.webkitAudioContext;
			if (!AudioContext) return;

			const context = new AudioContext();
			if (context.state === "suspended") await context.resume();

			const seconds = 2;
			const length = context.sampleRate * seconds;
			const buffer = context.createBuffer(1, length, context.sampleRate);
			const data = buffer.getChannelData(0);
			let low = 0;
			let high = 0;

			for (let index = 0; index < length; index++) {
				const white = Math.random() * 2 - 1;
				low = (low + (0.018 * white)) / 1.018;
				high = white - low;
				data[index] = (low * 3.2) + (high * 0.18);
			}

			const source = context.createBufferSource();
			const highpass = context.createBiquadFilter();
			const lowpass = context.createBiquadFilter();
			const gain = context.createGain();

			source.buffer = buffer;
			source.loop = true;
			highpass.type = "highpass";
			highpass.frequency.value = 260;
			lowpass.type = "lowpass";
			lowpass.frequency.value = 4200;
			gain.gain.value = 0;

			source.connect(highpass);
			highpass.connect(lowpass);
			lowpass.connect(gain);
			gain.connect(context.destination);
			source.start();

			const volume = Math.min(1, Math.max(0, Number(payload.Volume || 0.28)));
			gain.gain.linearRampToValueAtTime(volume, context.currentTime + 0.2);
			rainSound = { context, source, gain };
		} catch (error) {
			stopRainSound();
		}
	};

	document.addEventListener("click", async event => {
		const type = event.target.closest("[data-tab-type]");
		if (type) {
			currentType = type.dataset.tabType;
			fillForm(blankLocation(currentType));
			return;
		}

		const row = event.target.closest("[data-id]");
		if (row) {
			const location = locations.find(item => item.Id === row.dataset.id);
			if (location) fillForm(location);
			return;
		}

		const action = event.target.closest("[data-action]")?.dataset.action;
		if (!action) return;

		if (action === "close") {
			await post("Close");
			closePanel();
		}

		if (action === "new") {
			fillForm(blankLocation(currentType));
		}

		if (action === "position") {
			const coords = await post("CurrentPosition");
			for (const key of ["x","y","z","w"]) {
				const input = panel.querySelector(`#${key}`);
				if (input && coords[key] !== undefined) input.value = coords[key];
			}
		}

		if (action === "save") {
			const response = await post("SaveLocation", readForm());
			if (response && response.Locations) {
				locations = response.Locations;
				fillForm(response.Location || response.Locations[response.Locations.length - 1] || blankLocation(currentType));
			}
		}

		if (action === "delete") {
			const id = panel.querySelector("#id")?.value;
			if (!id) return;
			const response = await post("DeleteLocation", { Id: id });
			if (response && response.Locations) {
				locations = response.Locations;
				fillForm(locations[0] || blankLocation(currentType));
			}
		}
	});

	window.addEventListener("message", event => {
		const data = event.data || {};

		if (data.Action === "Open") openPanel(data.Payload || {});
		if (data.Action === "Close") closePanel();
		if (data.Action === "Refresh") {
			locations = data.Payload?.Locations || locations;
			renderRows();
		}
		if (data.Action === "Progress") renderProgress(data.Payload || {});
		if (data.Action === "ProgressClose") progress.classList.add("hidden");
		if (data.Action === "Sound") startRainSound(data.Payload || {});
		if (data.Action === "SoundStop") stopRainSound();
	});
})();
