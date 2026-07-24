local utils = require("utils")
local tokenModule = require("token_module")

local Handler = Handler or luajava.bindClass("android.os.Handler")
local Looper = Looper or luajava.bindClass("android.os.Looper")
local Runnable = Runnable or luajava.bindClass("java.lang.Runnable")
local Toast = Toast or luajava.bindClass("android.os.Toast")

local myReposModule = {}

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

function myReposModule.showFilesList(owner, repo, path, showMainScreen)
  if utils.loadToken() == "" then
    tokenModule.showTokenMissingScreen(showMainScreen)
    return
  end

  local url = "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/contents/" .. utils.urlEncode(path)
  httpRequestWithTimeout("Loading files...", url, "GET", nil, function(code, res)
    if code == 404 then
      local root = LinearLayout(service)
      root.setOrientation(LinearLayout.VERTICAL)
      root.setBackgroundColor(Color.BLACK)
      root.setPadding(20, 20, 20, 20)

      local scroll = ScrollView(service)
      local layout = LinearLayout(service)
      layout.setOrientation(LinearLayout.VERTICAL)

      layout.addView(utils.createHeader("No Files Found"))
      local info = TextView(service)
      info.setText("This repository is empty or has no files in this folder.")
      info.setTextColor(Color.YELLOW)
      info.setTextSize(16)
      info.setPadding(20, 20, 20, 20)
      layout.addView(info)

      local btnBack = Button(service)
      btnBack.setText("Back to Repo Menu")
      btnBack.setOnClickListener(View.OnClickListener({
        onClick = function() myReposModule.showRepoMenu(owner, repo, nil, showMainScreen) end
      }))
      layout.addView(btnBack)

      scroll.addView(layout)
      root.addView(scroll)
      utils.enableBackKey(root, function() myReposModule.showRepoMenu(owner, repo, nil, showMainScreen) end)
      utils.setScreen(root)
      return
    elseif code ~= 200 then
      local root = LinearLayout(service)
      root.setOrientation(LinearLayout.VERTICAL)
      root.setBackgroundColor(Color.BLACK)
      root.setPadding(20, 20, 20, 20)

      local scroll = ScrollView(service)
      local layout = LinearLayout(service)
      layout.setOrientation(LinearLayout.VERTICAL)

      layout.addView(utils.createHeader("Error " .. code))
      local btnBack = Button(service)
      btnBack.setText("Back")
      btnBack.setOnClickListener(View.OnClickListener({
        onClick = function() myReposModule.showRepoMenu(owner, repo, nil, showMainScreen) end
      }))
      layout.addView(btnBack)

      scroll.addView(layout)
      root.addView(scroll)
      utils.enableBackKey(root, function() myReposModule.showRepoMenu(owner, repo, nil, showMainScreen) end)
      utils.setScreen(root)
      return
    end

    local root = LinearLayout(service)
    root.setOrientation(LinearLayout.VERTICAL)
    root.setBackgroundColor(Color.BLACK)
    root.setPadding(20, 20, 20, 20)

    local scroll = ScrollView(service)
    local layout = LinearLayout(service)
    layout.setOrientation(LinearLayout.VERTICAL)

    layout.addView(utils.createHeader("Files in " .. repo))

    local hasItems = false
    pcall(function()
      local arr = JSONArray(res)
      if arr.length() > 0 then
        hasItems = true
      end
      for i = 0, arr.length() - 1 do
        local item = arr.getJSONObject(i)
        local itemName = item.getString("name")
        local itemType = item.getString("type")
        local itemPath = item.getString("path")
        local btn = Button(service)
        if itemType == "dir" then
          btn.setText("[Folder] " .. itemName)
        else
          btn.setText("[File] " .. itemName)
        end
        btn.setOnClickListener(View.OnClickListener({
          onClick = function()
            if itemType == "dir" then
              myReposModule.showFilesList(owner, repo, itemPath, showMainScreen)
            else
              httpRequestWithTimeout("Opening file...", "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/contents/" .. utils.urlEncode(itemPath), "GET", nil, function(fCode, fRes)
                if fCode == 200 then
                  local fObj = JSONObject(fRes)
                  local rawContent = fObj.getString("content")
                  local sha = fObj.getString("sha")
                  local downloadUrl = "https://raw.githubusercontent.com/" .. owner .. "/" .. repo .. "/main/" .. utils.urlEncode(itemPath)

                  local cleanB64 = (rawContent:gsub("%s+", ""))
                  local decodedBytes = Base64.decode(cleanB64, Base64.DEFAULT)
                  local decodedStr = String(decodedBytes, "UTF-8")

                  local editRoot = LinearLayout(service)
                  editRoot.setOrientation(LinearLayout.VERTICAL)
                  editRoot.setBackgroundColor(Color.BLACK)
                  editRoot.setPadding(20, 20, 20, 20)

                  local editScroll = ScrollView(service)
                  local editLayout = LinearLayout(service)
                  editLayout.setOrientation(LinearLayout.VERTICAL)

                  editLayout.addView(utils.createHeader("File: " .. itemName))

                  local lblName = TextView(service)
                  lblName.setText("File Name:")
                  lblName.setTextColor(Color.WHITE)
                  lblName.setTextSize(16)
                  lblName.setPadding(10, 10, 10, 5)
                  editLayout.addView(lblName)

                  local nameBox = EditText(service)
                  nameBox.setText(tostring(itemName))
                  nameBox.setTextColor(Color.WHITE)
                  nameBox.setHintTextColor(Color.GRAY)
                  editLayout.addView(nameBox)

                  local lblContent = TextView(service)
                  lblContent.setText("File Content:")
                  lblContent.setTextColor(Color.WHITE)
                  lblContent.setTextSize(16)
                  lblContent.setPadding(10, 20, 10, 5)
                  editLayout.addView(lblContent)

                  local editBox = EditText(service)
                  editBox.setText(tostring(decodedStr))
                  editBox.setTextColor(Color.WHITE)
                  editBox.setHintTextColor(Color.GRAY)
                  editLayout.addView(editBox)

                  local btnSave = Button(service)
                  btnSave.setText("Save Changes")
                  
                  local function updateFileEditState()
                    local nVal = tostring(nameBox.getText())
                    local cVal = tostring(editBox.getText())
                    btnSave.setEnabled(nVal ~= "" and cVal ~= "")
                  end
                  updateFileEditState()

                  local textWatcherObj = TextWatcher({
                    onTextChanged = function() updateFileEditState() end,
                    beforeTextChanged = function() end,
                    afterTextChanged = function() end
                  })
                  nameBox.addTextChangedListener(textWatcherObj)
                  editBox.addTextChangedListener(textWatcherObj)

                  btnSave.setOnClickListener(View.OnClickListener({
                    onClick = function()
                      local newName = tostring(nameBox.getText())
                      local newText = tostring(editBox.getText())
                      local encoded = Base64.encodeToString(String(newText).getBytes("UTF-8"), Base64.NO_WRAP)
                      
                      if utils.normalizeName(newName) ~= utils.normalizeName(itemName) and newName ~= "" then
                        local dirPath = itemPath:match("(.*/)") or ""
                        local newPath = dirPath .. newName
                        local jsonDelete = '{"message":"Renaming file","sha":"' .. sha .. '"}'
                        httpRequestWithTimeout("Renaming & Saving file...", "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/contents/" .. utils.urlEncode(itemPath), "DELETE", jsonDelete, function(dCode, dRes)
                          local jsonCreate = '{"message":"Created via GitHub Manager","content":"' .. encoded .. '"}'
                          httpRequestWithTimeout("Saving new file...", "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/contents/" .. utils.urlEncode(newPath), "PUT", jsonCreate, function(cCode, cRes)
                            myReposModule.showFilesList(owner, repo, path, showMainScreen)
                          end, function() myReposModule.showFilesList(owner, repo, path, showMainScreen) end)
                        end, function() myReposModule.showFilesList(owner, repo, path, showMainScreen) end)
                      else
                        local json = '{"message":"Updated via GitHub Manager","content":"' .. encoded .. '","sha":"' .. sha .. '"}'
                        httpRequestWithTimeout("Saving file...", "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/contents/" .. utils.urlEncode(itemPath), "PUT", json, function(sCode, sRes)
                          myReposModule.showFilesList(owner, repo, path, showMainScreen)
                        end, function() myReposModule.showFilesList(owner, repo, path, showMainScreen) end)
                      end
                    end
                  }))
                  editLayout.addView(btnSave)

                  local btnCopyRaw = Button(service)
                  btnCopyRaw.setText("Copy Raw URL")
                  btnCopyRaw.setOnClickListener(View.OnClickListener({
                    onClick = function()
                      service.copy(downloadUrl)
                    end
                  }))
                  editLayout.addView(btnCopyRaw)

                  local btnDeleteFile = Button(service)
                  btnDeleteFile.setText("Delete File")
                  btnDeleteFile.setOnClickListener(View.OnClickListener({
                    onClick = function()
                      local confRoot = LinearLayout(service)
                      confRoot.setOrientation(LinearLayout.VERTICAL)
                      confRoot.setBackgroundColor(Color.BLACK)
                      confRoot.setPadding(20, 20, 20, 20)

                      local confScroll = ScrollView(service)
                      local confLayout = LinearLayout(service)
                      confLayout.setOrientation(LinearLayout.VERTICAL)

                      confLayout.addView(utils.createHeader("Confirm File Deletion"))

                      local confInfo = TextView(service)
                      confInfo.setText("Are you sure you want to delete '" .. itemName .. "'?")
                      confInfo.setTextColor(Color.YELLOW)
                      confInfo.setTextSize(16)
                      confInfo.setPadding(20, 20, 20, 20)
                      confLayout.addView(confInfo)

                      local btnConfirmDel = Button(service)
                      btnConfirmDel.setText("Yes, Delete File")
                      btnConfirmDel.setOnClickListener(View.OnClickListener({
                        onClick = function()
                          local jsonDelete = '{"message":"Deleted via GitHub Manager","sha":"' .. sha .. '"}'
                          httpRequestWithTimeout("Deleting file...", "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/contents/" .. utils.urlEncode(itemPath), "DELETE", jsonDelete, function(dCode, dRes)
                            myReposModule.showFilesList(owner, repo, path, showMainScreen)
                          end, function() myReposModule.showFilesList(owner, repo, path, showMainScreen) end)
                        end
                      }))
                      confLayout.addView(btnConfirmDel)

                      local btnCancelDel = Button(service)
                      btnCancelDel.setText("Cancel")
                      btnCancelDel.setOnClickListener(View.OnClickListener({
                        onClick = function()
                          myReposModule.showFilesList(owner, repo, path, showMainScreen)
                        end
                      }))
                      confLayout.addView(btnCancelDel)

                      confScroll.addView(confLayout)
                      confRoot.addView(confScroll)
                      utils.enableBackKey(confRoot, function() myReposModule.showFilesList(owner, repo, path, showMainScreen) end)
                      utils.setScreen(confRoot)
                    end
                  }))
                  editLayout.addView(btnDeleteFile)

                  local btnCancel = Button(service)
                  btnCancel.setText("Cancel")
                  btnCancel.setOnClickListener(View.OnClickListener({
                    onClick = function() myReposModule.showFilesList(owner, repo, path, showMainScreen) end
                  }))
                  editLayout.addView(btnCancel)

                  editScroll.addView(editLayout)
                  editRoot.addView(editScroll)
                  utils.enableBackKey(editRoot, function() myReposModule.showFilesList(owner, repo, path, showMainScreen) end)
                  utils.setScreen(editRoot)
                end
              end, function() myReposModule.showFilesList(owner, repo, path, showMainScreen) end)
            end
          end
        }))
        layout.addView(btn)
      end
    end)

    if not hasItems then
      local info = TextView(service)
      info.setText("No files or folders found here.")
      info.setTextColor(Color.YELLOW)
      info.setTextSize(16)
      info.setPadding(20, 20, 20, 20)
      layout.addView(info)
    end

    local btnBack = Button(service)
    btnBack.setText("Back to Repo Menu")
    btnBack.setOnClickListener(View.OnClickListener({
      onClick = function() myReposModule.showRepoMenu(owner, repo, nil, showMainScreen) end
    }))
    layout.addView(btnBack)

    scroll.addView(layout)
    root.addView(scroll)
    utils.enableBackKey(root, function() myReposModule.showRepoMenu(owner, repo, nil, showMainScreen) end)
    utils.setScreen(root)
  end, function() myReposModule.showRepoMenu(owner, repo, nil, showMainScreen) end)
