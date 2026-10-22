local utils = require("utils")
local tokenModule = require("token_module")

local Handler = Handler or luajava.bindClass("android.os.Handler")
local Looper = Looper or luajava.bindClass("android.os.Looper")
local Runnable = Runnable or luajava.bindClass("java.lang.Runnable")
local Toast = Toast or luajava.bindClass("android.widget.Toast")
local CheckBox = luajava.bindClass("android.widget.CheckBox")
local Uri = luajava.bindClass("android.net.Uri")
local DownloadManager = luajava.bindClass("android.app.DownloadManager")
local Environment = luajava.bindClass("android.os.Environment")
local Long = luajava.bindClass("java.lang.Long")
local Byte = Byte or luajava.bindClass("java.lang.Byte")
local System = System or luajava.bindClass("java.lang.System")
local Array = luajava.bindClass("java.lang.reflect.Array")
local File = luajava.bindClass("java.io.File")
local FileInputStream = luajava.bindClass("java.io.FileInputStream")
local FileOutputStream = luajava.bindClass("java.io.FileOutputStream")
local ByteArrayOutputStream = luajava.bindClass("java.io.ByteArrayOutputStream")
local AlertDialog = luajava.bindClass("android.app.AlertDialog")
local DialogInterface = luajava.bindClass("android.content.DialogInterface")
local WindowManager = luajava.bindClass("android.view.WindowManager")
local Thread = luajava.bindClass("java.lang.Thread")
local URL = luajava.bindClass("java.net.URL")
local HttpURLConnection = luajava.bindClass("java.net.HttpURLConnection")
local KeyEvent = KeyEvent or luajava.bindClass("android.view.KeyEvent")

local releasesModule = {}

local function formatSize(bytes)
  local b = tonumber(bytes) or 0
  if b <= 0 then
    return "0 B"
  elseif b < 1024 then
    return b .. " B"
  elseif b < (1024 * 1024) then
    return string.format("%.2f KB", b / 1024)
  elseif b < (1024 * 1024 * 1024) then
    return string.format("%.2f MB", b / (1024 * 1024))
  else
    return string.format("%.2f GB", b / (1024 * 1024 * 1024))
  end
end

local function httpRequestWithTimeout(loadingText, url, method, data, callback, fallbackScreen)
  if loadingText then
    utils.showLoading(loadingText)
  end
  local isCompleted = false
  local handler = Handler(Looper.getMainLooper())

  local timeoutRunnable = Runnable({
    run = function()
      if not isCompleted then
        isCompleted = true
        Toast.makeText(service, "Internet error: Request timed out", Toast.LENGTH_SHORT).show()
        if fallbackScreen then
          fallbackScreen()
        end
      end
    end
  })

  handler.postDelayed(timeoutRunnable, 30000)

  utils.httpRequest(url, method, data, function(code, res)
    if not isCompleted then
      isCompleted = true
      handler.removeCallbacks(timeoutRunnable)
      callback(code, res)
    end
  end)
end

