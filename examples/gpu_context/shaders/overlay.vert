#version 460 core

layout(location = 0) in vec2 position;
layout(location = 1) in vec4 color;

layout(location = 0) out vec4 vertex_color;

layout(binding = 0) uniform OverlayUniforms {
    // x: angle, y: viewport aspect correction, z: pulse scale
    vec4 values;
} overlay;

void main() {
    float angle = overlay.values.x;
    float cosine = cos(angle);
    float sine = sin(angle);
    mat2 rotation = mat2(cosine, sine, -sine, cosine);
    vec2 transformed = rotation * position * overlay.values.z;
    transformed.x *= overlay.values.y;

    gl_Position = vec4(transformed, 0.0, 1.0);
    vertex_color = color;
}
