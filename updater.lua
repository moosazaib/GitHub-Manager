local utils = require("utils")

local updater = {}

updater.config = {
  CURRENT_VERSION = "1.0",
  VERSION_URL = "https://raw.githubusercontent.com/moosazaib/GitHub-Manager/main/virgin.txt",
  WHATSNEW_URL = "https://raw.githubusercontent.com/moosazaib/GitHub-Manager/main/what's%20new.txt",
  ZIP_URL = "https://github.com/moosazaib/GitHub-Manager/archive/refs/heads/main.zip",
  TARGET_PATH = "/storage/self/primary/解说/Plugins/GitHub Manager/",
  MAIN_FILE = "main.lua",
  UPDATER_FILE = "updater.lua",
  EXCLUDE_FILES = {
    ["virgin.txt"] = true,
    ["what's new.txt"] = true
  }
}

local Handler = luajava.bindClass("android.os.Handler")
local Looper = luajava.bindClass("android.os.Looper")
local Toast = luajava.bindClass("android.widget.Toast")
local URL = luajava.bindClass("java.net.URL")
local BufferedReader = luajava.bindClass("java.io.BufferedReader")
local InputStreamReader = luajava.bindClass("java.io.InputStreamReader")
local File = luajava.bindClass("java.io.File")
local FileOutputStream = luajava.bindClass("java.io.FileOutputStream")
local FileInputStream = luajava.bindClass("java.io.FileInputStream")
local ZipInputStream = luajava.bindClass("java.util.zip.ZipInputStream")
local Executors = luajava.bindClass("java.util.concurrent.Executors")
local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local ScrollView = luajava.bindClass("android.widget.ScrollView")
local TextView = luajava.bindClass("android.widget.TextView")
local Button = luajava.bindClass("android.widget.Button")
local Color = luajava.bindClass("android.graphics.Color")
local View = luajava.bindClass("android.view.View")
local Byte = luajava.bindClass("java.lang.Byte")
local StringClass = luajava.bindClass("java.lang.String")

local mainHandler = Handler(Looper.getMainLooper())
local executorService = Executors.newCachedThreadPool()

local function makeRunnable(fn)
  return luajava.createProxy("java.lang.Runnable", {
    run = function()
      fn()
    end
  })
end

local function makeOnClickListener(fn)
  return luajava.createProxy("android.view.View$OnClickListener", {
    onClick = function(v)
      fn(v)
    end
  })
end

local function runOnUI(fn)
  mainHandler.post(makeRunnable(function()
    fn()
  end))
end

local function runInBackground(fn)
  executorService.execute(makeRunnable(function()
    fn()
  end))
end

local function showToast(msg)
  runOnUI(function()
    Toast.makeText(service, msg, Toast.LENGTH_SHORT).show()
  end)
end

local function cleanHtmlContent(rawHtml)
  if not rawHtml then return nil end
  if not (rawHtml:find("<html") or rawHtml:find("<!DOCTYPE")) then
    return rawHtml
  end
  local extractedLines = {}
  for rawLinesMatch in rawHtml:gmatch('"rawLines":%s*%[(.-)%]') do
    for str in rawLinesMatch:gmatch('"([^"]-)"') do
      table.insert(extractedLines, str)
    end
  end
  if #extractedLines > 0 then
    return table.concat(extractedLines, "\n")
  end
  for codeLine in rawHtml:gmatch('class="[^"]*blob%-code[^"]*"[^>]*>(.-)</td>') do
    local cleanLine = codeLine:gsub("<[^>]+>", "")
    table.insert(extractedLines, cleanLine)
  end
  if #extractedLines > 0 then
    return table.concat(extractedLines, "\n")
  end
  local plain = rawHtml:gsub("<script.-</script>", ""):gsub("<style.-</style>", ""):gsub("<[^>]+>", "")
  return plain
end