local function startDownloadAssetFile(urlStr, saveFileName, knownTotalSize, onCancel, onSuccess)
  local isCancelled = false
  local handler = Handler(Looper.getMainLooper())
  local checkProgressRunnable
  local activeCancelDialog = nil

  local root = LinearLayout(service)
  root.setOrientation(LinearLayout.VERTICAL)
  root.setBackgroundColor(Color.BLACK)
  root.setPadding(20, 20, 20, 20)

  local scroll = ScrollView(service)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)

  layout.addView(utils.createHeader("Downloading Asset"))

  local txtFile = TextView(service)
  txtFile.setText("File: " .. saveFileName)
  txtFile.setTextColor(Color.WHITE)
  txtFile.setPadding(0, 10, 0, 10)
  layout.addView(txtFile)

  local btnStatus = Button(service)
  btnStatus.setText("Downloading...")
  btnStatus.setEnabled(false)
  layout.addView(btnStatus)

  local downloadManager = service.getSystemService(Context.DOWNLOAD_SERVICE)
  local downloadId = -1

  pcall(function()
    local request = DownloadManager.Request(Uri.parse(urlStr))
    request.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
    request.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, saveFileName)
    request.addRequestHeader("User-Agent", "GitHubManagerApp")
    request.addRequestHeader("Accept", "application/octet-stream")

    local savedToken = ""
    pcall(function() savedToken = utils.loadToken() end)
    if savedToken and savedToken:match("%S") then
      request.addRequestHeader("Authorization", "token " .. savedToken:match("^%s*(.-)%s*$"))
    end

    downloadId = downloadManager.enqueue(request)
  end)

  if downloadId == -1 then
    Toast.makeText(service, "Failed to start download.", Toast.LENGTH_SHORT).show()
    onCancel()
    return
  end

  local function doCancelAction()
    if isCancelled then return end
    isCancelled = true

    if activeCancelDialog then
      pcall(function() activeCancelDialog.dismiss() end)
      activeCancelDialog = nil
    end

    pcall(function()
      handler.removeCallbacksAndMessages(nil)
    end)

    Thread(Runnable({
      run = function()
        pcall(function()
          downloadManager.remove(tonumber(downloadId))
        end)
        pcall(function()
          local longArray = Array.newInstance(Long.TYPE, 1)
          Array.setLong(longArray, 0, tonumber(downloadId) or 0)
          downloadManager.remove(longArray)
        end)
        Handler(Looper.getMainLooper()).post(Runnable({
          run = function()
            Toast.makeText(service, "Download cancelled.", Toast.LENGTH_SHORT).show()
            onCancel()
          end
        }))
      end
    })).start()
  end

  local function showCancelConfirmation()
    pcall(function()
      if activeCancelDialog then
        activeCancelDialog.dismiss()
        activeCancelDialog = nil
      end
      local builder = AlertDialog.Builder(service)
      builder.setTitle("Cancel Download")
      builder.setMessage("Are you sure you want to cancel the download?")
      builder.setPositiveButton("Yes", DialogInterface.OnClickListener({
        onClick = function(dialog, which)
          activeCancelDialog = nil
          pcall(function() dialog.dismiss() end)
          doCancelAction()
        end
      }))
      builder.setNegativeButton("No", DialogInterface.OnClickListener({
        onClick = function(dialog, which)
          activeCancelDialog = nil
          pcall(function() dialog.dismiss() end)
        end
      }))
      local dlg = builder.create()
      pcall(function()
        if dlg.getWindow() then
          dlg.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
        end
      end)
      activeCancelDialog = dlg
      dlg.show()
    end)
  end

  local btnCancel = Button(service)
  btnCancel.setText("Cancel Download")
  btnCancel.setOnClickListener(View.OnClickListener({
    onClick = function()
      showCancelConfirmation()
    end
  }))
  layout.addView(btnCancel)

  scroll.addView(layout)
  root.addView(scroll)

  utils.enableBackKey(root, function()
    showCancelConfirmation()
  end)

  utils.setScreen(root)

  local lastStatusStr = ""
  checkProgressRunnable = Runnable({
    run = function()
      if isCancelled then return end
      local isDone = false
      local isSuccess = false

      pcall(function()
        local query = DownloadManager.Query()
        local idArray = Array.newInstance(Long.TYPE, 1)
        Array.setLong(idArray, 0, Long(downloadId).longValue())
        query.setFilterById(idArray)

        local cursor = downloadManager.query(query)
        if cursor then
          if cursor.moveToFirst() then
            local bytesIdx = cursor.getColumnIndex(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
            local totalIdx = cursor.getColumnIndex(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
            local statusIdx = cursor.getColumnIndex(DownloadManager.COLUMN_STATUS)

            if bytesIdx == -1 then bytesIdx = cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR) end
            if totalIdx == -1 then totalIdx = cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES) end
            if statusIdx == -1 then statusIdx = cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS) end

            local bytes = cursor.getLong(bytesIdx)
            local total = cursor.getLong(totalIdx)
            local status = cursor.getInt(statusIdx)

            local numBytes = tonumber(bytes) or 0
            local numTotal = tonumber(total) or 0
            if numTotal <= 0 and knownTotalSize and tonumber(knownTotalSize) and tonumber(knownTotalSize) > 0 then
              numTotal = tonumber(knownTotalSize)
            end

            local statusStr = ""
            if numTotal > 0 then
              local pct = math.floor((numBytes / numTotal) * 100)
              if pct > 100 then pct = 100 end
              statusStr = "Downloading " .. pct .. "% (" .. formatSize(numBytes) .. " / " .. formatSize(numTotal) .. ")"
            else
              statusStr = "Downloading " .. formatSize(numBytes) .. " / Unknown"
            end

            if statusStr ~= lastStatusStr then
              lastStatusStr = statusStr
              btnStatus.setText(statusStr)
            end

            if status == DownloadManager.STATUS_SUCCESSFUL then
              isDone = true
              isSuccess = true
              if numTotal > 0 then
                btnStatus.setText("Downloading 100% (" .. formatSize(numTotal) .. " / " .. formatSize(numTotal) .. ")")
              else
                btnStatus.setText("Downloading " .. formatSize(numBytes) .. " / " .. formatSize(numBytes))
              end
            elseif status == DownloadManager.STATUS_FAILED then
              isDone = true
              isSuccess = false
            end
          end
          cursor.close()
        end
      end)

      if isCancelled then return end

      if isDone then
        pcall(function() handler.removeCallbacksAndMessages(nil) end)
        if activeCancelDialog then
          pcall(function() activeCancelDialog.dismiss() end)
          activeCancelDialog = nil
        end
        if isSuccess then
          Toast.makeText(service, "Download complete! Saved to Download folder.", Toast.LENGTH_LONG).show()
          onSuccess()
        else
          Toast.makeText(service, "Download failed.", Toast.LENGTH_SHORT).show()
          onCancel()
        end
      else
        if not isCancelled then
          handler.postDelayed(checkProgressRunnable, 200)
        end
      end
    end
  })

  handler.postDelayed(checkProgressRunnable, 100)
end

