require "import"
import "android.view.WindowManager"
import "android.view.View"
import "android.view.KeyEvent"
import "android.graphics.Color"
import "android.widget.LinearLayout"
import "android.widget.ScrollView"
import "android.widget.TextView"
import "android.widget.Button"
import "android.widget.EditText"
import "android.os.Handler"
import "android.os.Looper"
import "java.net.URL"
import "java.net.HttpURLConnection"
import "java.io.BufferedReader"
import "java.io.InputStreamReader"
import "java.io.OutputStream"
import "java.lang.Thread"
import "java.lang.Runnable"
import "java.lang.String"
import "java.lang.StringBuilder"
import "android.util.Base64"
import "org.json.JSONArray"
import "org.json.JSONObject"
import "android.text.TextWatcher"
import "android.content.Intent"
import "android.net.Uri"
import "android.content.Context"
import "android.widget.Toast"
import "android.content.ClipboardManager"
import "android.content.ClipData"

local utils = {}

utils.tokenPath = service.getFilesDir().getAbsolutePath() .. "/gh_token.txt"

function utils.normalizeName(str)
  if not str then return "" end
  local cleaned = tostring(str):lower():gsub("%s+", ""):gsub("-", ""):gsub("_", "")
  return cleaned
end

function utils.urlEncode(str)
  if not str then return "" end
  return tostring(str):gsub(" ", "%%20")
end

utils.mainHandler = Handler(Looper.getMainLooper())

function utils.copyToClipboard(text)
  utils.mainHandler.post(Runnable({
    run = function()
      pcall(function()
        local cm = service.getSystemService(Context.CLIPBOARD_SERVICE)
        local clip = ClipData.newPlainText("Raw URL", text)
        cm.setPrimaryClip(clip)
        Toast.makeText(service, "Raw URL Copied!", Toast.LENGTH_SHORT).show()
        if utils.currentView then
          utils.currentView.requestFocus()
        end
      end)
    end
  }))
end

function utils.loadToken()
  local f = io.open(utils.tokenPath, "r")
  if f then
    local t = f:read("*a")
    f:close()
    if t then
      local cleanT = (t:gsub("%s+", ""))
      return tostring(cleanT)
    end
  end
  return ""
end

function utils.saveToken(newToken)
  local f = io.open(utils.tokenPath, "w")
  if f then
    f:write(tostring(newToken))
    f:close()
    return true
  end
  return false
end

function utils.deleteToken()
  pcall(function() os.remove(utils.tokenPath) end)
end

function utils.enableBackKey(rootView, backCallback)
  rootView.setFocusable(true)
  rootView.setFocusableInTouchMode(true)
  rootView.requestFocus()
  
  local listener = View.OnKeyListener({
    onKey = function(v, keyCode, event)
      if keyCode == KeyEvent.KEYCODE_BACK and event.getAction() == KeyEvent.ACTION_UP then
        if backCallback then
          backCallback()
        end
        return true
      end
      return false
    end
  })
  
  rootView.setOnKeyListener(listener)
  
  local function applyToChildren(viewGroup)
    pcall(function()
      local count = viewGroup.getChildCount()
      for i = 0, count - 1 do
        local child = viewGroup.getChildAt(i)
        child.setFocusable(true)
        child.setOnKeyListener(listener)
        pcall(function()
          if child.getChildCount then
            applyToChildren(child)
          end
        end)
      end
    end)
  end
  
  pcall(function()
    if rootView.getChildCount then
      applyToChildren(rootView)
    end
  end)
end

utils.wm = service.getSystemService(service.WINDOW_SERVICE)
utils.layoutParams = WindowManager.LayoutParams()
utils.layoutParams.width = WindowManager.LayoutParams.MATCH_PARENT
utils.layoutParams.height = WindowManager.LayoutParams.MATCH_PARENT
utils.layoutParams.type = WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
utils.layoutParams.flags = WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
utils.layoutParams.format = 1

utils.currentView = nil

function utils.setScreen(view)
  if utils.currentView ~= nil then
    pcall(function() utils.wm.removeViewImmediate(utils.currentView) end)
    pcall(function() utils.wm.removeView(utils.currentView) end)
  end
  utils.currentView = view
  if utils.currentView ~= nil then
    pcall(function() utils.wm.addView(utils.currentView, utils.layoutParams) end)
    pcall(function() utils.currentView.requestFocus() end)
  end
end

function utils.closeExtension()
  utils.setScreen(nil)
  pcall(function() service.finish() end)
  pcall(function() service.finishAndRemoveTask() end)
end

function utils.httpRequestWithToken(urlStr, method, jsonBody, customToken, callback)
  Thread(Runnable({
    run = function()
      local result = ""
      local code = 0
      local status, err = pcall(function()
        local url = URL(urlStr)
        local conn = url.openConnection()
        conn.setRequestMethod(method)
        conn.setRequestProperty("Authorization", "Bearer " .. customToken)
        conn.setRequestProperty("User-Agent", "GitHub-Manager-App")
        conn.setRequestProperty("Accept", "application/vnd.github.v3+json")
        if jsonBody and (method == "POST" or method == "PUT" or method == "PATCH" or method == "DELETE") then
          conn.setRequestProperty("Content-Type", "application/json; charset=UTF-8")
          conn.setDoOutput(true)
          local os = conn.getOutputStream()
          os.write(String(jsonBody).getBytes("UTF-8"))
          os.flush()
          os.close()
        end
        code = conn.getResponseCode()
        local is
        if code >= 200 and code < 300 then
          is = conn.getInputStream()
        else
          is = conn.getErrorStream()
        end
        if is then
          local br = BufferedReader(InputStreamReader(is, "UTF-8"))
          local sb = StringBuilder()
          local line = br.readLine()
          while line ~= nil do
            sb.append(line)
            line = br.readLine()
          end
          br.close()
          result = sb.toString()
        else
          result = ""
        end
      end)
      if not status then
        result = "Error: " .. tostring(err)
      end
      utils.mainHandler.post(Runnable({
        run = function()
          callback(code, result)
        end
      }))
    end
  })).start()
end

function utils.httpRequest(urlStr, method, jsonBody, callback)
  local token = utils.loadToken()
  if token == "" then
    utils.mainHandler.post(Runnable({
      run = function()
        callback(401, "Token missing")
      end
    }))
    return
  end
  utils.httpRequestWithToken(urlStr, method, jsonBody, token, callback)
end

function utils.createHeader(titleText)
  local title = TextView(service)
  title.setText(tostring(titleText))
  title.setTextSize(20)
  title.setTextColor(Color.WHITE)
  title.setPadding(30, 40, 30, 20)
  return title
end

function utils.showLoading(msg)
  local root = LinearLayout(service)
  root.setOrientation(LinearLayout.VERTICAL)
  root.setBackgroundColor(Color.BLACK)
  root.setPadding(20, 20, 20, 20)
  
  local scroll = ScrollView(service)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)
  layout.addView(utils.createHeader(msg))
  
  scroll.addView(layout)
  root.addView(scroll)
  utils.setScreen(root)
end

return utils