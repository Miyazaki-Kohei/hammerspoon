--[[
  chrome_translate.lua
  Chrome 標準のページ翻訳（Google翻訳）を ⌃⌥T で「原文 ⇔ 日本語」トグルする Hammerspoon モジュール

  仕組み:
    1. アドレスバーの翻訳アイコンをアクセシビリティ API で押して翻訳バブルを開く
    2. バブル内の言語タブ（例: 英語 | 日本語）のうち、選ばれていない方を押す
    3. バブルを Esc で閉じる
  → 拡張機能は使わず、Chrome 標準の翻訳をそのまま操作する

  使い方:
    ~/.hammerspoon/chrome_translate.lua に置き、~/.hammerspoon/init.lua に
      require("chrome_translate")
    を追加して Reload Config。Hammerspoon にアクセシビリティ権限が必要。

  ホットキー（Chrome が前面のときだけ有効）:
    ⌃⌥T   : 原文 ⇔ 日本語 を切り替え
    ⌃⌥⇧T  : 診断（Chrome のボタン類をコンソールに出力）
]]

local M = {}
local ax = hs.axuielement

local config = {
  bundleID      = "com.google.Chrome",
  hotkey        = { mods = { "ctrl", "alt" }, key = "t" },
  debugKey      = { mods = { "ctrl", "alt", "shift" }, key = "t" },
  -- 翻訳アイコンの読み上げ名（AXDescription と完全一致で探す）
  iconNames     = { ["翻訳"] = true, ["Translate"] = true, ["Translate this page"] = true },
  -- バブル内タブ検出のフォールバック用
  langTitles    = { ["日本語"] = true, ["英語"] = true, ["Japanese"] = true, ["English"] = true },
  maxDepth      = 30,
  bubbleTimeout = 2.0,   -- 秒
  pollInterval  = 0.05,  -- 秒
}

---------------------------------------------------------------------------
-- ユーティリティ
---------------------------------------------------------------------------

local function attr(el, name)
  local ok, v = pcall(function() return el:attributeValue(name) end)
  if ok then return v end
  return nil
end

-- 要素が消えていてもエラーにしない
local function press(el)
  return pcall(function() return el:performAction("AXPress") end)
end

-- AX ツリーを深さ優先で走査。ページ本体（AXWebArea）は巨大なので入らない
local function walk(el, visit, depth)
  depth = depth or 0
  if not el or depth > config.maxDepth then return end
  local role = attr(el, "AXRole")
  if role == "AXWebArea" then return end
  if visit(el, role) == "stop" then return "stop" end
  for _, child in ipairs(attr(el, "AXChildren") or {}) do
    if walk(child, visit, depth + 1) == "stop" then return "stop" end
  end
end

local function frontChrome()
  local app = hs.application.frontmostApplication()
  if app and app:bundleID() == config.bundleID then return app end
  return nil
end

---------------------------------------------------------------------------
-- 要素の検索
---------------------------------------------------------------------------

-- アドレスバー内の翻訳アイコン。ブックマークは名前が AXTitle に入るので一致しない
local function findTranslateIcon(win)
  local found
  walk(win, function(el, role)
    if role == "AXButton" and config.iconNames[attr(el, "AXDescription")] then
      found = el
      return "stop"
    end
  end)
  return found
end

-- 翻訳バブル内の 2 つの言語タブ（[原文, 翻訳先] の順）を返す
local function findLanguageTabs(appEl, allowFallback)
  local tabs = {}
  local function collect(root, filter)
    walk(root, function(el, role)
      if role == "AXRadioButton" or role == "AXTab" then
        local title = attr(el, "AXTitle") or attr(el, "AXDescription")
        if type(title) == "string" and title ~= "" and (not filter or filter(title)) then
          table.insert(tabs, el)
        end
      end
    end)
  end

  local windows = attr(appEl, "AXWindows") or {}

  -- 1) 通常のブラウザウィンドウ以外（＝バブル）から探す
  for _, w in ipairs(windows) do
    if attr(w, "AXSubrole") ~= "AXStandardWindow" then collect(w) end
  end

  -- 2) 見つからなければ、言語名に一致するタブを全ウィンドウから探す
  if #tabs < 2 and allowFallback then
    tabs = {}
    for _, w in ipairs(windows) do
      collect(w, function(t) return config.langTitles[t] end)
    end
  end

  if #tabs >= 2 then return tabs[1], tabs[2] end
  return nil