function releasesModule.showReleases(owner, repo, onOptionsBack)
  local root = LinearLayout(service)
  root.setOrientation(LinearLayout.VERTICAL)
  root.setBackgroundColor(Color.BLACK)
  root.setPadding(20, 20, 20, 20)

  local scroll = ScrollView(service)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)

  local btnTopBack = Button(service)
  btnTopBack.setText("Back to Options")
  btnTopBack.setOnClickListener(View.OnClickListener({
    onClick = function() onOptionsBack() end
  }))
  layout.addView(btnTopBack)

  layout.addView(utils.createHeader("Releases: " .. repo))

  local btnCreateRel = Button(service)
  btnCreateRel.setText("Create New Release")
  btnCreateRel.setOnClickListener(View.OnClickListener({
    onClick = function()
      releasesModule.showCreateRelease(owner, repo, function()
        releasesModule.showReleases(owner, repo, onOptionsBack)
      end)
    end
  }))
  layout.addView(btnCreateRel)

  local url = "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/releases"
  httpRequestWithTimeout("Loading releases...", url, "GET", nil, function(code, res)
    if code == 200 and res then
      local releasesList = {}
      pcall(function()
        local jsonArray = JSONArray(res)
        local len = jsonArray.length()
        for i = 0, len - 1 do
          table.insert(releasesList, jsonArray.getJSONObject(i))
        end
      end)

      if #releasesList == 0 then
        local emptyTv = TextView(service)
        emptyTv.setText("No releases found.")
        emptyTv.setTextColor(Color.GRAY)
        emptyTv.setPadding(10, 20, 10, 20)
        layout.addView(emptyTv)
      else
        for _, relObj in ipairs(releasesList) do
          local relId = relObj.optInt("id", 0)
          local tagName = relObj.optString("tag_name", "No Tag")
          local name = relObj.optString("name", "")
          if name == "" or name == "null" then name = tagName end
          local isDraft = relObj.optBoolean("draft", false)
          local isPre = relObj.optBoolean("prerelease", false)

          local extraTag = ""
          if isDraft then extraTag = extraTag .. " [Draft]" end
          if isPre then extraTag = extraTag .. " [Pre-release]" end

          local btnRel = Button(service)
          btnRel.setText(name .. " (" .. tagName .. ")" .. extraTag)
          btnRel.setTextColor(Color.WHITE)
          btnRel.setOnClickListener(View.OnClickListener({
            onClick = function()
              releasesModule.showReleaseDetails(owner, repo, relObj, function()
                releasesModule.showReleases(owner, repo, onOptionsBack)
              end)
            end
          }))
          layout.addView(btnRel)
        end
      end
    else
      Toast.makeText(service, "Failed to load releases.", Toast.LENGTH_SHORT).show()
    end

    scroll.addView(layout)
    root.addView(scroll)
    utils.enableBackKey(root, function() onOptionsBack() end)
    utils.setScreen(root)
  end, function() onOptionsBack() end)
end

function releasesModule.showCreateRelease(owner, repo, onBack)
  local cRoot = LinearLayout(service)
  cRoot.setOrientation(LinearLayout.VERTICAL)
  cRoot.setBackgroundColor(Color.BLACK)
  cRoot.setPadding(20, 20, 20, 20)

  local cScroll = ScrollView(service)
  local cLayout = LinearLayout(service)
  cLayout.setOrientation(LinearLayout.VERTICAL)

  local btnTopBack = Button(service)
  btnTopBack.setText("Back to Releases")
  btnTopBack.setOnClickListener(View.OnClickListener({
    onClick = function() onBack() end
  }))
  cLayout.addView(btnTopBack)

  cLayout.addView(utils.createHeader("Create Release"))

  local inputTag = EditText(service)
  inputTag.setHint("Tag Name e.g. v1.0.0 (Required)")
  inputTag.setTextColor(Color.WHITE)
  inputTag.setHintTextColor(Color.GRAY)
  cLayout.addView(inputTag)

  local inputTitle = EditText(service)
  inputTitle.setHint("Release Title (Optional)")
  inputTitle.setTextColor(Color.WHITE)
  inputTitle.setHintTextColor(Color.GRAY)
  cLayout.addView(inputTitle)

  local inputDesc = EditText(service)
  inputDesc.setHint("Release Description / Notes")
  inputDesc.setTextColor(Color.WHITE)
  inputDesc.setHintTextColor(Color.GRAY)
  cLayout.addView(inputDesc)

  local cbDraft = CheckBox(service)
  cbDraft.setText("Set as Draft")
  cbDraft.setTextColor(Color.WHITE)
  cLayout.addView(cbDraft)

  local cbPre = CheckBox(service)
  cbPre.setText("Set as Pre-release")
  cbPre.setTextColor(Color.WHITE)
  cLayout.addView(cbPre)

  local btnSubmit = Button(service)
  btnSubmit.setText("Publish Release")
  btnSubmit.setOnClickListener(View.OnClickListener({
    onClick = function()
      local tag = tostring(inputTag.getText()):match("^%s*(.-)%s*$")
      if tag == "" then
        Toast.makeText(service, "Tag name is required!", Toast.LENGTH_SHORT).show()
        return
      end
      local title = tostring(inputTitle.getText()):match("^%s*(.-)%s*$")
      local desc = tostring(inputDesc.getText())

      local bodyObj = JSONObject()
      bodyObj.put("tag_name", tag)
      if title ~= "" then bodyObj.put("name", title) end
      bodyObj.put("body", desc)
      bodyObj.put("draft", cbDraft.isChecked())
      bodyObj.put("prerelease", cbPre.isChecked())

      local url = "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/releases"
      httpRequestWithTimeout("Creating release...", url, "POST", bodyObj.toString(), function(code, res)
        if code == 201 or code == 200 then
          Toast.makeText(service, "Release created successfully!", Toast.LENGTH_SHORT).show()
          onBack()
        else
          Toast.makeText(service, "Failed to create release.", Toast.LENGTH_SHORT).show()
        end
      end, function() onBack() end)
    end
  }))
  cLayout.addView(btnSubmit)

  cScroll.addView(cLayout)
  cRoot.addView(cScroll)
  utils.enableBackKey(cRoot, function() onBack() end)
  utils.setScreen(cRoot)
end