end

function myReposModule.showRepoMenu(owner, repo, isPrivate, showMainScreen)
  if utils.loadToken() == "" then
    tokenModule.showTokenMissingScreen(showMainScreen)
    return
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
      myReposModule.showRepoMenu(owner, repo, fetchedPrivate, showMainScreen)
    end, function() showMainScreen() end)
    return
  end

  local root = LinearLayout(service)
  root.setOrientation(LinearLayout.VERTICAL)
  root.setBackgroundColor(Color.BLACK)
  root.setPadding(20, 20, 20, 20)

  local scroll = ScrollView(service)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)

  layout.addView(utils.createHeader("Repository: " .. repo))

  local btnBrowse = Button(service)
  btnBrowse.setText("Browse & Edit Files")
  btnBrowse.setOnClickListener(View.OnClickListener({
    onClick = function() myReposModule.showFilesList(owner, repo, "", showMainScreen) end
  }))
  layout.addView(btnBrowse)

  local btnCopyRepoUrl = Button(service)
  btnCopyRepoUrl.setText("Copy Repo Link")
  btnCopyRepoUrl.setOnClickListener(View.OnClickListener({
    onClick = function()
      local repoUrl = "https://github.com/" .. owner .. "/" .. repo
      service.copy(repoUrl)
    end
  }))
  layout.addView(btnCopyRepoUrl)

  local btnCopyZipUrl = Button(service)
  btnCopyZipUrl.setText("Copy Zip Link")
  btnCopyZipUrl.setOnClickListener(View.OnClickListener({
    onClick = function()
      local zipUrl = "https://github.com/" .. owner .. "/" .. repo .. "/archive/refs/heads/main.zip"
      service.copy(zipUrl)
    end
  }))
  layout.addView(btnCopyZipUrl)

  local btnUpload = Button(service)
  btnUpload.setText("Upload New File")
  btnUpload.setOnClickListener(View.OnClickListener({
    onClick = function()
      local uRoot = LinearLayout(service)
      uRoot.setOrientation(LinearLayout.VERTICAL)
      uRoot.setBackgroundColor(Color.BLACK)
      uRoot.setPadding(20, 20, 20, 20)

      local uScroll = ScrollView(service)
      local uLayout = LinearLayout(service)
      uLayout.setOrientation(LinearLayout.VERTICAL)

      uLayout.addView(utils.createHeader("New File in " .. repo))

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
          local fileName = tostring(inputName.getText())
          local fileContent = tostring(inputContent.getText())
          if fileName ~= "" then
            httpRequestWithTimeout("Checking file...", "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/contents/", "GET", nil, function(code, res)
              local found = false
              local existingFileName = ""
              local fileSha = ""
              if code == 200 then
                pcall(function()
                  local arr = JSONArray(res)
                  for i = 0, arr.length() - 1 do
                    local item = arr.getJSONObject(i)
                    local name = item.getString("name")
                    if utils.normalizeName(name) == utils.normalizeName(fileName) then
                      found = true
                      existingFileName = name
                      fileSha = item.getString("sha")
                      break
                    end
                  end
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
                httpRequestWithTimeout("Saving file...", "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/contents/" .. utils.urlEncode(shaToUse and shaToUse ~= "" and existingFileName or fileName), "PUT", json, function(cCode, cRes)
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
                      onClick = function() myReposModule.showRepoMenu(owner, repo, isPrivate, showMainScreen) end
                    }))
                    succLayout.addView(btnOk)

                    succScroll.addView(succLayout)
                    succRoot.addView(succScroll)
                    utils.enableBackKey(succRoot, function() myReposModule.showRepoMenu(owner, repo, isPrivate, showMainScreen) end)
                    utils.setScreen(succRoot)
                  else
                    myReposModule.showRepoMenu(owner, repo, isPrivate, showMainScreen)
                  end
                end, function() myReposModule.showRepoMenu(owner, repo, isPrivate, showMainScreen) end)
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
                info.setText("File '" .. existingFileName .. "' already exists. Do you want to overwrite it?")
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
                  onClick = function() myReposModule.showRepoMenu(owner, repo, isPrivate, showMainScreen) end
                }))
                confLayout.addView(btnNo)

                confScroll.addView(confLayout)
                confRoot.addView(confScroll)
                utils.enableBackKey(confRoot, function() myReposModule.showRepoMenu(owner, repo, isPrivate, showMainScreen) end)
                utils.setScreen(confRoot)
              else
                doSaveFile(nil)
              end
            end, function() myReposModule.showRepoMenu(owner, repo, isPrivate, showMainScreen) end)
          end
        end
      }))
      uLayout.addView(btnSubmit)

      local btnBack = Button(service)
      btnBack.setText("Back")
      btnBack.setOnClickListener(View.OnClickListener({
        onClick = function() myReposModule.showRepoMenu(owner, repo, isPrivate, showMainScreen) end
      }))
      uLayout.addView(btnBack)

      uScroll.addView(uLayout)
      uRoot.addView(uScroll)
      utils.enableBackKey(uRoot, function() myReposModule.showRepoMenu(owner, repo, isPrivate, showMainScreen) end)
      utils.setScreen(uRoot)
    end
  }))
  layout.addView(btnUpload)

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
                myReposModule.showRepoMenu(owner, newRName, isPrivate, showMainScreen)
              else
                myReposModule.showRepoMenu(owner, repo, isPrivate, showMainScreen)
              end
            end, function() myReposModule.showRepoMenu(owner, repo, isPrivate, showMainScreen) end)
          end
        end
      }))
      rLayout.addView(btnSubmitRename)

      local btnBackRen = Button(service)
      btnBackRen.setText("Back")
      btnBackRen.setOnClickListener(View.OnClickListener({
        onClick = function() myReposModule.showRepoMenu(owner, repo, isPrivate, showMainScreen) end
      }))
      rLayout.addView(btnBackRen)

      rScroll.addView(rLayout)
      rRoot.addView(rScroll)
      utils.enableBackKey(rRoot, function() myReposModule.showRepoMenu(owner, repo, isPrivate, showMainScreen) end)
      utils.setScreen(rRoot)
    end
  }))
  layout.addView(btnRenameRepo)

  local visStatusStr = isPrivate and "Private" or "Public"
  local btnToggleVisibility = Button(service)
  btnToggleVisibility.setText("Visibility: " .. visStatusStr)
  btnToggleVisibility.setOnClickListener(View.OnClickListener({
    onClick = function()
      local vRoot = LinearLayout(service)
      vRoot.setOrientation(LinearLayout.VERTICAL)
      vRoot.setBackgroundColor(Color.BLACK)
      vRoot.setPadding(20, 20, 20, 20)

      local vScroll = ScrollView(service)
      local vLayout = LinearLayout(service)
      vLayout.setOrientation(LinearLayout.VERTICAL)

      vLayout.addView(utils.createHeader("Visibility: " .. repo))

      local vInfo = TextView(service)
      vInfo.setText("Current Visibility: " .. visStatusStr)
      vInfo.setTextColor(Color.YELLOW)
      vInfo.setTextSize(16)
      vInfo.setPadding(20, 20, 20, 20)
      vLayout.addView(vInfo)

      if isPrivate then
        local btnMakePublic = Button(service)
        btnMakePublic.setText("Make Public")
        btnMakePublic.setOnClickListener(View.OnClickListener({
          onClick = function()
            httpRequestWithTimeout("Changing to Public...", "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo), "PATCH", '{"private":false}', function(pCode, pRes)
              myReposModule.showRepoMenu(owner, repo, false, showMainScreen)
            end, function() myReposModule.showRepoMenu(owner, repo, isPrivate, showMainScreen) end)
          end
        }))
        vLayout.addView(btnMakePublic)
      else
        local btnMakePrivate = Button(service)
        btnMakePrivate.setText("Make Private")
        btnMakePrivate.setOnClickListener(View.OnClickListener({
          onClick = function()
            httpRequestWithTimeout("Changing to Private...", "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo), "PATCH", '{"private":true}', function(pCode, pRes)
              myReposModule.showRepoMenu(owner, repo, true, showMainScreen)
            end, function() myReposModule.showRepoMenu(owner, repo, isPrivate, showMainScreen) end)
          end
        }))
        vLayout.addView(btnMakePrivate)
      end

      local btnBackVis = Button(service)
      btnBackVis.setText("Cancel")
      btnBackVis.setOnClickListener(View.OnClickListener({
        onClick = function() myReposModule.showRepoMenu(owner, repo, isPrivate, showMainScreen) end
      }))
      vLayout.addView(btnBackVis)

      vScroll.addView(vLayout)
      vRoot.addView(vScroll)
      utils.enableBackKey(vRoot, function() myReposModule.showRepoMenu(owner, repo, isPrivate, showMainScreen) end)
      utils.setScreen(vRoot)
    end
  }))
  layout.addView(btnToggleVisibility)

  local btnDelete = Button(service)
  btnDelete.setText("Delete Repository")
  btnDelete.setOnClickListener(View.OnClickListener({
    onClick = function()
      local rConfRoot = LinearLayout(service)
      rConfRoot.setOrientation(LinearLayout.VERTICAL)
      rConfRoot.setBackgroundColor(Color.BLACK)
      rConfRoot.setPadding(20, 20, 20, 20)

      local rConfScroll = ScrollView(service)
      local rConfLayout = LinearLayout(service)
      rConfLayout.setOrientation(LinearLayout.VERTICAL)

      rConfLayout.addView(utils.createHeader("Confirm Repository Deletion"))

      local rConfInfo = TextView(service)
      rConfInfo.setText("Are you sure you want to delete repository '" .. repo .. "'? This action cannot be undone.")
      rConfInfo.setTextColor(Color.YELLOW)
      rConfInfo.setTextSize(16)
      rConfInfo.setPadding(20, 20, 20, 20)
      rConfLayout.addView(rConfInfo)

      local btnConfirmRepoDel = Button(service)
      btnConfirmRepoDel.setText("Yes, Delete Repository")
      btnConfirmRepoDel.setOnClickListener(View.OnClickListener({
        onClick = function()
          httpRequestWithTimeout("Deleting repository...", "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo), "DELETE", nil, function(dCode, dRes)
            myReposModule.showMyRepos(showMainScreen)
          end, function() myReposModule.showRepoMenu(owner, repo, isPrivate, showMainScreen) end)
        end
      }))
      rConfLayout.addView(btnConfirmRepoDel)

      local btnCancelRepoDel = Button(service)
      btnCancelRepoDel.setText("Cancel")
      btnCancelRepoDel.setOnClickListener(View.OnClickListener({
        onClick = function()
          myReposModule.showRepoMenu(owner, repo, isPrivate, showMainScreen)
        end
      }))
      rConfLayout.addView(btnCancelRepoDel)

      rConfScroll.addView(rConfLayout)
      rConfRoot.addView(rConfScroll)
      utils.enableBackKey(rConfRoot, function() myReposModule.showRepoMenu(owner, repo, isPrivate, showMainScreen) end)
      utils.setScreen(rConfRoot)
    end
  }))
  layout.addView(btnDelete)

  local btnBackMain = Button(service)
  btnBackMain.setText("Back to All Repositories")
  btnBackMain.setOnClickListener(View.OnClickListener({
    onClick = function() myReposModule.showMyRepos(showMainScreen) end
  }))
  layout.addView(btnBackMain)

  scroll.addView(layout)
  root.addView(scroll)
  utils.enableBackKey(root, function() myReposModule.showMyRepos(showMainScreen) end)
  utils.setScreen(root)