end

local function isSelected(el)
  local v = attr(el, "AXValue")
  return v == 1 or v == true or attr(el, "AXSelected") == true
end

---------------------------------------------------------------------------
-- メイン処理
---------------------------------------------------------------------------

local busy = false

-- Chrome が背面だとアイコンを押してもバブルが開かないので、前面のときだけ動かす
function M.toggle()
  if busy then return end
  local app = frontChrome()
  if not app then return end

  local appEl = ax.applicationElement(app)
  -- バブルにフォーカスがあると AXFocusedWindow はバブルになるので、ブラウザ本体の AXMainWindow を使う
  local win = attr(appEl, "AXMainWindow") or attr(appEl, "AXFocusedWindow")
  if not win then return end

  local icon = findTranslateIcon(win)
  if not icon then
    hs.alert.show("翻訳アイコンが見つかりません")
    return
  end

  busy = true
  press(icon)

  local elapsed = 0
  local timer
  timer = hs.timer.doEvery(config.pollInterval, function()
    elapsed = elapsed + config.pollInterval
    local source, target = findLanguageTabs(appEl, elapsed > 0.5)

    if source and target then
      timer:stop()
      -- 選ばれていない方を押す（翻訳済みなら原文へ、原文なら翻訳へ）
      local next = isSelected(source) and target or source
      press(next)
      hs.timer.doAfter(0.15, function()
        hs.eventtap.keyStroke({}, "escape", 0, app)  -- バブルを閉じる
        busy = false
      end)
    elseif elapsed >= config.bubbleTimeout then
      timer:stop()
      busy = false
      hs.alert.show("翻訳バブルを検出できませんでした（⌃⌥⇧T で診断）")
    end
  end)
end

-- 診断: Chrome の全ウィンドウのボタン類をコンソールに出力
-- 翻訳バブルを手で開いた状態で実行すると、タブの構造も確認できる
function M.dump()
  local app = frontChrome()
  if not app then
    hs.alert.show("Chrome を前面にしてください")
    return
  end
  local appEl = ax.applicationElement(app)
  print("==== Chrome AX dump ====")
  for i, w in ipairs(attr(appEl, "AXWindows") or {}) do
    print(string.format("[window %d] subrole=%s title=%s",
      i, tostring(attr(w, "AXSubrole")), tostring(attr(w, "AXTitle"))))
    walk(w, function(el, role)
      if role == "AXButton" or role == "AXPopUpButton" or role == "AXMenuButton"
        or role == "AXRadioButton" or role == "AXTab" then
        print(string.format("  %-14s title=%s desc=%s help=%s value=%s",
          role,
          tostring(attr(el, "AXTitle")),
          tostring(attr(el, "AXDescription")),
          tostring(attr(el, "AXHelp")),
          tostring(attr(el, "AXValue"))))
      end
    end)
  end
  hs.openConsole()
end

---------------------------------------------------------------------------
-- ホットキー（Chrome が前面のときだけ有効にして、他アプリのキーを奪わない）
---------------------------------------------------------------------------

M.hotkey = hs.hotkey.new(config.hotkey.mods, config.hotkey.key, M.toggle)
M.debugHotkey = hs.hotkey.new(config.debugKey.mods, config.debugKey.key, M.dump)

local function updateHotkeys(bundleID)
  if bundleID == config.bundleID then
    M.hotkey:enable()
    M.debugHotkey:enable()
  else
    M.hotkey:disable()
    M.debugHotkey:disable()
  end
end

M.watcher = hs.application.watcher.new(function(_, event, app)
  if event == hs.application.watcher.activated and app then
    updateHotkeys(app:bundleID())
  end
end)
M.watcher:start()

local front = hs.application.frontmostApplication()
updateHotkeys(front and front:bundleID())

return M