local function fetchUrlText(urlString)
  local currentUrl = urlString
  local cacheBuster = "cb=" .. tostring(os.time()) .. tostring(math.random(1000, 9999))
  if not currentUrl:find("%?") then
    currentUrl = currentUrl .. "?" .. cacheBuster
  else
    currentUrl = currentUrl .. "&" .. cacheBuster
  end
  local lastErr = "Unknown connection error"
  for i = 1, 5 do
    local conn
    local success, res = pcall(function()
      local url = URL(currentUrl)
      conn = url.openConnection()
      conn.setRequestMethod("GET")
      conn.setConnectTimeout(8000)
      conn.setReadTimeout(8000)
      conn.setInstanceFollowRedirects(true)
      conn.setUseCaches(false)
      conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
      conn.setRequestProperty("Cache-Control", "no-cache, no-store, must-revalidate")
      conn.setRequestProperty("Pragma", "no-cache")
      conn.setRequestProperty("Expires", "0")
      local code = conn.getResponseCode()
      if code == 301 or code == 302 or code == 303 or code == 307 or code == 308 then
        local loc = conn.getHeaderField("Location")
        conn.disconnect()
        if loc then
          currentUrl = loc
          return "REDIRECT"
        end
        return nil
      end
      if code ~= 200 then
        return nil
      end
      local reader = BufferedReader(InputStreamReader(conn.getInputStream(), "UTF-8"))
      local lines = {}
      local line = reader.readLine()
      while line ~= nil do
        table.insert(lines, line)
        line = reader.readLine()
      end
      reader.close()
      return table.concat(lines, "\n")
    end)
    if conn then
      pcall(function() conn.disconnect() end)
    end
    if success then
      if res ~= "REDIRECT" then
        if res then
          return cleanHtmlContent(res)
        end
      end
    else
      lastErr = tostring(res)
    end
  end
  return nil, lastErr
end

local function downloadFile(urlString, destFile)
  local currentUrl = urlString
  local cacheBuster = "cb=" .. tostring(os.time()) .. tostring(math.random(1000, 9999))
  if not currentUrl:find("%?") then
    currentUrl = currentUrl .. "?" .. cacheBuster
  else
    currentUrl = currentUrl .. "&" .. cacheBuster
  end
  for i = 1, 5 do
    local conn
    local success, res = pcall(function()
      local url = URL(currentUrl)
      conn = url.openConnection()
      conn.setRequestMethod("GET")
      conn.setConnectTimeout(15000)
      conn.setReadTimeout(15000)
      conn.setInstanceFollowRedirects(true)
      conn.setUseCaches(false)
      conn.setRequestProperty("Cache-Control", "no-cache, no-store, must-revalidate")
      conn.setRequestProperty("Pragma", "no-cache")
      local code = conn.getResponseCode()
      if code == 301 or code == 302 or code == 303 or code == 307 or code == 308 then
        local loc = conn.getHeaderField("Location")
        conn.disconnect()
        if loc then
          currentUrl = loc
          return "REDIRECT"
        end
        return false
      end
      if code ~= 200 then
        return false
      end
      local input = conn.getInputStream()
      local output = FileOutputStream(destFile)
      local buffer = luajava.newArray(Byte.TYPE, 4096)
      local bytesRead = input.read(buffer)
      while bytesRead ~= -1 do
        output.write(buffer, 0, bytesRead)
        bytesRead = input.read(buffer)
      end
      output.close()
      input.close()
      return true
    end)
    if conn then
      pcall(function() conn.disconnect() end)
    end
    if success then
      if res ~= "REDIRECT" then
        return res == true
      end
    else
      return false
    end
  end
  return false
end

local function deleteDirectoryContents(dir)
  if not dir or not dir.exists() then return end
  local files = dir.listFiles()
  if files ~= nil then
    for i = 0, #files - 1 do
      local f = files[i]
      if f ~= nil then
        if f.isDirectory() then
          deleteDirectoryContents(f)
          f.delete()
        else
          f.delete()
        end
      end
    end
  end
end

local function extractZipExcluding(zipFile, destDir, excludeMap)
  local fis = FileInputStream(zipFile)
  local zis = ZipInputStream(fis)
  local entry = zis.getNextEntry()
  
  while entry ~= nil do
    local entryName = entry.getName()
    local slashIdx = entryName:find("/")
    if slashIdx then
      local relativePath = entryName:sub(slashIdx + 1)
      if relativePath ~= "" then
        local filename = relativePath:match("^.+/(.+)$") or relativePath
        local isExcluded = excludeMap[filename:lower()]
        local outFile = File(destDir, relativePath)
        
        if entry.isDirectory() then
          outFile.mkdirs()
        else
          if not isExcluded then
            local parent = outFile.getParentFile()
            if parent and not parent.exists() then
              parent.mkdirs()
            end
            local fos = FileOutputStream(outFile)
            local buf = luajava.newArray(Byte.TYPE, 4096)
            local len = zis.read(buf)
            while len > 0 do
              fos.write(buf, 0, len)
              len = zis.read(buf)
            end
            fos.close()
          end
        end
      end
    end
    zis.closeEntry()
    entry = zis.getNextEntry()
  end
  zis.close()
  fis.close()
