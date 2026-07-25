local utils = require("utils")

local aboutModule = {}

function aboutModule.showAboutScreen(showMainScreen)
  local root = LinearLayout(service)
  root.setOrientation(LinearLayout.VERTICAL)
  root.setBackgroundColor(Color.BLACK)
  root.setPadding(20, 20, 20, 20)

  local scroll = ScrollView(service)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)

  layout.addView(utils.createHeader("About & User Guide"))

  local infoCreator = TextView(service)
  infoCreator.setText("Created with brilliance and mastery by Moosa Zaib!\nThis powerful extension brings complete GitHub repository and file management right onto your device with absolute speed and convenience.")
  infoCreator.setTextColor(Color.CYAN)
  infoCreator.setTextSize(16)
  infoCreator.setPadding(20, 10, 20, 20)
  layout.addView(infoCreator)

  local btnContact = Button(service)
  btnContact.setText("Contact Moosa Zaib")
  btnContact.setOnClickListener(View.OnClickListener({
    onClick = function()
      pcall(function()
        local intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://wa.me/923123608972"))
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        service.startActivity(intent)
      end)
      utils.closeExtension()
    end
  }))
  layout.addView(btnContact)

  local guideHeader = TextView(service)
  guideHeader.setText("Step-by-Step Complete Guide:")
  guideHeader.setTextColor(Color.YELLOW)
  guideHeader.setTextSize(18)
  guideHeader.setPadding(20, 30, 20, 10)
  layout.addView(guideHeader)

  local step1 = TextView(service)
  step1.setText("Step 1: Setting Up Your Personal Access Token\nTo use this extension, you must connect it to your GitHub account using a Personal Access Token (PAT). Open 'Set / Edit Personal Access Token' from the main menu. Paste your token (starting with ghp_...) into the text box. Tap 'Save Token'. The app will instantly verify your token with GitHub, display your username and account name upon success, and securely save it for future use.")
  step1.setTextColor(Color.WHITE)
  step1.setTextSize(15)
  step1.setPadding(20, 10, 20, 15)
  layout.addView(step1)

  local step2 = TextView(service)
  step2.setText("Step 2: Viewing All Your Repositories\nOnce your token is saved and verified, go back to the main menu and tap 'My Repositories'. The extension will fetch a complete list of all your public and private repositories directly from your GitHub account.")
  step2.setTextColor(Color.WHITE)
  step2.setTextSize(15)
  step2.setPadding(20, 10, 20, 15)
  layout.addView(step2)

  local step3 = TextView(service)
  step3.setText("Step 3: Creating a New Repository (Public or Private)\nOpen 'My Repositories' from the main menu and tap 'Create New Repository' at the top of the repository list. Enter your desired repository name and tap 'Create'. Select whether you want it to be Public or Private to create it instantly.")
  step3.setTextColor(Color.WHITE)
  step3.setTextSize(15)
  step3.setPadding(20, 10, 20, 15)
  layout.addView(step3)

  local step4 = TextView(service)
  step4.setText("Step 4: Browsing & Managing Repository Files\nTap on any repository from your list to directly view its files and folders. Tap on any file to edit its content, copy its raw URL, or delete it. You can navigate through sub-folders seamlessly using the back button.")
  step4.setTextColor(Color.WHITE)
  step4.setTextSize(15)
  step4.setPadding(20, 10, 20, 15)
  layout.addView(step4)

  local step5 = TextView(service)
  step5.setText("Step 5: More Repository Options\nInside any repository screen, tap the 'More Options' button at the top to perform full management tasks:\n- Copy Repo / Zip Links\n- Upload New File\n- Rename Repository\n- Toggle Visibility (Public/Private)\n- Delete Repository")
  step5.setTextColor(Color.WHITE)
  step5.setTextSize(15)
  step5.setPadding(20, 10, 20, 15)
  layout.addView(step5)

  local step6 = TextView(service)
  step6.setText("Step 6: Easy Navigation & Closing Extension\nYou can press your phone's Back Button at any moment to safely return to the previous menu. To exit, tap 'Close Extension' on the main menu.")
  step6.setTextColor(Color.WHITE)
  step6.setTextSize(15)
  step6.setPadding(20, 10, 20, 15)
  layout.addView(step6)

  local step7 = TextView(service)
  step7.setText("Step 7: Automatic Updates\nWhenever you launch the extension with an active internet connection, it automatically checks for new updates in the background. If an update is found, an update dialog will appear showing the latest changes ('What's New'). Simply tap 'Update Now' to download and install the update automatically, then tap 'Restart Extension' to reload and apply all changes smoothly.")
  step7.setTextColor(Color.WHITE)
  step7.setTextSize(15)
  step7.setPadding(20, 10, 20, 20)
  layout.addView(step7)

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

return aboutModule
