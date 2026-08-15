local utils = require("utils")
local tokenModule = require("token_module")
local myReposModule = require("my_repos")
local publicRepos = require("public_repos")

local profileModule = {}

local View = luajava.bindClass("android.view.View")
local Color = luajava.bindClass("android.graphics.Color")
local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local ScrollView = luajava.bindClass("android.widget.ScrollView")
local TextView = luajava.bindClass("android.widget.TextView")
local Button = luajava.bindClass("android.widget.Button")
local EditText = luajava.bindClass("android.widget.EditText")
local JSONObject = luajava.bindClass("org.json.JSONObject")
local JSONArray = luajava.bindClass("org.json.JSONArray")
local AlertDialog = luajava.bindClass("android.app.AlertDialog")
local DialogInterface = luajava.bindClass("android.content.DialogInterface")
local WindowManager = luajava.bindClass("android.view.WindowManager")
local Toast = luajava.bindClass("android.widget.Toast")
local TextWatcher = luajava.bindClass("android.text.TextWatcher")

local currentSortOption = "Name (A-Z)"
local currentRepoSortOption = "Name (A-Z)"

local function formatAccessibleDate(isoStr)
  if not isoStr or isoStr == "" or isoStr == "N/A" then return "N/A" end
  local y, m, d, h, min = isoStr:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
  if not y then return isoStr end
  
  local months = {"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"}
  local monthName = months[tonumber(m)] or m
  
  local hourNum = tonumber(h)
  local ampm = "AM"
  if hourNum >= 12 then
    ampm = "PM"
    if hourNum > 12 then hourNum = hourNum - 12 end
  elseif hourNum == 0 then
    hourNum = 12
  end
  
  return string.format("%d %s %s at %02d:%s %s", tonumber(d), monthName, y, hourNum, min, ampm)
end

local function sortUsersList(list)
  if not list then return {} end
  local sorted = {}
  for _, v in ipairs(list) do
    table.insert(sorted, v)
  end
  if currentSortOption == "Name (A-Z)" then
    table.sort(sorted, function(a, b)
      return tostring(a.login):lower() < tostring(b.login):lower()
    end)
  elseif currentSortOption == "Name (Z-A)" then
    table.sort(sorted, function(a, b)
      return tostring(a.login):lower() > tostring(b.login):lower()
    end)
  end
  return sorted
end

local function sortReposList(list)
  if not list then return {} end
  local sorted = {}
  for _, v in ipairs(list) do
    table.insert(sorted, v)
  end
  if currentRepoSortOption == "Name (A-Z)" then
    table.sort(sorted, function(a, b)
      return tostring(a.full_name):lower() < tostring(b.full_name):lower()
    end)
  elseif currentRepoSortOption == "Name (Z-A)" then
    table.sort(sorted, function(a, b)
      return tostring(a.full_name):lower() > tostring(b.full_name):lower()
    end)
  elseif currentRepoSortOption == "Date Newest" then
    table.sort(sorted, function(a, b)
      return tostring(a.updated_at or "") > tostring(b.updated_at or "")
    end)
  elseif currentRepoSortOption == "Date Oldest" then
    table.sort(sorted, function(a, b)
      return tostring(a.updated_at or "") < tostring(b.updated_at or "")
    end)
  end
  return sorted
end

