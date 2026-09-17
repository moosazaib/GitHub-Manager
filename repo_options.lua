local utils = require("utils")
local tokenModule = require("token_module")
local createRepoModule = require("create_repo")

local Handler = Handler or luajava.bindClass("android.os.Handler")
local Looper = Looper or luajava.bindClass("android.os.Looper")
local Runnable = Runnable or luajava.bindClass("java.lang.Runnable")
local Toast = Toast or luajava.bindClass("android.widget.Toast")

local File = luajava.bindClass("java.io.File")
local FileInputStream = luajava.bindClass("java.io.FileInputStream")
local ByteArrayOutputStream = luajava.bindClass("java.io.ByteArrayOutputStream")
local Environment = luajava.bindClass("android.os.Environment")
local Byte = luajava.bindClass("java.lang.Byte")
local Array = luajava.bindClass("java.lang.reflect.Array")
local Thread = luajava.bindClass("java.lang.Thread")
local CheckBox = luajava.bindClass("android.widget.CheckBox")
local CompoundButton = luajava.bindClass("android.widget.CompoundButton")

local Uri = luajava.bindClass("android.net.Uri")
local DownloadManager = luajava.bindClass("android.app.DownloadManager")
local Long = luajava.bindClass("java.lang.Long")
local AlertDialog = luajava.bindClass("android.app.AlertDialog")
local DialogInterface = luajava.bindClass("android.content.DialogInterface")
local WindowManager = luajava.bindClass("android.view.WindowManager")

local repoOptionsModule = {}

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

local function startDownloadFile(urlStr, saveFileName, knownTotalSize, onCancel, onSuccess)
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

  layout.addView(utils.createHeader("Downloading File"))

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

    pcall(function()
      local longArray = Array.newInstance(Long.TYPE, 1)
      Array.setLong(longArray, 0, Long(downloadId).longValue())
      downloadManager.remove(longArray)
    end)

    Toast.makeText(service, "Download cancelled.", Toast.LENGTH_SHORT).show()
    onCancel()
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
              statusStr = "Downloading " .. formatSize(numBytes) .. " / " .. formatSize(numTotal)
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
                btnStatus.setText("Downloading " .. formatSize(numTotal) .. " / " .. formatSize(numTotal))
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

function repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
  if utils.loadToken() == "" then
    tokenModule.showTokenMissingScreen(showMainScreen)
    return
  end

  local function getFullPath(targetName)
    local cleanName = targetName:gsub("^/+", "")
    if currentPath and currentPath ~= "" then
      local cleanPath = currentPath:gsub("/+$", "")
      return cleanPath .. "/" .. cleanName
    end
    return cleanName
  end

  if isPrivate == nil then
    httpRequestWithTimeout("Loading repo info...", "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo), "GET", nil, function(code, res)
      local fetchedPrivate = false
      if code == 200 then
        pcall(function()
          local obj = JSONObject(res)
          fetchedPrivate = obj.getBoolean("private")
        end)
      end
      repoOptionsModule.showOptions(owner, repo, fetchedPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
    end, function() onBackToRepo() end)
    return
  end

  local root = LinearLayout(service)
  root.setOrientation(LinearLayout.VERTICAL)
  root.setBackgroundColor(Color.BLACK)
  root.setPadding(20, 20, 20, 20)

  local scroll = ScrollView(service)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)

  layout.addView(utils.createHeader("More Options: " .. repo))

  local btnStar = Button(service)
  btnStar.setText("Checking Star Status...")
  btnStar.setEnabled(false)
  layout.addView(btnStar)

  local currentStarsCount = 0
  local function updateStarButtonState(isStarred, starCount)
    currentStarsCount = starCount
    if isStarred then
      btnStar.setText("Unstar Repository (" .. starCount .. " Stars)")
    else
      btnStar.setText("Star Repository (" .. starCount .. " Stars)")
    end
    btnStar.setEnabled(true)
  end

  local function checkStarStatus()
    local url = "https://api.github.com/user/starred/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo)
    utils.httpRequest(url, "GET", nil, function(code, response)
      local isStarred = (code == 204)
      local countUrl = "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo)
      utils.httpRequest(countUrl, "GET", nil, function(cCode, cResp)
        local stars = currentStarsCount
        if cCode == 200 and cResp then
          pcall(function()
            local obj = JSONObject(cResp)
            stars = obj.optInt("stargazers_count", stars)
          end)
        end
        updateStarButtonState(isStarred, stars)
      end)
    end)
  end

  checkStarStatus()

  btnStar.setOnClickListener(View.OnClickListener({
    onClick = function()
      local url = "https://api.github.com/user/starred/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo)
      btnStar.setEnabled(false)
      utils.httpRequest(url, "GET", nil, function(code, response)
        local isCurrentlyStarred = (code == 204)
        local method = isCurrentlyStarred and "DELETE" or "PUT"

        utils.httpRequest(url, method, "", function(actCode, actResp)
          if actCode == 204 or actCode == 200 or actCode == 201 then
            if isCurrentlyStarred then
              Toast.makeText(service, "Repository unstarred!", Toast.LENGTH_SHORT).show()
            else
              Toast.makeText(service, "Repository starred!", Toast.LENGTH_SHORT).show()
            end
            checkStarStatus()
          else
            Toast.makeText(service, "Action failed. Check your token permissions.", Toast.LENGTH_SHORT).show()
            btnStar.setEnabled(true)
          end
        end)
      end)
    end
  }))

  local btnDesc = Button(service)
  btnDesc.setText("Loading Description...")
  btnDesc.setEnabled(false)
  layout.addView(btnDesc)

  local currentDesc = ""
  local function loadDescription()
    local url = "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo)
    utils.httpRequest(url, "GET", nil, function(code, res)
      if code == 200 and res then
        pcall(function()
          local obj = JSONObject(res)
          if not obj.isNull("description") then
            currentDesc = obj.optString("description", "")
          else
            currentDesc = ""
          end
        end)
      end
      if currentDesc ~= "" then
        btnDesc.setText("Description: " .. currentDesc)
      else
        btnDesc.setText("Description: No description provided")
      end
      btnDesc.setEnabled(true)
    end)
  end

  loadDescription()

  btnDesc.setOnClickListener(View.OnClickListener({
    onClick = function()
      local dRoot = LinearLayout(service)
      dRoot.setOrientation(LinearLayout.VERTICAL)
      dRoot.setBackgroundColor(Color.BLACK)
      dRoot.setPadding(20, 20, 20, 20)

      local dScroll = ScrollView(service)
      local dLayout = LinearLayout(service)
      dLayout.setOrientation(LinearLayout.VERTICAL)

      dLayout.addView(utils.createHeader("Edit Description"))

      local inputDesc = EditText(service)
      inputDesc.setHint("Type new description or leave empty...")
      inputDesc.setText(currentDesc)
      inputDesc.setTextColor(Color.WHITE)
      inputDesc.setHintTextColor(Color.GRAY)
      dLayout.addView(inputDesc)

      local btnSaveDesc = Button(service)
      btnSaveDesc.setText("Save Description")
      btnSaveDesc.setOnClickListener(View.OnClickListener({
        onClick = function()
          local newDesc = tostring(inputDesc.getText()):match("^%s*(.-)%s*$")
          local jsonBody = JSONObject()
          jsonBody.put("description", newDesc)

          httpRequestWithTimeout("Updating description...", "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo), "PATCH", jsonBody.toString(), function(pCode, pRes)
            if pCode == 200 then
              Toast.makeText(service, "Description updated successfully!", Toast.LENGTH_SHORT).show()
              repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
            else
              Toast.makeText(service, "Failed to update description.", Toast.LENGTH_SHORT).show()
              repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
            end
          end, function()
            repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
          end)
        end
      }))
      dLayout.addView(btnSaveDesc)

      local btnBackDesc = Button(service)
      btnBackDesc.setText("Back")
      btnBackDesc.setOnClickListener(View.OnClickListener({
        onClick = function()
          repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
        end
      }))
      dLayout.addView(btnBackDesc)

      dScroll.addView(dLayout)
      dRoot.addView(dScroll)
      utils.enableBackKey(dRoot, function()
        repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
      end)
      utils.setScreen(dRoot)
    end
  }))

  local btnDownloadRepo = Button(service)
  btnDownloadRepo.setText("Download Repository")
  btnDownloadRepo.setOnClickListener(View.OnClickListener({
    onClick = function()
      local defaultBranch = "main"
      utils.httpRequest("https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo), "GET", nil, function(bCode, bRes)
        local repoSizeInBytes = 0
        if bCode == 200 and bRes then
          pcall(function()
            local bObj = JSONObject(bRes)
            defaultBranch = bObj.optString("default_branch", "main")
            local sizeKB = bObj.optInt("size", 0)
            if sizeKB > 0 then
              repoSizeInBytes = sizeKB * 1024
            end
          end)
        end
        local zipUrl = "https://github.com/" .. owner .. "/" .. repo .. "/archive/refs/heads/" .. defaultBranch .. ".zip"
        local fileName = repo .. "-" .. defaultBranch .. ".zip"
        startDownloadFile(zipUrl, fileName, repoSizeInBytes, function()
          repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
        end, function()
          repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
        end)
      end)
    end
  }))
  layout.addView(btnDownloadRepo)

  local btnCopyRepoUrl = Button(service)
  btnCopyRepoUrl.setText("Copy Current Directory Link")
  btnCopyRepoUrl.setOnClickListener(View.OnClickListener({
    onClick = function()
      local targetUrl = "https://github.com/" .. owner .. "/" .. repo
      if currentPath and currentPath ~= "" then
        targetUrl = targetUrl .. "/tree/main/" .. currentPath
      end
      service.copy(targetUrl)
      Toast.makeText(service, "Copied to clipboard", Toast.LENGTH_SHORT).show()
    end
  }))
  layout.addView(btnCopyRepoUrl)

  local btnCopyZipUrl = Button(service)
  btnCopyZipUrl.setText("Copy Zip Link")
  btnCopyZipUrl.setOnClickListener(View.OnClickListener({
    onClick = function()
      local zipUrl = "https://github.com/" .. owner .. "/" .. repo .. "/archive/refs/heads/main.zip"
      service.copy(zipUrl)
      Toast.makeText(service, "Copied to clipboard", Toast.LENGTH_SHORT).show()
    end
  }))
  layout.addView(btnCopyZipUrl)

  local btnCreateTextFile = Button(service)
  btnCreateTextFile.setText("Create Text File")
  btnCreateTextFile.setOnClickListener(View.OnClickListener({
    onClick = function()
      local uRoot = LinearLayout(service)
      uRoot.setOrientation(LinearLayout.VERTICAL)
      uRoot.setBackgroundColor(Color.BLACK)
      uRoot.setPadding(20, 20, 20, 20)

      local uScroll = ScrollView(service)
      local uLayout = LinearLayout(service)
      uLayout.setOrientation(LinearLayout.VERTICAL)

      uLayout.addView(utils.createHeader("Create Text File in " .. repo))

      local inputName = EditText(service)
      inputName.setHint("File Name e.g. test.txt")
      inputName.setTextColor(Color.WHITE)
      inputName.setHintTextColor(Color.GRAY)
      uLayout.addView(inputName)

      local inputContent = EditText(service)
      inputContent.setHint("File Content")
      inputContent.setTextColor(Color.WHITE)
      inputContent.setHintTextColor(Color.GRAY)
      uLayout.addView(inputContent)

      local btnSubmit = Button(service)
      btnSubmit.setText("Create File")
      
      local function updateUploadState()
        local nVal = tostring(inputName.getText())
        local cVal = tostring(inputContent.getText())
        btnSubmit.setEnabled(nVal ~= "" and cVal ~= "")
      end
      updateUploadState()

      local uploadWatcher = TextWatcher({
        onTextChanged = function() updateUploadState() end,
        beforeTextChanged = function() end,
        afterTextChanged = function() end
      })
      inputName.addTextChangedListener(uploadWatcher)
      inputContent.addTextChangedListener(uploadWatcher)

      btnSubmit.setOnClickListener(View.OnClickListener({
        onClick = function()
          local fileName = tostring(inputName.getText()):match("^%s*(.-)%s*$")
          local fileContent = tostring(inputContent.getText())
          if fileName ~= "" then
            local fullFilePath = getFullPath(fileName)
            httpRequestWithTimeout("Checking file...", "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/contents/" .. utils.urlEncode(fullFilePath), "GET", nil, function(code, res)
              local found = false
              local existingFilePath = fullFilePath
              local fileSha = ""
              if code == 200 and res then
                pcall(function()
                  local obj = JSONObject(res)
                  found = true
                  existingFilePath = obj.optString("path", fullFilePath)
                  fileSha = obj.optString("sha", "")
                end)
              end

              local function doSaveFile(shaToUse)
                local encoded = Base64.encodeToString(String(fileContent).getBytes("UTF-8"), Base64.NO_WRAP)
                local json = ""
                if shaToUse and shaToUse ~= "" then
                  json = '{"message":"Updated via GitHub Manager","content":"' .. encoded .. '","sha":"' .. shaToUse .. '"}'
                else
                  json = '{"message":"Created via GitHub Manager","content":"' .. encoded .. '"}'
                end
                httpRequestWithTimeout("Saving file...", "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/contents/" .. utils.urlEncode(existingFilePath), "PUT", json, function(cCode, cRes)
                  if cCode == 201 or cCode == 200 then
                    local succRoot = LinearLayout(service)
                    succRoot.setOrientation(LinearLayout.VERTICAL)
                    succRoot.setBackgroundColor(Color.BLACK)
                    succRoot.setPadding(20, 20, 20, 20)

                    local succScroll = ScrollView(service)
                    local succLayout = LinearLayout(service)
                    succLayout.setOrientation(LinearLayout.VERTICAL)

                    succLayout.addView(utils.createHeader("Success"))
                    local info = TextView(service)
                    info.setText("File saved successfully!")
                    info.setTextColor(Color.GREEN)
                    info.setTextSize(16)
                    info.setPadding(20, 20, 20, 20)
                    succLayout.addView(info)

                    local btnOk = Button(service)
                    btnOk.setText("OK")
                    btnOk.setOnClickListener(View.OnClickListener({
                      onClick = function() onBackToRepo() end
                    }))
                    succLayout.addView(btnOk)

                    succScroll.addView(succLayout)
                    succRoot.addView(succScroll)
                    utils.enableBackKey(succRoot, function() onBackToRepo() end)
                    utils.setScreen(succRoot)
                  else
                    Toast.makeText(service, "Failed to save file.", Toast.LENGTH_SHORT).show()
                    onBackToRepo()
                  end
                end, function() onBackToRepo() end)
              end

              if found then
                local confRoot = LinearLayout(service)
                confRoot.setOrientation(LinearLayout.VERTICAL)
                confRoot.setBackgroundColor(Color.BLACK)
                confRoot.setPadding(20, 20, 20, 20)

                local confScroll = ScrollView(service)
                local confLayout = LinearLayout(service)
                confLayout.setOrientation(LinearLayout.VERTICAL)

                confLayout.addView(utils.createHeader("File Exists"))
                local info = TextView(service)
                info.setText("File '" .. fileName .. "' already exists. Do you want to overwrite it?")
                info.setTextColor(Color.YELLOW)
                info.setTextSize(16)
                info.setPadding(20, 20, 20, 20)
                confLayout.addView(info)

                local btnYes = Button(service)
                btnYes.setText("Yes, Overwrite")
                btnYes.setOnClickListener(View.OnClickListener({
                  onClick = function()
                    doSaveFile(fileSha)
                  end
                }))
                confLayout.addView(btnYes)

                local btnNo = Button(service)
                btnNo.setText("Cancel")
                btnNo.setOnClickListener(View.OnClickListener({
                  onClick = function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath) end
                }))
                confLayout.addView(btnNo)

                confScroll.addView(confLayout)
                confRoot.addView(confScroll)
                utils.enableBackKey(confRoot, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath) end)
                utils.setScreen(confRoot)
              else
                doSaveFile(nil)
              end
            end, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath) end)
          end
        end
      }))
      uLayout.addView(btnSubmit)

      local btnBack = Button(service)
      btnBack.setText("Back")
      btnBack.setOnClickListener(View.OnClickListener({
        onClick = function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath) end
      }))
      uLayout.addView(btnBack)

      uScroll.addView(uLayout)
      uRoot.addView(uScroll)
      utils.enableBackKey(uRoot, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath) end)
      utils.setScreen(uRoot)
    end
  }))
  layout.addView(btnCreateTextFile)

  local btnCreateFolder = Button(service)
  btnCreateFolder.setText("Create Folder")
  btnCreateFolder.setOnClickListener(View.OnClickListener({
    onClick = function()
      local fRoot = LinearLayout(service)
      fRoot.setOrientation(LinearLayout.VERTICAL)
      fRoot.setBackgroundColor(Color.BLACK)
      fRoot.setPadding(20, 20, 20, 20)

      local fScroll = ScrollView(service)
      local fLayout = LinearLayout(service)
      fLayout.setOrientation(LinearLayout.VERTICAL)

      fLayout.addView(utils.createHeader("Create Folder in " .. repo))

      local inputFolderName = EditText(service)
      inputFolderName.setHint("Folder Name e.g. my_folder")
      inputFolderName.setTextColor(Color.WHITE)
      inputFolderName.setHintTextColor(Color.GRAY)
      fLayout.addView(inputFolderName)

      local btnSubmitFolder = Button(service)
      btnSubmitFolder.setText("Create Folder")

      local function updateFolderState()
        local fVal = tostring(inputFolderName.getText()):match("^%s*(.-)%s*$")
        btnSubmitFolder.setEnabled(fVal ~= "")
      end
      updateFolderState()

      inputFolderName.addTextChangedListener(TextWatcher({
        onTextChanged = function() updateFolderState() end,
        beforeTextChanged = function() end,
        afterTextChanged = function() end
      }))

      btnSubmitFolder.setOnClickListener(View.OnClickListener({
        onClick = function()
          local folderName = tostring(inputFolderName.getText()):match("^%s*(.-)%s*$")
          if folderName ~= "" then
            folderName = folderName:gsub("^/+", ""):gsub("/+$", "")
            local fullFolderPath = getFullPath(folderName)

            local checkUrl = "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/contents/" .. utils.urlEncode(fullFolderPath)
            httpRequestWithTimeout("Checking folder...", checkUrl, "GET", nil, function(code, res)
              local exists = false
              if code == 200 and res then
                pcall(function()
                  if res:sub(1,1) == "[" then
                    exists = true
                  else
                    local obj = JSONObject(res)
                    if obj.optString("type") == "dir" then
                      exists = true
                    end
                  end
                end)
              end

              if exists then
                pcall(function()
                  local builder = AlertDialog.Builder(service)
                  builder.setMessage("This folder is already exist")
                  local dlg = builder.create()
                  pcall(function()
                    if dlg.getWindow() then
                      dlg.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                    end
                  end)
                  dlg.show()

                  Handler(Looper.getMainLooper()).postDelayed(Runnable({
                    run = function()
                      pcall(function() dlg.dismiss() end)
                      repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
                    end
                  }), 500)
                end)
              else
                local defaultBranch = "main"
                utils.httpRequest("https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo), "GET", nil, function(bCode, bRes)
                  if bCode == 200 and bRes then
                    pcall(function()
                      local bObj = JSONObject(bRes)
                      defaultBranch = bObj.optString("default_branch", "main")
                    end)
                  end

                  local refUrl = "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/git/refs/heads/" .. utils.urlEncode(defaultBranch)
                  httpRequestWithTimeout("Creating folder...", refUrl, "GET", nil, function(rCode, rRes)
                    if rCode == 200 and rRes then
                      local latestCommitSha = ""
                      pcall(function()
                        local rObj = JSONObject(rRes)
                        latestCommitSha = rObj.getJSONObject("object").optString("sha", "")
                      end)

                      if latestCommitSha ~= "" then
                        local commitUrl = "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/git/commits/" .. latestCommitSha
                        httpRequestWithTimeout("Creating folder...", commitUrl, "GET", nil, function(cCode, cRes)
                          if cCode == 200 and cRes then
                            local baseTreeSha = ""
                            pcall(function()
                              local cObj = JSONObject(cRes)
                              baseTreeSha = cObj.getJSONObject("tree").optString("sha", "")
                            end)

                            if baseTreeSha ~= "" then
                              local treeJson = '{"base_tree":"' .. baseTreeSha .. '","tree":[{"path":"' .. fullFolderPath .. '","mode":"040000","type":"tree","sha":"4b825dc642cb6eb9a060e54bf8d69288fbee4904"}]}'
                              local postTreeUrl = "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/git/trees"
                              httpRequestWithTimeout("Creating folder...", postTreeUrl, "POST", treeJson, function(tCode, tRes)
                                if tCode == 201 and tRes then
                                  local newTreeSha = ""
                                  pcall(function()
                                    local tObj = JSONObject(tRes)
                                    newTreeSha = tObj.optString("sha", "")
                                  end)

                                  if newTreeSha ~= "" then
                                    local newCommitJson = '{"message":"Create folder ' .. fullFolderPath .. ' via GitHub Manager","tree":"' .. newTreeSha .. '","parents":["' .. latestCommitSha .. '"]}'
                                    local postCommitUrl = "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/git/commits"
                                    httpRequestWithTimeout("Creating folder...", postCommitUrl, "POST", newCommitJson, function(ncCode, ncRes)
                                      if ncCode == 201 and ncRes then
                                        local newCommitSha = ""
                                        pcall(function()
                                          local ncObj = JSONObject(ncRes)
                                          newCommitSha = ncObj.optString("sha", "")
                                        end)

                                        if newCommitSha ~= "" then
                                          local updateRefJson = '{"sha":"' .. newCommitSha .. '"}'
                                          httpRequestWithTimeout("Creating folder...", refUrl, "PATCH", updateRefJson, function(uCode, uRes)
                                            if uCode == 200 then
                                              Toast.makeText(service, "Folder created successfully!", Toast.LENGTH_SHORT).show()
                                              onBackToRepo()
                                            else
                                              Toast.makeText(service, "Failed to create folder.", Toast.LENGTH_SHORT).show()
                                              repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
                                            end
                                          end, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath) end)
                                        else
                                          Toast.makeText(service, "Failed to create folder.", Toast.LENGTH_SHORT).show()
                                          repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
                                        end
                                      else
                                        Toast.makeText(service, "Failed to create folder.", Toast.LENGTH_SHORT).show()
                                        repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
                                      end
                                    end, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath) end)
                                  else
                                    Toast.makeText(service, "Failed to create folder.", Toast.LENGTH_SHORT).show()
                                    repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
                                  end
                                else
                                  Toast.makeText(service, "Failed to create folder.", Toast.LENGTH_SHORT).show()
                                  repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
                                end
                              end, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath) end)
                            else
                              Toast.makeText(service, "Failed to create folder.", Toast.LENGTH_SHORT).show()
                              repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
                            end
                          else
                            Toast.makeText(service, "Failed to create folder.", Toast.LENGTH_SHORT).show()
                            repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
                          end
                        end, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath) end)
                      else
                        Toast.makeText(service, "Failed to create folder.", Toast.LENGTH_SHORT).show()
                        repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
                      end
                    else
                      Toast.makeText(service, "Failed to create folder.", Toast.LENGTH_SHORT).show()
                      repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
                    end
                  end, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath) end)
                end)
              end
            end, function()
              repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
            end)
          end
        end
      }))
      fLayout.addView(btnSubmitFolder)

      local btnBackF = Button(service)
      btnBackF.setText("Back")
      btnBackF.setOnClickListener(View.OnClickListener({
        onClick = function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath) end
      }))
      fLayout.addView(btnBackF)

      fScroll.addView(fLayout)
      fRoot.addView(fScroll)
      utils.enableBackKey(fRoot, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath) end)
      utils.setScreen(fRoot)
    end
  }))
  layout.addView(btnCreateFolder)

  local function showUploadErrorDialog(fileName, errCode, errRes)
    local errRoot = LinearLayout(service)
    errRoot.setOrientation(LinearLayout.VERTICAL)
    errRoot.setBackgroundColor(Color.BLACK)
    errRoot.setPadding(20, 20, 20, 20)

    local errScroll = ScrollView(service)
    local errLayout = LinearLayout(service)
    errLayout.setOrientation(LinearLayout.VERTICAL)

    errLayout.addView(utils.createHeader("Upload Error Log"))

    local infoTv = TextView(service)
    infoTv.setText("File: " .. tostring(fileName) .. "\nHTTP Code: " .. tostring(errCode) .. "\n\nResponse:\n" .. tostring(errRes or "No Response Body"))
    infoTv.setTextColor(Color.RED)
    infoTv.setTextSize(14)
    infoTv.setPadding(10, 10, 10, 10)
    errLayout.addView(infoTv)

    local btnCopy = Button(service)
    btnCopy.setText("Copy Error Log")
    btnCopy.setOnClickListener(View.OnClickListener({
      onClick = function()
        service.copy("File: " .. tostring(fileName) .. "\nHTTP Code: " .. tostring(errCode) .. "\nResponse: " .. tostring(errRes))
        Toast.makeText(service, "Copied to clipboard", Toast.LENGTH_SHORT).show()
      end
    }))
    errLayout.addView(btnCopy)

    local btnOk = Button(service)
    btnOk.setText("Close")
    btnOk.setOnClickListener(View.OnClickListener({
      onClick = function() onBackToRepo() end
    }))
    errLayout.addView(btnOk)

    errScroll.addView(errLayout)
    errRoot.addView(errScroll)
    utils.enableBackKey(errRoot, function() onBackToRepo() end)
    utils.setScreen(errRoot)
  end

  local function processUploadQueue(queue, index)
    if index > #queue then
      local succRoot = LinearLayout(service)
      succRoot.setOrientation(LinearLayout.VERTICAL)
      succRoot.setBackgroundColor(Color.BLACK)
      succRoot.setPadding(20, 20, 20, 20)

      local succScroll = ScrollView(service)
      local succLayout = LinearLayout(service)
      succLayout.setOrientation(LinearLayout.VERTICAL)

      succLayout.addView(utils.createHeader("Success"))
      local info = TextView(service)
      info.setText("All selected files processed successfully!")
      info.setTextColor(Color.GREEN)
      info.setTextSize(16)
      info.setPadding(20, 20, 20, 20)
      succLayout.addView(info)

      local btnOk = Button(service)
      btnOk.setText("OK")
      btnOk.setOnClickListener(View.OnClickListener({
        onClick = function() onBackToRepo() end
      }))
      succLayout.addView(btnOk)

      succScroll.addView(succLayout)
      succRoot.addView(succScroll)
      utils.enableBackKey(succRoot, function() onBackToRepo() end)
      utils.setScreen(succRoot)
      return
    end

    local currentFile = queue[index]
    local fileName = currentFile.getName()
    local fullUploadPath = getFullPath(fileName)

    httpRequestWithTimeout("Checking file " .. index .. "/" .. #queue .. " (" .. fileName .. ")...", "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/contents/" .. utils.urlEncode(fullUploadPath), "GET", nil, function(code, res)
      local found = false
      local existingFilePath = fullUploadPath
      local fileSha = ""
      if code == 200 and res then
        pcall(function()
          local obj = JSONObject(res)
          found = true
          existingFilePath = obj.optString("path", fullUploadPath)
          fileSha = obj.optString("sha", "")
        end)
      end

      local function doUpload(shaToUse)
        utils.showLoading("Reading and encoding " .. index .. "/" .. #queue .. "...")
        Thread(Runnable({
          run = function()
            local encoded = ""
            pcall(function()
              local fis = FileInputStream(currentFile)
              local baos = ByteArrayOutputStream()
              local buffer = Array.newInstance(Byte.TYPE, 65536)
              local len = fis.read(buffer)
              while len > 0 do
                baos.write(buffer, 0, len)
                len = fis.read(buffer)
              end
              fis.close()
              encoded = Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP)
            end)

            Handler(Looper.getMainLooper()).post(Runnable({
              run = function()
                if encoded == "" then
                  showUploadErrorDialog(fileName, 0, "Failed to read file from local storage")
                  return
                end
                local json = ""
                if shaToUse and shaToUse ~= "" then
                  json = '{"message":"Updated via GitHub Manager","content":"' .. encoded .. '","sha":"' .. shaToUse .. '"}'
                else
                  json = '{"message":"Created via GitHub Manager","content":"' .. encoded .. '"}'
                end
                httpRequestWithTimeout("Uploading " .. index .. "/" .. #queue .. " (" .. fileName .. ")...", "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/contents/" .. utils.urlEncode(existingFilePath), "PUT", json, function(cCode, cRes)
                  if cCode ~= 200 and cCode ~= 201 then
                    showUploadErrorDialog(fileName, cCode, cRes)
                  else
                    processUploadQueue(queue, index + 1)
                  end
                end, function() showUploadErrorDialog(fileName, -1, "Request Timed Out") end)
              end
            }))
          end
        })).start()
      end

      if found then
        local confRoot = LinearLayout(service)
        confRoot.setOrientation(LinearLayout.VERTICAL)
        confRoot.setBackgroundColor(Color.BLACK)
        confRoot.setPadding(20, 20, 20, 20)

        local confScroll = ScrollView(service)
        confLayout = LinearLayout(service)
        confLayout.setOrientation(LinearLayout.VERTICAL)

        confLayout.addView(utils.createHeader("File Exists (" .. index .. "/" .. #queue .. ")"))
        local info = TextView(service)
        info.setText("File '" .. fileName .. "' already exists. Do you want to overwrite it or remove it from list?")
        info.setTextColor(Color.YELLOW)
        info.setTextSize(16)
        info.setPadding(20, 20, 20, 20)
        confLayout.addView(info)

        local btnYes = Button(service)
        btnYes.setText("Yes, Overwrite")
        btnYes.setOnClickListener(View.OnClickListener({
          onClick = function()
            doUpload(fileSha)
          end
        }))
        confLayout.addView(btnYes)

        local btnRemove = Button(service)
        btnRemove.setText("Remove from list")
        btnRemove.setOnClickListener(View.OnClickListener({
          onClick = function()
            processUploadQueue(queue, index + 1)
          end
        }))
        confLayout.addView(btnRemove)

        confScroll.addView(confLayout)
        confRoot.addView(confScroll)
        utils.enableBackKey(confRoot, function() processUploadQueue(queue, index + 1) end)
        utils.setScreen(confRoot)
      else
        doUpload(nil)
      end
    end, function() showUploadErrorDialog(fileName, -1, "Checking file timed out") end)
  end

  local function openFilePicker(path)
    local currentLocalPath = path
    if not currentLocalPath or currentLocalPath == "" then
      pcall(function()
        local prefs = service.getSharedPreferences("github_manager_prefs", 0)
        local saved = prefs.getString("last_upload_path", "")
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

    pLayout.addView(utils.createHeader("Select Files"))

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
        openFilePicker(parentFile.getAbsolutePath())
      else
        repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
      end
    end

    local btnBackOpt = Button(service)
    btnBackOpt.setText("Back to Options")
    btnBackOpt.setOnClickListener(View.OnClickListener({
      onClick = function()
        repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
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

    local selectedFilesMap = {}
    local validCheckBoxes = {}

    local btnSelectAll = Button(service)
    btnSelectAll.setText("Select All Eligible Files")
    btnSelectAll.setVisibility(View.GONE)
    pLayout.addView(btnSelectAll)

    local btnUploadSelected = Button(service)
    btnUploadSelected.setText("Upload Selected Files")
    btnUploadSelected.setVisibility(View.GONE)
    pLayout.addView(btnUploadSelected)

    local isProgrammaticCheck = false

    local function updateUIState()
      local selectedCount = 0
      for _ in pairs(selectedFilesMap) do selectedCount = selectedCount + 1 end

      if selectedCount > 0 then
        btnUploadSelected.setText("Upload Selected Files (" .. selectedCount .. ")")
        btnUploadSelected.setVisibility(View.VISIBLE)
      else
        btnUploadSelected.setVisibility(View.GONE)
      end

      if #validCheckBoxes > 0 then
        btnSelectAll.setVisibility(View.VISIBLE)
        if selectedCount == #validCheckBoxes then
          btnSelectAll.setText("Deselect All Eligible Files")
        else
          btnSelectAll.setText("Select All Eligible Files")
        end
      else
        btnSelectAll.setVisibility(View.GONE)
      end
    end

    btnSelectAll.setOnClickListener(View.OnClickListener({
      onClick = function()
        local selectedCount = 0
        for _ in pairs(selectedFilesMap) do selectedCount = selectedCount + 1 end

        local targetState = (selectedCount < #validCheckBoxes)
        isProgrammaticCheck = true
        for _, item in ipairs(validCheckBoxes) do
          item.cb.setChecked(targetState)
          if targetState then
            selectedFilesMap[item.file.getAbsolutePath()] = item.file
          else
            selectedFilesMap[item.file.getAbsolutePath()] = nil
          end
        end
        isProgrammaticCheck = false
        updateUIState()
      end
    }))

    btnUploadSelected.setOnClickListener(View.OnClickListener({
      onClick = function()
        pcall(function()
          local prefs = service.getSharedPreferences("github_manager_prefs", 0)
          prefs.edit().putString("last_upload_path", currentLocalPath).apply()
        end)
        local queue = {}
        for _, f in pairs(selectedFilesMap) do
          table.insert(queue, f)
        end
        table.sort(queue, function(a, b) return string.lower(a.getName()) < string.lower(b.getName()) end)
        if #queue > 0 then
          processUploadQueue(queue, 1)
        end
      end
    }))

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
            openFilePicker(dItem.getAbsolutePath())
          end
        }))
        pLayout.addView(b)
      end

      for _, fItem in ipairs(files) do
        local cb = CheckBox(service)
        local bytes = fItem.length()
        local sizeStr = formatSize(bytes)

        cb.setText("[File] " .. fItem.getName() .. " (" .. sizeStr .. ")")
        cb.setTextColor(Color.WHITE)

        if bytes > (50 * 1024 * 1024) then
          cb.setEnabled(false)
          cb.setTextColor(Color.GRAY)
          cb.setText("[File] " .. fItem.getName() .. " (" .. sizeStr .. ") - Exceeds 50MB")
          cb.setOnClickListener(View.OnClickListener({
            onClick = function()
              if service and service.speak then
                service.speak("File size exceeds 50MB limit")
              else
                Toast.makeText(service, "File size exceeds 50MB limit!", Toast.LENGTH_SHORT).show()
              end
            end
          }))
        else
          table.insert(validCheckBoxes, { cb = cb, file = fItem })
          cb.setOnCheckedChangeListener(CompoundButton.OnCheckedChangeListener({
            onCheckedChanged = function(buttonView, isChecked)
              if not isProgrammaticCheck then
                if isChecked then
                  selectedFilesMap[fItem.getAbsolutePath()] = fItem
                else
                  selectedFilesMap[fItem.getAbsolutePath()] = nil
                end
                updateUIState()
              end
            end
          }))
        end
        pLayout.addView(cb)
      end

      updateUIState()
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

  local btnUploadStorageFile = Button(service)
  btnUploadStorageFile.setText("Upload File From Phone Storage")
  btnUploadStorageFile.setOnClickListener(View.OnClickListener({
    onClick = function()
      openFilePicker(nil)
    end
  }))
  layout.addView(btnUploadStorageFile)

  local btnRenameRepo = Button(service)
  btnRenameRepo.setText("Rename Repository")
  btnRenameRepo.setOnClickListener(View.OnClickListener({
    onClick = function()
      local rRoot = LinearLayout(service)
      rRoot.setOrientation(LinearLayout.VERTICAL)
      rRoot.setBackgroundColor(Color.BLACK)
      rRoot.setPadding(20, 20, 20, 20)

      local rScroll = ScrollView(service)
      local rLayout = LinearLayout(service)
      rLayout.setOrientation(LinearLayout.VERTICAL)

      rLayout.addView(utils.createHeader("Rename " .. repo))

      local inputNewRepoName = EditText(service)
      inputNewRepoName.setHint("New Repository Name")
      inputNewRepoName.setText(tostring(repo))
      inputNewRepoName.setTextColor(Color.WHITE)
      inputNewRepoName.setHintTextColor(Color.GRAY)
      rLayout.addView(inputNewRepoName)

      local btnSubmitRename = Button(service)
      btnSubmitRename.setText("Rename")
      
      local function updateRenameState()
        local val = tostring(inputNewRepoName.getText())
        btnSubmitRename.setEnabled(val ~= "")
      end
      updateRenameState()

      inputNewRepoName.addTextChangedListener(TextWatcher({
        onTextChanged = function() updateRenameState() end,
        beforeTextChanged = function() end,
        afterTextChanged = function() end
      }))

      btnSubmitRename.setOnClickListener(View.OnClickListener({
        onClick = function()
          local newRName = tostring(inputNewRepoName.getText())
          if newRName ~= "" and utils.normalizeName(newRName) ~= utils.normalizeName(repo) then
            local jsonRename = '{"name":"' .. newRName .. '"}'
            httpRequestWithTimeout("Renaming repository...", "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo), "PATCH", jsonRename, function(renCode, renRes)
              if renCode == 200 then
                repoOptionsModule.showOptions(owner, newRName, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
              else
                repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
              end
            end, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath) end)
          end
        end
      }))
      rLayout.addView(btnSubmitRename)

      local btnBackR = Button(service)
      btnBackR.setText("Back")
      btnBackR.setOnClickListener(View.OnClickListener({
        onClick = function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath) end
      }))
      rLayout.addView(btnBackR)

      rScroll.addView(rLayout)
      rRoot.addView(rScroll)
      utils.enableBackKey(rRoot, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath) end)
      utils.setScreen(rRoot)
    end
  }))
  layout.addView(btnRenameRepo)

  local btnToggleVisibility = Button(service)
  if isPrivate then
    btnToggleVisibility.setText("Make Public")
  else
    btnToggleVisibility.setText("Make Private")
  end

  btnToggleVisibility.setOnClickListener(View.OnClickListener({
    onClick = function()
      local confRoot = LinearLayout(service)
      confRoot.setOrientation(LinearLayout.VERTICAL)
      confRoot.setBackgroundColor(Color.BLACK)
      confRoot.setPadding(20, 20, 20, 20)

      local confScroll = ScrollView(service)
      local confLayout = LinearLayout(service)
      confLayout.setOrientation(LinearLayout.VERTICAL)

      confLayout.addView(utils.createHeader("Change Visibility"))

      local targetVis = isPrivate and "PUBLIC" or "PRIVATE"
      local confInfo = TextView(service)
      confInfo.setText("Are you sure you want to make '" .. repo .. "' " .. targetVis .. "?")
      confInfo.setTextColor(Color.YELLOW)
      confInfo.setTextSize(16)
      confInfo.setPadding(20, 20, 20, 20)
      confLayout.addView(confInfo)

      local btnConfirmVis = Button(service)
      btnConfirmVis.setText("Yes, Change to " .. targetVis)
      btnConfirmVis.setOnClickListener(View.OnClickListener({
        onClick = function()
          local newPrivateState = not isPrivate
          local jsonBody = '{"private":' .. tostring(newPrivateState) .. '}'
          httpRequestWithTimeout("Changing visibility...", "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo), "PATCH", jsonBody, function(vCode, vRes)
            if vCode == 200 then
              Toast.makeText(service, "Visibility updated successfully!", Toast.LENGTH_SHORT).show()
              repoOptionsModule.showOptions(owner, repo, newPrivateState, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
            else
              Toast.makeText(service, "Failed to change visibility.", Toast.LENGTH_SHORT).show()
              repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
            end
          end, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath) end)
        end
      }))
      confLayout.addView(btnConfirmVis)

      local btnCancelVis = Button(service)
      btnCancelVis.setText("Cancel")
      btnCancelVis.setOnClickListener(View.OnClickListener({
        onClick = function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath) end
      }))
      confLayout.addView(btnCancelVis)

      confScroll.addView(confLayout)
      confRoot.addView(confScroll)
      utils.enableBackKey(confRoot, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath) end)
      utils.setScreen(confRoot)
    end
  }))
  layout.addView(btnToggleVisibility)

  local btnDeleteRepo = Button(service)
  btnDeleteRepo.setText("Delete Repository")
  btnDeleteRepo.setOnClickListener(View.OnClickListener({
    onClick = function()
      local confRoot = LinearLayout(service)
      confRoot.setOrientation(LinearLayout.VERTICAL)
      confRoot.setBackgroundColor(Color.BLACK)
      confRoot.setPadding(20, 20, 20, 20)

      local confScroll = ScrollView(service)
      local confLayout = LinearLayout(service)
      confLayout.setOrientation(LinearLayout.VERTICAL)

      confLayout.addView(utils.createHeader("Confirm Repository Deletion"))

      local confInfo = TextView(service)
      confInfo.setText("Are you sure you want to permanently delete repository '" .. repo .. "'?")
      confInfo.setTextColor(Color.RED)
      confInfo.setTextSize(16)
      confInfo.setPadding(20, 20, 20, 20)
      confLayout.addView(confInfo)

      local btnConfirmDel = Button(service)
      btnConfirmDel.setText("Yes, Delete Repository")
      btnConfirmDel.setOnClickListener(View.OnClickListener({
        onClick = function()
          httpRequestWithTimeout("Deleting repository...", "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo), "DELETE", nil, function(dCode, dRes)
            if dCode == 204 or dCode == 200 then
              Toast.makeText(service, "Repository deleted successfully!", Toast.LENGTH_SHORT).show()
              onRepoDeleted()
            else
              Toast.makeText(service, "Failed to delete repository.", Toast.LENGTH_SHORT).show()
              repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath)
            end
          end, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath) end)
        end
      }))
      confLayout.addView(btnConfirmDel)

      local btnCancelDel = Button(service)
      btnCancelDel.setText("Cancel")
      btnCancelDel.setOnClickListener(View.OnClickListener({
        onClick = function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath) end
      }))
      confLayout.addView(btnCancelDel)

      confScroll.addView(confLayout)
      confRoot.addView(confScroll)
      utils.enableBackKey(confRoot, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted, currentPath) end)
      utils.setScreen(confRoot)
    end
  }))
  layout.addView(btnDeleteRepo)

  local btnBack = Button(service)
  btnBack.setText("Back to Repository")
  btnBack.setOnClickListener(View.OnClickListener({
    onClick = function() onBackToRepo() end
  }))
  layout.addView(btnBack)

  scroll.addView(layout)
  root.addView(scroll)

  utils.enableBackKey(root, function() onBackToRepo() end)
  utils.setScreen(root)
end

return repoOptionsModule
