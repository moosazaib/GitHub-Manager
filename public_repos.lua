local utils = require("utils")
local tokenModule = require("token_module")
local myReposModule = require("my_repos")

local Toast = luajava.bindClass("android.widget.Toast")
local View = luajava.bindClass("android.view.View")
local Color = luajava.bindClass("android.graphics.Color")
local LinearLayout = luajava.bindClass("android.widget.LinearLayout")
local ScrollView = luajava.bindClass("android.widget.ScrollView")
local TextView = luajava.bindClass("android.widget.TextView")
local Button = luajava.bindClass("android.widget.Button")
local EditText = luajava.bindClass("android.widget.EditText")
local JSONObject = luajava.bindClass("org.json.JSONObject")
local JSONArray = luajava.bindClass("org.json.JSONArray")
local TextWatcher = luajava.bindClass("android.text.TextWatcher")
local Base64 = luajava.bindClass("android.util.Base64")
local String = luajava.bindClass("java.lang.String")
local AlertDialog = luajava.bindClass("android.app.AlertDialog")
local DialogInterface = luajava.bindClass("android.content.DialogInterface")
local WindowManager = luajava.bindClass("android.view.WindowManager")

local URL = luajava.bindClass("java.net.URL")
local BufferedReader = luajava.bindClass("java.io.BufferedReader")
local InputStreamReader = luajava.bindClass("java.io.InputStreamReader")
local StringBuilder = luajava.bindClass("java.lang.StringBuilder")
local Handler = luajava.bindClass("android.os.Handler")
local Looper = luajava.bindClass("android.os.Looper")
local Runnable = luajava.bindClass("java.lang.Runnable")
local Thread = luajava.bindClass("java.lang.Thread")
local Context = luajava.bindClass("android.content.Context")
local Uri = luajava.bindClass("android.net.Uri")
local DownloadManager = luajava.bindClass("android.app.DownloadManager")
local Environment = luajava.bindClass("android.os.Environment")
local Array = luajava.bindClass("java.lang.reflect.Array")
local Long = luajava.bindClass("java.lang.Long")

local publicRepos = {}
local currentSortOption = "Name (A-Z)"
local currentFileSortOption = "Name (A-Z)"
local currentPublicUserSortOption = "Name (A-Z)"
local lastFetchedItems = nil

local currentPageIndex = 0
local pageSize = 10
local cachedQueryForPagination = ""

local userListPageSize = 100
local currentUsersList = {}
local currentUsersPageIndex = 0
local totalApiUsersCount = 0

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

local function getSearchHistory()
  local list = {}
  pcall(function()
    local sp = service.getSharedPreferences("public_repos_prefs", Context.MODE_PRIVATE)
    local jsonStr = sp.getString("search_history", "[]")
    local jsonArr = JSONArray(jsonStr)
    for i = 0, jsonArr.length() - 1 do
      table.insert(list, jsonArr.getString(i))
    end
  end)
  return list
end

local function saveSearchHistory(list)
  pcall(function()
    local jsonArr = JSONArray()
    for _, val in ipairs(list) do
      jsonArr.put(val)
    end
    local sp = service.getSharedPreferences("public_repos_prefs", Context.MODE_PRIVATE)
    local editor = sp.edit()
    editor.putString("search_history", jsonArr.toString())
    editor.commit()
  end)
end

local function addQueryToHistory(query)
  if not query or query:match("^%s*$") then return end
  local cleanQuery = query:match("^%s*(.-)%s*$")
  local list = getSearchHistory()
  local newList = {}
  table.insert(newList, cleanQuery)
  for _, item in ipairs(list) do
    if item ~= cleanQuery then
      table.insert(newList, item)
    end
  end
  while #newList > 5 do
    table.remove(newList)
  end
  saveSearchHistory(newList)
end

local function deleteQueryFromHistory(query)
  local list = getSearchHistory()
  local newList = {}
  for _, item in ipairs(list) do
    if item ~= query then
      table.insert(newList, item)
    end
  end
  saveSearchHistory(newList)
end

local function clearAllSearchHistory()
  saveSearchHistory({})
end

local function sortRepositoriesList(list)
  if not list then return {} end
  local sorted = {}
  for _, v in ipairs(list) do
    table.insert(sorted, v)
  end
  if currentSortOption == "Name (A-Z)" then
    table.sort(sorted, function(a, b)
      return tostring(a.full_name):lower() < tostring(b.full_name):lower()
    end)
  elseif currentSortOption == "Name (Z-A)" then
    table.sort(sorted, function(a, b)
      return tostring(a.full_name):lower() > tostring(b.full_name):lower()
    end)
  elseif currentSortOption == "Date Newest" then
    table.sort(sorted, function(a, b)
      local tA = tostring(a.updated_at or "")
      local tB = tostring(b.updated_at or "")
      return tA > tB
    end)
  elseif currentSortOption == "Date Oldest" then
    table.sort(sorted, function(a, b)
      local tA = tostring(a.updated_at or "")
      local tB = tostring(b.updated_at or "")
      return tA < tB
    end)
  end
  return sorted
end

local function sortFilesList(list)
  if not list then return {} end
  local sorted = {}
  local folders = {}
  local files = {}
  
  for _, v in ipairs(list) do
    if v.type == "dir" then
      table.insert(folders, v)
    else
      table.insert(files, v)
    end
  end

  local function compareItems(a, b)
    if currentFileSortOption == "Name (A-Z)" then
      return tostring(a.name):lower() < tostring(b.name):lower()
    elseif currentFileSortOption == "Name (Z-A)" then
      return tostring(a.name):lower() > tostring(b.name):lower()
    elseif currentFileSortOption == "Date Newest" then
      local tA = tostring(a.sha or "")
      local tB = tostring(b.sha or "")
      return tA > tB
    elseif currentFileSortOption == "Date Oldest" then
      local tA = tostring(a.sha or "")
      local tB = tostring(b.sha or "")
      return tA < tB
    end
    return false
  end

  table.sort(folders, compareItems)
  table.sort(files, compareItems)

  for _, f in ipairs(folders) do table.insert(sorted, f) end
  for _, f in ipairs(files) do table.insert(sorted, f) end

  return sorted