end

function myReposModule.showMyRepos(showMainScreen)
  if utils.loadToken() == "" then
    tokenModule.showTokenMissingScreen(showMainScreen)
    return
  end

  httpRequestWithTimeout("Fetching Repositories...", "https://api.github.com/user/repos?per_page=100", "GET", nil, function(code, res)
    if code ~= 200 then
      local errRoot = LinearLayout(service)
      errRoot.setOrientation(LinearLayout.VERTICAL)
      errRoot.setBackgroundColor(Color.BLACK)
      errRoot.setPadding(20, 20, 20, 20)

      local errScroll = ScrollView(service)
      local errLayout = LinearLayout(service)
      errLayout.setOrientation(LinearLayout.VERTICAL)

      errLayout.addView(utils.createHeader("Error " .. code .. ": Check Token"))
      local btnBack = Button(service)
      btnBack.setText("Back")
      btnBack.setOnClickListener(View.OnClickListener({
        onClick = function() showMainScreen() end
      }))
      errLayout.addView(btnBack)

      errScroll.addView(errLayout)
      errRoot.addView(errScroll)
      utils.enableBackKey(errRoot, function() showMainScreen() end)
      utils.setScreen(errRoot)
      return
    end

    local rRoot = LinearLayout(service)
    rRoot.setOrientation(LinearLayout.VERTICAL)
    rRoot.setBackgroundColor(Color.BLACK)
    rRoot.setPadding(20, 20, 20, 20)

    local rScroll = ScrollView(service)
    local rLayout = LinearLayout(service)
    rLayout.setOrientation(LinearLayout.VERTICAL)

    rLayout.addView(utils.createHeader("Select Repository"))

    pcall(function()
      local arr = JSONArray(res)
      if arr.length() == 0 then
        local info = TextView(service)
        info.setText("No repositories found in your account.")
        info.setTextColor(Color.YELLOW)
        info.setTextSize(16)
        info.setPadding(20, 20, 20, 20)
        rLayout.addView(info)
      else
        for i = 0, arr.length() - 1 do
          local obj = arr.getJSONObject(i)
          local rName = obj.getString("name")
          local ownerObj = obj.getJSONObject("owner")
          local ownerName = ownerObj.getString("login")
          local isPriv = obj.getBoolean("private")
          local btn = Button(service)
          btn.setText(rName)
          btn.setOnClickListener(View.OnClickListener({
            onClick = function()
              myReposModule.showRepoMenu(ownerName, rName, isPriv, showMainScreen)
            end
          }))
          rLayout.addView(btn)
        end
      end
    end)

    local btnBack = Button(service)
    btnBack.setText("Back")
    btnBack.setOnClickListener(View.OnClickListener({
      onClick = function() showMainScreen() end
    }))
    rLayout.addView(btnBack)

    rScroll.addView(rLayout)
    rRoot.addView(rScroll)
    utils.enableBackKey(rRoot, function() showMainScreen() end)
    utils.setScreen(rRoot)
  end, function() showMainScreen() end)
end

return myReposModule