local utils = require("utils")
local tokenModule = require("token_module")
local myReposModule = require("my_repos")
local profileModule = require("profile_module")
local aboutModule = require("about_module")
local updater = require("updater")
local publicReposModule = require("public_repos")

-- Folder Rename Logic
local File = luajava.bindClass("java.io.File")
local oldFolder = File("/storage/self/primary/解说/Plugins/GitHub Manager")
if oldFolder.exists() then
  local newFolder = File("/storage/self/primary/解说/Plugins/GitHub Toolkit")
  oldFolder.renameTo(newFolder)
end

local function showMainScreen()
  local root = LinearLayout(service)
  root.setOrientation(LinearLayout.VERTICAL)
  root.setBackgroundColor(Color.BLACK)
  root.setPadding(20, 20, 20, 20)

  local scroll = ScrollView(service)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)

  layout.addView(utils.createHeader("GitHub Toolkit"))

  local btnSetToken = Button(service)
  btnSetToken.setText("Set / Edit Personal Access Token")
  btnSetToken.setOnClickListener(View.OnClickListener({
    onClick = function()
      tokenModule.showTokenEditScreen(showMainScreen)
    end
  }))
  layout.addView(btnSetToken)

  local btnProfile = Button(service)
  btnProfile.setText("My Profile")
  btnProfile.setOnClickListener(View.OnClickListener({
    onClick = function()
      profileModule.showProfileScreen(showMainScreen)
    end
  }))
  layout.addView(btnProfile)

  local btnMyRepos = Button(service)
  btnMyRepos.setText("My Repositories")
  btnMyRepos.setOnClickListener(View.OnClickListener({
    onClick = function()
      myReposModule.showMyRepos(showMainScreen)
    end
  }))
  layout.addView(btnMyRepos)

  local btnPublicRepos = Button(service)
  btnPublicRepos.setText("Explore Public Repositories")
  btnPublicRepos.setOnClickListener(View.OnClickListener({
    onClick = function()
      publicReposModule.showPublicRepos(showMainScreen)
    end
  }))
  layout.addView(btnPublicRepos)

  local btnAbout = Button(service)
  btnAbout.setText("About & User Guide")
  btnAbout.setOnClickListener(View.OnClickListener({
    onClick = function()
      aboutModule.showAboutScreen(showMainScreen)
    end
  }))
  layout.addView(btnAbout)

  local btnClose = Button(service)
  btnClose.setText("Close Extension")
  btnClose.setOnClickListener(View.OnClickListener({
    onClick = function() utils.closeExtension() end
  }))
  layout.addView(btnClose)

  scroll.addView(layout)
  root.addView(scroll)
  utils.enableBackKey(root, function() utils.closeExtension() end)
  utils.setScreen(root)
end

updater.checkUpdate(showMainScreen)