function releasesModule.showReleaseDetails(owner, repo, relObj, onBack)
  local relId = relObj.optInt("id", 0)
  local tagName = relObj.optString("tag_name", "")
  local name = relObj.optString("name", "")
  if name == "" or name == "null" then name = tagName end
  local body = relObj.optString("body", "")
  local isDraft = relObj.optBoolean("draft", false)
  local isPre = relObj.optBoolean("prerelease", false)
  local htmlUrl = relObj.optString("html_url", "")

  local dRoot = LinearLayout(service)
  dRoot.setOrientation(LinearLayout.VERTICAL)
  dRoot.setBackgroundColor(Color.BLACK)
  dRoot.setPadding(20, 20, 20, 20)

  local dScroll = ScrollView(service)
  local dLayout = LinearLayout(service)
  dLayout.setOrientation(LinearLayout.VERTICAL)

  local btnTopBack = Button(service)
  btnTopBack.setText("Back to Releases List")
  btnTopBack.setOnClickListener(View.OnClickListener({
    onClick = function() onBack() end
  }))
  dLayout.addView(btnTopBack)

  dLayout.addView(utils.createHeader("Release: " .. name))

  local tvInfo = TextView(service)
  local infoStr = "Tag: " .. tagName .. "\n"
  infoStr = infoStr .. "Draft: " .. tostring(isDraft) .. "\n"
  infoStr = infoStr .. "Pre-release: " .. tostring(isPre) .. "\n\n"
  if body ~= "" and body ~= "null" then
    infoStr = infoStr .. "Description:\n" .. body
  else
    infoStr = infoStr .. "No description provided."
  end
  tvInfo.setText(infoStr)
  tvInfo.setTextColor(Color.WHITE)
  tvInfo.setPadding(10, 10, 10, 10)
  dLayout.addView(tvInfo)

  local btnCopyLink = Button(service)
  btnCopyLink.setText("Copy Release Link")
  btnCopyLink.setOnClickListener(View.OnClickListener({
    onClick = function()
      if htmlUrl ~= "" then
        service.copy(htmlUrl)
        Toast.makeText(service, "Copied to clipboard", Toast.LENGTH_SHORT).show()
      else
        Toast.makeText(service, "No URL available", Toast.LENGTH_SHORT).show()
      end
    end
  }))
  dLayout.addView(btnCopyLink)

  local btnAssets = Button(service)
  btnAssets.setText("View Release Assets")
  btnAssets.setOnClickListener(View.OnClickListener({
    onClick = function()
      releasesModule.showReleaseAssets(owner, repo, relObj, function()
        releasesModule.showReleaseDetails(owner, repo, relObj, onBack)
      end)
    end
  }))
  dLayout.addView(btnAssets)

  local btnEdit = Button(service)
  btnEdit.setText("Edit Release")
  btnEdit.setOnClickListener(View.OnClickListener({
    onClick = function()
      releasesModule.showEditRelease(owner, repo, relObj, function()
        local url = "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/releases/" .. relId
        httpRequestWithTimeout("Loading release...", url, "GET", nil, function(code, res)
          if code == 200 and res then
            pcall(function()
              local updatedObj = JSONObject(res)
              releasesModule.showReleaseDetails(owner, repo, updatedObj, onBack)
            end)
          else
            releasesModule.showReleaseDetails(owner, repo, relObj, onBack)
          end
        end, function()
          releasesModule.showReleaseDetails(owner, repo, relObj, onBack)
        end)
      end)
    end
  }))
  dLayout.addView(btnEdit)

  local btnDelete = Button(service)
  btnDelete.setText("Delete Release")
  btnDelete.setTextColor(Color.RED)
  btnDelete.setOnClickListener(View.OnClickListener({
    onClick = function()
      local confRoot = LinearLayout(service)
      confRoot.setOrientation(LinearLayout.VERTICAL)
      confRoot.setBackgroundColor(Color.BLACK)
      confRoot.setPadding(20, 20, 20, 20)

      local confScroll = ScrollView(service)
      local confLayout = LinearLayout(service)
      confLayout.setOrientation(LinearLayout.VERTICAL)

      confLayout.addView(utils.createHeader("Confirm Release Deletion"))

      local confInfo = TextView(service)
      confInfo.setText("Are you sure you want to delete release '" .. name .. "'?")
      confInfo.setTextColor(Color.RED)
      confInfo.setTextSize(16)
      confInfo.setPadding(20, 20, 20, 20)
      confLayout.addView(confInfo)

      local btnConfirmDel = Button(service)
      btnConfirmDel.setText("Yes, Delete Release")
      btnConfirmDel.setOnClickListener(View.OnClickListener({
        onClick = function()
          local delUrl = "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/releases/" .. relId
          httpRequestWithTimeout("Deleting release...", delUrl, "DELETE", nil, function(dCode, dRes)
            if dCode == 204 or dCode == 200 then
              Toast.makeText(service, "Release deleted successfully!", Toast.LENGTH_SHORT).show()
              onBack()
            else
              Toast.makeText(service, "Failed to delete release.", Toast.LENGTH_SHORT).show()
              releasesModule.showReleaseDetails(owner, repo, relObj, onBack)
            end
          end, function() releasesModule.showReleaseDetails(owner, repo, relObj, onBack) end)
        end
      }))
      confLayout.addView(btnConfirmDel)

      local btnCancelDel = Button(service)
      btnCancelDel.setText("Cancel")
      btnCancelDel.setOnClickListener(View.OnClickListener({
        onClick = function()
          releasesModule.showReleaseDetails(owner, repo, relObj, onBack)
        end
      }))
      confLayout.addView(btnCancelDel)

      confScroll.addView(confLayout)
      confRoot.addView(confScroll)
      utils.enableBackKey(confRoot, function() releasesModule.showReleaseDetails(owner, repo, relObj, onBack) end)
      utils.setScreen(confRoot)
    end
  }))
  dLayout.addView(btnDelete)

  dScroll.addView(dLayout)
  dRoot.addView(dScroll)
  utils.enableBackKey(dRoot, function() onBack() end)
  utils.setScreen(dRoot)
end

