import std/[asyncnet, asyncdispatch, streams, strformat]
import types/types

import pkg/uuids

type
  PacketHandshake* = object
    protVer*: int
    servAddr*: string
    servPort*: uint16
    nextState*: ConnectionState
  
  PacketLoginStart* = object
    name*: string
  
  PacketStatusPing* = object
    val*: int64
    
  PacketKind* = enum
    Handshake, 
    
    LoginStart, 
    
    StatusRequest, StatusResponse, StatusPing,

    KeepAlive
  
  # Packets send from the client to the server
  Packet* = object
    case kind*: PacketKind
    of Handshake:
      handshake*: PacketHandshake
    of LoginStart:
      loginStart*: PacketLoginStart
    of KeepAlive:
      keepalive*: PacketKeepalive
    of StatusResponse:
      # no fields there
      discard
    of StatusPing:
      ping*: PacketStatusPing
    else:
      discard
  
  # Both clientbount and serverbound
  PacketLoginSuccess* = object
    uuid*: UUID
    username*: string
  
  PacketKeepalive* = object
    id*: int64

template readVarAux(numBytes: int): untyped {.dirty.} = 
  var 
    shift = 0

  var temp = await s.recv(1)
  #echo "reading stuff - ", cast[seq[char]](temp)
  var b = temp[0].ord.int8
  result = result or ((b and 0x7F) shl shift)
  shift += 7
  while (b and 0x80) != 0:
    # Should really almost never happen
    if unlikely(shift == numBytes * 7):
      # TODO: Use stew/result ?
      raise newException(ValueError, "VarInt longer than 5 bytes!")
    temp = await s.recv(1)
    b = temp[0].ord.int8
    result = result or ((b and 0x7F) shl shift)
    shift += 7

proc readVarInt*(s: AsyncSocket): Future[int32] {.async.} = 
  readVarAux(5)

proc readVarLong*(s: AsyncSocket): Future[int64] {.async.} = 
  readVarAux(10)

proc readHandshakePkt(s: StringStream): PacketHandshake = 
  result.protVer = int s.readVarint()
  result.servAddr = s.readString()
  result.servPort = s.readUint16()
  let state = s.readVarint()
  result.nextState = ConnectionState(state)

proc readLoginStartPkt*(s: StringStream): PacketLoginStart = 
  result.name = s.readString()

proc readKeepalivePkt*(s: StringStream): PacketKeepalive = 
  result.id = s.readVarLong()

proc readPacket*(s: AsyncSocket, state: ConnectionState): Future[Packet] {.async.} = 
  echo "Reading packet.."
  let len = await s.readVarint()
  echo fmt"Got len {len}, reading data..."
  let stream = newStringStream(await s.recv(len.int))
  let pktId = int stream.readVarint()
  case state
  of Handshaking:
    echo fmt"Got handshake pktId {pktId}"
    case pktId
    of 0x00:
      let pkt = stream.readHandshakePkt()
      result = Packet(kind: Handshake, handshake: pkt)
    else:
      echo fmt"Don't know how to receive a packet of id {pktId}, state {state}"
  of Status:
    echo fmt"Got status pktId {pktId}"
    case pktId
    of 0x00:
      result = Packet(kind: StatusRequest)
    of 0x01:
      let val = stream.readVarLong()
      echo "Ping val is ", val
      result = Packet(kind: StatusPing, ping: PacketStatusPing(val: val))
    else:
      echo fmt"Don't know how to receive a packet of id {pktId}, state {state}"
  of Login:
    echo fmt"Got login pktId {pktId}"
    case pktId
    of 0x00:
      let pkt = stream.readLoginStartPkt()
      result = Packet(kind: LoginStart, loginStart: pkt)
    else:
      echo fmt"Don't know how to receive a packet of id {pktId}, state {state}"
  of Play:
    echo fmt"Got play pktId {pktId}"
    case pktId
    of 0x10:
      let pkt = stream.readKeepalivePkt()
      result = Packet(kind: KeepAlive, keepalive: pkt)
    else:
      echo fmt"Don't know how to receive a packet of id {pktId}, state {state}"