end

local function sortPublicUsersList(list)
  if not list then return {} end
  local sorted = {}
  for _, v in ipairs(list) do
    table.insert(sorted, v)
  end
  if currentPublicUserSortOption == "Name (A-Z)" then
    table.sort(sorted, function(a, b)
      return tostring(a.login):lower() < tostring(b.login):lower()
    end)
  elseif currentPublicUserSortOption == "Name (Z-A)" then
    table.sort(sorted, function(a, b)
      return tostring(a.login):lower() > tostring(b.login):lower()
    end)
  end
  return sorted
end

local renderRepositories

local function httpPublicRequest(urlStr, method, data, callback)
  Thread(Runnable({
    run = function()
      local code = -1
      local response = ""
      pcall(function()
        local url = URL(urlStr)
        local conn = url.openConnection()
        local reqMethod = method or "GET"
        conn.setRequestMethod(reqMethod)
        conn.setConnectTimeout(15000)
        conn.setReadTimeout(15000)
        conn.setRequestProperty("User-Agent", "GitHubManagerApp")
        conn.setRequestProperty("Accept", "application/vnd.github.v3+json")

        local savedToken = ""
        pcall(function() savedToken = utils.loadToken() end)
        if savedToken and savedToken:match("%S") then
          conn.setRequestProperty("Authorization", "token " .. savedToken:match("^%s*(.-)%s*$"))
        end

        if reqMethod == "POST" or reqMethod == "PUT" or reqMethod == "PATCH" or (data and data ~= "") then
          conn.setDoOutput(true)
          local sendData = data or ""
          if sendData ~= "" then
            conn.setRequestProperty("Content-Type", "application/json")
          end
          local os = conn.getOutputStream()
          os.write(String(sendData).getBytes("UTF-8"))
          os.flush()
          os.close()
        end

        code = conn.getResponseCode()
        local isStream = (code >= 200 and code < 300) and conn.getInputStream() or conn.getErrorStream()
        if isStream then
          local reader = BufferedReader(InputStreamReader(isStream, "UTF-8"))
          local sb = StringBuilder()
          local line = reader.readLine()
          while line do
            sb.append(line)
            sb.append("\n")
            line = reader.readLine()
          end
          reader.close()
          response = sb.toString()
        end
      end)

      Handler(Looper.getMainLooper()).post(Runnable({
        run = function()
          callback(code, response)
        end
      }))
    end
  })).start()
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