function releasesModule.showEditRelease(owner, repo, relObj, onBack)
  local relId = relObj.optInt("id", 0)
  local tagName = relObj.optString("tag_name", "")
  local name = relObj.optString("name", "")
  local body = relObj.optString("body", "")
  local isDraft = relObj.optBoolean("draft", false)
  local isPre = relObj.optBoolean("prerelease", false)

  local eRoot = LinearLayout(service)
  eRoot.setOrientation(LinearLayout.VERTICAL)
  eRoot.setBackgroundColor(Color.BLACK)
  eRoot.setPadding(20, 20, 20, 20)

  local eScroll = ScrollView(service)
  local eLayout = LinearLayout(service)
  eLayout.setOrientation(LinearLayout.VERTICAL)

  local btnTopBack = Button(service)
  btnTopBack.setText("Back to Details")
  btnTopBack.setOnClickListener(View.OnClickListener({
    onClick = function() onBack() end
  }))
  eLayout.addView(btnTopBack)

  eLayout.addView(utils.createHeader("Edit Release"))

  local inputTag = EditText(service)
  inputTag.setHint("Tag Name")
  inputTag.setText(tagName)
  inputTag.setTextColor(Color.WHITE)
  inputTag.setHintTextColor(Color.GRAY)
  eLayout.addView(inputTag)

  local inputTitle = EditText(service)
  inputTitle.setHint("Release Title")
  inputTitle.setText(name)
  inputTitle.setTextColor(Color.WHITE)
  inputTitle.setHintTextColor(Color.GRAY)
  eLayout.addView(inputTitle)

  local inputDesc = EditText(service)
  inputDesc.setHint("Release Description")
  inputDesc.setText(body)
  inputDesc.setTextColor(Color.WHITE)
  inputDesc.setHintTextColor(Color.GRAY)
  eLayout.addView(inputDesc)

  local cbDraft = CheckBox(service)
  cbDraft.setText("Set as Draft")
  cbDraft.setChecked(isDraft)
  cbDraft.setTextColor(Color.WHITE)
  eLayout.addView(cbDraft)

  local cbPre = CheckBox(service)
  cbPre.setText("Set as Pre-release")
  cbPre.setChecked(isPre)
  cbPre.setTextColor(Color.WHITE)
  eLayout.addView(cbPre)

  local btnSave = Button(service)
  btnSave.setText("Save Changes")
  btnSave.setOnClickListener(View.OnClickListener({
    onClick = function()
      local newTag = tostring(inputTag.getText()):match("^%s*(.-)%s*$")
      local newTitle = tostring(inputTitle.getText()):match("^%s*(.-)%s*$")
      local newDesc = tostring(inputDesc.getText())

      local bodyObj = JSONObject()
      if newTag ~= "" then bodyObj.put("tag_name", newTag) end
      bodyObj.put("name", newTitle)
      bodyObj.put("body", newDesc)
      bodyObj.put("draft", cbDraft.isChecked())
      bodyObj.put("prerelease", cbPre.isChecked())

      local url = "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/releases/" .. relId
      httpRequestWithTimeout("Updating release...", url, "PATCH", bodyObj.toString(), function(code, res)
        if code == 200 then
          Toast.makeText(service, "Release updated successfully!", Toast.LENGTH_SHORT).show()
          onBack()
        else
          Toast.makeText(service, "Failed to update release.", Toast.LENGTH_SHORT).show()
        end
      end, function() onBack() end)
    end
  }))
  eLayout.addView(btnSave)

  eScroll.addView(eLayout)
  eRoot.addView(eScroll)
  utils.enableBackKey(eRoot, function() onBack() end)
  utils.setScreen(eRoot)
end

function releasesModule.showReleaseAssets(owner, repo, relObj, onBack)
  local relId = relObj.optInt("id", 0)
  local url = "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/releases/" .. relId

  httpRequestWithTimeout("Refreshing assets...", url, "GET", nil, function(code, res)
    local currentRelObj = relObj
    if code == 200 and res then
      pcall(function()
        currentRelObj = JSONObject(res)
      end)
    end

    local tagName = currentRelObj.optString("tag_name", "")
    local name = currentRelObj.optString("name", "")
    if name == "" or name == "null" then name = tagName end

    local aRoot = LinearLayout(service)
    aRoot.setOrientation(LinearLayout.VERTICAL)
    aRoot.setBackgroundColor(Color.BLACK)
    aRoot.setPadding(20, 20, 20, 20)

    local aScroll = ScrollView(service)
    local aLayout = LinearLayout(service)
    aLayout.setOrientation(LinearLayout.VERTICAL)

    local btnTopBack = Button(service)
    btnTopBack.setText("Back to Release Details")
    btnTopBack.setOnClickListener(View.OnClickListener({
      onClick = function() onBack() end
    }))
    aLayout.addView(btnTopBack)

    aLayout.addView(utils.createHeader("Release Assets: " .. name))

    local btnUploadAsset = Button(service)
    btnUploadAsset.setText("Upload Asset File")
    btnUploadAsset.setOnClickListener(View.OnClickListener({
      onClick = function()
        releasesModule.openAssetFilePicker(owner, repo, currentRelObj, nil, function()
          releasesModule.showReleaseAssets(owner, repo, currentRelObj, onBack)
        end)
      end
    }))
    aLayout.addView(btnUploadAsset)

    local assetsList = {}
    pcall(function()
      local jsonArray = currentRelObj.getJSONArray("assets")
      local len = jsonArray.length()
      for i = 0, len - 1 do
        table.insert(assetsList, jsonArray.getJSONObject(i))
      end
    end)

    if #assetsList == 0 then
      local emptyTv = TextView(service)
      emptyTv.setText("No assets attached to this release.")
      emptyTv.setTextColor(Color.GRAY)
      emptyTv.setPadding(10, 20, 10, 20)
      aLayout.addView(emptyTv)
    else
      for _, assetObj in ipairs(assetsList) do
        local assetName = assetObj.optString("name", "Unnamed Asset")
        local assetSize = assetObj.optLong("size", 0)
        local sizeStr = formatSize(assetSize)

        local btnAsset = Button(service)
        btnAsset.setText(assetName .. " (" .. sizeStr .. ")")
        btnAsset.setTextColor(Color.WHITE)
        btnAsset.setOnClickListener(View.OnClickListener({
          onClick = function()
            releasesModule.showAssetOptions(owner, repo, currentRelObj, assetObj, function()
              releasesModule.showReleaseAssets(owner, repo, currentRelObj, onBack)
            end)
          end
        }))
        aLayout.addView(btnAsset)
      end
    end

    aScroll.addView(aLayout)
    aRoot.addView(aScroll)
    utils.enableBackKey(aRoot, function() onBack() end)
    utils.setScreen(aRoot)
  end, function()
    onBack()
  end)
