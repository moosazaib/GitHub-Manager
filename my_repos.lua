local utils = require("utils")
local tokenModule = require("token_module")
local createRepoModule = require("create_repo")
local repoOptionsModule = require("repo_options")

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

  local parentPath = (path and path ~= "") and (path:match("(.+)/[^/]+$") or "") or nil

  local url = "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo) .. "/contents/" .. utils.urlEncode(path or "")
  httpRequestWithTimeout("Loading files...", url, "GET", nil, function(code, res)
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
    end

    local btnBack = Button(service)
    if path and path ~= "" then
      btnBack.setText("Back to Previous Folder")
      btnBack.setOnClickListener(View.OnClickListener({
        onClick = function() myReposModule.showFilesList(owner, repo, parentPath, showMainScreen) end
      }))
    else
      btnBack.setText("Back to All Repositories")
      btnBack.setOnClickListener(View.OnClickListener({
        onClick = function() myReposModule.showMyRepos(showMainScreen) end
      }))
    end
    layout.addView(btnBack)

    scroll.addView(layout)
    root.addView(scroll)

    local backHandler = function()
      if path and path ~= "" then
        myReposModule.showFilesList(owner, repo, parentPath, showMainScreen)
      else
        myReposModule.showMyRepos(showMainScreen)
      end
    end
    utils.enableBackKey(root, backHandler)
    utils.setScreen(root)
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
          local btn = Button(service)
          btn.setText(rName)
          btn.setOnClickListener(View.OnClickListener({
            onClick = function()
              myReposModule.showFilesList(ownerName, rName, "", showMainScreen)
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