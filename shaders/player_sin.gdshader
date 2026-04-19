shader_type canvas_item;

// sin_ratio: 0.0 = Чистий (0–29%), 1.0 = Скверний (30–59%)
uniform float sin_ratio : hint_range(0.0, 1.0) = 0.0;

// Параметри золотого ореолу (чистий стан)
uniform vec4  aura_color     : source_color = vec4(1.0, 0.88, 0.35, 1.0);
uniform float aura_strength  : hint_range(0.0, 1.0) = 0.28;

// Параметри скверного стану
uniform vec4  eye_tint_color  : source_color = vec4(0.9, 0.05, 0.05, 1.0);
uniform float eye_tint_strength : hint_range(0.0, 1.0) = 0.55;
uniform vec4  vein_color      : source_color = vec4(0.08, 0.0, 0.12, 1.0);
uniform float vein_strength   : hint_range(0.0, 1.0) = 0.35;

// Зони: очі — верхня чверть спрайту, прожилки — руки (бокові смуги)
float eye_zone(vec2 uv) {
	// верхня чверть по Y, центральна третина по X
	float in_y = smoothstep(0.30, 0.22, uv.y);
	float in_x = 1.0 - smoothstep(0.28, 0.42, abs(uv.x - 0.5));
	return in_y * in_x;
}

float vein_zone(vec2 uv) {
	// бокові смуги — умовні "руки", середина по Y
	float in_y = smoothstep(0.35, 0.45, uv.y) * smoothstep(0.80, 0.70, uv.y);
	float in_x = smoothstep(0.28, 0.18, abs(uv.x - 0.5));
	// тонкий меандр по вертикалі — імітація прожилок
	float wave = sin(uv.y * 38.0 + 1.4) * 0.5 + 0.5;
	return in_y * in_x * wave;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	// --- Чистий стан: золоте підсвічування ---
	// Тільки на непрозорих пікселях, зменшується до нуля при sin_ratio = 1
	float clean_t = 1.0 - sin_ratio;
	vec3 gold_mix = mix(tex.rgb, aura_color.rgb, aura_strength * clean_t);

	// --- Скверний стан: червоні очі + темні прожилки ---
	float eye_mask  = eye_zone(UV)  * tex.a;
	float vein_mask = vein_zone(UV) * tex.a;

	vec3 evil_rgb = gold_mix;
	evil_rgb = mix(evil_rgb, eye_tint_color.rgb,  eye_mask  * eye_tint_strength  * sin_ratio);
	evil_rgb = mix(evil_rgb, vein_color.rgb,       vein_mask * vein_strength      * sin_ratio);

	// Легке потемніння всього персонажа при переході
	evil_rgb = mix(evil_rgb, evil_rgb * 0.72, sin_ratio * 0.4);

	COLOR = vec4(evil_rgb, tex.a);
}
