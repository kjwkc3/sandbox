package png

import "core:c"
import "core:encoding/endian"
import "core:fmt"
import "core:hash"
import "core:mem"
import "core:os"
import zlib "vendor:zlib"

PNG_SIGNATURE :: []u8{0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A}

IHDR_TYPE :: []u8{'I', 'H', 'D', 'R'}
IDAT_TYPE :: []u8{'I', 'D', 'A', 'T'}
IEND_TYPE :: []u8{'I', 'E', 'N', 'D'}

ColorType :: enum u8 {
	GRAY       = 0,
	RGB        = 2,
	PALETTE    = 3,
	GRAY_ALPHA = 4,
	RGBA       = 6,
}

write_u32_be :: proc(buf: []u8, val: u32) {
	endian.unchecked_put_u32be(buf, val)
}

chunk_crc :: proc(chunk_type, data: []u8) -> u32 {
	crc := hash.crc32(chunk_type)
	if len(data) > 0 {
		crc = hash.crc32(data, crc)
	}
	return crc
}

write_chunk :: proc(f: ^os.File, chunk_type, data: []u8) {
	len_buf := [4]u8{}
	write_u32_be(len_buf[:], u32(len(data)))
	os.write(f, len_buf[:])
	os.write(f, chunk_type)
	if len(data) > 0 {
		os.write(f, data)
	}
	crc_buf := [4]u8{}
	write_u32_be(crc_buf[:], chunk_crc(chunk_type, data))
	os.write(f, crc_buf[:])
}

deflate_compress :: proc(data: []u8) -> []u8 {
	stream: zlib.z_stream
	mem.zero(&stream, size_of(zlib.z_stream))

	stream.next_in = raw_data(data)
	stream.avail_in = c.uint(len(data))

	estimate := zlib.compressBound(c.ulong(len(data)))
	compressed := make([]u8, int(estimate))
	stream.next_out = raw_data(compressed)
	stream.avail_out = c.uint(estimate)

	rc := zlib.deflateInit(&stream, zlib.DEFAULT_COMPRESSION)
	if rc != zlib.OK {
		delete(compressed)
		return nil
	}
	defer zlib.deflateEnd(&stream)

	rc = zlib.deflate(&stream, zlib.FINISH)
	if rc != zlib.STREAM_END {
		delete(compressed)
		return nil
	}

	actual_size := int(stream.total_out)
	return compressed[:actual_size]
}

write_png :: proc(path: string, pixels: []u8, width, height: int) -> bool {
	f, err := os.open(path, os.O_WRONLY | os.O_CREATE | os.O_TRUNC)
	if err != nil {
		fmt.println("Failed to create PNG file:", path)
		return false
	}
	defer os.close(f)

	os.write(f, PNG_SIGNATURE)

	ihdr_data := make([]u8, 13)
	defer delete(ihdr_data)
	write_u32_be(ihdr_data[0:4], u32(width))
	write_u32_be(ihdr_data[4:8], u32(height))
	ihdr_data[8] = 8
	ihdr_data[9] = u8(ColorType.RGBA)
	ihdr_data[10] = 0
	ihdr_data[11] = 0
	ihdr_data[12] = 0
	write_chunk(f, IHDR_TYPE, ihdr_data)

	stride := width * 4
	filtered := make([]u8, (stride + 1) * height)
	defer delete(filtered)

	for y in 0 ..< height {
		dst := y * (stride + 1)
		filtered[dst] = 0
		src := y * stride
		for x in 0 ..< stride {
			filtered[dst + 1 + x] = pixels[src + x]
		}
	}

	compressed := deflate_compress(filtered)
	defer delete(compressed)

	write_chunk(f, IDAT_TYPE, compressed)

	write_chunk(f, IEND_TYPE, nil)

	return true
}
