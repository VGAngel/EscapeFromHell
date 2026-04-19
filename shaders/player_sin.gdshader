shader_type canvas_item;

// Наступний спрайт стану (поточний — вбудований TEXTURE)
uniform sampler2D texture_next : source_color, filter_linear_mipmap;

// 0.0 = повністю TEXTURE (поточний стан), 1.0 = повністю texture_next
uniform float blend_t : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 cur = texture(TEXTURE, UV);
	vec4 nxt = texture(texture_next, UV);
	COLOR = mix(cur, nxt, blend_t);
}