end

function releasesModule.showAssetOptions(owner, repo, relObj, assetObj, onBack)
  local relId = relObj.optInt("id", 0)
  local assetId = assetObj.optInt("id", 0)
  local assetName = assetObj.optString("name", "Unnamed Asset")
  local assetSize = assetObj.optLong("size", 0)
  local assetUrl = assetObj.optString("browser_download_url", "")
  local downloadApiUrl = assetObj.optString("url", "")
  local targetUrl = downloadApiUrl ~= "" and downloadApiUrl or assetUrl

  local oRoot = LinearLayout(service)
  oRoot.setOrientation(LinearLayout.VERTICAL)
  oRoot.setBackgroundColor(Color.BLACK)
  oRoot.setPadding(20, 20, 20, 20)

  local oScroll = ScrollView(service)
  local oLayout = LinearLayout(service)
  oLayout.setOrientation(LinearLayout.VERTICAL)

  local btnTopBack = Button(service)
  btnTopBack.setText("Back to Assets List")
  btnTopBack.setOnClickListener(View.OnClickListener({
    onClick = function() onBack() end
  }))
  oLayout.addView(btnTopBack)

  oLayout.addView(utils.createHeader("Asset: " .. assetName))

  local btnDownload = Button(service)
  btnDownload.setText("Download Asset")
  btnDownload.setOnClickListener(View.OnClickListener({
    onClick = function()
      startDownloadAssetFile(targetUrl, assetName, assetSize, function()
        onBack()
      end, function()
        onBack()
      end)
    end
  }))
  oLayout.addView(btnDownload)

  local btnCopyLink = Button(service)
  btnCopyLink.setText("Copy Direct Download Link")
  btnCopyLink.setOnClickListener(View.OnClickListener({
    onClick = function()
      if assetUrl ~= "" then
        service.copy(assetUrl)
        Toast.makeText(service, "Copied to clipboard", Toast.LENGTH_SHORT).show()
      else
        Toast.makeText(service, "No URL available", Toast.LENGTH_SHORT).show()
      end
    end
  }))
  oLayout.addView(btnCopyLink)

  local btnDelete = Button(service)
  btnDelete.setText("Delete Asset")
  btnDelete.setTextColor(Color.RED)
  btnDelete.setOnClickListener(View.OnClickListener({
    onClick = function()
      local confRoot = LinearLayout(service)
      confRoot.setOrientation(LinearLayout.VERTICAL)
      confRoot.setBackgroundColor(Color.BLACK)
      confRoot.setPadding(20, 20, 20, 20)

      local confScroll = ScrollView(service)
      local confLayout = LinearLayout(service)
      confLayout.setOrientation(LinearLayout.VERTICAL)

      confLayout.addView(utils.createHeader("Confirm Asset Deletion"))

      local confInfo = TextView(service)
      confInfo.setText("Are you sure you want to delete asset '" .. assetName .. "'?")
      confInfo.setTextColor(Color.RED)
      confInfo.setTextSize(16)
      confInfo.setPadding(20, 20, 20, 20)
      confLayout.addView(confInfo)

      local btnConfirmDel = Button(service)
      btnConfirmDel.setText("Yes, Delete Asset")
      btnConfirmDel.setOnClickListener(View.OnClickListener({
        onClick = function()
          local delUrl = "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/releases/assets/" .. assetId
          httpRequestWithTimeout("Deleting asset...", delUrl, "DELETE", nil, function(dCode, dRes)
            if dCode == 204 or dCode == 200 then
              Toast.makeText(service, "Asset deleted successfully!", Toast.LENGTH_SHORT).show()
              onBack()
            else
              Toast.makeText(service, "Failed to delete asset.", Toast.LENGTH_SHORT).show()
              releasesModule.showAssetOptions(owner, repo, relObj, assetObj, onBack)
            end
          end, function() releasesModule.showAssetOptions(owner, repo, relObj, assetObj, onBack) end)
        end
      }))
      confLayout.addView(btnConfirmDel)

      local btnCancelDel = Button(service)
      btnCancelDel.setText("Cancel")
      btnCancelDel.setOnClickListener(View.OnClickListener({
        onClick = function()
          releasesModule.showAssetOptions(owner, repo, relObj, assetObj, onBack)
        end
      }))
      confLayout.addView(btnCancelDel)

      confScroll.addView(confLayout)
      confRoot.addView(confScroll)
      utils.enableBackKey(confRoot, function() releasesModule.showAssetOptions(owner, repo, relObj, assetObj, onBack) end)
      utils.setScreen(confRoot)
    end
  }))
  oLayout.addView(btnDelete)

  oScroll.addView(oLayout)
  oRoot.addView(oScroll)
  utils.enableBackKey(oRoot, function() onBack() end)
  utils.setScreen(oRoot)
end