function profileModule.showProfileScreen(showMainScreen)
  local currentToken = utils.loadToken()
  if not currentToken or currentToken == "" then
    tokenModule.showTokenMissingScreen(showMainScreen)
    return
  end

  utils.showLoading("Loading Profile...")

  utils.httpRequestWithToken("https://api.github.com/user", "GET", nil, currentToken, function(code, res, headers)
    if code == 200 then
      local profileData = {}
      pcall(function()
        local obj = JSONObject(res)
        profileData.login = (obj.has("login") and not obj.isNull("login")) and obj.getString("login") or "N/A"
        profileData.type = (obj.has("type") and not obj.isNull("type")) and obj.getString("type") or "User"
        profileData.name = (obj.has("name") and not obj.isNull("name")) and obj.getString("name") or ""
        profileData.bio = (obj.has("bio") and not obj.isNull("bio")) and obj.getString("bio") or ""
        profileData.location = (obj.has("location") and not obj.isNull("location")) and obj.getString("location") or ""
        profileData.public_repos = obj.has("public_repos") and tostring(obj.getInt("public_repos")) or "0"
        profileData.total_private_repos = obj.has("total_private_repos") and tostring(obj.getInt("total_private_repos")) or (obj.has("owned_private_repos") and tostring(obj.getInt("owned_private_repos")) or "0")
        profileData.public_gists = obj.has("public_gists") and tostring(obj.getInt("public_gists")) or "0"
        profileData.private_gists = obj.has("private_gists") and tostring(obj.getInt("private_gists")) or "0"
        profileData.followers = obj.has("followers") and tostring(obj.getInt("followers")) or "0"
        profileData.following = obj.has("following") and tostring(obj.getInt("following")) or "0"
        profileData.created_at = (obj.has("created_at") and not obj.isNull("created_at")) and obj.getString("created_at") or "N/A"
        profileData.starred_repos = "0"
        
        profileData.plan_name = "Free"
        if obj.has("plan") and not obj.isNull("plan") then
          local planObj = obj.getJSONObject("plan")
          if planObj.has("name") and not planObj.isNull("name") then
            local pName = planObj.getString("name")
            profileData.plan_name = pName:sub(1,1):upper() .. pName:sub(2)
          end
        end
      end)

      utils.httpRequestWithToken("https://api.github.com/user/starred?per_page=100", "GET", nil, currentToken, function(starCode, starRes, starHeaders)
        if starCode == 200 then
          pcall(function()
            local linkHeader = ""
            if type(starHeaders) == "table" then
              for k, v in pairs(starHeaders) do
                if tostring(k):lower() == "link" then
                  linkHeader = tostring(v)
                  break
                end
              end
            elseif starHeaders and starHeaders.getHeaderField then
              linkHeader = starHeaders.getHeaderField("Link") or ""
            end

            if linkHeader ~= "" then
              local lastPage = linkHeader:match('page=(%d+)>;%s*rel="last"')
              if lastPage then
                profileData.starred_repos = lastPage
              else
                local arr = JSONArray(starRes)
                profileData.starred_repos = tostring(arr.length())
              end
            else
              local arr = JSONArray(starRes)
              profileData.starred_repos = tostring(arr.length())
            end
          end)
        end

        local root = LinearLayout(service)
        root.setOrientation(LinearLayout.VERTICAL)
        root.setBackgroundColor(Color.BLACK)
        root.setPadding(20, 20, 20, 20)

        local scroll = ScrollView(service)
        local layout = LinearLayout(service)
        layout.setOrientation(LinearLayout.VERTICAL)

        local btnBack = Button(service)
        btnBack.setText("Back")
        btnBack.setOnClickListener(View.OnClickListener({
          onClick = function() showMainScreen() end
        }))
        layout.addView(btnBack)

        layout.addView(utils.createHeader("My GitHub Profile"))

        local txtUser = TextView(service)
        txtUser.setText("Username: " .. profileData.login)
        txtUser.setTextColor(Color.WHITE)
        txtUser.setTextSize(16)
        txtUser.setPadding(10, 10, 10, 10)
        layout.addView(txtUser)

        local txtType = TextView(service)
        txtType.setText("Account Type: " .. profileData.type)
        txtType.setTextColor(Color.WHITE)
        txtType.setTextSize(16)
        txtType.setPadding(10, 10, 10, 10)
        layout.addView(txtType)

        local nameVal = (profileData.name ~= "") and profileData.name or "No Name Added"
        local txtName = TextView(service)
        txtName.setText("Name: " .. nameVal)
        txtName.setTextColor(Color.WHITE)
        txtName.setTextSize(16)
        txtName.setPadding(10, 10, 10, 10)
        layout.addView(txtName)

        local btnName = Button(service)
        btnName.setText((profileData.name ~= "") and "Edit Name" or "Add Name")
        btnName.setOnClickListener(View.OnClickListener({
          onClick = function()
            profileModule.showSingleFieldEditScreen(showMainScreen, "name", "Name", profileData.name)
          end
        }))
        layout.addView(btnName)

        local bioVal = (profileData.bio ~= "") and profileData.bio or "No Bio Added"
        local txtBio = TextView(service)
        txtBio.setText("Bio: " .. bioVal)
        txtBio.setTextColor(Color.WHITE)
        txtBio.setTextSize(16)
        txtBio.setPadding(10, 10, 10, 10)
        layout.addView(txtBio)

        local btnBio = Button(service)
        btnBio.setText((profileData.bio ~= "") and "Edit Bio" or "Add Bio")
        btnBio.setOnClickListener(View.OnClickListener({
          onClick = function()
            profileModule.showSingleFieldEditScreen(showMainScreen, "bio", "Bio", profileData.bio)
          end
        }))
        layout.addView(btnBio)

        local locVal = (profileData.location ~= "") and profileData.location or "No Location Added"
        local txtLoc = TextView(service)
        txtLoc.setText("Location: " .. locVal)
        txtLoc.setTextColor(Color.WHITE)
        txtLoc.setTextSize(16)
        txtLoc.setPadding(10, 10, 10, 10)
        layout.addView(txtLoc)

        local btnLoc = Button(service)
        btnLoc.setText((profileData.location ~= "") and "Edit Location" or "Add Location")
        btnLoc.setOnClickListener(View.OnClickListener({
          onClick = function()
            profileModule.showLocationEditScreen(showMainScreen, profileData.location)
          end
        }))
        layout.addView(btnLoc)

        local otherDetails = {
          {"Public Repositories", profileData.public_repos},
          {"Private Repositories", profileData.total_private_repos},
          {"Starred Repositories", profileData.starred_repos},
          {"Public Gists", profileData.public_gists},
          {"Private Gists", profileData.private_gists},
          {"Followers", profileData.followers},
          {"Following", profileData.following},
          {"GitHub Plan", profileData.plan_name},
          {"Account Created", formatAccessibleDate(profileData.created_at)}
        }

        for _, item in ipairs(otherDetails) do
          local txt = TextView(service)
          txt.setText(item[1] .. ": " .. item[2])
          txt.setTextColor(Color.WHITE)
          txt.setTextSize(16)
          txt.setPadding(10, 10, 10, 10)
          layout.addView(txt)

          if item[1] == "Starred Repositories" then
            local btnViewStarred = Button(service)
            btnViewStarred.setText("View Starred Repositories")
            btnViewStarred.setOnClickListener(View.OnClickListener({
              onClick = function()
                profileModule.showStarredReposScreen(showMainScreen, profileData.login)
              end
            }))
            layout.addView(btnViewStarred)
          elseif item[1] == "Followers" then
            local btnViewFollowers = Button(service)
            btnViewFollowers.setText("View Followers List")
            btnViewFollowers.setOnClickListener(View.OnClickListener({
              onClick = function()
                publicRepos.showPublicUserListScreen(profileData.login, "followers", "Followers List", function()
                  profileModule.showProfileScreen(showMainScreen)
                end, 1, tonumber(profileData.followers) or 0)
              end
            }))
            layout.addView(btnViewFollowers)
          elseif item[1] == "Following" then
            local btnViewFollowing = Button(service)
            btnViewFollowing.setText("View Following List")
            btnViewFollowing.setOnClickListener(View.OnClickListener({
              onClick = function()
                publicRepos.showPublicUserListScreen(profileData.login, "following", "Following List", function()
                  profileModule.showProfileScreen(showMainScreen)
                end, 1, tonumber(profileData.following) or 0)
              end
            }))
            layout.addView(btnViewFollowing)
          end
        end

        scroll.addView(layout)
        root.addView(scroll)
        utils.enableBackKey(root, function() showMainScreen() end)
        utils.setScreen(root)
      end)
    else
      local errRoot = LinearLayout(service)
      errRoot.setOrientation(LinearLayout.VERTICAL)
      errRoot.setBackgroundColor(Color.BLACK)
      errRoot.setPadding(20, 20, 20, 20)

      local errScroll = ScrollView(service)
      local errLayout = LinearLayout(service)
      errLayout.setOrientation(LinearLayout.VERTICAL)

      local btnErrBack = Button(service)
      btnErrBack.setText("Back")
      btnErrBack.setOnClickListener(View.OnClickListener({
        onClick = function() showMainScreen() end
      }))
      errLayout.addView(btnErrBack)

      errLayout.addView(utils.createHeader("Error"))

      local errInfo = TextView(service)
      errInfo.setText("Failed to fetch profile details (Error " .. tostring(code) .. ").")
      errInfo.setTextColor(Color.YELLOW)
      errInfo.setTextSize(16)
      errInfo.setPadding(20, 20, 20, 20)
      errLayout.addView(errInfo)

      errScroll.addView(errLayout)
      errRoot.addView(errScroll)
      utils.enableBackKey(errRoot, function() showMainScreen() end)
      utils.setScreen(errRoot)
    end
  end)
