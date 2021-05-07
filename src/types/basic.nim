import std/[streams, asyncnet, endians]

template readVarAux(maxVal: untyped): untyped {.dirty.} = 
  var 
    shift = 0

  var b = s.readInt8()
  result = result or ((b and 0x7F) shl shift)
  shift += 7
  while (b and 0x80) != 0:
    # Should really almost never happen
    if unlikely(shift == maxVal * 7):
      # TODO: Use stew/result ?
      raise newException(ValueError, "VarInt longer than 5 bytes!")
    b = s.readInt8()
    result = result or ((b and 0x7F) shl shift)
    shift += 7

proc readVarInt*(s: StringStream): int32 = 
  ## Reads a VarInt from a stream `s`
  readVarAux(5)

proc readVarLong*(s: StringStream): int64 = 
  ## Reads a VarLong from a stream `s`
  readVarAux(10)

# https://github.com/SolitudeSF/runeterra_decks/blob/master/src/runeterra_decks/codes.nim#L34
template writeVarAux(T: typedesc): untyped {.dirty.} = 
  if val.T == 0:
    s.write(0.byte)
    inc result
  else:
    var value = val.T

    while value != 0:
      var byteVal = value and 0x7F
      value = value shr 7

      if value != 0:
        byteVal = byteVal or 0x80

      s.write(byteVal.byte)
      inc result

proc writeVarInt*(s: StringStream, val: int32): int {.discardable.} =
  ## Writes a VarInt of `val` to a stream `s`. Returns the number of
  ## bytes written
  writeVarAux(uint32)

proc writeVarLong*(s: StringStream, val: int64): int {.discardable.} =
  ## Writes a VarLong of `val` to a stream `s`. Returns the number of
  ## bytes written
  writeVarAux(uint64)

proc readString*(s: StringStream): string =
  ## Reads a string from a stream `s`
  let sz = s.readVarint().int
  result = s.readStr(sz)

proc writeString*(s: StringStream, str: string) =
  ## Writes a string `str` into a stream `s`
  s.writeVarint(int32 str.len)
  s.write(str)

import stew/endians2
const shouldSwap = cpuEndian == littleEndian

proc writePosition*(s: StringStream, x, y, z: int) = 
  let val: uint64 = ((x.uint64 and 0x3FFFFFF'u64) shl 38) or ((z.uint64 and 0x3FFFFFF'u64) shl 12) or (y.uint64 and 0xFFF'u64)

  s.write(val.toBE())

proc writeDouble*(s: StringStream, val: float64) = 
  s.write(cast[uint64](val).toBE())

proc writeFloat*(s: StringStream, val: float32) = 
  s.write(cast[uint32](val).toBE())

proc writeInt*(s: StringStream, val: int32) = 
  s.write(cast[uint32](val).toBE())

proc writeLong*(s: StringStream, val: int64) = 
  s.write(cast[uint64](val).toBE())

var strm = newStringStream()
strm.writeVarInt(27)
strm.setPosition(0)

let len = strm.readVarInt()
echo "Len: ", len


# @[27, 2, 147, 77, 225, 97, 160, 224, 0, 167, 81, 156, 56, 154, 116, 108, 127, 177, 9, 89, 97, 114, 100, 97, 110, 105, 99, 111]
# @[27, 2, 239, 75, 196, 35, 140, 56, 109, 45, 157, 128, 54, 167, 68, 177, 174, 167, 9, 89, 97, 114, 100, 97, 110, 105, 99, 111]

# length varint - len 1, val 27

# packet id varint - len 1, val 2

# body - 26:
# uuid len 16, val xxx
# username len + string - len 10, val 1 + yardanico

