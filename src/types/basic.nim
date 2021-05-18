import std/[streams, asyncnet, endians]

# template readVarAux(maxVal: untyped): untyped {.dirty.} = 
#   var 
#     numRead = 0

#   var b = s.readInt8()
#   result = result or ((b.uint8 and 0b01111111).int32 shl (numRead * 7))
#   numRead += 1
#   while (b.uint8 and 0b10000000) != 0:
#     # Should really almost never happen
#     if unlikely(numRead == maxVal):
#       # TODO: Use stew/result ?
#       raise newException(ValueError, "VarInt longer than " & $maxVal & " bytes!")
#     b = s.readInt8()
#     result = result or ((b.uint8 and 0b01111111).int32 shl (numRead * 7))
#     numRead += 1

proc readVarInt*(s: StringStream): int32 = 
  ## Reads a VarInt from a stream `s`
  var 
    numRead = 0

  var b = s.readInt8()
  result = result or ((b.uint8 and 0b01111111).int32 shl (numRead * 7))
  numRead += 1
  while (b.uint8 and 0b10000000) != 0:
    # Should really almost never happen
    if unlikely(numRead == 5):
      # TODO: Use stew/result ?
      raise newException(ValueError, "VarInt longer than 5 bytes!")
    b = s.readInt8()
    result = result or ((b.uint8 and 0b01111111).int32 shl (numRead * 7))
    numRead += 1

proc readVarLong*(s: StringStream): int64 = 
  ## Reads a VarLong from a stream `s`
  var 
    numRead = 0

  var b = s.readInt8()
  result = result or ((b.uint8 and 0b01111111).int64 shl (numRead * 7))
  numRead += 1
  while (b.uint8 and 0b10000000) != 0:
    # Should really almost never happen
    if unlikely(numRead == 10):
      # TODO: Use stew/result ?
      raise newException(ValueError, "VarInt longer than 10 bytes!")
    b = s.readInt8()
    result = result or ((b.uint8 and 0b01111111).int64 shl (numRead * 7))
    numRead += 1

# https://github.com/SolitudeSF/runeterra_decks/blob/master/src/runeterra_decks/codes.nim#L34
template writeVarAux(T: typedesc): untyped {.dirty.} = 
  if val.T == 0:
    s.write(0.byte)
    inc result
  else:
    var value = val.T

    while value != 0:
      var byteVal = value and 0b01111111
      value = value shr 7

      if value != 0:
        byteVal = byteVal or 0b10000000

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

proc readLong*(s: StringStream): int64 =
  result = s.readUint64().fromBE().int64

# var strm = newStringStream()
# strm.writeVarInt(27)
# strm.setPosition(0)

# let len = strm.readVarInt()
# echo "Len: ", len


# @[27, 2, 147, 77, 225, 97, 160, 224, 0, 167, 81, 156, 56, 154, 116, 108, 127, 177, 9, 89, 97, 114, 100, 97, 110, 105, 99, 111]
# @[27, 2, 239, 75, 196, 35, 140, 56, 109, 45, 157, 128, 54, 167, 68, 177, 174, 167, 9, 89, 97, 114, 100, 97, 110, 105, 99, 111]

# length varint - len 1, val 27

# packet id varint - len 1, val 2

# body - 26:
# uuid len 16, val xxx
# username len + string - len 10, val 1 + yardanico

