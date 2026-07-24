local utils = require("utils")
local tokenModule = require("token_module")
local myReposModule = require("my_repos")
local createRepoModule = require("create_repo")
local aboutModule = require("about_module")
local updater = require("updater")

local function showMainScreen()
  local root = LinearLayout(service)
  root.setOrientation(LinearLayout.VERTICAL)
  root.setBackgroundColor(Color.BLACK)
  root.setPadding(20, 20, 20, 20)

  local scroll = ScrollView(service)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)

  layout.addView(utils.createHeader("GitHub Manager"))

  local btnSetToken = Button(service)
  btnSetToken.setText("Set / Edit Personal Access Token")
  btnSetToken.setOnClickListener(View.OnClickListener({
    onClick = function()
      tokenModule.showTokenEditScreen(showMainScreen)
    end
  }))
  layout.addView(btnSetToken)

  local btnMyRepos = Button(service)
  btnMyRepos.setText("My Repositories")
  btnMyRepos.setOnClickListener(View.OnClickListener({
    onClick = function()
      myReposModule.showMyRepos(showMainScreen)
    end
  }))
  layout.addView(btnMyRepos)

  local btnCreateRepo = Button(service)
  btnCreateRepo.setText("Create New Repository")
  btnCreateRepo.setOnClickListener(View.OnClickListener({
    onClick = function()
      createRepoModule.showCreateRepoScreen(showMainScreen)
    end
  }))
  layout.addView(btnCreateRepo)

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