proc packAndSendPacket(sock: AsyncSocket, strm: StringStream, pktId: uint8) {.async.} = 
  # I know that this stuff is ugly...
  strm.setPosition(0)

  var body = newStringStream()
  # write packet id
  body.writeVarint(int32 pktId)
  # write data itself
  body.write(strm.readAll())
  body.setPosition(0)
  let bodyData = body.readAll()
  
  var final = newStringStream()
  # write length of data + length of packet id
  final.writeVarint(int32(bodyData.len))
  #final.setPosition(0)
  #echo "Read length: ", final.readVarInt()
  # write whole body
  final.write(bodyData)
  final.setPosition(0)

  let resp = final.readAll()
  echo cast[seq[uint8]](resp)
  echo "Full total length: ", resp.len
  echo "Sending data..."
  await sock.send resp
  echo "Done sending data!"

proc sendPacket*(s: AsyncSocket, pkt: PacketLoginSuccess) {.async.} = 
  # https://wiki.vg/Protocol#Login_Success
  var strm = newStringStream()
  strm.write pkt.uuid.mostSigBits()
  strm.write pkt.uuid.leastSigBits()
  #strm.writeVarInt int32 pkt.username.len
  #strm.write(pkt.username)
  strm.writeString(pkt.username)
  
  await s.packAndSendPacket(strm, 0x02)

proc sendServerKeepalive*(s: AsyncSocket, pkt: PacketKeepalive) {.async.} = 
  # https://wiki.vg/Protocol#Keep_Alive_.28clientbound.29
  var strm = newStringStream()
  strm.writeVarLong(int64(pkt.id))

  await s.packAndSendPacket(strm, 0x1F)

proc sendClientKeepalive*(s: AsyncSocket, pkt: PacketKeepalive) {.async.} = 
  # https://wiki.vg/Protocol#Keep_Alive_.28clientbound.29
  var strm = newStringStream()
  strm.writeVarLong(int64(pkt.id))

  await s.packAndSendPacket(strm, 0x10)

proc sendStatusResponse*(s: AsyncSocket, data: string) {.async.} = 
  # https://wiki.vg/Protocol#Keep_Alive_.28clientbound.29
  echo "Sending status response..."
  var strm = newStringStream()
  strm.writeString(data)

  await s.packAndSendPacket(strm, 0x00)

proc sendStatusPong*(s: AsyncSocket, val: int64) {.async.} = 
  # https://wiki.vg/Protocol#Keep_Alive_.28clientbound.29
  echo "Sending status pong..."
  var strm = newStringStream()
  strm.writeVarLong(int64(val))

  await s.packAndSendPacket(strm, 0x01)

proc sendSpawnPosition*(s: AsyncSocket) {.async.} = 
  var strm = newStringStream()
  strm.writePosition(0, 0, 0)

  await s.packAndSendPacket(strm, 0x42)

proc sendPlayerPositionAndLook*(s: AsyncSocket) {.async.} = 
  var strm = newStringStream()
  strm.writeDouble(0) # x
  strm.writeDouble(0) # y
  strm.writeDouble(0) # z
  strm.writeFloat(0) # yaw
  strm.writeFloat(0) # pitch
  strm.write(0'u8) # flags
  strm.writeVarInt(1337) # teleport id

  await s.packAndSendPacket(strm, 0x34) 

proc sendJoinGame*(s: AsyncSocket) {.async.} = 
  var strm = newStringStream()

  strm.writeInt(1337) # player eid
  strm.write(0'u8) # is hardcore
  strm.write(0'u8) # gamemode - survival
  strm.write(-1'i8) # previous gamemode
  strm.writeVarInt(1) # world count
  strm.writeString("test") # world name
  # dimension codec
  # dimension
  strm.writeString("test") # world the player is spawned into
  strm.writeLong(0) # first 8 bytes of the sha256 of the world seed
  strm.writeVarInt(0) # unused, max players
  strm.writeVarInt(16) # view distance
  strm.write(0'u8) # is reduced debug
  strm.write(1'u8) # enable respawn screen
  strm.write(0'u8) # is debug world
  strm.write(0'u8) # is flat world