end

function profileModule.showStarredReposScreen(showMainScreen, currentUsername)
  local currentToken = utils.loadToken()
  if not currentToken or currentToken == "" then
    tokenModule.showTokenMissingScreen(showMainScreen)
    return
  end

  utils.showLoading("Fetching Starred Repositories...")

  local root = LinearLayout(service)
  root.setOrientation(LinearLayout.VERTICAL)
  root.setBackgroundColor(Color.BLACK)
  root.setPadding(20, 20, 20, 20)

  local scroll = ScrollView(service)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)

  local btnBack = Button(service)
  btnBack.setText("Back")
  btnBack.setOnClickListener(View.OnClickListener({
    onClick = function()
      profileModule.showProfileScreen(showMainScreen)
    end
  }))
  layout.addView(btnBack)

  layout.addView(utils.createHeader("Starred Repositories"))

  local btnSort = Button(service)
  btnSort.setText("Sort By: " .. currentRepoSortOption)
  layout.addView(btnSort)

  local edtSearch = EditText(service)
  edtSearch.setHint("Search starred repositories...")
  edtSearch.setTextColor(Color.WHITE)
  edtSearch.setHintTextColor(Color.GRAY)
  layout.addView(edtSearch)

  local btnSearch = Button(service)
  btnSearch.setText("Search")
  btnSearch.setEnabled(false)
  layout.addView(btnSearch)

  edtSearch.addTextChangedListener(TextWatcher({
    afterTextChanged = function(s)
      local str = tostring(s):gsub("^%s*(.-)%s*$", "%1")
      if str == "" then
        btnSearch.setEnabled(false)
      else
        btnSearch.setEnabled(true)
      end
    end,
    beforeTextChanged = function(s, start, count, after) end,
    onTextChanged = function(s, start, before, count) end
  }))

  local listContainer = LinearLayout(service)
  listContainer.setOrientation(LinearLayout.VERTICAL)
  layout.addView(listContainer)

  scroll.addView(layout)
  root.addView(scroll)

  local rawRepoList = {}

  local function renderRepos(repos)
    listContainer.removeAllViews()
    local sorted = sortReposList(repos)

    if #sorted == 0 then
      local txtEmpty = TextView(service)
      txtEmpty.setText("No starred repositories found.")
      txtEmpty.setTextColor(Color.GRAY)
      txtEmpty.setPadding(10, 20, 10, 20)
      listContainer.addView(txtEmpty)
      return
    end

    for _, repo in ipairs(sorted) do
      local btnRepo = Button(service)
      btnRepo.setText(repo.full_name .. " (" .. repo.stars .. " Stars)\n" .. repo.description)
      btnRepo.setOnClickListener(View.OnClickListener({
        onClick = function()
          if currentUsername ~= "" and tostring(repo.owner_login):lower() == tostring(currentUsername):lower() then
            local customShowProfileScreen = function()
              profileModule.showStarredReposScreen(showMainScreen, currentUsername)
            end
            myReposModule.showFilesList(repo.owner_login, repo.name, "", customShowProfileScreen)
          else
            local mainOnBack = function()
              profileModule.showStarredReposScreen(showMainScreen, currentUsername)
            end
            publicRepos.showRepoDetails(repo, mainOnBack, "")
          end
        end
      }))
      listContainer.addView(btnRepo)
    end
  end

  btnSort.setOnClickListener(View.OnClickListener({
    onClick = function()
      local options = {"Name (A-Z)", "Name (Z-A)", "Date Newest", "Date Oldest", "Cancel"}
      pcall(function()
        local builder = AlertDialog.Builder(service)
        builder.setTitle("Sort By")
        builder.setItems(options, DialogInterface.OnClickListener({
          onClick = function(dialog, which)
            pcall(function() dialog.dismiss() end)
            local selectedOption = options[which + 1]
            if selectedOption ~= "Cancel" then
              currentRepoSortOption = selectedOption
              btnSort.setText("Sort By: " .. currentRepoSortOption)
              renderRepos(rawRepoList)
            end
          end
        }))
        local dlg = builder.create()
        pcall(function()
          if dlg.getWindow() then
            dlg.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
          end
        end)
        dlg.show()
      end)
    end
  }))

  btnSearch.setOnClickListener(View.OnClickListener({
    onClick = function()
      local q = tostring(edtSearch.getText()):gsub("^%s*(.-)%s*$", "%1"):lower()
      if q == "" then
        renderRepos(rawRepoList)
      else
        local filtered = {}
        for _, repo in ipairs(rawRepoList) do
          if repo.full_name:lower():find(q, 1, true) or repo.description:lower():find(q, 1, true) then
            table.insert(filtered, repo)
          end
        end
        renderRepos(filtered)
      end
    end
  }))

  local apiUrl = "https://api.github.com/user/starred?per_page=100"
  utils.httpRequestWithToken(apiUrl, "GET", nil, currentToken, function(code, res)
    if utils.hideLoading then utils.hideLoading() end
    if code == 200 then
      rawRepoList = {}
      pcall(function()
        local arr = JSONArray(res)
        if arr and arr.length() > 0 then
          for i = 0, arr.length() - 1 do
            local itemObj = arr.getJSONObject(i)
            local repoName = itemObj.getString("name")
            local fullName = itemObj.getString("full_name")
            local stars = itemObj.optInt("stargazers_count", 0)
            local desc = itemObj.optString("description", "No description")
            local defaultBranch = itemObj.optString("default_branch", "main")
            local updatedAt = itemObj.optString("updated_at", "")
            
            local ownerName = ""
            if itemObj.has("owner") then
              ownerName = itemObj.getJSONObject("owner").getString("login")
            end

            table.insert(rawRepoList, {
              name = repoName,
              full_name = fullName,
              stars = stars,
              description = desc,
              default_branch = defaultBranch,
              owner_login = ownerName,
              updated_at = updatedAt
            })
          end
        end
      end)
      renderRepos(rawRepoList)
    else
      listContainer.removeAllViews()
      local errTxt = TextView(service)
      errTxt.setText("Failed to load starred repositories (Error " .. tostring(code) .. ").")
      errTxt.setTextColor(Color.RED)
      listContainer.addView(errTxt)
    end

    utils.enableBackKey(root, function()
      profileModule.showProfileScreen(showMainScreen)
    end)
    utils.setScreen(root)
  end)
