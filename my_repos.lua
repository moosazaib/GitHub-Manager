local utils = require("utils")
local tokenModule = require("token_module")
local createRepoModule = require("create_repo")
local repoOptionsModule = require("repo_options")

local Handler = Handler or luajava.bindClass("android.os.Handler")
local Looper = Looper or luajava.bindClass("android.os.Looper")
local Runnable = Runnable or luajava.bindClass("java.lang.Runnable")
local Toast = Toast or luajava.bindClass("android.os.Toast")
local String = String or luajava.bindClass("java.lang.String")
local Base64 = Base64 or luajava.bindClass("android.util.Base64")
local View = View or luajava.bindClass("android.view.View")
local Context = Context or luajava.bindClass("android.content.Context")
local Vibrator = Vibrator or luajava.bindClass("android.os.Vibrator")
local CheckBox = CheckBox or luajava.bindClass("android.widget.CheckBox")
local Color = Color or luajava.bindClass("android.graphics.Color")
local LinearLayout = LinearLayout or luajava.bindClass("android.widget.LinearLayout")
local ScrollView = ScrollView or luajava.bindClass("android.widget.ScrollView")
local TextView = TextView or luajava.bindClass("android.widget.TextView")
local Button = Button or luajava.bindClass("android.widget.Button")
local EditText = EditText or luajava.bindClass("android.widget.EditText")
local JSONArray = JSONArray or luajava.bindClass("org.json.JSONArray")
local JSONObject = JSONObject or luajava.bindClass("org.json.JSONObject")
local TextWatcher = TextWatcher or luajava.bindClass("android.widget.TextWatcher")

local myReposModule = {}

local function doVibrate()
  pcall(function()
    local v = service.getSystemService(Context.VIBRATOR_SERVICE)
    if v then
      v.vibrate(50)
    end
  end)
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

