// MapLibre triangulated fill-outline fragment shader with vertex-evaluated
// outline paint values.
#version 460 core

layout(location = 0) out vec4 frag_color;

in vec2 v_normal;
in float v_width;
in float v_gamma_scale;
in float v_dpr;
in vec4 v_outline_color;
in float v_opacity;

void main() {
    float dist = length(v_normal) * v_width;
    float blur2 = (1.0 / v_dpr) * v_gamma_scale;
    float alpha = clamp(min(dist + blur2, v_width - dist) / blur2, 0.0, 1.0);
    frag_color = v_outline_color * (alpha * v_opacity);
}