function publicRepos.showPublicUserProfile(targetUsername, onBackToParent)
  local savedToken = utils.loadToken()
  utils.showLoading("Loading Profile...")

  local url = "https://api.github.com/users/" .. utils.urlEncode(targetUsername)
  httpPublicRequest(url, "GET", nil, function(code, res)
    pcall(function()
      if utils.hideLoading then utils.hideLoading() end
    end)
    if code == 200 and res then
      local profileData = {}
      pcall(function()
        local obj = JSONObject(res)
        profileData.login = (obj.has("login") and not obj.isNull("login")) and obj.getString("login") or targetUsername
        profileData.type = (obj.has("type") and not obj.isNull("type")) and obj.getString("type") or "User"
        profileData.name = (obj.has("name") and not obj.isNull("name")) and obj.getString("name") or ""
        profileData.bio = (obj.has("bio") and not obj.isNull("bio")) and obj.getString("bio") or ""
        profileData.location = (obj.has("location") and not obj.isNull("location")) and obj.getString("location") or ""
        profileData.email = (obj.has("email") and not obj.isNull("email")) and obj.getString("email") or ""
        profileData.public_repos = obj.has("public_repos") and tostring(obj.getInt("public_repos")) or "0"
        profileData.public_gists = obj.has("public_gists") and tostring(obj.getInt("public_gists")) or "0"
        profileData.followers = obj.has("followers") and tostring(obj.getInt("followers")) or "0"
        profileData.following = obj.has("following") and tostring(obj.getInt("following")) or "0"
        profileData.created_at = (obj.has("created_at") and not obj.isNull("created_at")) and obj.getString("created_at") or "N/A"
      end)

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
        onClick = function() onBackToParent() end
      }))
      layout.addView(btnBack)

      layout.addView(utils.createHeader(profileData.login .. "'s Profile"))

      local details = {
        {"Username", profileData.login},
        {"Account Type", profileData.type},
        {"Name", (profileData.name ~= "") and profileData.name or "No Name Added"},
        {"Bio", (profileData.bio ~= "") and profileData.bio or "No Bio Added"},
        {"Location", (profileData.location ~= "") and profileData.location or "No Location Added"},
        {"Email", (profileData.email ~= "" and profileData.email ~= "null") and profileData.email or "No Public Email"},
        {"Public Repositories", profileData.public_repos},
        {"Public Gists", profileData.public_gists},
        {"Followers", profileData.followers},
        {"Following", profileData.following},
        {"Account Created", formatAccessibleDate(profileData.created_at)}
      }

      for _, item in ipairs(details) do
        local txt = TextView(service)
        txt.setText(item[1] .. ": " .. item[2])
        txt.setTextColor(Color.WHITE)
        txt.setTextSize(16)
        txt.setPadding(10, 10, 10, 10)
        layout.addView(txt)

        if item[1] == "Followers" then
          local btnViewFollowers = Button(service)
          btnViewFollowers.setText("View Followers List")
          btnViewFollowers.setOnClickListener(View.OnClickListener({
            onClick = function()
              publicRepos.showPublicUserListScreen(profileData.login, "followers", "Followers List", function()
                publicRepos.showPublicUserProfile(targetUsername, onBackToParent)
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
                publicRepos.showPublicUserProfile(targetUsername, onBackToParent)
              end, 1, tonumber(profileData.following) or 0)
            end
          }))
          layout.addView(btnViewFollowing)
        end
      end

      local btnCopyProfile = Button(service)
      btnCopyProfile.setText("Copy Profile")
      btnCopyProfile.setOnClickListener(View.OnClickListener({
        onClick = function()
          local fullInfo = "Username: " .. profileData.login .. "\n" ..
                           "Account Type: " .. profileData.type .. "\n" ..
                           "Name: " .. ((profileData.name ~= "") and profileData.name or "No Name Added") .. "\n" ..
                           "Bio: " .. ((profileData.bio ~= "") and profileData.bio or "No Bio Added") .. "\n" ..
                           "Location: " .. ((profileData.location ~= "") and profileData.location or "No Location Added") .. "\n" ..
                           "Email: " .. ((profileData.email ~= "" and profileData.email ~= "null") and profileData.email or "No Public Email") .. "\n" ..
                           "Public Repositories: " .. profileData.public_repos .. "\n" ..
                           "Public Gists: " .. profileData.public_gists .. "\n" ..
                           "Followers: " .. profileData.followers .. "\n" ..
                           "Following: " .. profileData.following .. "\n" ..
                           "Account Created: " .. formatAccessibleDate(profileData.created_at)
          service.copy(fullInfo)
          Toast.makeText(service, "Profile info copied successfully", Toast.LENGTH_SHORT).show()
        end
      }))
      layout.addView(btnCopyProfile)

      local btnFollow = Button(service)
      btnFollow.setText("Checking Status...")
      btnFollow.setEnabled(false)
      layout.addView(btnFollow)

      local function checkFollowStatus()
        if savedToken == "" then
          btnFollow.setText("Follow")
          btnFollow.setEnabled(true)
          return
        end
        local checkUrl = "https://api.github.com/user/following/" .. utils.urlEncode(profileData.login)
        httpPublicRequest(checkUrl, "GET", nil, function(fCode)
          if fCode == 24 or fCode == 204 then
            btnFollow.setText("Unfollow")
          else
            btnFollow.setText("Follow")
          end
          btnFollow.setEnabled(true)
        end)
      end

      checkFollowStatus()

      btnFollow.setOnClickListener(View.OnClickListener({
        onClick = function()
          local curToken = utils.loadToken()
          if curToken == "" then
            tokenModule.showTokenMissingScreen(function()
              publicRepos.showPublicUserProfile(targetUsername, onBackToParent)
            end)
            return
          end

          local currentText = tostring(btnFollow.getText())
          local targetUrl = "https://api.github.com/user/following/" .. utils.urlEncode(profileData.login)
          btnFollow.setEnabled(false)

          if currentText == "Unfollow" then
            httpPublicRequest(targetUrl, "DELETE", nil, function(actCode)
              if actCode == 204 or actCode == 200 then
                Toast.makeText(service, "Unfollowed " .. profileData.login, Toast.LENGTH_SHORT).show()
                checkFollowStatus()
              else
                Toast.makeText(service, "Failed to unfollow user.", Toast.LENGTH_SHORT).show()
                btnFollow.setEnabled(true)
              end
            end)
          else
            httpPublicRequest(targetUrl, "PUT", "", function(actCode)
              if actCode == 204 or actCode == 200 or actCode == 201 then
                Toast.makeText(service, "Followed " .. profileData.login, Toast.LENGTH_SHORT).show()
                checkFollowStatus()
              else
                Toast.makeText(service, "Failed to follow user.", Toast.LENGTH_SHORT).show()
                btnFollow.setEnabled(true)
              end
            end)
          end
        end
      }))

      scroll.addView(layout)
      root.addView(scroll)
      utils.enableBackKey(root, function() onBackToParent() end)
      utils.setScreen(root)
    else
      Toast.makeText(service, "Failed to load profile details.", Toast.LENGTH_SHORT).show()
    end
  end)
end

