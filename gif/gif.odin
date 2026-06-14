package gif

import "core:fmt"

Writer :: struct {
    buf:       []u8,
    pos:       int,
    width:     int,
    height:    int,
    palette:   [256][3]u8,
    pal_count: int,
}

create :: proc(w, h: int, allocator := context.allocator) -> Writer {
    return Writer{
        buf = make([]u8, w * h * 4 + 65536, allocator),
        width = w,
        height = h,
    }
}

destroy :: proc(w: ^Writer, allocator := context.allocator) {
    delete(w.buf, allocator)
}

put :: proc(w: ^Writer, b: u8) {
    if w.pos < len(w.buf) {
        w.buf[w.pos] = b
        w.pos += 1
    }
}

put16 :: proc(w: ^Writer, v: u16) {
    put(w, u8(v & 0xFF))
    put(w, u8(v >> 8))
}

put_str :: proc(w: ^Writer, s: string) {
    for i in 0 ..< len(s) {
        put(w, s[i])
    }
}

Header :: proc(w: ^Writer) {
    put_str(w, "GIF89a")
}

LSD :: proc(w: ^Writer) {
    put16(w, u16(w.width))
    put16(w, u16(w.height))

    size := 1
    for size < w.pal_count { size *= 2 }
    bits: int = 0
    s := size
    for s > 2 { s >>= 1; bits += 1 }

    packed := u8(0x80 | bits)
    if bits > 0 {
        packed = u8(0x80 | (bits - 1))
    }
    put(w, packed)
    put(w, 0)
    put(w, 0)
}

GCT :: proc(w: ^Writer, count: int) {
    size := 1
    for size < count { size *= 2 }

    for i in 0 ..< size {
        if i < count {
            put(w, w.palette[i][0])
            put(w, w.palette[i][1])
            put(w, w.palette[i][2])
        } else {
            put(w, 0)
            put(w, 0)
            put(w, 0)
        }
    }
}

Netscape :: proc(w: ^Writer, loops: u16) {
    put(w, 0x21)
    put(w, 0xFF)
    put(w, 11)
    put_str(w, "NETSCAPE2.0")
    put(w, 3)
    put(w, 1)
    put16(w, loops)
    put(w, 0)
}

BuildPalette :: proc(w: ^Writer, pixels: []u8) {
    seen: [65536]bool
    w.pal_count = 0

    for i in 0 ..< len(pixels) / 4 {
        r := pixels[i * 4]
        g := pixels[i * 4 + 1]
        b := pixels[i * 4 + 2]
        key := u32(r >> 3) << 10 | u32(g >> 3) << 5 | u32(b >> 3)

        if !seen[key] && w.pal_count < 256 {
            seen[key] = true
            w.palette[w.pal_count] = [3]u8{r, g, b}
            w.pal_count += 1
        }
    }

    if w.pal_count < 2 {
        w.pal_count = 2
    }
}

find_color :: proc(w: ^Writer, r, g, b: u8) -> u8 {
    best: u8 = 0
    best_d: u32 = 0xFFFFFFFF
    for i in 0 ..< w.pal_count {
        dr := u32(r) - u32(w.palette[i][0])
        dg := u32(g) - u32(w.palette[i][1])
        db := u32(b) - u32(w.palette[i][2])
        d := dr * dr + dg * dg + db * db
        if d < best_d {
            best_d = d
            best = u8(i)
        }
    }
    return best
}