function myReposModule.showFilesList(owner, repo, path, showMainScreen)
  if utils.loadToken() == "" then
    tokenModule.showTokenMissingScreen(showMainScreen)
    return
  end

  local parentPath = (path and path ~= "") and (path:match("(.+)/[^/]+$") or "") or nil

  local url = "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/contents/" .. utils.urlEncode(path or "")
  httpRequestWithTimeout("Loading files...", url, "GET", nil, function(code, res)
    local itemsList = {}
    local hasItems = false

    if code == 200 then
      pcall(function()
        local arr = JSONArray(res)
        if arr.length() > 0 then
          hasItems = true
        end
        for i = 0, arr.length() - 1 do
          local item = arr.getJSONObject(i)
          local shaVal = ""
          pcall(function()
            if item.has("sha") and not item.isNull("sha") then
              shaVal = item.getString("sha")
            end
          end)
          table.insert(itemsList, {
            name = item.getString("name"),
            type = item.getString("type"),
            path = item.getString("path"),
            sha = shaVal
          })
        end
      end)
    end

    local isSelectionMode = false
    local selectedMap = {}

    local renderScreen
    renderScreen = function()
      local root = LinearLayout(service)
      root.setOrientation(LinearLayout.VERTICAL)
      root.setBackgroundColor(Color.BLACK)
      root.setPadding(20, 20, 20, 20)

      local scroll = ScrollView(service)
      local layout = LinearLayout(service)
      layout.setOrientation(LinearLayout.VERTICAL)

      layout.addView(utils.createHeader("Repository: " .. repo))

      local btnMoreOptions = Button(service)
      btnMoreOptions.setText("More Options")
      btnMoreOptions.setOnClickListener(View.OnClickListener({
        onClick = function()
          repoOptionsModule.showOptions(owner, repo, nil, showMainScreen, function()
            myReposModule.showFilesList(owner, repo, path, showMainScreen)
          end, function()
            myReposModule.showMyRepos(showMainScreen)
          end)
        end
      }))
      layout.addView(btnMoreOptions)

      local btnSelectAll
      local updateSelectAllText = function()
        if not btnSelectAll then return end
        local countSelected = 0
        for _ in pairs(selectedMap) do
          countSelected = countSelected + 1
        end
        if countSelected == #itemsList and #itemsList > 0 then
          btnSelectAll.setText("Deselect All")
        else
          btnSelectAll.setText("Select All")
        end
      end

      if isSelectionMode then
        btnSelectAll = Button(service)
        updateSelectAllText()

        btnSelectAll.setOnClickListener(View.OnClickListener({
          onClick = function()
            local countSelected = 0
            for _ in pairs(selectedMap) do
              countSelected = countSelected + 1
            end
            if countSelected == #itemsList and #itemsList > 0 then
              selectedMap = {}
              isSelectionMode = false
              renderScreen()
            else
              selectedMap = {}
              for _, it in ipairs(itemsList) do
                selectedMap[it.path] = true
              end
              renderScreen()
            end
          end
        }))
        layout.addView(btnSelectAll)

        local btnDeleteSelected = Button(service)
        btnDeleteSelected.setText("Delete Selected Files")
        btnDeleteSelected.setOnClickListener(View.OnClickListener({
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
            confInfo.setText("Are you sure you want to delete selected files?")
            confInfo.setTextColor(Color.YELLOW)
            confInfo.setTextSize(16)
            confInfo.setPadding(20, 20, 20, 20)
            confLayout.addView(confInfo)

            local btnConfirmDel = Button(service)
            btnConfirmDel.setText("Yes, Delete Selected Files")
            btnConfirmDel.setOnClickListener(View.OnClickListener({
              onClick = function()
                local toDelete = {}
                for _, it in ipairs(itemsList) do
                  if selectedMap[it.path] then
                    table.insert(toDelete, it)
                  end
                end

                local function doDelete(idx)
                  if idx > #toDelete then
                    myReposModule.showFilesList(owner, repo, path, showMainScreen)
                    return
                  end
                  local itemDel = toDelete[idx]
                  local jsonDelete = '{"message":"Deleted via GitHub Manager","sha":"' .. itemDel.sha .. '"}'
                  httpRequestWithTimeout("Deleting files...", "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/contents/" .. utils.urlEncode(itemDel.path), "DELETE", jsonDelete, function(dCode, dRes)
                    doDelete(idx + 1)
                  end, function()
                    doDelete(idx + 1)
                  end)
                end

                doDelete(1)
              end
            }))
            confLayout.addView(btnConfirmDel)

            local btnCancelDel = Button(service)
            btnCancelDel.setText("Cancel")
            btnCancelDel.setOnClickListener(View.OnClickListener({
              onClick = function()
                renderScreen()
              end
            }))
            confLayout.addView(btnCancelDel)

            confScroll.addView(confLayout)
            confRoot.addView(confScroll)
            utils.enableBackKey(confRoot, function()
              renderScreen()
            end)
            utils.setScreen(confRoot)
          end
        }))
        layout.addView(btnDeleteSelected)
      end

      if code == 404 then
        local info = TextView(service)
        info.setText("This repository is empty or has no files in this folder.")
        info.setTextColor(Color.YELLOW)
        info.setTextSize(16)
        info.setPadding(20, 20, 20, 20)
        layout.addView(info)
      elseif code ~= 200 then
        local info = TextView(service)
        info.setText("Error loading files: " .. code)
        info.setTextColor(Color.RED)
        info.setTextSize(16)
        info.setPadding(20, 20, 20, 20)
        layout.addView(info)
      else
        if not hasItems then
          local info = TextView(service)
          info.setText("No files or folders found here.")
          info.setTextColor(Color.YELLOW)
          info.setTextSize(16)
          info.setPadding(20, 20, 20, 20)
          layout.addView(info)
        else
          for _, itemData in ipairs(itemsList) do
            local itemName = itemData.name
            local itemType = itemData.type
            local itemPath = itemData.path

            if isSelectionMode then
              local cb = CheckBox(service)
              if itemType == "dir" then
                cb.setText("[Folder] " .. itemName)
              else
                cb.setText("[File] " .. itemName)
              end
              cb.setTextColor(Color.WHITE)
              cb.setChecked(selectedMap[itemPath] == true)

              cb.setOnClickListener(View.OnClickListener({
                onClick = function()
                  if cb.isChecked() then
                    selectedMap[itemPath] = true
                  else
                    selectedMap[itemPath] = nil
                  end

                  local selCount = 0
                  for _ in pairs(selectedMap) do
                    selCount = selCount + 1
                  end

                  if selCount == 0 then
                    isSelectionMode = false
                    renderScreen()
                  else
                    updateSelectAllText()
                  end
                end
              }))
              layout.addView(cb)
            else
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

                        local isBinary = false
                        local decodedLuaStr = ""

                        if cleanB64 ~= "" then
                          pcall(function()
                            local decodedBytes = Base64.decode(cleanB64, Base64.DEFAULT)
                            local utfStr = String(decodedBytes, "UTF-8")
                            local strVal = tostring(utfStr)

                            if utfStr.indexOf(0) >= 0 or utfStr.indexOf(65533) >= 0 or strVal:find("\0", 1, true) or strVal:gsub("%s+", "") == "" then
                              isBinary = true
                            else
                              decodedLuaStr = strVal
                            end
                          end)
                        else
                          isBinary = true
                        end

                        if isBinary or (cleanB64 ~= "" and decodedLuaStr:gsub("%s+", "") == "") then
                          isBinary = true
                          decodedLuaStr = ""
                        end

                        local editRoot = LinearLayout(service)
                        editRoot.setOrientation(LinearLayout.VERTICAL)
                        editRoot.setBackgroundColor(Color.BLACK)
                        editRoot.setPadding(20, 20, 20, 20)

                        local editScroll = ScrollView(service)
                        local editLayout = LinearLayout(service)
                        editLayout.setOrientation(LinearLayout.VERTICAL)

                        editLayout.addView(utils.createHeader("File: " .. itemName))

                        if isBinary then
                          local lblBinary = TextView(service)
                          lblBinary.setText("No text was found in this file, so editing has been disabled for file safety.")
                          lblBinary.setTextColor(Color.YELLOW)
                          lblBinary.setTextSize(14)
                          lblBinary.setPadding(10, 15, 10, 15)
                          editLayout.addView(lblBinary)
                        else
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
                          editBox.setText(decodedLuaStr)
                          editBox.setTextColor(Color.WHITE)
                          editBox.setHintTextColor(Color.GRAY)
                          editLayout.addView(editBox)

                          local btnSave = Button(service)
                          btnSave.setText("Save Changes")
                          
                          local function updateFileEditState()
                            local nVal = tostring(nameBox.getText())
                            btnSave.setEnabled(nVal ~= "")
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
                        end

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
                            confLayout = LinearLayout(service)
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
                                utils.enableBackKey(editRoot, function() myReposModule.showFilesList(owner, repo, path, showMainScreen) end)
                                utils.setScreen(editRoot)
                              end
                            }))
                            confLayout.addView(btnCancelDel)

                            confScroll.addView(confLayout)
                            confRoot.addView(confScroll)
                            utils.enableBackKey(confRoot, function()
                              utils.enableBackKey(editRoot, function() myReposModule.showFilesList(owner, repo, path, showMainScreen) end)
                              utils.setScreen(editRoot)
                            end)
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

              btn.setOnLongClickListener(View.OnLongClickListener({
                onLongClick = function()
                  doVibrate()
                  isSelectionMode = true
                  selectedMap = {}
                  selectedMap[itemPath] = true
                  renderScreen()
                  return true
                end
              }))
              layout.addView(btn)
            end
          end
        end
      end

      local btnBack = Button(service)
      if path and path ~= "" then
        btnBack.setText("Back to Previous Folder")
        btnBack.setOnClickListener(View.OnClickListener({
          onClick = function()
            if isSelectionMode then
              isSelectionMode = false
              selectedMap = {}
              renderScreen()
            else
              myReposModule.showFilesList(owner, repo, parentPath, showMainScreen)
            end
          end
        }))
      else
        btnBack.setText("Back to All Repositories")
        btnBack.setOnClickListener(View.OnClickListener({
          onClick = function()
            if isSelectionMode then
              isSelectionMode = false
              selectedMap = {}
              renderScreen()
            else
              myReposModule.showMyRepos(showMainScreen)
            end
          end
        }))
      end
      layout.addView(btnBack)

      scroll.addView(layout)
      root.addView(scroll)

      local backHandler = function()
        if isSelectionMode then
          isSelectionMode = false
          selectedMap = {}
          renderScreen()
        elseif path and path ~= "" then
          myReposModule.showFilesList(owner, repo, parentPath, showMainScreen)
        else
          myReposModule.showMyRepos(showMainScreen)
        end
      end
      utils.enableBackKey(root, backHandler)
      utils.setScreen(root)
    end

    renderScreen()
  end, function()
    if path and path ~= "" then
      myReposModule.showFilesList(owner, repo, parentPath, showMainScreen)
    else
      myReposModule.showMyRepos(showMainScreen)
    end
  end)
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

    local repoList = {}
    pcall(function()
      local arr = JSONArray(res)
      for i = 0, arr.length() - 1 do
        local obj = arr.getJSONObject(i)
        local rName = obj.getString("name")
        local ownerObj = obj.getJSONObject("owner")
        local ownerName = ownerObj.getString("login")
        table.insert(repoList, { name = rName, owner = ownerName, key = ownerName .. "/" .. rName })
      end
    end)

    local isSelectionMode = false
    local selectedMap = {}

    local renderScreen
    renderScreen = function()
      local rRoot = LinearLayout(service)
      rRoot.setOrientation(LinearLayout.VERTICAL)
      rRoot.setBackgroundColor(Color.BLACK)
      rRoot.setPadding(20, 20, 20, 20)

      local rScroll = ScrollView(service)
      local rLayout = LinearLayout(service)
      rLayout.setOrientation(LinearLayout.VERTICAL)

      rLayout.addView(utils.createHeader("Select Repository"))

      local btnCreateRepo = Button(service)
      btnCreateRepo.setText("Create New Repository")
      btnCreateRepo.setOnClickListener(View.OnClickListener({
        onClick = function()
          createRepoModule.showCreateRepoScreen(function()
            myReposModule.showMyRepos(showMainScreen)
          end)
        end
      }))
      rLayout.addView(btnCreateRepo)

      local btnSelectAll
      local updateSelectAllText = function()
        if not btnSelectAll then return end
        local countSelected = 0
        for _ in pairs(selectedMap) do
          countSelected = countSelected + 1
        end
        if countSelected == #repoList and #repoList > 0 then
          btnSelectAll.setText("Deselect All")
        else
          btnSelectAll.setText("Select All")
        end
      end

      if isSelectionMode then
        btnSelectAll = Button(service)
        updateSelectAllText()

        btnSelectAll.setOnClickListener(View.OnClickListener({
          onClick = function()
            local countSelected = 0
            for _ in pairs(selectedMap) do
              countSelected = countSelected + 1
            end
            if countSelected == #repoList and #repoList > 0 then
              selectedMap = {}
              isSelectionMode = false
              renderScreen()
            else
              selectedMap = {}
              for _, r in ipairs(repoList) do
                selectedMap[r.key] = true
              end
              renderScreen()
            end
          end
        }))
        rLayout.addView(btnSelectAll)

        local btnDeleteSelected = Button(service)
        btnDeleteSelected.setText("Delete Selected Repositories")
        btnDeleteSelected.setOnClickListener(View.OnClickListener({
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
            confInfo.setText("Are you sure you want to delete selected repositories?")
            confInfo.setTextColor(Color.YELLOW)
            confInfo.setTextSize(16)
            confInfo.setPadding(20, 20, 20, 20)
            confLayout.addView(confInfo)

            local btnConfirmDel = Button(service)
            btnConfirmDel.setText("Yes, Delete Selected Repositories")
            btnConfirmDel.setOnClickListener(View.OnClickListener({
              onClick = function()
                local toDelete = {}
                for _, r in ipairs(repoList) do
                  if selectedMap[r.key] then
                    table.insert(toDelete, r)
                  end
                end

                local function doDelete(idx)
                  if idx > #toDelete then
                    myReposModule.showMyRepos(showMainScreen)
                    return
                  end
                  local itemDel = toDelete[idx]
                  httpRequestWithTimeout("Deleting repositories...", "https://api.github.com/repos/" .. utils.urlEncode(itemDel.owner) .. "/" .. utils.urlEncode(itemDel.name), "DELETE", nil, function(dCode, dRes)
                    doDelete(idx + 1)
                  end, function()
                    doDelete(idx + 1)
                  end)
                end

                doDelete(1)
              end
            }))
            confLayout.addView(btnConfirmDel)

            local btnCancelDel = Button(service)
            btnCancelDel.setText("Cancel")
            btnCancelDel.setOnClickListener(View.OnClickListener({
              onClick = function()
                renderScreen()
              end
            }))
            confLayout.addView(btnCancelDel)

            confScroll.addView(confLayout)
            confRoot.addView(confScroll)
            utils.enableBackKey(confRoot, function()
              renderScreen()
            end)
            utils.setScreen(confRoot)
          end
        }))
        rLayout.addView(btnDeleteSelected)
      end

      if #repoList == 0 then
        local info = TextView(service)
        info.setText("No repositories found in your account.")
        info.setTextColor(Color.YELLOW)
        info.setTextSize(16)
        info.setPadding(20, 20, 20, 20)
        rLayout.addView(info)
      else
        for _, rData in ipairs(repoList) do
          local rName = rData.name
          local ownerName = rData.owner
          local rKey = rData.key

          if isSelectionMode then
            local cb = CheckBox(service)
            cb.setText(rName)
            cb.setTextColor(Color.WHITE)
            cb.setChecked(selectedMap[rKey] == true)

            cb.setOnClickListener(View.OnClickListener({
              onClick = function()
                if cb.isChecked() then
                  selectedMap[rKey] = true
                else
                  selectedMap[rKey] = nil
                end

                local selCount = 0
                for _ in pairs(selectedMap) do
                  selCount = selCount + 1
                end

                if selCount == 0 then
                  isSelectionMode = false
                  renderScreen()
                else
                  updateSelectAllText()
                end
              end
            }))
            rLayout.addView(cb)
          else
            local btn = Button(service)
            btn.setText(rName)
            btn.setOnClickListener(View.OnClickListener({
              onClick = function()
                myReposModule.showFilesList(ownerName, rName, "", showMainScreen)
              end
            }))
            btn.setOnLongClickListener(View.OnLongClickListener({
              onLongClick = function()
                doVibrate()
                isSelectionMode = true
                selectedMap = {}
                selectedMap[rKey] = true
                renderScreen()
                return true
              end
            }))
            rLayout.addView(btn)
          end
        end
      end

      local btnBack = Button(service)
      btnBack.setText("Back")
      btnBack.setOnClickListener(View.OnClickListener({
        onClick = function()
          if isSelectionMode then
            isSelectionMode = false
            selectedMap = {}
            renderScreen()
          else
            showMainScreen()
          end
        end
      }))
      rLayout.addView(btnBack)

      rScroll.addView(rLayout)
      rRoot.addView(rScroll)

      local backHandler = function()
        if isSelectionMode then
          isSelectionMode = false
          selectedMap = {}
          renderScreen()
        else
          showMainScreen()
        end
      end

      utils.enableBackKey(rRoot, backHandler)
      utils.setScreen(rRoot)
    end

    renderScreen()
  end, function() showMainScreen() end)
end

return myReposModule
