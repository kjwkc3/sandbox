package render

import "core:c"
import "core:fmt"
import "core:strings"

import gl "vendor:OpenGL"
import stbi "vendor:stb/image"

TextureCache :: struct {
	textures: map[string]u32,
}

init_texture_cache :: proc(cache: ^TextureCache, allocator := context.allocator) {
	cache.textures = make(map[string]u32, allocator)
}

delete_texture_cache :: proc(cache: ^TextureCache) {
	for _, &tex_id in cache.textures {
		gl.DeleteTextures(1, &tex_id)
	}
	delete(cache.textures)
}

load_texture :: proc(cache: ^TextureCache, path: string, allocator := context.allocator) -> u32 {
	if tex_id, ok := cache.textures[path]; ok {
		return tex_id
	}

	cpath := strings.clone_to_cstring(path, allocator)
	width, height, channels_in_file: c.int
	data := stbi.load(cpath, &width, &height, &channels_in_file, 4)
	if data == nil {
		fmt.printf("stbi: failed to load texture %s\n", path)
		return 0
	}
	defer stbi.image_free(data)

	tex_id: u32
	gl.GenTextures(1, &tex_id)
	gl.BindTexture(gl.TEXTURE_2D, tex_id)

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, i32(gl.REPEAT))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, i32(gl.REPEAT))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(gl.LINEAR_MIPMAP_LINEAR))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(gl.LINEAR))

	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		gl.RGBA,
		width,
		height,
		0,
		gl.RGBA,
		gl.UNSIGNED_BYTE,
		data,
	)
	gl.GenerateMipmap(gl.TEXTURE_2D)
	gl.BindTexture(gl.TEXTURE_2D, 0)

	cache.textures[path] = tex_id
	return tex_id
}

bind_texture :: proc(unit: u32, tex_id: u32) {
	gl.ActiveTexture(gl.TEXTURE0 + unit)
	gl.BindTexture(gl.TEXTURE_2D, tex_id)
}

upload_texture_rgba :: proc(width, height: c.int, data: [^]byte) -> u32 {
	tex_id: u32
	gl.GenTextures(1, &tex_id)
	gl.BindTexture(gl.TEXTURE_2D, tex_id)

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, i32(gl.REPEAT))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, i32(gl.REPEAT))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(gl.LINEAR_MIPMAP_LINEAR))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(gl.LINEAR))

	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		gl.RGBA,
		width,
		height,
		0,
		gl.RGBA,
		gl.UNSIGNED_BYTE,
		data,
	)
	gl.GenerateMipmap(gl.TEXTURE_2D)
	gl.BindTexture(gl.TEXTURE_2D, 0)
	return tex_id
}

load_texture_from_memory :: proc(
	cache: ^TextureCache,
	key: string,
	pixels: []u8,
	width, height: c.int,
	allocator := context.allocator,
) -> u32 {
	if tex_id, ok := cache.textures[key]; ok {
		return tex_id
	}

	data := raw_data(pixels)
	if data == nil || len(pixels) == 0 {
		return 0
	}

	tex_id := upload_texture_rgba(width, height, data)
	if tex_id == 0 {
		return 0
	}

	cache.textures[strings.clone(key, allocator)] = tex_id
	return tex_id
}

load_texture_from_file_bytes :: proc(
	cache: ^TextureCache,
	key: string,
	bytes: []u8,
	allocator := context.allocator,
) -> u32 {
	if tex_id, ok := cache.textures[key]; ok {
		return tex_id
	}

	width, height, channels_in_file: c.int
	data := stbi.load_from_memory(raw_data(bytes), c.int(len(bytes)), &width, &height, &channels_in_file, 4)
	if data == nil {
		fmt.printf("stbi: failed to decode embedded texture %s\n", key)
		return 0
	}
	defer stbi.image_free(data)

	tex_id := upload_texture_rgba(width, height, data)
	if tex_id == 0 {
		return 0
	}

	cache.textures[strings.clone(key, allocator)] = tex_id
	return tex_id
}