end

function profileModule.showSingleFieldEditScreen(showMainScreen, fieldKey, fieldLabel, currentValue)
  local currentToken = utils.loadToken()
  if not currentToken or currentToken == "" then
    tokenModule.showTokenMissingScreen(showMainScreen)
    return
  end

  local root = LinearLayout(service)
  root.setOrientation(LinearLayout.VERTICAL)
  root.setBackgroundColor(Color.BLACK)
  root.setPadding(20, 20, 20, 20)

  local scroll = ScrollView(service)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)

  local actionTitle = (currentValue ~= "") and ("Edit " .. fieldLabel) or ("Add " .. fieldLabel)
  layout.addView(utils.createHeader(actionTitle))

  local inputField = EditText(service)
  inputField.setHint(fieldLabel)
  inputField.setText(currentValue or "")
  inputField.setTextColor(Color.WHITE)
  inputField.setHintTextColor(Color.GRAY)
  layout.addView(inputField)

  local btnSave = Button(service)
  btnSave.setText("Save Changes")
  btnSave.setOnClickListener(View.OnClickListener({
    onClick = function()
      local jsonBody = JSONObject()
      jsonBody.put(fieldKey, tostring(inputField.getText()))

      utils.showLoading("Updating " .. fieldLabel .. "...")

      utils.httpRequestWithToken("https://api.github.com/user", "PATCH", jsonBody.toString(), currentToken, function(code, res)
        if code == 200 then
          local succRoot = LinearLayout(service)
          succRoot.setOrientation(LinearLayout.VERTICAL)
          succRoot.setBackgroundColor(Color.BLACK)
          succRoot.setPadding(20, 20, 20, 20)

          local succScroll = ScrollView(service)
          local succLayout = LinearLayout(service)
          succLayout.setOrientation(LinearLayout.VERTICAL)

          local btnBackProf = Button(service)
          btnBackProf.setText("Back to Profile")
          btnBackProf.setOnClickListener(View.OnClickListener({
            onClick = function() profileModule.showProfileScreen(showMainScreen) end
          }))
          succLayout.addView(btnBackProf)

          succLayout.addView(utils.createHeader("Success"))

          local txtMsg = TextView(service)
          txtMsg.setText(fieldLabel .. " updated successfully!")
          txtMsg.setTextColor(Color.GREEN)
          txtMsg.setTextSize(18)
          txtMsg.setPadding(20, 10, 20, 10)
          succLayout.addView(txtMsg)

          succScroll.addView(succLayout)
          succRoot.addView(succScroll)
          utils.enableBackKey(succRoot, function() profileModule.showProfileScreen(showMainScreen) end)
          utils.setScreen(succRoot)
        else
          local errRoot = LinearLayout(service)
          errRoot.setOrientation(LinearLayout.VERTICAL)
          errRoot.setBackgroundColor(Color.BLACK)
          errRoot.setPadding(20, 20, 20, 20)

          local errScroll = ScrollView(service)
          local errLayout = LinearLayout(service)
          errLayout.setOrientation(LinearLayout.VERTICAL)

          local btnErrBack = Button(service)
          btnErrBack.setText("Back to Profile")
          btnErrBack.setOnClickListener(View.OnClickListener({
            onClick = function() profileModule.showProfileScreen(showMainScreen) end
          }))
          errLayout.addView(btnErrBack)

          errLayout.addView(utils.createHeader("Update Error"))

          local errInfo = TextView(service)
          errInfo.setText("Failed to update " .. fieldLabel .. " (Code: " .. tostring(code) .. ")\nResponse: " .. tostring(res))
          errInfo.setTextColor(Color.YELLOW)
          errInfo.setTextSize(14)
          errInfo.setPadding(20, 20, 20, 20)
          errLayout.addView(errInfo)

          errScroll.addView(errLayout)
          errRoot.addView(errScroll)
          utils.enableBackKey(errRoot, function() profileModule.showProfileScreen(showMainScreen) end)
          utils.setScreen(errRoot)
        end
      end)
    end
  }))
  layout.addView(btnSave)

  local btnCancel = Button(service)
  btnCancel.setText("Cancel")
  btnCancel.setOnClickListener(View.OnClickListener({
    onClick = function() profileModule.showProfileScreen(showMainScreen) end
  }))
  layout.addView(btnCancel)

  scroll.addView(layout)
  root.addView(scroll)
  utils.enableBackKey(root, function() profileModule.showProfileScreen(showMainScreen) end)
  utils.setScreen(root)
