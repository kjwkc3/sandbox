package render

import gl "vendor:OpenGL"

ShaderProgram :: struct {
	id: u32,
}

MODEL_VERT :: `
#version 330 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aNormal;
layout (location = 2) in vec2 aTexCoord;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;
uniform mat3 normalMat;

out vec3 FragPos;
out vec3 Normal;
out vec2 TexCoord;

void main() {
    FragPos = vec3(model * vec4(aPos, 1.0));
    Normal = normalMat * aNormal;
    TexCoord = aTexCoord;
    gl_Position = projection * view * vec4(FragPos, 1.0);
}
`

MODEL_FRAG :: `
#version 330 core
in vec3 FragPos;
in vec3 Normal;
in vec2 TexCoord;

uniform sampler2D baseColorMap;
uniform bool useTexture;
uniform vec3 lightDir;
uniform vec3 lightColor;
uniform vec3 viewPos;
uniform vec3 objectColor;

out vec4 FragColor;

void main() {
    vec3 albedo = useTexture ? texture(baseColorMap, TexCoord).rgb : objectColor;

    float ambientStrength = 0.20;
    vec3 ambient = ambientStrength * lightColor;

    vec3 norm = normalize(Normal);
    vec3 ld = normalize(-lightDir);
    float diff = dot(norm, ld) * 0.5 + 0.5;
    vec3 diffuse = diff * lightColor;

    float specularStrength = 0.15;
    vec3 viewDir = normalize(viewPos - FragPos);
    vec3 reflectDir = reflect(-ld, norm);
    float spec = pow(max(dot(viewDir, reflectDir), 0.0), 32.0);
    vec3 specular = specularStrength * spec * lightColor;

    vec3 result = (ambient + diffuse + specular) * albedo;
    FragColor = vec4(result, 1.0);
}
`

compile_shader :: proc(source: cstring, shader_type: u32) -> u32 {
	shader := gl.CreateShader(shader_type)
	src := source
	gl.ShaderSource(shader, 1, &src, nil)
	gl.CompileShader(shader)

	success: i32
	gl.GetShaderiv(shader, gl.COMPILE_STATUS, &success)
	if success == 0 {
		log_len: i32
		gl.GetShaderiv(shader, gl.INFO_LOG_LENGTH, &log_len)
		if log_len > 0 {
			log := make([]u8, log_len, context.temp_allocator)
			gl.GetShaderInfoLog(shader, log_len, nil, raw_data(log))
			panic(string(log))
		}
		panic("Shader compile failed")
	}
	return shader
}

create_shader :: proc(vs_src, fs_src: cstring) -> ShaderProgram {
	vs := compile_shader(vs_src, gl.VERTEX_SHADER)
	defer gl.DeleteShader(vs)

	fs := compile_shader(fs_src, gl.FRAGMENT_SHADER)
	defer gl.DeleteShader(fs)

	program := gl.CreateProgram()
	gl.AttachShader(program, vs)
	gl.AttachShader(program, fs)
	gl.LinkProgram(program)

	success: i32
	gl.GetProgramiv(program, gl.LINK_STATUS, &success)
	if success == 0 {
		log_len: i32
		gl.GetProgramiv(program, gl.INFO_LOG_LENGTH, &log_len)
		if log_len > 0 {
			log := make([]u8, log_len, context.temp_allocator)
			gl.GetProgramInfoLog(program, log_len, nil, raw_data(log))
			panic(string(log))
		}
		panic("Shader link failed")
	}
	return ShaderProgram{id = program}
}

use_shader :: proc(shader: ShaderProgram) {
	gl.UseProgram(shader.id)
}

set_mat4 :: proc(shader: ShaderProgram, name: cstring, mat: [16]f32) {
	loc := gl.GetUniformLocation(shader.id, name)
	m := mat
	gl.UniformMatrix4fv(loc, 1, false, raw_data(m[:]))
}

set_mat3 :: proc(shader: ShaderProgram, name: cstring, mat: [9]f32) {
	loc := gl.GetUniformLocation(shader.id, name)
	m := mat
	gl.UniformMatrix3fv(loc, 1, false, raw_data(m[:]))
}

set_vec3 :: proc(shader: ShaderProgram, name: cstring, v: [3]f32) {
	loc := gl.GetUniformLocation(shader.id, name)
	gl.Uniform3f(loc, v[0], v[1], v[2])
}

set_bool :: proc(shader: ShaderProgram, name: cstring, value: bool) {
	loc := gl.GetUniformLocation(shader.id, name)
	gl.Uniform1i(loc, value ? 1 : 0)
}

set_texture :: proc(shader: ShaderProgram, name: cstring, unit: i32, tex_id: u32) {
	bind_texture(u32(unit), tex_id)
	loc := gl.GetUniformLocation(shader.id, name)
	gl.Uniform1i(loc, unit)
}

delete_shader :: proc(shader: ShaderProgram) {
	gl.DeleteProgram(shader.id)
}
