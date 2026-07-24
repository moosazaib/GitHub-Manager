local utils = require("utils")

local tokenModule = {}

function tokenModule.showTokenMissingScreen(showMainScreen)
  local root = LinearLayout(service)
  root.setOrientation(LinearLayout.VERTICAL)
  root.setBackgroundColor(Color.BLACK)
  root.setPadding(20, 20, 20, 20)

  local scroll = ScrollView(service)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)

  layout.addView(utils.createHeader("Token Required"))

  local info = TextView(service)
  info.setText("Please set your GitHub Personal Access Token first!")
  info.setTextColor(Color.YELLOW)
  info.setTextSize(16)
  info.setPadding(20, 20, 20, 20)
  layout.addView(info)

  local btnBack = Button(service)
  btnBack.setText("Back to Main Menu")
  btnBack.setOnClickListener(View.OnClickListener({
    onClick = function() showMainScreen() end
  }))
  layout.addView(btnBack)

  scroll.addView(layout)
  root.addView(scroll)
  utils.enableBackKey(root, function() showMainScreen() end)
  utils.setScreen(root)
end

function tokenModule.showTokenEditScreen(showMainScreen)
  local root = LinearLayout(service)
  root.setOrientation(LinearLayout.VERTICAL)
  root.setBackgroundColor(Color.BLACK)
  root.setPadding(20, 20, 20, 20)

  local scroll = ScrollView(service)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)

  layout.addView(utils.createHeader("Set / Edit Personal Access Token"))

  local currentToken = utils.loadToken()

  local inputToken = EditText(service)
  inputToken.setHint("Paste your token here (ghp_...)")
  inputToken.setText(tostring(currentToken))
  inputToken.setTextColor(Color.WHITE)
  inputToken.setHintTextColor(Color.GRAY)
  layout.addView(inputToken)

  local btnSave = Button(service)
  btnSave.setText("Save Token")
  
  local function updateSaveState()
    local val = tostring(inputToken.getText())
    local clean = (val:gsub("%s+", ""))
    btnSave.setEnabled(clean ~= "")
  end
  updateSaveState()

  inputToken.addTextChangedListener(TextWatcher({
    onTextChanged = function() updateSaveState() end,
    beforeTextChanged = function() end,
    afterTextChanged = function() end
  }))

  btnSave.setOnClickListener(View.OnClickListener({
    onClick = function()
      local rawVal = tostring(inputToken.getText())
      local cleanVal = (rawVal:gsub("%s+", ""))
      if cleanVal == "" then
        local errRoot = LinearLayout(service)
        errRoot.setOrientation(LinearLayout.VERTICAL)
        errRoot.setBackgroundColor(Color.BLACK)
        errRoot.setPadding(20, 20, 20, 20)

        local errScroll = ScrollView(service)
        local errLayout = LinearLayout(service)
        errLayout.setOrientation(LinearLayout.VERTICAL)

        errLayout.addView(utils.createHeader("Invalid Token"))
        local errInfo = TextView(service)
        errInfo.setText("Token cannot be empty. Please enter a valid token.")
        errInfo.setTextColor(Color.YELLOW)
        errInfo.setTextSize(16)
        errInfo.setPadding(20, 20, 20, 20)
        errLayout.addView(errInfo)

        local btnErrBack = Button(service)
        btnErrBack.setText("Try Again")
        btnErrBack.setOnClickListener(View.OnClickListener({
          onClick = function() tokenModule.showTokenEditScreen(showMainScreen) end
        }))
        errLayout.addView(btnErrBack)

        errScroll.addView(errLayout)
        errRoot.addView(errScroll)
        utils.enableBackKey(errRoot, function() tokenModule.showTokenEditScreen(showMainScreen) end)
        utils.setScreen(errRoot)
        return
      end

      utils.showLoading("Verifying Token...")
      utils.httpRequestWithToken("https://api.github.com/user", "GET", nil, cleanVal, function(vCode, vRes)
        if vCode == 200 then
          if utils.saveToken(cleanVal) then
            local uName = ""
            local uLogin = ""
            pcall(function()
              local obj = JSONObject(vRes)
              uLogin = obj.getString("login")
              if obj.has("name") and not obj.isNull("name") then
                uName = obj.getString("name")
              end
            end)

            local succRoot = LinearLayout(service)
            succRoot.setOrientation(LinearLayout.VERTICAL)
            succRoot.setBackgroundColor(Color.BLACK)
            succRoot.setPadding(20, 20, 20, 20)

            local succScroll = ScrollView(service)
            local succLayout = LinearLayout(service)
            succLayout.setOrientation(LinearLayout.VERTICAL)

            succLayout.addView(utils.createHeader("Token Verified Successfully!"))

            local txtStatus = TextView(service)
            txtStatus.setText("Logged in successfully!")
            txtStatus.setTextColor(Color.GREEN)
            txtStatus.setTextSize(18)
            txtStatus.setPadding(20, 10, 20, 10)
            succLayout.addView(txtStatus)

            local txtUser = TextView(service)
            txtUser.setText("Username: " .. uLogin)
            txtUser.setTextColor(Color.WHITE)
            txtUser.setTextSize(16)
            txtUser.setPadding(20, 10, 20, 10)
            succLayout.addView(txtUser)

            if uName ~= "" and uName ~= "null" then
              local txtName = TextView(service)
              txtName.setText("Name: " .. uName)
              txtName.setTextColor(Color.WHITE)
              txtName.setTextSize(16)
              txtName.setPadding(20, 10, 20, 10)
              succLayout.addView(txtName)
            end

            local btnContinue = Button(service)
            btnContinue.setText("Continue to Main Menu")
            btnContinue.setOnClickListener(View.OnClickListener({
              onClick = function() showMainScreen() end
            }))
            succLayout.addView(btnContinue)

            succScroll.addView(succLayout)
            succRoot.addView(succScroll)
            utils.enableBackKey(succRoot, function() showMainScreen() end)
            utils.setScreen(succRoot)
          end
        else
          local errRoot = LinearLayout(service)
          errRoot.setOrientation(LinearLayout.VERTICAL)
          errRoot.setBackgroundColor(Color.BLACK)
          errRoot.setPadding(20, 20, 20, 20)

          local errScroll = ScrollView(service)
          local errLayout = LinearLayout(service)
          errLayout.setOrientation(LinearLayout.VERTICAL)

          errLayout.addView(utils.createHeader("Invalid Token"))
          local errInfo = TextView(service)
          errInfo.setText("Token verification failed (Error " .. vCode .. "). Please check your token and try again.")
          errInfo.setTextColor(Color.YELLOW)
          errInfo.setTextSize(16)
          errInfo.setPadding(20, 20, 20, 20)
          errLayout.addView(errInfo)

          local btnErrBack = Button(service)
          btnErrBack.setText("Try Again")
          btnErrBack.setOnClickListener(View.OnClickListener({
            onClick = function() tokenModule.showTokenEditScreen(showMainScreen) end
          }))
          errLayout.addView(btnErrBack)

          errScroll.addView(errLayout)
          errRoot.addView(errScroll)
          utils.enableBackKey(errRoot, function() tokenModule.showTokenEditScreen(showMainScreen) end)
          utils.setScreen(errRoot)
        end
      end)
    end
  }))
  layout.addView(btnSave)

  if currentToken ~= "" then
    local btnDeleteToken = Button(service)
    btnDeleteToken.setText("Delete Token")
    btnDeleteToken.setOnClickListener(View.OnClickListener({
      onClick = function()
        local dConfRoot = LinearLayout(service)
        dConfRoot.setOrientation(LinearLayout.VERTICAL)
        dConfRoot.setBackgroundColor(Color.BLACK)
        dConfRoot.setPadding(20, 20, 20, 20)

        local dConfScroll = ScrollView(service)
        local dConfLayout = LinearLayout(service)
        dConfLayout.setOrientation(LinearLayout.VERTICAL)

        dConfLayout.addView(utils.createHeader("Confirm Token Deletion"))

        local dConfInfo = TextView(service)
        dConfInfo.setText("Are you sure you want to delete your saved Personal Access Token?")
        dConfInfo.setTextColor(Color.YELLOW)
        dConfInfo.setTextSize(16)
        dConfInfo.setPadding(20, 20, 20, 20)
        dConfLayout.addView(dConfInfo)

        local btnConfirmTokDel = Button(service)
        btnConfirmTokDel.setText("Yes, Delete Token")
        btnConfirmTokDel.setOnClickListener(View.OnClickListener({
          onClick = function()
            utils.deleteToken()
            showMainScreen()
          end
        }))
        dConfLayout.addView(btnConfirmTokDel)

        local btnCancelTokDel = Button(service)
        btnCancelTokDel.setText("Cancel")
        btnCancelTokDel.setOnClickListener(View.OnClickListener({
          onClick = function()
            tokenModule.showTokenEditScreen(showMainScreen)
          end
        }))
        dConfLayout.addView(btnCancelTokDel)

        dConfScroll.addView(dConfLayout)
        dConfRoot.addView(dConfScroll)
        utils.enableBackKey(dConfRoot, function() tokenModule.showTokenEditScreen(showMainScreen) end)
        utils.setScreen(dConfRoot)
      end
    }))
    layout.addView(btnDeleteToken)
  end

  local btnBack = Button(service)
  btnBack.setText("Cancel")
  btnBack.setOnClickListener(View.OnClickListener({
    onClick = function() showMainScreen() end
  }))
  layout.addView(btnBack)

  scroll.addView(layout)
  root.addView(scroll)
  utils.enableBackKey(root, function() showMainScreen() end)
  utils.setScreen(root)
end

return tokenModule