Frame :: proc(w: ^Writer, pixels: []u8, delay_cs: u16) {
    fmt.println("GIF.Frame start", w.width, "x", w.height, "pixels", len(pixels), "pos", w.pos)

    put(w, 0x21)
    put(w, 0xF9)
    put(w, 4)
    put(w, 0x00)
    put16(w, delay_cs)
    put(w, 0)
    put(w, 0)

    put(w, 0x2C)
    put16(w, 0)
    put16(w, 0)
    put16(w, u16(w.width))
    put16(w, u16(w.height))
    put(w, 0)

    min_bits: u32 = 2
    for (u32(1) << min_bits) < u32(w.pal_count) {
        min_bits += 1
    }

    indices := make([]u8, w.width * w.height)

    fmt.println("GIF.Frame index loop start", w.width * w.height)
    for i in 0 ..< w.width * w.height {
        indices[i] = find_color(w, pixels[i*4], pixels[i*4+1], pixels[i*4+2])
        if i == 0 {
            fmt.println("first index", indices[0], "first pixel", pixels[0], pixels[1], pixels[2])
        }
    }
    fmt.println("GIF.Frame index loop done")

    lzw_encode(w, indices, u8(min_bits))
    fmt.println("GIF.Frame done", w.pos)
}

Trailer :: proc(w: ^Writer) {
    put(w, 0x3B)
}

lzw_encode :: proc(w: ^Writer, data: []u8, min_code_size: u8) {
    put(w, min_code_size)

    clear := u32(1) << u32(min_code_size)
    eoi := clear + 1

    table: [4096]struct { prev: u32, byte: u8 }
    table_len := int(eoi + 1)

    bit_buf: u32 = 0
    bits_left: u32 = 0
    code_bits := u32(min_code_size) + 1
    next_code := eoi + 1

    sub: [255]u8
    sub_len := 0

    flush_sub :: proc(w: ^Writer, s: []u8, n: int) {
        if n > 0 {
            put(w, u8(n))
            for i in 0 ..< n {
                put(w, s[i])
            }
        }
    }

    flush_bits :: proc(w: ^Writer, buf: ^u32, bits: ^u32, s: []u8, sn: ^int) {
        for bits^ >= 8 {
            if sn^ == 255 {
                flush_sub(w, s, sn^)
                sn^ = 0
            }
            s[sn^] = u8(buf^ & 0xFF)
            sn^ += 1
            buf^ >>= 8
            bits^ -= 8
        }
    }

    fmt.println("LZW start", "len", len(data), "min_code_size", min_code_size, "clear", clear, "eoi", eoi, "table_len", table_len, "code_bits", code_bits)
    current := u32(data[0])

    bit_buf |= clear << bits_left
    bits_left += code_bits
    flush_bits(w, &bit_buf, &bits_left, sub[:], &sub_len)

    for i in 1 ..< len(data) {
        b := u32(data[i])
        found: bool = false
        idx: u32 = 0

        for j := eoi + 1; j < u32(table_len); j += 1 {
            if table[j].prev == current && table[j].byte == u8(b) {
                idx = j
                found = true
                break
            }
        }

        if found {
            current = idx
        } else {
            bit_buf |= current << bits_left
            bits_left += code_bits
            flush_bits(w, &bit_buf, &bits_left, sub[:], &sub_len)

            if next_code < 4096 {
                table[table_len] = {current, u8(b)}
                table_len += 1
                next_code += 1
                if next_code == (1 << code_bits) && code_bits < 12 {
                    code_bits += 1
                }
            } else {
                bit_buf |= clear << bits_left
                bits_left += code_bits
                flush_bits(w, &bit_buf, &bits_left, sub[:], &sub_len)
                table_len = int(eoi + 1)
                code_bits = u32(min_code_size) + 1
                next_code = eoi + 1
            }
            current = b
        }
    }

    bit_buf |= current << bits_left
    bits_left += code_bits
    flush_bits(w, &bit_buf, &bits_left, sub[:], &sub_len)

    bit_buf |= eoi << bits_left
    bits_left += code_bits
    flush_bits(w, &bit_buf, &bits_left, sub[:], &sub_len)

    if bits_left > 0 {
        sub[sub_len] = u8(bit_buf & 0xFF)
        sub_len += 1
        bits_left = 0
        bit_buf = 0
    }

    if sub_len > 0 {
        flush_sub(w, sub[:], sub_len)
    }
    put(w, 0)
}

Bytes :: proc(w: ^Writer) -> []u8 {
    return w.buf[:w.pos]
}