end

local function updateVersionInFile(newVersion)
  updater.config.CURRENT_VERSION = newVersion
  local filePath = updater.config.TARGET_PATH .. updater.config.UPDATER_FILE
  local rf = io.open(filePath, "r")
  if rf then
    local content = rf:read("*a")
    rf:close()
    if content then
      local updatedContent = content:gsub('CURRENT_VERSION%s*=%s*["\']([^"\']+)["\']', 'CURRENT_VERSION = "' .. newVersion .. '"')
      local wf = io.open(filePath, "w")
      if wf then
        wf:write(updatedContent)
        wf:flush()
        wf:close()
      end
    end
  end
end

function updater.showErrorDialog(msg, onDismiss)
  local root = LinearLayout(service)
  root.setOrientation(LinearLayout.VERTICAL)
  root.setBackgroundColor(Color.BLACK)

  local scroll = ScrollView(service)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)
  layout.setPadding(20, 20, 20, 20)

  local tvMsg = TextView(service)
  tvMsg.setText("Error Checking Update!\n\nDetails:\n" .. tostring(msg) .. "\n\nLocal Version: " .. tostring(updater.config.CURRENT_VERSION))
  tvMsg.setTextSize(18)
  tvMsg.setTextColor(Color.RED)
  tvMsg.setPadding(0, 20, 0, 20)
  layout.addView(tvMsg)

  local btnClose = Button(service)
  btnClose.setText("Close")
  btnClose.setOnClickListener(makeOnClickListener(function()
    onDismiss()
  end))
  layout.addView(btnClose)

  scroll.addView(layout)
  root.addView(scroll)

  utils.enableBackKey(root, function()
    onDismiss()
  end)

  utils.setScreen(root)
end

function updater.showUpdateDialog(onlineVersion, whatsNewText, onDismiss)
  local root = LinearLayout(service)
  root.setOrientation(LinearLayout.VERTICAL)
  root.setBackgroundColor(Color.BLACK)

  local isDownloading = false

  utils.enableBackKey(root, function()
    if isDownloading then
      Toast.makeText(service, "Downloading in progress...", Toast.LENGTH_SHORT).show()
    else
      onDismiss()
    end
  end)

  local scroll = ScrollView(service)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)
  layout.setPadding(20, 20, 20, 20)

  local btnDismiss = Button(service)
  btnDismiss.setText("Dismiss Update Dialog")
  btnDismiss.setOnClickListener(makeOnClickListener(function()
    if not isDownloading then
      onDismiss()
    end
  end))
  layout.addView(btnDismiss)

  local titleView = TextView(service)
  titleView.setText("Update Available: v" .. onlineVersion)
  titleView.setTextSize(20)
  titleView.setTextColor(Color.GREEN)
  titleView.setPadding(0, 10, 0, 10)
  layout.addView(titleView)

  local headerWhatsNew = TextView(service)
  headerWhatsNew.setText("What's New:")
  headerWhatsNew.setTextSize(18)
  headerWhatsNew.setTextColor(Color.YELLOW)
  headerWhatsNew.setPadding(0, 10, 0, 10)
  layout.addView(headerWhatsNew)

  if whatsNewText and whatsNewText ~= "" then
    for line in whatsNewText:gmatch("[^\r\n]+") do
      local lineView = TextView(service)
      lineView.setText(line)
      lineView.setTextSize(16)
      lineView.setTextColor(Color.WHITE)
      lineView.setPadding(0, 5, 0, 5)
      layout.addView(lineView)
    end
  else
    local lineView = TextView(service)
    lineView.setText("No details provided.")
    lineView.setTextSize(16)
    lineView.setTextColor(Color.WHITE)
    layout.addView(lineView)
  end

  local btnUpdate = Button(service)
  btnUpdate.setText("Update Now")

  local btnCancel = Button(service)
  btnCancel.setText("Cancel")
  btnCancel.setVisibility(View.GONE)

  btnUpdate.setOnClickListener(makeOnClickListener(function()
    if isDownloading then return end
    isDownloading = true
    btnDismiss.setEnabled(false)
    btnUpdate.setText("Downloading...")
    btnUpdate.setEnabled(false)
    btnCancel.setVisibility(View.VISIBLE)

    runInBackground(function()
      local tempZip = File(service.getCacheDir(), "update_temp.zip")
      local success = downloadFile(updater.config.ZIP_URL, tempZip)
      
      if not success then
        isDownloading = false
        runOnUI(function()
          btnDismiss.setEnabled(true)
          btnUpdate.setText("Update Now")
          btnUpdate.setEnabled(true)
          btnCancel.setVisibility(View.GONE)
          Toast.makeText(service, "Download failed! Try again.", Toast.LENGTH_SHORT).show()
        end)
        return
      end

      local destDir = File(updater.config.TARGET_PATH)
      deleteDirectoryContents(destDir)
      
      pcall(function()
        extractZipExcluding(tempZip, destDir, updater.config.EXCLUDE_FILES)
      end)
      
      if tempZip.exists() then
        tempZip.delete()
      end

      updateVersionInFile(onlineVersion)

      runOnUI(function()
        updater.showRestartDialog()
      end)
    end)
  end))

  btnCancel.setOnClickListener(makeOnClickListener(function()
    if isDownloading then
      isDownloading = false
      btnDismiss.setEnabled(true)
      btnUpdate.setText("Update Now")
      btnUpdate.setEnabled(true)
      btnCancel.setVisibility(View.GONE)
      Toast.makeText(service, "Update canceled.", Toast.LENGTH_SHORT).show()
    end
  end))

  layout.addView(btnUpdate)
  layout.addView(btnCancel)

  scroll.addView(layout)
  root.addView(scroll)
  utils.setScreen(root)
