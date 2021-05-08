import std/[asyncnet, asyncdispatch, strformat, random, json, base64, streams, strutils, parsecfg]

import types/types
import packet

import pkg/uuids

type
  Player = ref object
    name: string
    uuid: UUID
    conn: AsyncSocket
    state: ConnectionState

proc faviconTo64(): string =
    let strm = newFileStream("favicon.png")
    let data = encode(strm.readAll)
    result = "data:image/png;base64," & data

let favicon = faviconTo64()
var players {.threadvar.}: seq[Player]
var conf = loadConfig("server.cfg")

proc startInteraction(pl: Player) {.async.} =
  while true:
    case pl.state
    of Handshaking:
      echo "Doing handshake.."
      let pkt = await readPacket(pl.conn, pl.state)
      echo pkt
      let hs = pkt.handshake
      pl.state = hs.nextState
    
    of Status:
      echo "Doing status..."
      let pkt = await readPacket(pl.conn, pl.state)
      echo pkt
      case pkt.kind
      of StatusRequest:
        let resp = $ %*{
          "version": {
            "name": "1.16.5",
            "protocol": 754
          },
          "players": {
            "max": conf.getSectionValue("Server", "max_players", "64").parseInt,
            "online": 0,
            "sample": [
              {
                "name": "thinkofdeath",
                "id": "4566e69f-c907-48ee-8d71-d7ba5aa00d20"
              }
            ]
          },
          "description": {
            "text": conf.getSectionValue("Server", "motd", "<unknow>")
          },
          "favicon": favicon
        }
        #echo resp
        await pl.conn.sendStatusResponse(resp)
      of StatusPing:
        echo "Got ping: ", pkt.ping.val
        await pl.conn.sendStatusPong(pkt.ping.val)
        # Close the connection
        pl.conn.close()
        # Exit the loop
        break
        #players.del
      else:
        echo fmt"Didn't handle the packet of kind {pkt.kind}, current state {pl.state}"

    of Login:
      echo "Handling login..."
      let pkt = await readPacket(pl.conn, pl.state)
      echo pkt
      let ls = pkt.loginStart
      pl.name = ls.name
      pl.uuid = genUUID()

      echo pl.name
      echo pl.uuid

      echo "Sending login success..."
      await pl.conn.sendPacket PacketLoginSuccess(
        uuid: pl.uuid,
        username: pl.name
      )
      echo "Switching state..."
      # Switch state to Play
      pl.state = Play
      #await sleepAsync(15000)
      await pl.conn.sendSpawnPosition()
      await pl.conn.sendPlayerPositionAndLook()

      # Enable clientbound keep-alive
      let kacb = proc (fd: AsyncFd): bool {.closure.} = 
        asyncCheck pl.conn.sendServerKeepalive PacketKeepalive(
          id: int64 rand(1 .. 1000000)
        )
        result = false # we want to be called again
      
      addTimer(10000, false, kacb)
    
    of Play:
      let pkt = await readPacket(pl.conn, pl.state)
      case pkt.kind
      of KeepAlive:
        # We must answer with the same packet
        await pl.conn.sendClientKeepalive(pkt.keepalive)
      else:
        echo fmt"Didn't handle the packet of kind {pkt.kind}, current state {pl.state}"


proc connWrapper(pl: Player) {.async.} = 
  try:
    await pl.startInteraction()
  except:
    echo getCurrentExceptionMsg()
    echo getStackTrace()

var server = newAsyncSocket()

proc chook {.noconv.} = 
  echo "Ok, bye..."
  try:
    for pl in players:
      pl.conn.close()
    server.close()
  except:
    discard

proc serve() {.async.} =
  echo "Init server..."
  
  setControlCHook(chook)
  
  echo "Bind to port " & $((conf.getSectionValue("Server","port")).parseInt) & "..."
  server.bindAddr(Port((conf.getSectionValue("Server","port")).parseInt))
  echo "Start listen..."
  server.listen()

  echo "Done."

  while true:
    let client = await server.accept()
    var player = Player(conn: client, state: Handshaking)
    players.add player
    
    asyncCheck player.connWrapper()

asyncCheck serve()
runForever()