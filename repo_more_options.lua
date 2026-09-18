local utils = require("utils")
local tokenModule = require("token_module")

local Toast = luajava.bindClass("android.widget.Toast")
local View = luajava.bindClass("android.view.View")
local Color = luajava.bindClass("android.graphics.Color")
local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local ScrollView = luajava.bindClass("android.widget.ScrollView")
local Button = luajava.bindClass("android.widget.Button")
local JSONObject = luajava.bindClass("org.json.JSONObject")

local repoMoreOptions = {}

function repoMoreOptions.showMoreOptions(item, onBackToSearch, currentPath, publicRepos, httpPublicRequest, startDownloadFile)
  local root = LinearLayout(service)
  root.setOrientation(LinearLayout.VERTICAL)
  root.setBackgroundColor(Color.BLACK)
  root.setPadding(20, 20, 20, 20)

  local scroll = ScrollView(service)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)

  local btnBack = Button(service)
  btnBack.setText("Back to Repository")
  btnBack.setOnClickListener(View.OnClickListener({
    onClick = function()
      publicRepos.showRepoDetails(item, onBackToSearch, currentPath)
    end
  }))
  layout.addView(btnBack)

  layout.addView(utils.createHeader("More Options: " .. item.name))

  local btnStar = Button(service)
  btnStar.setText("Checking Star Status...")
  btnStar.setEnabled(false)
  layout.addView(btnStar)

  local function updateStarButtonState(isStarred, starCount)
    item.stars = starCount
    if isStarred then
      btnStar.setText("Unstar Repository (" .. starCount .. " Stars)")
    else
      btnStar.setText("Star Repository (" .. starCount .. " Stars)")
    end
    btnStar.setEnabled(true)
  end

  local function checkStarStatus()
    local url = "https://api.github.com/user/starred/" .. utils.urlEncode(item.owner_login) .. "/" .. utils.urlEncode(item.name)
    httpPublicRequest(url, "GET", nil, function(code, response)
      local isStarred = (code == 204)
      local countUrl = "https://api.github.com/repos/" .. utils.urlEncode(item.owner_login) .. "/" .. utils.urlEncode(item.name)
      httpPublicRequest(countUrl, "GET", nil, function(cCode, cResp)
        local currentStars = item.stars or 0
        if cCode == 200 and cResp then
          pcall(function()
            local obj = JSONObject(cResp)
            currentStars = obj.optInt("stargazers_count", currentStars)
          end)
        end
        updateStarButtonState(isStarred, currentStars)
      end)
    end)
  end

  if utils.loadToken() == "" then
    btnStar.setText("Star Repository (" .. (item.stars or 0) .. " Stars)")
    btnStar.setEnabled(true)
  else
    checkStarStatus()
  end

  btnStar.setOnClickListener(View.OnClickListener({
    onClick = function()
      if utils.loadToken() == "" then
        tokenModule.showTokenMissingScreen(function()
          repoMoreOptions.showMoreOptions(item, onBackToSearch, currentPath, publicRepos, httpPublicRequest, startDownloadFile)
        end)
        return
      end

      local url = "https://api.github.com/user/starred/" .. utils.urlEncode(item.owner_login) .. "/" .. utils.urlEncode(item.name)
      
      btnStar.setEnabled(false)
      httpPublicRequest(url, "GET", nil, function(code, response)
        local isCurrentlyStarred = (code == 204)
        local method = "PUT"
        if isCurrentlyStarred then
          method = "DELETE"
        end

        httpPublicRequest(url, method, "", function(actCode, actResp)
          if actCode == 204 or actCode == 200 then
            checkStarStatus()
          else
            Toast.makeText(service, "Failed to update star status.", Toast.LENGTH_SHORT).show()
            btnStar.setEnabled(true)
          end
        end)
      end)
    end
  }))

  local btnDownloadRepo = Button(service)
  btnDownloadRepo.setText("Download Repository")
  btnDownloadRepo.setOnClickListener(View.OnClickListener({
    onClick = function()
      local defaultBranch = item.default_branch or "main"
      httpPublicRequest("https://api.github.com/repos/" .. utils.urlEncode(item.owner_login) .. "/" .. utils.urlEncode(item.name), "GET", nil, function(bCode, bRes)
        local repoSizeInBytes = 0
        if bCode == 200 and bRes then
          pcall(function()
            local bObj = JSONObject(bRes)
            defaultBranch = bObj.optString("default_branch", defaultBranch)
            local sizeKB = bObj.optInt("size", 0)
            if sizeKB > 0 then
              repoSizeInBytes = sizeKB * 1024
            end
          end)
        end
        local zipUrl = "https://github.com/" .. item.owner_login .. "/" .. item.name .. "/archive/refs/heads/" .. defaultBranch .. ".zip"
        local fileName = item.name .. "-" .. defaultBranch .. ".zip"
        startDownloadFile(zipUrl, fileName, repoSizeInBytes, function()
          repoMoreOptions.showMoreOptions(item, onBackToSearch, currentPath, publicRepos, httpPublicRequest, startDownloadFile)
        end, function()
          repoMoreOptions.showMoreOptions(item, onBackToSearch, currentPath, publicRepos, httpPublicRequest, startDownloadFile)
        end)
      end)
    end
  }))
  layout.addView(btnDownloadRepo)

  local btnCopyRepoUrl = Button(service)
  btnCopyRepoUrl.setText("Copy Repo Link")
  btnCopyRepoUrl.setOnClickListener(View.OnClickListener({
    onClick = function()
      local repoUrl = "https://github.com/" .. item.owner_login .. "/" .. item.name
      service.copy(repoUrl)
    end
  }))
  layout.addView(btnCopyRepoUrl)

  local btnCopyZipUrl = Button(service)
  btnCopyZipUrl.setText("Copy Zip Link")
  btnCopyZipUrl.setOnClickListener(View.OnClickListener({
    onClick = function()
      local defaultBranch = item.default_branch or "main"
      local zipUrl = "https://github.com/" .. item.owner_login .. "/" .. item.name .. "/archive/refs/heads/" .. defaultBranch .. ".zip"
      service.copy(zipUrl)
    end
  }))
  layout.addView(btnCopyZipUrl)

  local btnForkRepo = Button(service)
  btnForkRepo.setText("Fork to My Repositories")
  btnForkRepo.setOnClickListener(View.OnClickListener({
    onClick = function()
      if utils.loadToken() == "" then
        tokenModule.showTokenMissingScreen(function()
          repoMoreOptions.showMoreOptions(item, onBackToSearch, currentPath, publicRepos, httpPublicRequest, startDownloadFile)
        end)
        return
      end

      utils.showLoading("Forking repository...")
      local forkUrl = "https://api.github.com/repos/" .. utils.urlEncode(item.owner_login) .. "/" .. utils.urlEncode(item.name) .. "/forks"
      httpPublicRequest(forkUrl, "POST", "", function(fCode, fRes)
        pcall(function()
          if utils.hideLoading then utils.hideLoading() end
        end)
        if fCode == 202 or fCode == 200 or fCode == 201 then
          Toast.makeText(service, "Repository successfully forked!", Toast.LENGTH_LONG).show()
        else
          Toast.makeText(service, "Failed to fork repository (Error " .. tostring(fCode) .. ").", Toast.LENGTH_SHORT).show()
        end
        repoMoreOptions.showMoreOptions(item, onBackToSearch, currentPath, publicRepos, httpPublicRequest, startDownloadFile)
      end)
    end
  }))
  layout.addView(btnForkRepo)

  scroll.addView(layout)
  root.addView(scroll)

  utils.enableBackKey(root, function()
    publicRepos.showRepoDetails(item, onBackToSearch, currentPath)
  end)

  utils.setScreen(root)
end

return repoMoreOptions
