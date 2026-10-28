--[[
  streamdeck_reconnect.lua
  Stream Deck のアプリが本体との接続に失敗したら、アプリを再起動してつなぎ直す Hammerspoon モジュール

  スリープ復帰時などに、アプリが本体を読み取れず（Read FW version: FAILED）接続をあきらめることがある。
  このときアプリのログに出る「Problem with connecting HID device」を監視して再起動する。
  アプリはログを開いたまま書き続け、ファイルの変更通知が届かないので、一定間隔で追記分を読む。
  再起動は続けて maxRetries 回まで。それでもつながらなければ通知を出して止める。

  使い方:
    ~/.hammerspoon/init.lua に require("streamdeck_reconnect") を追加して Reload Config
]]

local M = {}
local log = hs.logger.new("streamdeck", "info")

local config = {
  bundleID     = "com.elgato.StreamDeck",
  appName      = "Elgato Stream Deck",
  logDir       = os.getenv("HOME") .. "/Library/Logs/ElgatoStreamDeck",
  logName      = "StreamDeck.log",
  failure      = "Problem with connecting HID device",        -- 完全一致の部分文字列
  success      = "device status changed .*: connected$",      -- Lua パターン
  pollInterval = 5,    -- 秒
  maxRetries   = 3,
  retryWindow  = 600,  -- 秒。最後の再起動からこれだけ経っていれば回数を数え直す
  quitTimeout  = 10,   -- 秒。終了しなければ強制終了する
  launchDelay  = 2,    -- 秒。終了を確かめてから起動するまで
}
M.config = config

local state = { offset = 0, inode = nil, retries = 0, lastRestart = 0, busy = false }
M.state = state

---------------------------------------------------------------------------
-- ログの監視
---------------------------------------------------------------------------

-- 前回から追記された行を返す。書きかけの行は次回に回す
-- アプリを起動するたびにログは StreamDeck.1.log へ回され、新しいファイルになる
local function readNewLines()
  local path = config.logDir .. "/" .. config.logName
  local a = hs.fs.attributes(path)
  if not a then return {} end
  if a.ino ~= state.inode or a.size < state.offset then
    state.inode, state.offset = a.ino, 0
  end
  if a.size == state.offset then return {} end
  local f = io.open(path, "r")
  if not f then return {} end
  f:seek("set", state.offset)
  local text = f:read("a")
  f:close()
  local cut = text:match(".*\n()")
  if not cut then return {} end
  state.offset = state.offset + cut - 1
  local lines = {}
  for line in text:sub(1, cut - 1):gmatch("[^\n]+") do lines[#lines + 1] = line end
  return lines
end

-- 接続の成否を表す最後の行から "failure" / "success" / nil を返す
local function lastStatus(lines)
  local status
  for _, line in ipairs(lines) do
    if line:find(config.failure, 1, true) then
      status = "failure"
    elseif line:find(config.success) then
      status = "success"
    end
  end
  return status
end

function M.notify(text)
  hs.notify.new({ title = "Stream Deck", informativeText = text }):send()
end

local function onFailure()
  if os.time() - state.lastRestart > config.retryWindow then state.retries = 0 end
  if state.retries >= config.maxRetries then
    log.w("connection failed; giving up")
    M.notify("本体につながりません。USB ケーブルを挿し直してください")
    return
  end
  state.retries = state.retries + 1
  state.lastRestart = os.time()
  log.i(string.format("connection failed; restarting (%d/%d)", state.retries, config.maxRetries))
  M.restart()
end

local function check()
  local status = lastStatus(readNewLines())
  if status == "failure" then
    onFailure()
  elseif status == "success" then
    state.retries = 0
  end
end

---------------------------------------------------------------------------
-- 再起動
---------------------------------------------------------------------------

-- アプリを終了し、プロセスが消えたのを確かめてから、ログイン時と同じくバックグラウンドで起動する
function M.restart()
  if state.busy then return end
  state.busy = true
  local app = hs.application.get(config.bundleID)
  if app then app:kill() end
  local deadline = hs.timer.secondsSinceEpoch() + config.quitTimeout
  M.timer = hs.timer.doEvery(0.5, function()
    local running = hs.application.get(config.bundleID)
    if running and hs.timer.secondsSinceEpoch() < deadline then return end
    if running then running:kill9() end
    M.timer:stop()
    M.timer = hs.timer.doAfter(config.launchDelay, function()
      M.task = hs.task.new("/usr/bin/open", nil, { "-a", config.appName, "--args", "--runinbk" }):start()
      state.busy = false
    end)
  end)
end

---------------------------------------------------------------------------
-- 開始・停止
---------------------------------------------------------------------------

-- 読み込み時点のログも確かめ、接続に失敗したままならすぐに再起動する
function M.start()
  state.offset, state.inode, state.retries, state.lastRestart = 0, nil, 0, 0
  check()
  M.poller = hs.timer.doEvery(config.pollInterval, check)
end

function M.stop()
  if M.poller then M.poller:stop() end
  M.poller = nil
end

M.start()

return M