end

function profileModule.showLocationEditScreen(showMainScreen, currentLoc)
  local currentToken = utils.loadToken()
  if not currentToken or currentToken == "" then
    tokenModule.showTokenMissingScreen(showMainScreen)
    return
  end

  local existingCity = ""
  local existingCountry = ""
  if currentLoc and currentLoc ~= "" then
    local commaPos = currentLoc:find(",")
    if commaPos then
      existingCity = currentLoc:sub(1, commaPos - 1):gsub("^%s*(.-)%s*$", "%1")
      existingCountry = currentLoc:sub(commaPos + 1):gsub("^%s*(.-)%s*$", "%1")
    else
      existingCity = currentLoc:gsub("^%s*(.-)%s*$", "%1")
    end
  end

  local root = LinearLayout(service)
  root.setOrientation(LinearLayout.VERTICAL)
  root.setBackgroundColor(Color.BLACK)
  root.setPadding(20, 20, 20, 20)

  local scroll = ScrollView(service)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)

  local actionTitle = (currentLoc ~= "") and "Edit Location" or "Add Location"
  layout.addView(utils.createHeader(actionTitle))

  local inputCountry = EditText(service)
  inputCountry.setHint("Country")
  inputCountry.setText(existingCountry)
  inputCountry.setTextColor(Color.WHITE)
  inputCountry.setHintTextColor(Color.GRAY)
  layout.addView(inputCountry)

  local inputCity = EditText(service)
  inputCity.setHint("City")
  inputCity.setText(existingCity)
  inputCity.setTextColor(Color.WHITE)
  inputCity.setHintTextColor(Color.GRAY)
  layout.addView(inputCity)

  local btnSave = Button(service)
  btnSave.setText("Save Changes")
  btnSave.setOnClickListener(View.OnClickListener({
    onClick = function()
      local rawCity = tostring(inputCity.getText()):gsub("^%s*(.-)%s*$", "%1")
      local rawCountry = tostring(inputCountry.getText()):gsub("^%s*(.-)%s*$", "%1")

      local combinedLoc = ""
      if rawCity ~= "" and rawCountry ~= "" then
        combinedLoc = rawCity .. ", " .. rawCountry
      elseif rawCity ~= "" then
        combinedLoc = rawCity
      elseif rawCountry ~= "" then
        combinedLoc = ", " .. rawCountry
      end

      local jsonBody = JSONObject()
      jsonBody.put("location", combinedLoc)

      utils.showLoading("Updating Location...")

      utils.httpRequestWithToken("https://api.github.com/user", "PATCH", jsonBody.toString(), currentToken, function(code, res)
        if code == 200 then
          local succRoot = LinearLayout(service)
          succRoot.setOrientation(LinearLayout.VERTICAL)
          succRoot.setBackgroundColor(Color.BLACK)
          succRoot.setPadding(20, 20, 20, 20)

          local succScroll = ScrollView(service)
          local succLayout = LinearLayout(service)
          succLayout.setOrientation(LinearLayout.VERTICAL)

          local btnBackProf = Button(service)
          btnBackProf.setText("Back to Profile")
          btnBackProf.setOnClickListener(View.OnClickListener({
            onClick = function() profileModule.showProfileScreen(showMainScreen) end
          }))
          succLayout.addView(btnBackProf)

          succLayout.addView(utils.createHeader("Success"))

          local txtMsg = TextView(service)
          txtMsg.setText("Location updated successfully!")
          txtMsg.setTextColor(Color.GREEN)
          txtMsg.setTextSize(18)
          txtMsg.setPadding(20, 10, 20, 10)
          succLayout.addView(txtMsg)

          succScroll.addView(succLayout)
          succRoot.addView(succScroll)
          utils.enableBackKey(succRoot, function() profileModule.showProfileScreen(showMainScreen) end)
          utils.setScreen(succRoot)
        else
          local errRoot = LinearLayout(service)
          errRoot.setOrientation(LinearLayout.VERTICAL)
          errRoot.setBackgroundColor(Color.BLACK)
          errRoot.setPadding(20, 20, 20, 20)

          local errScroll = ScrollView(service)
          local errLayout = LinearLayout(service)
          errLayout.setOrientation(LinearLayout.VERTICAL)

          local btnErrBack = Button(service)
          btnErrBack.setText("Back to Profile")
          btnErrBack.setOnClickListener(View.OnClickListener({
            onClick = function() profileModule.showProfileScreen(showMainScreen) end
          }))
          errLayout.addView(btnErrBack)

          errLayout.addView(utils.createHeader("Update Error"))

          local errInfo = TextView(service)
          errInfo.setText("Failed to update Location (Code: " .. tostring(code) .. ")\nResponse: " .. tostring(res))
          errInfo.setTextColor(Color.YELLOW)
          errInfo.setTextSize(14)
          errInfo.setPadding(20, 20, 20, 20)
          errLayout.addView(errInfo)

          errScroll.addView(errLayout)
          errRoot.addView(errScroll)
          utils.enableBackKey(errRoot, function() profileModule.showProfileScreen(showMainScreen) end)
          utils.setScreen(errRoot)
        end
      end)
    end
  }))
  layout.addView(btnSave)

  local btnCancel = Button(service)
  btnCancel.setText("Cancel")
  btnCancel.setOnClickListener(View.OnClickListener({
    onClick = function() profileModule.showProfileScreen(showMainScreen) end
  }))
  layout.addView(btnCancel)

  scroll.addView(layout)
  root.addView(scroll)
  utils.enableBackKey(root, function() profileModule.showProfileScreen(showMainScreen) end)
  utils.setScreen(root)
end

return profileModule
