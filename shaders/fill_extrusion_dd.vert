// Fill extrusion vertex shader - data-driven base/height/color variant.
// Native source: short2(pos) + short4(normal_ed) + float2(base) +
// float2(height) + float4(packed color) = 44 bytes. Dart expands the six
// signed shorts to floats before upload, producing this 56-byte GPU layout.
// Source-function values are duplicated into both zoom stops; composite
// values retain both stops and use the drawable interpolation factors.
#version 460 core

layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec4 a_normal_ed;
layout(location = 2) in vec2 a_base_range;
layout(location = 3) in vec2 a_height_range;
layout(location = 4) in vec4 a_color_range;

layout(binding = 0) uniform FillExtrusionDrawableUBO {
    mat4 matrix;
    vec2 pixel_coord_upper;
    vec2 pixel_coord_lower;
    float height_factor;
    float tile_ratio;
    float base_t;
    float height_t;
    float color_t;
    float pad1, pad2;
    uint data_driven_mask; // bit0=color; occupies native pad at byte 108
} drawable;

layout(binding = 1) uniform FillExtrusionPropsUBO {
    vec4 color;
    vec4 light_color;    // xyz used
    vec4 light_pos_base; // xyz=light_position, w=base
    float height;
    float light_intensity;
    float vertical_gradient;
    float opacity;
    float fade;
    float from_scale;
    float to_scale;
    float pad1;
} props;

out vec4 v_color;

// Exact port of MapLibre's unpack_float/decode_color helpers. Paint binders
// encode premultiplied RG and BA byte pairs as exactly representable floats.
vec2 unpack_float(const float packed_value) {
    int packed_int_value = int(packed_value);
    int v0 = packed_int_value / 256;
    return vec2(v0, packed_int_value - v0 * 256);
}

vec4 decode_color(const vec2 encoded_color) {
    return vec4(
        unpack_float(encoded_color.x) / 255.0,
        unpack_float(encoded_color.y) / 255.0
    );
}

void main() {
    // RAW normal is scaled by 16384; the LSB of x is the top/side flag.
    vec3 normal = a_normal_ed.xyz;

    float base = max(0.0, mix(a_base_range.x, a_base_range.y, drawable.base_t));
    float height = max(0.0, mix(a_height_range.x, a_height_range.y, drawable.height_t));
    vec4 color;
    if ((drawable.data_driven_mask & 1u) != 0u) {
        vec4 min_color = decode_color(a_color_range.xy);
        vec4 max_color = decode_color(a_color_range.zw);
        color = mix(min_color, max_color, drawable.color_t);
    } else {
        color = props.color;
    }

    float t = mod(normal.x, 2.0);

    gl_Position = drawable.matrix * vec4(a_pos, t > 0.0 ? height : base, 1.0);

    // Relative luminance of the surface color
    float colorvalue = color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722;

    v_color = vec4(0.0, 0.0, 0.0, 1.0);

    // Slight ambient so no extrusion is totally black
    vec4 ambientlight = vec4(0.03, 0.03, 0.03, 1.0);
    color += ambientlight;

    // cos(theta) between surface normal and light ray
    float directional = clamp(dot(normal / 16384.0, props.light_pos_base.xyz), 0.0, 1.0);
    directional = mix((1.0 - props.light_intensity),
                      max((1.0 - colorvalue + props.light_intensity), 1.0),
                      directional);

    // Vertical gradient along side surfaces
    if (normal.y != 0.0) {
        directional *= (
            (1.0 - props.vertical_gradient) +
            (props.vertical_gradient *
             clamp((t + base) * pow(height / 150.0, 0.5),
                   mix(0.7, 0.98, 1.0 - props.light_intensity), 1.0)));
    }

    v_color.r += clamp(color.r * directional * props.light_color.r,
                       mix(0.0, 0.3, 1.0 - props.light_color.r), 1.0);
    v_color.g += clamp(color.g * directional * props.light_color.g,
                       mix(0.0, 0.3, 1.0 - props.light_color.g), 1.0);
    v_color.b += clamp(color.b * directional * props.light_color.b,
                       mix(0.0, 0.3, 1.0 - props.light_color.b), 1.0);
    v_color *= props.opacity;
}
