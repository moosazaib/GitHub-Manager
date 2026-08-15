local utils = require("utils")
local tokenModule = require("token_module")

local Handler = Handler or luajava.bindClass("android.os.Handler")
local Looper = Looper or luajava.bindClass("android.os.Looper")
local Runnable = Runnable or luajava.bindClass("java.lang.Runnable")
local Toast = Toast or luajava.bindClass("android.os.Toast")

local createRepoModule = {}

local function httpRequestWithTimeout(loadingText, url, method, data, callback, showMainScreen)
  utils.showLoading(loadingText)
  local isCompleted = false
  local handler = Handler(Looper.getMainLooper())

  local timeoutRunnable = Runnable({
    run = function()
      if not isCompleted then
        isCompleted = true
        Toast.makeText(service, "Internet error: Request timed out", Toast.LENGTH_SHORT).show()
        showMainScreen()
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

function createRepoModule.showCreateRepoScreen(showMainScreen)
  if utils.loadToken() == "" then
    tokenModule.showTokenMissingScreen(showMainScreen)
    return
  end

  local cRoot = LinearLayout(service)
  cRoot.setOrientation(LinearLayout.VERTICAL)
  cRoot.setBackgroundColor(Color.BLACK)
  cRoot.setPadding(20, 20, 20, 20)

  local cScroll = ScrollView(service)
  local cLayout = LinearLayout(service)
  cLayout.setOrientation(LinearLayout.VERTICAL)

  cLayout.addView(utils.createHeader("Create Repository"))

  local input = EditText(service)
  input.setHint("Repository Name")
  input.setTextColor(Color.WHITE)
  input.setHintTextColor(Color.GRAY)
  cLayout.addView(input)

  local inputDesc = EditText(service)
  inputDesc.setHint("Description (Optional)")
  inputDesc.setTextColor(Color.WHITE)
  inputDesc.setHintTextColor(Color.GRAY)
  cLayout.addView(inputDesc)

  local btnSub = Button(service)
  btnSub.setText("Create")

  local function updateCreateRepoState()
    local val = tostring(input.getText())
    btnSub.setEnabled(val ~= "")
  end
  updateCreateRepoState()

  input.addTextChangedListener(TextWatcher({
    onTextChanged = function() updateCreateRepoState() end,
    beforeTextChanged = function() end,
    afterTextChanged = function() end
  }))

  btnSub.setOnClickListener(View.OnClickListener({
    onClick = function()
      local rName = tostring(input.getText())
      local rDesc = tostring(inputDesc.getText())
      if rName ~= "" then
        httpRequestWithTimeout("Checking repository...", "https://api.github.com/user/repos?per_page=100", "GET", nil, function(code, res)
          if code == 200 then
            local found = false
            local existingName = ""
            local ownerName = ""
            pcall(function()
              local arr = JSONArray(res)
              for i = 0, arr.length() - 1 do
                local obj = arr.getJSONObject(i)
                local name = obj.getString("name")
                if utils.normalizeName(name) == utils.normalizeName(rName) then
                  found = true
                  existingName = name
                  ownerName = obj.getJSONObject("owner").getString("login")
                  break
                end
              end
            end)

            local function doCreateRepo(isPrivate)
              local jsonObj = JSONObject()
              jsonObj.put("name", rName)
              jsonObj.put("private", isPrivate)
              if rDesc ~= "" then
                jsonObj.put("description", rDesc)
              end
              local json = jsonObj.toString()

              httpRequestWithTimeout("Creating repository...", "https://api.github.com/user/repos", "POST", json, function(cCode, cRes)
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
                  info.setText("Repository '" .. rName .. "' created successfully!")
                  info.setTextColor(Color.GREEN)
                  info.setTextSize(16)
                  info.setPadding(20, 20, 20, 20)
                  succLayout.addView(info)

                  local btnOk = Button(service)
                  btnOk.setText("OK")
                  btnOk.setOnClickListener(View.OnClickListener({
                    onClick = function() showMainScreen() end
                  }))
                  succLayout.addView(btnOk)

                  succScroll.addView(succLayout)
                  succRoot.addView(succScroll)
                  utils.enableBackKey(succRoot, function() showMainScreen() end)
                  utils.setScreen(succRoot)
                else
                  showMainScreen()
                end
              end, showMainScreen)
            end

            local function showVisibilityOption(onSelected)
              local visRoot = LinearLayout(service)
              visRoot.setOrientation(LinearLayout.VERTICAL)
              visRoot.setBackgroundColor(Color.BLACK)
              visRoot.setPadding(20, 20, 20, 20)

              local visScroll = ScrollView(service)
              local visLayout = LinearLayout(service)
              visLayout.setOrientation(LinearLayout.VERTICAL)

              visLayout.addView(utils.createHeader("Select Repository Type"))

              local txtAsk = TextView(service)
              txtAsk.setText("Choose repository visibility for '" .. rName .. "':")
              txtAsk.setTextColor(Color.YELLOW)
              txtAsk.setTextSize(16)
              txtAsk.setPadding(20, 20, 20, 20)
              visLayout.addView(txtAsk)

              local btnPub = Button(service)
              btnPub.setText("Public Repository")
              btnPub.setOnClickListener(View.OnClickListener({
                onClick = function() onSelected(false) end
              }))
              visLayout.addView(btnPub)

              local btnPriv = Button(service)
              btnPriv.setText("Private Repository")
              btnPriv.setOnClickListener(View.OnClickListener({
                onClick = function() onSelected(true) end
              }))
              visLayout.addView(btnPriv)

              local btnCancelVis = Button(service)
              btnCancelVis.setText("Cancel")
              btnCancelVis.setOnClickListener(View.OnClickListener({
                onClick = function() showMainScreen() end
              }))
              visLayout.addView(btnCancelVis)

              visScroll.addView(visLayout)
              visRoot.addView(visScroll)
              utils.enableBackKey(visRoot, function() showMainScreen() end)
              utils.setScreen(visRoot)
            end

            if found then
              local confRoot = LinearLayout(service)
              confRoot.setOrientation(LinearLayout.VERTICAL)
              confRoot.setBackgroundColor(Color.BLACK)
              confRoot.setPadding(20, 20, 20, 20)

              local confScroll = ScrollView(service)
              local confLayout = LinearLayout(service)
              confLayout.setOrientation(LinearLayout.VERTICAL)

              confLayout.addView(utils.createHeader("Repository Exists"))
              local info = TextView(service)
              info.setText("Repository '" .. existingName .. "' already exists. Do you want to overwrite it?")
              info.setTextColor(Color.YELLOW)
              info.setTextSize(16)
              info.setPadding(20, 20, 20, 20)
              confLayout.addView(info)

              local btnYes = Button(service)
              btnYes.setText("Yes, Overwrite")
              btnYes.setOnClickListener(View.OnClickListener({
                onClick = function()
                  showVisibilityOption(function(isPrivate)
                    httpRequestWithTimeout("Overwriting repository...", "https://api.github.com/repos/" .. utils.urlEncode(ownerName) .. "/" .. utils.urlEncode(existingName), "DELETE", nil, function(dCode, dRes)
                      doCreateRepo(isPrivate)
                    end, showMainScreen)
                  end)
                end
              }))
              confLayout.addView(btnYes)

              local btnNo = Button(service)
              btnNo.setText("Cancel")
              btnNo.setOnClickListener(View.OnClickListener({
                onClick = function() showMainScreen() end
              }))
              confLayout.addView(btnNo)

              confScroll.addView(confLayout)
              confRoot.addView(confScroll)
              utils.enableBackKey(confRoot, function() showMainScreen() end)
              utils.setScreen(confRoot)
            else
              showVisibilityOption(function(isPrivate)
                doCreateRepo(isPrivate)
              end)
            end
          else
            showMainScreen()
          end
        end, showMainScreen)
      end
    end
  }))
  cLayout.addView(btnSub)

  local btnBack = Button(service)
  btnBack.setText("Back")
  btnBack.setOnClickListener(View.OnClickListener({
    onClick = function() showMainScreen() end
  }))
  cLayout.addView(btnBack)

  cScroll.addView(cLayout)
  cRoot.addView(cScroll)
  utils.enableBackKey(cRoot, function() showMainScreen() end)
  utils.setScreen(cRoot)
end

return createRepoModule
