local utils = require("utils")
local tokenModule = require("token_module")
local createRepoModule = require("create_repo")

local Handler = Handler or luajava.bindClass("android.os.Handler")
local Looper = Looper or luajava.bindClass("android.os.Looper")
local Runnable = Runnable or luajava.bindClass("java.lang.Runnable")
local Toast = Toast or luajava.bindClass("android.os.Toast")

local repoOptionsModule = {}

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

function repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted)
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
      repoOptionsModule.showOptions(owner, repo, fetchedPrivate, showMainScreen, onBackToRepo, onRepoDeleted)
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
                      onClick = function() onBackToRepo() end
                    }))
                    succLayout.addView(btnOk)

                    succScroll.addView(succLayout)
                    succRoot.addView(succScroll)
                    utils.enableBackKey(succRoot, function() onBackToRepo() end)
                    utils.setScreen(succRoot)
                  else
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
                  onClick = function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted) end
                }))
                confLayout.addView(btnNo)

                confScroll.addView(confLayout)
                confRoot.addView(confScroll)
                utils.enableBackKey(confRoot, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted) end)
                utils.setScreen(confRoot)
              else
                doSaveFile(nil)
              end
            end, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted) end)
          end
        end
      }))
      uLayout.addView(btnSubmit)

      local btnBack = Button(service)
      btnBack.setText("Back")
      btnBack.setOnClickListener(View.OnClickListener({
        onClick = function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted) end
      }))
      uLayout.addView(btnBack)

      uScroll.addView(uLayout)
      uRoot.addView(uScroll)
      utils.enableBackKey(uRoot, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted) end)
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
                repoOptionsModule.showOptions(owner, newRName, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted)
              else
                repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted)
              end
            end, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted) end)
          end
        end
      }))
      rLayout.addView(btnSubmitRename)

      local btnBackRen = Button(service)
      btnBackRen.setText("Back")
      btnBackRen.setOnClickListener(View.OnClickListener({
        onClick = function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted) end
      }))
      rLayout.addView(btnBackRen)

      rScroll.addView(rLayout)
      rRoot.addView(rScroll)
      utils.enableBackKey(rRoot, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted) end)
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
              repoOptionsModule.showOptions(owner, repo, false, showMainScreen, onBackToRepo, onRepoDeleted)
            end, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted) end)
          end
        }))
        vLayout.addView(btnMakePublic)
      else
        local btnMakePrivate = Button(service)
        btnMakePrivate.setText("Make Private")
        btnMakePrivate.setOnClickListener(View.OnClickListener({
          onClick = function()
            httpRequestWithTimeout("Changing to Private...", "https://api.github.com/repos/" .. utils.urlEncode(owner) .. "/" .. utils.urlEncode(repo), "PATCH", '{"private":true}', function(pCode, pRes)
              repoOptionsModule.showOptions(owner, repo, true, showMainScreen, onBackToRepo, onRepoDeleted)
            end, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted) end)
          end
        }))
        vLayout.addView(btnMakePrivate)
      end

      local btnBackVis = Button(service)
      btnBackVis.setText("Cancel")
      btnBackVis.setOnClickListener(View.OnClickListener({
        onClick = function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted) end
      }))
      vLayout.addView(btnBackVis)

      vScroll.addView(vLayout)
      vRoot.addView(vScroll)
      utils.enableBackKey(vRoot, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted) end)
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
            if onRepoDeleted then
              onRepoDeleted()
            else
              showMainScreen()
            end
          end, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted) end)
        end
      }))
      rConfLayout.addView(btnConfirmRepoDel)

      local btnCancelRepoDel = Button(service)
      btnCancelRepoDel.setText("Cancel")
      btnCancelRepoDel.setOnClickListener(View.OnClickListener({
        onClick = function()
          repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted)
        end
      }))
      rConfLayout.addView(btnCancelRepoDel)

      rConfScroll.addView(rConfLayout)
      rConfRoot.addView(rConfScroll)
      utils.enableBackKey(rConfRoot, function() repoOptionsModule.showOptions(owner, repo, isPrivate, showMainScreen, onBackToRepo, onRepoDeleted) end)
      utils.setScreen(rConfRoot)
    end
  }))
  layout.addView(btnDelete)

  local btnClose = Button(service)
  btnClose.setText("Close Options")
  btnClose.setOnClickListener(View.OnClickListener({
    onClick = function() onBackToRepo() end
  }))
  layout.addView(btnClose)

  scroll.addView(layout)
  root.addView(scroll)
  utils.enableBackKey(root, function() onBackToRepo() end)
  utils.setScreen(root)
end

return repoOptionsModule