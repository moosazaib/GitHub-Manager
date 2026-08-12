local utils = require("utils")
local tokenModule = require("token_module")

local profileModule = {}

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

function profileModule.showProfileScreen(showMainScreen)
  local currentToken = utils.loadToken()
  if not currentToken or currentToken == "" then
    tokenModule.showTokenMissingScreen(showMainScreen)
    return
  end

  utils.showLoading("Loading Profile...")

  utils.httpRequestWithToken("https://api.github.com/user", "GET", nil, currentToken, function(code, res)
    if code == 200 then
      local profileData = {}
      pcall(function()
        local obj = JSONObject(res)
        profileData.login = (obj.has("login") and not obj.isNull("login")) and obj.getString("login") or "N/A"
        profileData.type = (obj.has("type") and not obj.isNull("type")) and obj.getString("type") or "User"
        profileData.name = (obj.has("name") and not obj.isNull("name")) and obj.getString("name") or ""
        profileData.bio = (obj.has("bio") and not obj.isNull("bio")) and obj.getString("bio") or ""
        profileData.location = (obj.has("location") and not obj.isNull("location")) and obj.getString("location") or ""
        profileData.email = (obj.has("email") and not obj.isNull("email")) and obj.getString("email") or ""
        profileData.public_repos = obj.has("public_repos") and tostring(obj.getInt("public_repos")) or "0"
        profileData.total_private_repos = obj.has("total_private_repos") and tostring(obj.getInt("total_private_repos")) or (obj.has("owned_private_repos") and tostring(obj.getInt("owned_private_repos")) or "0")
        profileData.public_gists = obj.has("public_gists") and tostring(obj.getInt("public_gists")) or "0"
        profileData.private_gists = obj.has("private_gists") and tostring(obj.getInt("private_gists")) or "0"
        profileData.followers = obj.has("followers") and tostring(obj.getInt("followers")) or "0"
        profileData.following = obj.has("following") and tostring(obj.getInt("following")) or "0"
        profileData.created_at = (obj.has("created_at") and not obj.isNull("created_at")) and obj.getString("created_at") or "N/A"
        
        profileData.plan_name = "Free"
        if obj.has("plan") and not obj.isNull("plan") then
          local planObj = obj.getJSONObject("plan")
          if planObj.has("name") and not planObj.isNull("name") then
            local pName = planObj.getString("name")
            profileData.plan_name = pName:sub(1,1):upper() .. pName:sub(2)
          end
        end
      end)

      local root = LinearLayout(service)
      root.setOrientation(LinearLayout.VERTICAL)
      root.setBackgroundColor(Color.BLACK)
      root.setPadding(20, 20, 20, 20)

      local scroll = ScrollView(service)
      local layout = LinearLayout(service)
      layout.setOrientation(LinearLayout.VERTICAL)

      local btnBack = Button(service)
      btnBack.setText("Back to Main Menu")
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

      local emailVal = (profileData.email ~= "" and profileData.email ~= "null") and profileData.email or "No Public Email"
      local txtEmail = TextView(service)
      txtEmail.setText("Email: " .. emailVal)
      txtEmail.setTextColor(Color.WHITE)
      txtEmail.setTextSize(16)
      txtEmail.setPadding(10, 10, 10, 10)
      layout.addView(txtEmail)

      local btnEmail = Button(service)
      btnEmail.setText("Manage Email Visibility")
      btnEmail.setOnClickListener(View.OnClickListener({
        onClick = function()
          profileModule.showEmailVisibilityScreen(showMainScreen, profileData.email)
        end
      }))
      layout.addView(btnEmail)

      local otherDetails = {
        {"Public Repositories", profileData.public_repos},
        {"Private Repositories", profileData.total_private_repos},
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
      end

      scroll.addView(layout)
      root.addView(scroll)
      utils.enableBackKey(root, function() showMainScreen() end)
      utils.setScreen(root)
    else
      local errRoot = LinearLayout(service)
      errRoot.setOrientation(LinearLayout.VERTICAL)
      errRoot.setBackgroundColor(Color.BLACK)
      errRoot.setPadding(20, 20, 20, 20)

      local errScroll = ScrollView(service)
      local errLayout = LinearLayout(service)
      errLayout.setOrientation(LinearLayout.VERTICAL)

      local btnErrBack = Button(service)
      btnErrBack.setText("Back to Main Menu")
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
          errInfo.setText("Failed to update " .. fieldLabel .. " (Error " .. tostring(code) .. ").")
          errInfo.setTextColor(Color.YELLOW)
          errInfo.setTextSize(16)
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
          errInfo.setText("Failed to update Location (Error " .. tostring(code) .. ").")
          errInfo.setTextColor(Color.YELLOW)
          errInfo.setTextSize(16)
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

function profileModule.showEmailVisibilityScreen(showMainScreen, currentPublicEmail)
  local currentToken = utils.loadToken()
  if not currentToken or currentToken == "" then
    tokenModule.showTokenMissingScreen(showMainScreen)
    return
  end

  utils.showLoading("Fetching Emails...")

  utils.httpRequestWithToken("https://api.github.com/user/emails", "GET", nil, currentToken, function(code, res)
    local primaryEmail = ""
    if code == 200 then
      pcall(function()
        local arr = JSONArray(res)
        for i = 0, arr.length() - 1 do
          local item = arr.getJSONObject(i)
          local eAddr = item.getString("email")
          local isPrimary = item.has("primary") and item.getBoolean("primary")
          if isPrimary then
            primaryEmail = eAddr
            break
          end
        end
        if primaryEmail == "" and arr.length() > 0 then
          primaryEmail = arr.getJSONObject(0).getString("email")
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

    layout.addView(utils.createHeader("Email Visibility"))

    local displayAddr = primaryEmail ~= "" and primaryEmail or (currentPublicEmail ~= "" and currentPublicEmail ~= "null" and currentPublicEmail or "N/A")
    local isCurrentlyPublic = (currentPublicEmail ~= "" and currentPublicEmail ~= "null")

    local txtEmail = TextView(service)
    txtEmail.setText("Account Email: " .. displayAddr)
    txtEmail.setTextColor(Color.WHITE)
    txtEmail.setTextSize(16)
    txtEmail.setPadding(10, 10, 10, 10)
    layout.addView(txtEmail)

    local txtStatus = TextView(service)
    txtStatus.setText("Current Visibility: " .. (isCurrentlyPublic and "Public" or "Private"))
    txtStatus.setTextColor(Color.WHITE)
    txtStatus.setTextSize(16)
    txtStatus.setPadding(10, 10, 10, 10)
    layout.addView(txtStatus)

    local btnAction = Button(service)
    btnAction.setText(isCurrentlyPublic and "Make Email Private" or "Make Email Public")
    btnAction.setOnClickListener(View.OnClickListener({
      onClick = function()
        local jsonBody = JSONObject()
        if isCurrentlyPublic then
          jsonBody.put("email", "")
        else
          local targetEmail = primaryEmail ~= "" and primaryEmail or currentPublicEmail
          jsonBody.put("email", targetEmail)
        end

        utils.showLoading("Updating Email Visibility...")

        utils.httpRequestWithToken("https://api.github.com/user", "PATCH", jsonBody.toString(), currentToken, function(patchCode, patchRes)
          if patchCode == 200 then
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
            txtMsg.setText("Email visibility updated successfully!")
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
            errInfo.setText("Failed to update Email visibility (Error " .. tostring(patchCode) .. ").")
            errInfo.setTextColor(Color.YELLOW)
            errInfo.setTextSize(16)
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
    layout.addView(btnAction)

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
  end)
end

return profileModule