function releasesModule.openAssetFilePicker(owner, repo, relObj, path, onComplete)
  local relId = relObj.optInt("id", 0)
  local currentLocalPath = path
  if not currentLocalPath or currentLocalPath == "" then
    pcall(function()
      local prefs = service.getSharedPreferences("github_manager_prefs", 0)
      local saved = prefs.getString("last_asset_upload_path", "")
      if saved and saved ~= "" then
        local checkFile = File(saved)
        if checkFile.exists() and checkFile.isDirectory() and checkFile.canRead() then
          currentLocalPath = saved
        end
      end
    end)
  end

  if not currentLocalPath or currentLocalPath == "" then
    pcall(function()
      currentLocalPath = Environment.getExternalStorageDirectory().getAbsolutePath()
    end)
    if not currentLocalPath or currentLocalPath == "" then
      currentLocalPath = "/sdcard"
    end
  end

  local pRoot = LinearLayout(service)
  pRoot.setOrientation(LinearLayout.VERTICAL)
  pRoot.setBackgroundColor(Color.BLACK)
  pRoot.setPadding(20, 20, 20, 20)

  local pScroll = ScrollView(service)
  local pLayout = LinearLayout(service)
  pLayout.setOrientation(LinearLayout.VERTICAL)

  pLayout.addView(utils.createHeader("Select File to Upload (Up to 2GB)"))

  local rootStoragePath = ""
  pcall(function()
    rootStoragePath = Environment.getExternalStorageDirectory().getAbsolutePath()
  end)
  local dirDisplayName = ""
  if currentLocalPath == rootStoragePath or currentLocalPath == "/sdcard" or currentLocalPath == "/storage/emulated/0" then
    dirDisplayName = "Internal Storage"
  else
    local fCurr = File(currentLocalPath)
    dirDisplayName = fCurr.getName()
    if not dirDisplayName or dirDisplayName == "" then
      dirDisplayName = currentLocalPath
    end
  end

  local pathInfo = TextView(service)
  pathInfo.setText(dirDisplayName)
  pathInfo.setTextColor(Color.YELLOW)
  pathInfo.setPadding(10, 10, 10, 10)
  pLayout.addView(pathInfo)

  local fDir = File(currentLocalPath)
  local parentFile = fDir.getParentFile()

  local function goBackDir()
    if parentFile and parentFile.exists() and parentFile.canRead() and parentFile.getAbsolutePath() ~= "/" then
      releasesModule.openAssetFilePicker(owner, repo, relObj, parentFile.getAbsolutePath(), onComplete)
    else
      onComplete()
    end
  end

  local btnBackOpt = Button(service)
  btnBackOpt.setText("Back to Assets")
  btnBackOpt.setOnClickListener(View.OnClickListener({
    onClick = function()
      onComplete()
    end
  }))
  pLayout.addView(btnBackOpt)

  local btnUp = Button(service)
  btnUp.setText("Back to Previous Directory")
  btnUp.setOnClickListener(View.OnClickListener({
    onClick = function()
      goBackDir()
    end
  }))
  pLayout.addView(btnUp)

  local filesList = fDir.listFiles()
  if filesList then
    local dirs = {}
    local files = {}
    local len = Array.getLength(filesList)
    for i = 0, len - 1 do
      local item = Array.get(filesList, i)
      if item and item.canRead() and not item.isHidden() then
        if item.isDirectory() then
          table.insert(dirs, item)
        else
          table.insert(files, item)
        end
      end
    end

    table.sort(dirs, function(a, b) return string.lower(a.getName()) < string.lower(b.getName()) end)
    table.sort(files, function(a, b) return string.lower(a.getName()) < string.lower(b.getName()) end)

    for _, dItem in ipairs(dirs) do
      local b = Button(service)
      b.setText("[Folder] " .. dItem.getName())
      b.setTextColor(Color.CYAN)
      b.setOnClickListener(View.OnClickListener({
        onClick = function()
          releasesModule.openAssetFilePicker(owner, repo, relObj, dItem.getAbsolutePath(), onComplete)
        end
      }))
      pLayout.addView(b)
    end

    for _, fItem in ipairs(files) do
      local btnFile = Button(service)
      local bytes = fItem.length()
      local sizeStr = formatSize(bytes)
      local fileName = fItem.getName()

      btnFile.setText("[File] " .. fileName .. " (" .. sizeStr .. ")")
      btnFile.setTextColor(Color.WHITE)

      if bytes > (2 * 1024 * 1024 * 1024) then
        btnFile.setEnabled(false)
        btnFile.setTextColor(Color.GRAY)
        btnFile.setText("[File] " .. fileName .. " (" .. sizeStr .. ") - Exceeds 2GB limit")
        btnFile.setOnClickListener(View.OnClickListener({
          onClick = function()
            Toast.makeText(service, "File size exceeds 2GB limit!", Toast.LENGTH_SHORT).show()
          end
        }))
      else
        btnFile.setOnClickListener(View.OnClickListener({
          onClick = function()
            pcall(function()
              local prefs = service.getSharedPreferences("github_manager_prefs", 0)
              prefs.edit().putString("last_asset_upload_path", currentLocalPath).apply()
            end)

            local existingAssetId = nil
            pcall(function()
              local jsonArray = relObj.getJSONArray("assets")
              local len = jsonArray.length()
              for i = 0, len - 1 do
                local ast = jsonArray.getJSONObject(i)
                if ast.optString("name", "") == fileName then
                  existingAssetId = ast.optInt("id", 0)
                  break
                end
              end
            end)

            local function doStartUpload(assetIdToReplace)
              releasesModule.uploadAssetFile(owner, repo, relId, fItem, assetIdToReplace, function(success)
                if success then
                  onComplete()
                end
              end)
            end

            if existingAssetId then
              local confRoot = LinearLayout(service)
              confRoot.setOrientation(LinearLayout.VERTICAL)
              confRoot.setBackgroundColor(Color.BLACK)
              confRoot.setPadding(20, 20, 20, 20)

              local confScroll = ScrollView(service)
              local confLayout = LinearLayout(service)
              confLayout.setOrientation(LinearLayout.VERTICAL)

              confLayout.addView(utils.createHeader("Asset Exists"))
              local info = TextView(service)
              info.setText("Asset '" .. fileName .. "' already exists in this release. Do you want to replace it?")
              info.setTextColor(Color.YELLOW)
              info.setTextSize(16)
              info.setPadding(20, 20, 20, 20)
              confLayout.addView(info)

              local btnYes = Button(service)
              btnYes.setText("Yes, Replace")
              btnYes.setOnClickListener(View.OnClickListener({
                onClick = function()
                  doStartUpload(existingAssetId)
                end
              }))
              confLayout.addView(btnYes)

              local btnNo = Button(service)
              btnNo.setText("Cancel")
              btnNo.setOnClickListener(View.OnClickListener({
                onClick = function()
                  releasesModule.openAssetFilePicker(owner, repo, relObj, currentLocalPath, onComplete)
                end
              }))
              confLayout.addView(btnNo)

              confScroll.addView(confLayout)
              confRoot.addView(confScroll)
              utils.enableBackKey(confRoot, function() releasesModule.openAssetFilePicker(owner, repo, relObj, currentLocalPath, onComplete) end)
              utils.setScreen(confRoot)
            else
              doStartUpload(nil)
            end
          end
        }))
      end
      pLayout.addView(btnFile)
    end
  else
    local emptyTv = TextView(service)
    emptyTv.setText("Folder is empty or unreadable.")
    emptyTv.setTextColor(Color.GRAY)
    emptyTv.setPadding(20, 20, 20, 20)
    pLayout.addView(emptyTv)
  end

  pScroll.addView(pLayout)
  pRoot.addView(pScroll)
  utils.enableBackKey(pRoot, function()
    goBackDir()
  end)
  utils.setScreen(pRoot)