end

function updater.showRestartDialog()
  local root = LinearLayout(service)
  root.setOrientation(LinearLayout.VERTICAL)
  root.setBackgroundColor(Color.BLACK)

  local scroll = ScrollView(service)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)
  layout.setPadding(20, 20, 20, 20)

  local tvMsg = TextView(service)
  tvMsg.setText("Update completed successfully! Please restart the extension.")
  tvMsg.setTextSize(18)
  tvMsg.setTextColor(Color.GREEN)
  tvMsg.setPadding(0, 20, 0, 20)
  layout.addView(tvMsg)

  local btnRestart = Button(service)
  btnRestart.setText("Restart Extension")
  btnRestart.setOnClickListener(makeOnClickListener(function()
    for k, _ in pairs(package.loaded) do
      if k ~= "string" and k ~= "table" and k ~= "math" and k ~= "coroutine" and k ~= "package" and k ~= "io" and k ~= "os" and k ~= "debug" and k ~= "luajava" then
        package.loaded[k] = nil
      end
    end
    pcall(function()
      utils.closeExtension()
    end)
    mainHandler.postDelayed(makeRunnable(function()
      pcall(function()
        dofile(updater.config.TARGET_PATH .. updater.config.MAIN_FILE)
      end)
    end), 300)
  end))
  layout.addView(btnRestart)

  scroll.addView(layout)
  root.addView(scroll)

  utils.enableBackKey(root, function()
    pcall(function()
      utils.closeExtension()
    end)
  end)

  utils.setScreen(root)
end

function updater.checkUpdate(onFinished)
  showToast("Checking for updates...")
  
  runInBackground(function()
    local onlineVersionRaw, errDetail = fetchUrlText(updater.config.VERSION_URL)
    
    if not onlineVersionRaw then
      runOnUI(function()
        updater.showErrorDialog(errDetail or "Failed to fetch online version", onFinished)
      end)
      return
    end

    local onlineVersion = onlineVersionRaw:match("^%s*(.-)%s*$")
    
    if onlineVersion == updater.config.CURRENT_VERSION then
      runOnUI(function()
        showToast("No update available.")
        if onFinished then
          onFinished()
        end
      end)
    else
      local whatsNewText = fetchUrlText(updater.config.WHATSNEW_URL) or ""
      runOnUI(function()
        updater.showUpdateDialog(onlineVersion, whatsNewText, onFinished)
      end)
    end
  end)
end

return updater