function publicRepos.showPublicUserListScreen(targetUsername, listType, headerTitle, onBackToParent, page, totalCount)
  local apiPage = page or 1
  if totalCount then totalApiUsersCount = totalCount end
  utils.showLoading("Loading " .. headerTitle .. "...")

  local url = "https://api.github.com/users/" .. utils.urlEncode(targetUsername) .. "/" .. listType .. "?per_page=100&page=" .. tostring(apiPage)
  httpPublicRequest(url, "GET", nil, function(code, res)
    pcall(function()
      if utils.hideLoading then utils.hideLoading() end
    end)

    local rawUserList = {}
    if code == 200 and res then
      pcall(function()
        local arr = JSONArray(res)
        for i = 0, arr.length() - 1 do
          local obj = arr.getJSONObject(i)
          table.insert(rawUserList, { login = obj.getString("login") })
        end
      end)
    end

    currentUsersList = rawUserList
    currentUsersPageIndex = 0

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
      onClick = function() onBackToParent() end
    }))
    layout.addView(btnBack)

    layout.addView(utils.createHeader(headerTitle))

    local btnSort = Button(service)
    btnSort.setText("Sort By: " .. currentPublicUserSortOption)
    layout.addView(btnSort)

    local edtSearch = EditText(service)
    edtSearch.setHint("Search user...")
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

    local function renderUsers(users)
      listContainer.removeAllViews()
      local sorted = sortPublicUsersList(users)

      if #sorted == 0 then
        local txtEmpty = TextView(service)
        txtEmpty.setText("No users found.")
        txtEmpty.setTextColor(Color.GRAY)
        txtEmpty.setPadding(10, 20, 10, 20)
        listContainer.addView(txtEmpty)
      else
        local totalUsers = #sorted
        local totalPages = math.ceil(totalUsers / userListPageSize)
        if currentUsersPageIndex >= totalPages then
          currentUsersPageIndex = totalPages - 1
        end
        if currentUsersPageIndex < 0 then
          currentUsersPageIndex = 0
        end

        local startIndex = currentUsersPageIndex * userListPageSize + 1
        local endIndex = startIndex + userListPageSize - 1
        if endIndex > totalUsers then
          endIndex = totalUsers
        end

        for i = startIndex, endIndex do
          local u = sorted[i]
          local itemLayout = LinearLayout(service)
          itemLayout.setOrientation(LinearLayout.VERTICAL)
          itemLayout.setPadding(10, 15, 10, 15)

          local btnUser = Button(service)
          btnUser.setText(u.login)
          btnUser.setOnClickListener(View.OnClickListener({
            onClick = function()
              local curToken = utils.loadToken()
              if curToken and curToken:match("%S") then
                httpPublicRequest("https://api.github.com/user", "GET", nil, function(uCode, uRes)
                  local myLogin = ""
                  if uCode == 200 and uRes then
                    pcall(function()
                      local uObj = JSONObject(uRes)
                      myLogin = uObj.optString("login", "")
                    end)
                  end
                  if myLogin ~= "" and u.login:lower() == myLogin:lower() then
                    pcall(function()
                      local builder = AlertDialog.Builder(service)
                      builder.setTitle("Notice")
                      builder.setMessage("You can view your own profile by clicking My Profile.")
                      builder.setPositiveButton("OK", DialogInterface.OnClickListener({
                        onClick = function(dialog, which)
                          pcall(function() dialog.dismiss() end)
                        end
                      }))
                      local dlg = builder.create()
                      if dlg.getWindow() then
                        dlg.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
                      end
                      dlg.show()
                    end)
                  else
                    publicRepos.showPublicUserProfile(u.login, function()
                      publicRepos.showPublicUserListScreen(targetUsername, listType, headerTitle, onBackToParent, apiPage, totalApiUsersCount)
                    end)
                  end
                end)
              else
                publicRepos.showPublicUserProfile(u.login, function()
                  publicRepos.showPublicUserListScreen(targetUsername, listType, headerTitle, onBackToParent, apiPage, totalApiUsersCount)
                end)
              end
            end
          }))
          itemLayout.addView(btnUser)

          listContainer.addView(itemLayout)
        end
      end

      local paginationLayout = LinearLayout(service)
      paginationLayout.setOrientation(LinearLayout.HORIZONTAL)
      paginationLayout.setPadding(0, 10, 0, 10)

      local maxApiPages = math.ceil(totalApiUsersCount / 100)
      if maxApiPages < 1 then maxApiPages = 1 end

      local btnPrev = Button(service)
      btnPrev.setText("Previous Page")
      local prevParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0)
      btnPrev.setLayoutParams(prevParams)
      btnPrev.setEnabled(apiPage > 1)
      btnPrev.setOnClickListener(View.OnClickListener({
        onClick = function()
          if apiPage > 1 then
            publicRepos.showPublicUserListScreen(targetUsername, listType, headerTitle, onBackToParent, apiPage - 1, totalApiUsersCount)
          end
        end
      }))
      paginationLayout.addView(btnPrev)

      local btnNext = Button(service)
      btnNext.setText("Next Page")
      local nextParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0)
      btnNext.setLayoutParams(nextParams)
      btnNext.setEnabled(apiPage < maxApiPages or #rawUserList == 100)
      btnNext.setOnClickListener(View.OnClickListener({
        onClick = function()
          publicRepos.showPublicUserListScreen(targetUsername, listType, headerTitle, onBackToParent, apiPage + 1, totalApiUsersCount)
        end
      }))
      paginationLayout.addView(btnNext)

      listContainer.addView(paginationLayout)
    end

    btnSort.setOnClickListener(View.OnClickListener({
      onClick = function()
        local options = {"Name (A-Z)", "Name (Z-A)", "Cancel"}
        pcall(function()
          local builder = AlertDialog.Builder(service)
          builder.setTitle("Sort By")
          builder.setItems(options, DialogInterface.OnClickListener({
            onClick = function(dialog, which)
              pcall(function() dialog.dismiss() end)
              local selectedOption = options[which + 1]
              if selectedOption ~= "Cancel" then
                currentPublicUserSortOption = selectedOption
                btnSort.setText("Sort By: " .. currentPublicUserSortOption)
                currentUsersPageIndex = 0
                renderUsers(currentUsersList)
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
          currentUsersList = rawUserList
        else
          local filtered = {}
          for _, u in ipairs(rawUserList) do
            if u.login:lower():find(q, 1, true) then
              table.insert(filtered, u)
            end
          end
          currentUsersList = filtered
        end
        currentUsersPageIndex = 0
        renderUsers(currentUsersList)
      end
    }))

    if code == 200 then
      renderUsers(currentUsersList)
    else
      listContainer.removeAllViews()
      local errTxt = TextView(service)
      errTxt.setText("Failed to load list (Error " .. tostring(code) .. ").")
      errTxt.setTextColor(Color.RED)
      listContainer.addView(errTxt)
    end

    utils.enableBackKey(root, function() onBackToParent() end)
    utils.setScreen(root)
  end)
end

local function searchRepositories(query, container, mainOnBack)
  container.removeAllViews()

  local loadingText = TextView(service)
  loadingText.setText("Searching repositories, please wait...")
  loadingText.setTextColor(Color.WHITE)
  loadingText.setPadding(0, 20, 0, 20)
  container.addView(loadingText)

  local cleanQuery = query:match("^%s*(.-)%s*$")
  cachedQueryForPagination = cleanQuery

  local ownerMatch, repoMatch = cleanQuery:match("github%.com/([^/]+)/([^/%s/?#]+)")
  if not ownerMatch or not repoMatch then
    ownerMatch, repoMatch = cleanQuery:match("^([^/]+)/([^/%s]+)$")
  end

  if ownerMatch and repoMatch then
    repoMatch = repoMatch:gsub("%.git$", "")
    local directUrl = "https://api.github.com/repos/" .. utils.urlEncode(ownerMatch) .. "/" .. utils.urlEncode(repoMatch)
    httpPublicRequest(directUrl, "GET", nil, function(code, response)
      container.removeAllViews()
      local directList = {}
      if code == 200 and response then
        pcall(function()
          local itemObj = JSONObject(response)
          local repoName = itemObj.getString("name")
          local fullName = itemObj.getString("full_name")
          local stars = itemObj.optInt("stargazers_count", 0)
          local desc = itemObj.optString("description", "No description")
          local defaultBranch = itemObj.optString("default_branch", "main")
          local updatedAt = itemObj.optString("updated_at", "")
          
          local ownerName = ownerMatch
          pcall(function()
            if itemObj.has("owner") then
              ownerName = itemObj.getJSONObject("owner").getString("login")
            end
          end)

          table.insert(directList, {
            name = repoName,
            full_name = fullName,
            stars = stars,
            description = desc,
            default_branch = defaultBranch,
            owner_login = ownerName,
            updated_at = updatedAt
          })
        end)
      end

      if #directList > 0 then
        lastFetchedItems = directList
        currentPageIndex = 0
        renderRepositories(container, directList, query, mainOnBack)
      else
        lastFetchedItems = {}
        currentPageIndex = 0
        local emptyText = TextView(service)
        emptyText.setText("No repository found for link: " .. cleanQuery)
        emptyText.setTextColor(Color.YELLOW)
        container.addView(emptyText)
      end
    end)
    return
  end

  local url1 = "https://api.github.com/search/repositories?q=" .. utils.urlEncode(cleanQuery)

  httpPublicRequest(url1, "GET", nil, function(code, response)
    local itemsList = {}
    if code == 200 and response then
      pcall(function()
        local jsonObj = JSONObject(response)
        if jsonObj.has("items") then
          local itemsArr = jsonObj.getJSONArray("items")
          for i = 0, itemsArr.length() - 1 do
            local itemObj = itemsArr.getJSONObject(i)
            local repoName = itemObj.getString("name")
            local fullName = itemObj.getString("full_name")
            local stars = itemObj.optInt("stargazers_count", 0)
            local desc = itemObj.optString("description", "No description")
            local defaultBranch = itemObj.optString("default_branch", "main")
            local updatedAt = itemObj.optString("updated_at", "")
            
            local ownerName = ""
            pcall(function()
              if itemObj.has("owner") then
                ownerName = itemObj.getJSONObject("owner").getString("login")
              end
            end)

            table.insert(itemsList, {
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
    end

    if #itemsList > 0 then
      lastFetchedItems = itemsList
      currentPageIndex = 0
      renderRepositories(container, itemsList, query, mainOnBack)
    else
      local url2 = "https://api.github.com/users/" .. utils.urlEncode(cleanQuery) .. "/repos"
      httpPublicRequest(url2, "GET", nil, function(code2, response2)
        container.removeAllViews()
        local userItemsList = {}
        if code2 == 200 and response2 then
          pcall(function()
            local arr = JSONArray(response2)
            for i = 0, arr.length() - 1 do
              local itemObj = arr.getJSONObject(i)
              local repoName = itemObj.getString("name")
              local fullName = itemObj.getString("full_name")
              local stars = itemObj.optInt("stargazers_count", 0)
              local desc = itemObj.optString("description", "No description")
              local defaultBranch = itemObj.optString("default_branch", "main")
              local updatedAt = itemObj.optString("updated_at", "")
              
              local ownerName = cleanQuery
              pcall(function()
                if itemObj.has("owner") then
                  ownerName = itemObj.getJSONObject("owner").getString("login")
                end
              end)

              table.insert(userItemsList, {
                name = repoName,
                full_name = fullName,
                stars = stars,
                description = desc,
                default_branch = defaultBranch,
                owner_login = ownerName,
                updated_at = updatedAt
              })
            end
          end)
        end

        if #userItemsList > 0 then
          lastFetchedItems = userItemsList
          currentPageIndex = 0
          renderRepositories(container, userItemsList, query, mainOnBack)
        else
          lastFetchedItems = {}
          currentPageIndex = 0
          local emptyText = TextView(service)
          emptyText.setText("No repository or username found for: " .. cleanQuery)
          emptyText.setTextColor(Color.YELLOW)
          container.addView(emptyText)
        end
      end)
    end
  end)
end

renderRepositories = function(container, items, query, mainOnBack)
  container.removeAllViews()
  local sortedItems = sortRepositoriesList(items)
  if #sortedItems > 0 then
    local totalItems = #sortedItems
    local totalPages = math.ceil(totalItems / pageSize)
    if currentPageIndex >= totalPages then
      currentPageIndex = totalPages - 1
    end
    if currentPageIndex < 0 then
      currentPageIndex = 0
    end

    local startIndex = currentPageIndex * pageSize + 1
    local endIndex = startIndex + pageSize - 1
    if endIndex > totalItems then
      endIndex = totalItems
    end

    for i = startIndex, endIndex do
      local item = sortedItems[i]
      local btnRepo = Button(service)
      btnRepo.setText(item.full_name .. " (" .. item.stars .. " Stars)\n" .. item.description)
      btnRepo.setOnClickListener(View.OnClickListener({
        onClick = function()
          local savedToken = utils.loadToken()
          local backToPublicMenu = function()
            publicRepos.showPublicRepos(mainOnBack, query)
          end

          if savedToken == "" then
            publicRepos.showRepoDetails(item, backToPublicMenu, "")
          else
            httpPublicRequest("https://api.github.com/user", "GET", nil, function(uCode, uRes)
              local currentUsername = ""
              if uCode == 200 and uRes then
                pcall(function()
                  local uObj = JSONObject(uRes)
                  currentUsername = uObj.optString("login", "")
                end)
              end

              if currentUsername ~= "" and tostring(item.owner_login):lower() == tostring(currentUsername):lower() then
                myReposModule.showFilesList(item.owner_login, item.name, "", backToPublicMenu)
              else
                publicRepos.showRepoDetails(item, backToPublicMenu, "")
              end
            end)
          end
        end
      }))
      container.addView(btnRepo)
    end

    local paginationLayout = LinearLayout(service)
    paginationLayout.setOrientation(LinearLayout.HORIZONTAL)
    paginationLayout.setPadding(0, 10, 0, 10)

    local btnPrev = Button(service)
    btnPrev.setText("Previous Search Result")
    local prevParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0)
    btnPrev.setLayoutParams(prevParams)
    btnPrev.setEnabled(currentPageIndex > 0)
    btnPrev.setOnClickListener(View.OnClickListener({
      onClick = function()
        if currentPageIndex > 0 then
          currentPageIndex = currentPageIndex - 1
          renderRepositories(container, items, query, mainOnBack)
        end
      end
    }))
    paginationLayout.addView(btnPrev)

    local btnNext = Button(service)
    btnNext.setText("Next Search Result")
    local nextParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0)
    btnNext.setLayoutParams(nextParams)
    btnNext.setEnabled(currentPageIndex < totalPages - 1)
    btnNext.setOnClickListener(View.OnClickListener({
      onClick = function()
        if currentPageIndex < totalPages - 1 then
          currentPageIndex = currentPageIndex + 1
          renderRepositories(container, items, query, mainOnBack)
        end
      end
    }))
    paginationLayout.addView(btnNext)

    container.addView(paginationLayout)
  else
    local emptyText = TextView(service)
    emptyText.setText("No repositories found.")
    emptyText.setTextColor(Color.YELLOW)
    container.addView(emptyText)
  end
end

function publicRepos.showPublicRepos(mainOnBack, initialQuery)
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
      mainOnBack()
    end
  }))
  layout.addView(btnBack)

  layout.addView(utils.createHeader("Public Repositories"))

  local resultsContainer = LinearLayout(service)
  resultsContainer.setOrientation(LinearLayout.VERTICAL)

  local btnSort = Button(service)
  btnSort.setText("Sort By: " .. currentSortOption)
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
              currentSortOption = selectedOption
              btnSort.setText("Sort By: " .. currentSortOption)
              if lastFetchedItems and #lastFetchedItems > 0 then
                local currentQ = ""
                pcall(function() currentQ = tostring(edtSearch.getText()):match("^%s*(.-)%s*$") end)
                renderRepositories(resultsContainer, lastFetchedItems, currentQ, mainOnBack)
              end
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
  layout.addView(btnSort)

  local edtSearch = EditText(service)
  edtSearch.setHint("Type repository, user name or link...")
  edtSearch.setTextColor(Color.WHITE)
  edtSearch.setHintTextColor(Color.GRAY)
  if initialQuery and initialQuery ~= "" then
    edtSearch.setText(initialQuery)
  end
  layout.addView(edtSearch)

  local btnSearch = Button(service)
  btnSearch.setText("Search")
  btnSearch.setEnabled(initialQuery ~= nil and initialQuery ~= "")

  edtSearch.addTextChangedListener(TextWatcher({
    onTextChanged = function()
      local query = tostring(edtSearch.getText()):match("^%s*(.-)%s*$")
      btnSearch.setEnabled(query ~= "")
    end,
    beforeTextChanged = function() end,
    afterTextChanged = function() end
  }))
  layout.addView(btnSearch)

  local txtHeader = TextView(service)
  txtHeader.setText("Search History")
  txtHeader.setTextColor(Color.YELLOW)
  txtHeader.setPadding(0, 15, 0, 5)

  local historyContainer = LinearLayout(service)
  historyContainer.setOrientation(LinearLayout.VERTICAL)

  local function renderHistory()
    historyContainer.removeAllViews()
    local historyList = getSearchHistory()

    if #historyList == 0 then
      local txtEmpty = TextView(service)
      txtEmpty.setText("No Search History")
      txtEmpty.setTextColor(Color.GRAY)
      txtEmpty.setPadding(0, 5, 0, 15)
      historyContainer.addView(txtEmpty)
    else
      local btnClearAll = Button(service)
      btnClearAll.setText("Clear All Search History")
      btnClearAll.setOnClickListener(View.OnClickListener({
        onClick = function()
          clearAllSearchHistory()
          publicRepos.showPublicRepos(mainOnBack, initialQuery)
        end
      }))
      historyContainer.addView(btnClearAll)

      for _, hQuery in ipairs(historyList) do
        local rowLayout = LinearLayout(service)
        rowLayout.setOrientation(LinearLayout.HORIZONTAL)
        rowLayout.setPadding(0, 5, 0, 5)

        local btnItem = Button(service)
        btnItem.setText(hQuery)
        local itemParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0)
        btnItem.setLayoutParams(itemParams)
        btnItem.setOnClickListener(View.OnClickListener({
          onClick = function()
            addQueryToHistory(hQuery)
            publicRepos.showPublicRepos(mainOnBack, hQuery)
          end
        }))
        rowLayout.addView(btnItem)

        local btnDelete = Button(service)
        btnDelete.setText("Delete")
        local delParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        btnDelete.setLayoutParams(delParams)
        btnDelete.setOnClickListener(View.OnClickListener({
          onClick = function()
            deleteQueryFromHistory(hQuery)
            publicRepos.showPublicRepos(mainOnBack, initialQuery)
          end
        }))
        rowLayout.addView(btnDelete)

        historyContainer.addView(rowLayout)
      end
    end
  end

  if not initialQuery or initialQuery == "" then
    layout.addView(txtHeader)
    layout.addView(historyContainer)
    renderHistory()
  end

  layout.addView(resultsContainer)

  btnSearch.setOnClickListener(View.OnClickListener({
    onClick = function()
      local query = tostring(edtSearch.getText()):match("^%s*(.-)%s*$")
      if query ~= "" then
        pcall(function()
          layout.removeView(txtHeader)
          layout.removeView(historyContainer)
        end)
        addQueryToHistory(query)
        searchRepositories(query, resultsContainer, mainOnBack)
      end
    end
  }))

  scroll.addView(layout)
  root.addView(scroll)

  utils.enableBackKey(root, function()
    mainOnBack()
  end)

  utils.setScreen(root)

  if initialQuery and initialQuery ~= "" then
    addQueryToHistory(initialQuery)
    if lastFetchedItems and cachedQueryForPagination == initialQuery:match("^%s*(.-)%s*$") then
      renderRepositories(resultsContainer, lastFetchedItems, initialQuery, mainOnBack)
    else
      searchRepositories(initialQuery, resultsContainer, mainOnBack)
    end
  end
end

function publicRepos.showRepoDetails(item, onBackToSearch, path)
  local currentPath = path or ""
  local root = LinearLayout(service)
  root.setOrientation(LinearLayout.VERTICAL)
  root.setBackgroundColor(Color.BLACK)
  root.setPadding(20, 20, 20, 20)

  local scroll = ScrollView(service)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)

  local btnTopBack = Button(service)
  btnTopBack.setText("Back")

  local handleBackAction = function()
    if currentPath ~= "" then
      local parentPath = currentPath:match("(.+)/[^/]+$") or ""
      publicRepos.showRepoDetails(item, onBackToSearch, parentPath)
    else
      if type(onBackToSearch) == "function" then
        onBackToSearch()
      end
    end
  end

  btnTopBack.setOnClickListener(View.OnClickListener({
    onClick = handleBackAction
  }))
  layout.addView(btnTopBack)

  layout.addView(utils.createHeader(item.name or "Repository"))

  if currentPath == "" then
    local ownerNameVal = tostring(item.owner_login ~= "" and item.owner_login or "Unknown")
    local txtOwner = TextView(service)
    txtOwner.setText("Owner: " .. ownerNameVal)
    txtOwner.setTextColor(Color.WHITE)
    txtOwner.setPadding(0, 10, 0, 5)
    layout.addView(txtOwner)

    local btnViewOwner = Button(service)
    btnViewOwner.setText("View " .. ownerNameVal .. " Profile")
    btnViewOwner.setOnClickListener(View.OnClickListener({
      onClick = function()
        local backToDetails = function()
          publicRepos.showRepoDetails(item, onBackToSearch, currentPath)
        end
        publicRepos.showPublicUserProfile(ownerNameVal, backToDetails)
      end
    }))
    layout.addView(btnViewOwner)

    local txtDesc = TextView(service)
    txtDesc.setText("Description: " .. tostring(item.description ~= "" and item.description or "No description provided"))
    txtDesc.setTextColor(Color.LTGRAY)
    txtDesc.setPadding(0, 0, 0, 15)
    layout.addView(txtDesc)
  end

  local edtSearchFile = EditText(service)
  edtSearchFile.setHint("Search files in folder...")
  edtSearchFile.setTextColor(Color.WHITE)
  edtSearchFile.setHintTextColor(Color.GRAY)
  layout.addView(edtSearchFile)

  local btnSearchFile = Button(service)
  btnSearchFile.setText("Search")
  btnSearchFile.setEnabled(false)
  layout.addView(btnSearchFile)

  local btnSortFiles = Button(service)
  btnSortFiles.setText("Sort By: " .. currentFileSortOption)
  layout.addView(btnSortFiles)

  local btnMoreOptions = Button(service)
  btnMoreOptions.setText("More Options")
  btnMoreOptions.setOnClickListener(View.OnClickListener({
    onClick = function()
      publicRepos.showMoreOptions(item, onBackToSearch, currentPath)
    end
  }))
  layout.addView(btnMoreOptions)

  local txtFilesHeader = TextView(service)
  txtFilesHeader.setText("Files & Folders " .. (currentPath ~= "" and ("(" .. currentPath .. ")") or ""))
  txtFilesHeader.setTextColor(Color.YELLOW)
  txtFilesHeader.setPadding(0, 15, 0, 10)
  layout.addView(txtFilesHeader)

  local filesContainer = LinearLayout(service)
  filesContainer.setOrientation(LinearLayout.VERTICAL)
  layout.addView(filesContainer)

  scroll.addView(layout)
  root.addView(scroll)

  utils.enableBackKey(root, handleBackAction)
  utils.setScreen(root)

  local rawFilesList = {}

  local function renderCurrentFiles(listToRender)
    filesContainer.removeAllViews()
    local sortedList = sortFilesList(listToRender)
    if #sortedList == 0 then
      local emptyText = TextView(service)
      emptyText.setText("No files or folders found.")
      emptyText.setTextColor(Color.GRAY)
      filesContainer.addView(emptyText)
      return
    end

    for _, fItem in ipairs(sortedList) do
      local btnItem = Button(service)
      if fItem.type == "dir" then
        btnItem.setText("[Folder] " .. fItem.name)
      else
        btnItem.setText("[File] " .. fItem.name)
      end

      btnItem.setOnClickListener(View.OnClickListener({
        onClick = function()
          if fItem.type == "dir" then
            publicRepos.showRepoDetails(item, onBackToSearch, fItem.path)
          else
            publicRepos.showFileView(item, fItem.path, fItem.name, onBackToSearch, currentPath)
          end
        end
      }))
      filesContainer.addView(btnItem)
    end
  end

  edtSearchFile.addTextChangedListener(TextWatcher({
    onTextChanged = function()
      local qText = tostring(edtSearchFile.getText())
      btnSearchFile.setEnabled(qText:match("%S") ~= nil)
    end,
    beforeTextChanged = function() end,
    afterTextChanged = function() end
  }))

  btnSearchFile.setOnClickListener(View.OnClickListener({
    onClick = function()
      local qText = tostring(edtSearchFile.getText()):match("^%s*(.-)%s*$")
      if qText ~= "" then
        local lowerQ = qText:lower()
        local filtered = {}
        for _, f in ipairs(rawFilesList) do
          if tostring(f.name):lower():find(lowerQ, 1, true) then
            table.insert(filtered, f)
          end
        end
        renderCurrentFiles(filtered)
      end
    end
  }))

  btnSortFiles.setOnClickListener(View.OnClickListener({
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
              currentFileSortOption = selectedOption
              btnSortFiles.setText("Sort By: " .. currentFileSortOption)
              local qText = tostring(edtSearchFile.getText()):match("^%s*(.-)%s*$")
              if qText and qText ~= "" then
                local lowerQ = qText:lower()
                local filtered = {}
                for _, f in ipairs(rawFilesList) do
                  if tostring(f.name):lower():find(lowerQ, 1, true) then
                    table.insert(filtered, f)
                  end
                end
                renderCurrentFiles(filtered)
              else
                renderCurrentFiles(rawFilesList)
              end
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

  local url = "https://api.github.com/repos/" .. utils.urlEncode(item.owner_login) .. "/" .. utils.urlEncode(item.name) .. "/contents/" .. utils.urlEncode(currentPath)
  httpPublicRequest(url, "GET", nil, function(code, response)
    filesContainer.removeAllViews()
    if code ~= 200 or not response then
      local errText = TextView(service)
      errText.setText("Failed to load files (Error Code: " .. code .. ").")
      errText.setTextColor(Color.RED)
      filesContainer.addView(errText)
      return
    end

    rawFilesList = {}
    pcall(function()
      local arr = JSONArray(response)
      for i = 0, arr.length() - 1 do
        local obj = arr.getJSONObject(i)
        table.insert(rawFilesList, {
          name = obj.getString("name"),
          type = obj.getString("type"),
          path = obj.getString("path"),
          sha = obj.optString("sha", ""),
          size = obj.optInt("size", 0)
        })
      end
    end)

    if #rawFilesList == 0 then
      local emptyText = TextView(service)
      emptyText.setText("This folder is empty.")
      emptyText.setTextColor(Color.GRAY)
      filesContainer.addView(emptyText)
      return
    end

    renderCurrentFiles(rawFilesList)
  end)
end

function publicRepos.showMoreOptions(item, onBackToSearch, currentPath)
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
          publicRepos.showMoreOptions(item, onBackToSearch, currentPath)
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
          publicRepos.showMoreOptions(item, onBackToSearch, currentPath)
        end, function()
          publicRepos.showMoreOptions(item, onBackToSearch, currentPath)
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
          publicRepos.showMoreOptions(item, onBackToSearch, currentPath)
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
        publicRepos.showMoreOptions(item, onBackToSearch, currentPath)
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

function publicRepos.showFileView(item, filePath, fileName, onBackToSearch, currentPath)
  local root = LinearLayout(service)
  root.setOrientation(LinearLayout.VERTICAL)
  root.setBackgroundColor(Color.BLACK)
  root.setPadding(20, 20, 20, 20)

  local scroll = ScrollView(service)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)

  local btnBack = Button(service)
  btnBack.setText("Back to Folder")
  btnBack.setOnClickListener(View.OnClickListener({
    onClick = function()
      publicRepos.showRepoDetails(item, onBackToSearch, currentPath)
    end
  }))
  layout.addView(btnBack)

  layout.addView(utils.createHeader(fileName))

  local btnDownload = Button(service)
  btnDownload.setText("Download File")
  btnDownload.setEnabled(false)
  layout.addView(btnDownload)

  local txtContent = TextView(service)
  txtContent.setText("Loading file content...")
  txtContent.setTextColor(Color.WHITE)
  txtContent.setPadding(0, 15, 0, 15)
  layout.addView(txtContent)

  scroll.addView(layout)
  root.addView(scroll)

  utils.enableBackKey(root, function()
    publicRepos.showRepoDetails(item, onBackToSearch, currentPath)
  end)

  utils.setScreen(root)

  local url = "https://api.github.com/repos/" .. utils.urlEncode(item.owner_login) .. "/" .. utils.urlEncode(item.name) .. "/contents/" .. utils.urlEncode(filePath)
  httpPublicRequest(url, "GET", nil, function(code, response)
    if code ~= 200 or not response then
      txtContent.setText("Failed to load file content (Error Code: " .. code .. ").")
      txtContent.setTextColor(Color.RED)
      return
    end

    local downloadUrl = ""
    local decodedText = ""
    local parseSuccess = false
    local fileSize = 0

    pcall(function()
      local obj = JSONObject(response)
      if obj.has("download_url") and not obj.isNull("download_url") then
        downloadUrl = obj.getString("download_url")
      end

      if obj.has("size") and not obj.isNull("size") then
        fileSize = obj.getInt("size")
      end

      if obj.has("content") then
        local rawContent = obj.getString("content")
        rawContent = rawContent:gsub("%s+", "")
        local decodedBytes = Base64.decode(rawContent, Base64.DEFAULT)
        decodedText = String(decodedBytes, "UTF-8").toString()
        parseSuccess = true
      end
    end)

    if parseSuccess then
      txtContent.setText(decodedText)
    else
      txtContent.setText("Unable to preview this file type directly.")
      txtContent.setTextColor(Color.YELLOW)
    end

    if downloadUrl ~= "" then
      btnDownload.setEnabled(true)
      btnDownload.setOnClickListener(View.OnClickListener({
        onClick = function()
          startDownloadFile(downloadUrl, fileName, fileSize, function()
            publicRepos.showFileView(item, filePath, fileName, onBackToSearch, currentPath)
          end, function()
            publicRepos.showFileView(item, filePath, fileName, onBackToSearch, currentPath)
          end)
        end
      }))
    end
  end)
end

return publicRepos
