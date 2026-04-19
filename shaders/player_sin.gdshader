shader_type canvas_item;

// sin_ratio: 0.0=Чистий, 0.33=Скверний, 0.66=Падений, 1.0=Демон
uniform float sin_ratio : hint_range(0.0, 1.0) = 0.0;

// ── Чистий: золотий ореол ──────────────────────────────────────────────────
uniform vec4  clean_aura_color    : source_color = vec4(1.0, 0.88, 0.35, 1.0);
uniform float clean_aura_strength : hint_range(0.0, 1.0) = 0.22;

// ── Скверний (30–59%): червоні очі + темні прожилки ───────────────────────
uniform vec4  taint_eye_color     : source_color = vec4(0.95, 0.05, 0.0, 1.0);
uniform float taint_eye_strength  : hint_range(0.0, 1.0) = 0.55;
uniform vec4  taint_vein_color    : source_color = vec4(0.08, 0.0, 0.15, 1.0);
uniform float taint_vein_strength : hint_range(0.0, 1.0) = 0.30;

// ── Падений (60–84%): яскраве ліве око, темніша мантія ────────────────────
uniform vec4  fall_aura_color     : source_color = vec4(0.35, 0.0, 0.5, 1.0);
uniform float fall_aura_strength  : hint_range(0.0, 1.0) = 0.30;
uniform float fall_darken         : hint_range(0.0, 1.0) = 0.35;

// ── Демон (85–100%): обидва ока, тріщини, темна аура ──────────────────────
uniform vec4  demon_crack_color   : source_color = vec4(1.0, 0.15, 0.0, 1.0);
uniform float demon_crack_strength: hint_range(0.0, 1.0) = 0.45;
uniform float demon_darken        : hint_range(0.0, 1.0) = 0.55;
uniform vec4  demon_aura_color    : source_color = vec4(0.6, 0.0, 0.0, 1.0);
uniform float demon_aura_strength : hint_range(0.0, 1.0) = 0.40;

// ── Зони ──────────────────────────────────────────────────────────────────
float eye_zone(vec2 uv) {
	float in_y = smoothstep(0.32, 0.22, uv.y);
	float in_x = 1.0 - smoothstep(0.25, 0.40, abs(uv.x - 0.5));
	return in_y * in_x;
}

float left_eye_zone(vec2 uv) {
	// ліве oko (права сторона спрайту — персонаж дивиться вправо)
	float in_y = smoothstep(0.32, 0.22, uv.y);
	float in_x = smoothstep(0.50, 0.60, uv.x) * smoothstep(0.72, 0.62, uv.x);
	return in_y * in_x;
}

float vein_zone(vec2 uv) {
	float in_y = smoothstep(0.38, 0.48, uv.y) * smoothstep(0.78, 0.68, uv.y);
	float in_x = smoothstep(0.30, 0.18, abs(uv.x - 0.5));
	float wave = sin(uv.y * 40.0 + 1.2) * 0.5 + 0.5;
	return in_y * in_x * wave;
}

float crack_zone(vec2 uv) {
	// тріщини — хаотична сітка по всьому тілу
	float net = sin(uv.x * 28.0) * sin(uv.y * 36.0 + 0.7);
	return smoothstep(0.70, 0.85, net) * smoothstep(0.15, 0.25, uv.y);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a < 0.01) { COLOR = tex; return; }

	vec3 col = tex.rgb;

	// Визначаємо вагу кожного стану
	// 0.0–0.33 = чистий→скверний, 0.33–0.66 = скверний→падений, 0.66–1.0 = падений→демон
	float t_taint = clamp(sin_ratio / 0.33, 0.0, 1.0);
	float t_fall  = clamp((sin_ratio - 0.33) / 0.33, 0.0, 1.0);
	float t_demon = clamp((sin_ratio - 0.66) / 0.34, 0.0, 1.0);

	// ── Чистий: золоте підсвічування (зникає при t_taint) ──────────────────
	float clean_w = 1.0 - t_taint;
	col = mix(col, clean_aura_color.rgb, clean_aura_strength * clean_w * tex.a);

	// ── Скверний: червоні очі + прожилки ────────────────────────────────────
	float eye_m  = eye_zone(UV) * tex.a;
	float vein_m = vein_zone(UV) * tex.a;
	col = mix(col, taint_eye_color.rgb,  eye_m  * taint_eye_strength  * t_taint);
	col = mix(col, taint_vein_color.rgb, vein_m * taint_vein_strength * t_taint);
	col = mix(col, col * (1.0 - 0.15 * t_taint), t_taint);

	// ── Падений: яскраве ліве oko, темно-фіолетова аура, темніша мантія ─────
	float leye_m = left_eye_zone(UV) * tex.a;
	col = mix(col, taint_eye_color.rgb, leye_m * 0.85 * t_fall);
	col = mix(col, fall_aura_color.rgb, fall_aura_strength * t_fall * (1.0 - leye_m));
	col = mix(col, col * (1.0 - fall_darken), t_fall * 0.6);

	// ── Демон: обидва ока, тріщини, темна аура ───────────────────────────────
	float crack_m = crack_zone(UV) * tex.a;
	col = mix(col, demon_crack_color.rgb, crack_m * demon_crack_strength * t_demon);
	col = mix(col, demon_aura_color.rgb, demon_aura_strength * t_demon * (1.0 - crack_m) * 0.5);
	col = mix(col, col * (1.0 - demon_darken), t_demon * 0.7);

	COLOR = vec4(col, tex.a);
}
