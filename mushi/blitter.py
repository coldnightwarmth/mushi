"""Parse CV1000 command lists, preserving original coordinates and attributes."""
import struct


def commands(ram: bytes, address: int, *, base: int = 0x0c000000):
    cursor = (address & 0x1fffffff) - base
    if not 0 <= cursor < len(ram):
        raise ValueError("Command list is outside captured RAM")
    for _ in range(100000):
        if cursor + 2 > len(ram):
            raise ValueError("Unterminated command list")
        op = struct.unpack_from(">H", ram, cursor)[0] >> 12
        start = cursor
        if op in (0, 15):
            return
        if op == 12:
            if cursor + 4 > len(ram):
                raise ValueError("Truncated clip command")
            yield dict(kind="clip", address=base+cursor, enabled=bool(struct.unpack_from(">H",ram,cursor+2)[0]))
            cursor += 4
        elif op in (1, 2):
            length = 20 if op == 1 else 16
            if cursor + length > len(ram):
                raise ValueError("Truncated graphics command")
            words = struct.unpack_from(">" + "H"*(length//2), ram, cursor)
            width, height = (words[6] & 8191)+1, (words[7] & 4095)+1
            command = dict(kind="draw" if op==1 else "upload",address=base+cursor,words=list(words),
                           width=width,height=height,dst_x=words[4],dst_y=words[5])
            if op == 1:
                command.update(src_x=words[2]&8191,src_y=words[3]&4095,attributes=words[0],alpha=words[1])
                cursor += 20
            else:
                cursor += 16+width*height*2
                if cursor > len(ram):
                    raise ValueError("Upload pixels extend beyond RAM")
            yield command
        else:
            raise ValueError(f"Unknown blitter command {op:x} at {base+start:#x}")
    raise ValueError("Command count exceeds limit")