end

function releasesModule.uploadAssetFile(owner, repo, relId, fileObj, existingAssetId, onComplete)
  local fileName = fileObj.getName()
  local fileSize = fileObj.length()

  local function performUpload()
    local urlStr = "https://uploads.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/releases/" .. relId .. "/assets?name=" .. utils.urlEncode(fileName)

    local uRoot = LinearLayout(service)
    uRoot.setOrientation(LinearLayout.VERTICAL)
    uRoot.setBackgroundColor(Color.BLACK)
    uRoot.setPadding(20, 20, 20, 20)
    uRoot.setFocusableInTouchMode(true)
    uRoot.requestFocus()
    uRoot.setOnKeyListener(View.OnKeyListener({
      onKey = function(v, keyCode, event)
        if keyCode == KeyEvent.KEYCODE_BACK then
          return true
        end
        return false
      end
    }))

    local uScroll = ScrollView(service)
    local uLayout = LinearLayout(service)
    uLayout.setOrientation(LinearLayout.VERTICAL)

    uLayout.addView(utils.createHeader("Uploading Asset"))

    local txtWarning = TextView(service)
    txtWarning.setText("Do NOT use system back")
    txtWarning.setTextColor(Color.RED)
    txtWarning.setTextSize(16)
    txtWarning.setPadding(0, 10, 0, 10)
    uLayout.addView(txtWarning)

    local txtFile = TextView(service)
    txtFile.setText("File: " .. fileName)
    txtFile.setTextColor(Color.WHITE)
    txtFile.setPadding(0, 10, 0, 10)
    uLayout.addView(txtFile)

    local txtStatus = TextView(service)
    txtStatus.setText("Uploading in progress...")
    txtStatus.setTextColor(Color.YELLOW)
    txtStatus.setTextSize(16)
    txtStatus.setPadding(0, 10, 0, 10)
    uLayout.addView(txtStatus)

    uScroll.addView(uLayout)
    uRoot.addView(uScroll)

    utils.setScreen(uRoot)

    Thread(Runnable({
      run = function()
        local success = false
        pcall(function()
          local url = URL(urlStr)
          local conn = url.openConnection()
          conn.setDoOutput(true)
          conn.setRequestMethod("POST")
          conn.setRequestProperty("Content-Type", "application/octet-stream")
          conn.setRequestProperty("User-Agent", "GitHubManagerApp")

          local savedToken = ""
          pcall(function() savedToken = utils.loadToken() end)
          if savedToken and savedToken:match("%S") then
            conn.setRequestProperty("Authorization", "token " .. savedToken:match("^%s*(.-)%s*$"))
          end

          if fileSize > 0 then
            conn.setFixedLengthStreamingMode(fileSize)
          end
          conn.connect()

          local os = conn.getOutputStream()
          local fis = FileInputStream(fileObj)
          local buffer = Array.newInstance(Byte.TYPE, 16384)

          local len = fis.read(buffer)
          while len > 0 do
            os.write(buffer, 0, len)
            len = fis.read(buffer)
          end

          os.flush()
          os.close()
          fis.close()

          local responseCode = conn.getResponseCode()
          if responseCode == 201 or responseCode == 200 then
            success = true
          end
        end)

        Handler(Looper.getMainLooper()).post(Runnable({
          run = function()
            if success then
              Toast.makeText(service, "Asset uploaded successfully!", Toast.LENGTH_SHORT).show()
              onComplete(true)
            else
              Toast.makeText(service, "Failed to upload asset.", Toast.LENGTH_SHORT).show()
              onComplete(false)
            end
          end
        }))
      end
    })).start()
  end

  if existingAssetId then
    local delUrl = "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/releases/assets/" .. existingAssetId
    httpRequestWithTimeout("Replacing existing asset...", delUrl, "DELETE", nil, function(dCode, dRes)
      if dCode == 204 or dCode == 200 then
        performUpload()
      else
        Toast.makeText(service, "Failed to replace existing asset.", Toast.LENGTH_SHORT).show()
        onComplete(false)
      end
    end, function() onComplete(false) end)
  else
    performUpload()
  end
end

return releasesModule
