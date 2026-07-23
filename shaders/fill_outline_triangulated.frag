// MapLibre triangulated fill-outline fragment shader.
#version 460 core

layout(location = 0) out vec4 frag_color;

layout(binding = 1) uniform FillEvaluatedPropsUBO {
    vec4 color;
    vec4 outline_color;
    float opacity;
    float fade;
    float from_scale;
    float to_scale;
} props;

in vec2 v_normal;
in float v_width;
in float v_gamma_scale;
in float v_dpr;

void main() {
    float dist = length(v_normal) * v_width;
    float blur2 = (1.0 / v_dpr) * v_gamma_scale;
    float alpha = clamp(min(dist + blur2, v_width - dist) / blur2, 0.0, 1.0);
    frag_color = props.outline_color * (alpha * props.opacity);
}
