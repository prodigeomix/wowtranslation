-- WoWTranslate.lua
-- WoWTranslate.lua
-- Main addon file: chat hooks, display, and coordination
-- Chinese to English translation for WoW 1.12


-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

SLASH_WOWTRANSLATE1 = "/wt"
SLASH_WOWTRANSLATE2 = "/wowtranslate"

SlashCmdList["WOWTRANSLATE"] = function(msg)
    if not WoWTranslateDB then
        WoWTranslateDB = {}
        WT_InitializeSettings()
    end

    local cmd, arg = WT_strsplit(" ", msg, 2)
    cmd = string.lower(cmd or "")

    if cmd == "on" or cmd == "enable" then
        WoWTranslateDB.enabled = true
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[WoWTranslate] Enabled|r")

    elseif cmd == "off" or cmd == "disable" then
        WoWTranslateDB.enabled = false
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[WoWTranslate] Disabled|r")

    elseif cmd == "status" then
        local dllStatus = WoWTranslate_API.IsAvailable()
            and "|cFF00FF00Connected|r"
            or "|cFFFF0000Not loaded|r"

        local cacheStats = WoWTranslate_CacheStats()
        local glossaryCount = WoWTranslate_GetGlossaryCount()
        local pendingCount = WoWTranslate_API.GetPendingCount()

        local queuedCount = 0
        for _ in pairs(WT_pendingMessages) do
            queuedCount = queuedCount + 1
        end

        local outgoingQueuedCount = 0
        for _ in pairs(WT_outgoingQueue) do
            outgoingQueuedCount = outgoingQueuedCount + 1
        end

        local outgoingStatus = WoWTranslateDB.outgoingEnabled
            and "|cFF00FF00ON|r"
            or "|cFFFF0000OFF|r"

        local hookStatus = WT_IsOutgoingHookActive()
            and "|cFF00FF00ACTIVE|r"
            or "|cFFFF0000INACTIVE|r"

        DEFAULT_CHAT_FRAME:AddMessage("[WoWTranslate] Status:")
        DEFAULT_CHAT_FRAME:AddMessage("  DLL: " .. dllStatus)
        DEFAULT_CHAT_FRAME:AddMessage("  Incoming: " .. (WoWTranslateDB.enabled and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"))
        DEFAULT_CHAT_FRAME:AddMessage("  Outgoing: " .. outgoingStatus)
        DEFAULT_CHAT_FRAME:AddMessage("  Outgoing Hook: " .. hookStatus)
        DEFAULT_CHAT_FRAME:AddMessage("  Glossary entries: " .. glossaryCount)
        DEFAULT_CHAT_FRAME:AddMessage("  Cached translations: " .. cacheStats.entries)
        DEFAULT_CHAT_FRAME:AddMessage("  Cache hit rate: " .. string.format("%.1f%%", cacheStats.hitRate))
        DEFAULT_CHAT_FRAME:AddMessage("  Pending API requests: " .. pendingCount)
        DEFAULT_CHAT_FRAME:AddMessage("  Queued incoming: " .. queuedCount)
        DEFAULT_CHAT_FRAME:AddMessage("  Queued outgoing: " .. outgoingQueuedCount)
        local cbErr = WoWTranslate_API.GetLastCallbackError and WoWTranslate_API.GetLastCallbackError()
        if cbErr then
            DEFAULT_CHAT_FRAME:AddMessage("  |cFFFF4444Last callback error:|r " .. cbErr)
        end
        local rlActive, rlRemaining = WoWTranslate_API.GetRateLimitInfo()
        if rlActive then
            DEFAULT_CHAT_FRAME:AddMessage("  |cFFFF4444API backoff active:|r " .. rlRemaining .. "s remaining (use /wt reset to clear)")
        end

    elseif cmd == "test" then
        local testText = arg or "\228\189\160\229\165\189"
        DEFAULT_CHAT_FRAME:AddMessage("[WoWTranslate] Testing: " .. testText)

        local cached, found = WoWTranslate_CacheGet(testText)
        if found then
            DEFAULT_CHAT_FRAME:AddMessage("[WoWTranslate] Cache hit: " .. cached)
            return
        end

        if not WoWTranslate_API.IsAvailable() then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[WoWTranslate] DLL not available|r")
            return
        end

        DEFAULT_CHAT_FRAME:AddMessage("[WoWTranslate] Requesting from API...")
        WoWTranslate_API.Translate(testText, function(result, err)
            if result then
                DEFAULT_CHAT_FRAME:AddMessage("[WoWTranslate] API result: " .. result)
                WoWTranslate_CacheSave(testText, result)
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[WoWTranslate] API error: " .. (err or "unknown") .. "|r")
            end
        end)

    elseif cmd == "clearcache" then
        WoWTranslate_CacheClear()
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[WoWTranslate] Cache cleared|r")

    elseif cmd == "debug" then
        WT_DEBUG_MODE = not WT_DEBUG_MODE
        WoWTranslateDB.debugMode = WT_DEBUG_MODE
        DEFAULT_CHAT_FRAME:AddMessage("[WoWTranslate] Debug mode: " .. (WT_DEBUG_MODE and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"))

    elseif cmd == "log" then
        DEFAULT_CHAT_FRAME:AddMessage("[WoWTranslate] Recent log entries:")
        local logs = WoWTranslateDebugLog or {}
        local start = math.max(1, table.getn(logs) - 19)
        for i = start, table.getn(logs) do
            DEFAULT_CHAT_FRAME:AddMessage("  " .. logs[i])
        end

    elseif cmd == "clearlog" then
        WoWTranslateDebugLog = {}
        DEFAULT_CHAT_FRAME:AddMessage("[WoWTranslate] Debug log cleared")

    elseif cmd == "testlink" then
        -- Test hyperlink parsing and localization
        local testMsg = "|cffffffff|Hplayer:TestName|h[TestName]|h|r says hello"
        DEFAULT_CHAT_FRAME:AddMessage("[WoWTranslate] Testing hyperlink parse:")
        DEFAULT_CHAT_FRAME:AddMessage("  Input: " .. testMsg)
        local segs = WT_SplitIntoSegments(testMsg)
        for idx, seg in ipairs(segs) do
            DEFAULT_CHAT_FRAME:AddMessage("  Seg " .. idx .. " [" .. seg.type .. "]: " .. seg.content)
        end

    elseif cmd == "testitem" then
        -- Test item localization with a known item
        DEFAULT_CHAT_FRAME:AddMessage("[WoWTranslate] Testing item localization...")
        local itemId = 2589  -- Default: Linen Cloth (common item)
        if arg and arg ~= "" then
            itemId = tonumber(arg) or 19716
        end
        DEFAULT_CHAT_FRAME:AddMessage("  Item ID: " .. tostring(itemId))
        local itemName = GetItemInfo(itemId)
        if itemName then
            DEFAULT_CHAT_FRAME:AddMessage("  GetItemInfo returned: " .. itemName)
            -- Create a fake Chinese link to test localization
            local testLink = "|cffa335ee|Hitem:" .. itemId .. ":0:0:0|h[测试物品]|h|r"
            DEFAULT_CHAT_FRAME:AddMessage("  Test link: " .. testLink)
            local localized = WT_LocalizeHyperlink(testLink)
            DEFAULT_CHAT_FRAME:AddMessage("  Localized: " .. localized)
        else
            DEFAULT_CHAT_FRAME:AddMessage("  GetItemInfo returned nil - item not in client cache")
            DEFAULT_CHAT_FRAME:AddMessage("  Try: /wt testitem with an item ID you've seen (hover over an item link first)")
        end

    elseif cmd == "testquest" then
        -- Test quest localization using pfQuest database
        DEFAULT_CHAT_FRAME:AddMessage("[WoWTranslate] Testing quest localization...")
        local questId = 913  -- Default: Stranglethorn Fever (common quest)
        if arg and arg ~= "" then
            questId = tonumber(arg) or 913
        end
        DEFAULT_CHAT_FRAME:AddMessage("  Quest ID: " .. tostring(questId))

        -- Check if pfQuest database is available
        if not pfDB or not pfDB["quests"] then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000  pfQuest database not found!|r")
            DEFAULT_CHAT_FRAME:AddMessage("  Quest localization requires pfQuest addon to be installed")
            return
        end

        local questName = WT_GetEnglishQuestName(questId)
        if questName then
            DEFAULT_CHAT_FRAME:AddMessage("  WT_GetEnglishQuestName returned: " .. questName)
            -- Create a fake Chinese link to test localization
            local testLink = "|cffffff00|Hquest:" .. questId .. ":60|h[测试任务]|h|r"
            DEFAULT_CHAT_FRAME:AddMessage("  Test link: " .. testLink)
            local localized = WT_LocalizeHyperlink(testLink)
            DEFAULT_CHAT_FRAME:AddMessage("  Localized: " .. localized)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000  Quest not found in pfQuest database|r")
            DEFAULT_CHAT_FRAME:AddMessage("  Try: /wt testquest <questId> with a known quest ID")
        end

    -- =====================================================================
    -- OUTGOING TRANSLATION COMMANDS
    -- =====================================================================
    elseif cmd == "outgoing" then
        if arg == "on" or arg == "enable" then
            WoWTranslate_SetOutgoingEnabled(true)
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[WoWTranslate] Outgoing translation enabled|r")
        elseif arg == "off" or arg == "disable" then
            WoWTranslate_SetOutgoingEnabled(false)
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[WoWTranslate] Outgoing translation disabled|r")
        else
            -- No arg: toggle
            WoWTranslate_SetOutgoingEnabled(not WoWTranslateDB.outgoingEnabled)
            local status = WoWTranslateDB.outgoingEnabled and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"
            DEFAULT_CHAT_FRAME:AddMessage("[WoWTranslate] Outgoing translation: " .. status)
        end

    elseif cmd == "outchannel" then
        if not WoWTranslateDB.outgoingChannels then
            WoWTranslateDB.outgoingChannels = WT_defaults.outgoingChannels
        end

        if arg and arg ~= "" then
            local channelType = string.upper(arg)
            if WoWTranslateDB.outgoingChannels[channelType] ~= nil then
                WoWTranslateDB.outgoingChannels[channelType] = not WoWTranslateDB.outgoingChannels[channelType]
                local newStatus = WoWTranslateDB.outgoingChannels[channelType] and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"
                DEFAULT_CHAT_FRAME:AddMessage("[WoWTranslate] Outgoing " .. channelType .. ": " .. newStatus)
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[WoWTranslate] Unknown channel: " .. channelType .. "|r")
                DEFAULT_CHAT_FRAME:AddMessage("  Valid channels: WHISPER, PARTY, GUILD, RAID, SAY, YELL, BATTLEGROUND, CHANNEL")
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("[WoWTranslate] Outgoing channel settings:")
            for channelType, enabled in pairs(WoWTranslateDB.outgoingChannels) do
                local status = enabled and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"
                DEFAULT_CHAT_FRAME:AddMessage("  " .. channelType .. ": " .. status)
            end
            DEFAULT_CHAT_FRAME:AddMessage("  Usage: /wt outchannel <WHISPER|PARTY|GUILD|RAID|SAY|YELL|BATTLEGROUND|CHANNEL>")
        end

    elseif cmd == "prefix" then
        if arg and arg ~= "" then
            WoWTranslateDB.outgoingPrefix = arg
            DEFAULT_CHAT_FRAME:AddMessage("[WoWTranslate] Outgoing prefix set to: " .. arg)
        else
            DEFAULT_CHAT_FRAME:AddMessage("[WoWTranslate] Current prefix: " .. (WoWTranslateDB.outgoingPrefix or "[Translated]"))
            DEFAULT_CHAT_FRAME:AddMessage("  Usage: /wt prefix <text>")
        end

    elseif cmd == "testout" then
        local testText = arg or "Hello, how are you?"
        DEFAULT_CHAT_FRAME:AddMessage("[WoWTranslate] Testing outgoing translation:")
        DEFAULT_CHAT_FRAME:AddMessage("  Input: " .. testText)

        if not WoWTranslate_API.IsAvailable() then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[WoWTranslate] DLL not available|r")
            return
        end

        DEFAULT_CHAT_FRAME:AddMessage("[WoWTranslate] Requesting from API...")
        WoWTranslate_API.TranslateOutgoing(testText, function(result, err)
            if result then
                DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[WoWTranslate] Translation:|r " .. result)
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[WoWTranslate] Error: " .. (err or "unknown") .. "|r")
            end
        end)

    -- =====================================================================
    -- CONFIGURATION UI COMMANDS
    -- =====================================================================
    elseif cmd == "reset" then
        -- Full recovery: re-hook frames (fixes disabled handlers), clear stale API state
        local cleared = WoWTranslate_API.GetPendingCount()
        WoWTranslate_API.ClearPending()
        WoWTranslate_API.ResetBackoff()
        WT_dllWarnShown = false
        WT_translationErrWarnShown = false
        WT_HookChatFrames(true)  -- force re-install all chat frame hooks
        local ok = WoWTranslate_API.CheckDLL()
        if ok then
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[WoWTranslate] Reset OK — hooks reinstalled, DLL responding, cleared " .. cleared .. " stale request(s)|r")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[WoWTranslate] Reset: hooks reinstalled but DLL not responding — try /reload|r")
        end

    elseif cmd == "hooktest" then
        -- Check whether SetScript("OnEvent") hooks are installed on each chat frame
        local hookedCount = 0
        local totalFrames = 0
        for i = 1, NUM_CHAT_WINDOWS do
            local f = getglobal("ChatFrame" .. i)
            if f then
                totalFrames = totalFrames + 1
                if f.WoWTranslateHooked then
                    hookedCount = hookedCount + 1
                end
            end
        end

        if hookedCount == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF4444[WT hooktest] NO frames hooked (0/" .. totalFrames .. ")|r")
        elseif hookedCount < totalFrames then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF8800[WT hooktest] Partially hooked: " .. hookedCount .. "/" .. totalFrames .. " frames|r")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[WT hooktest] All " .. hookedCount .. "/" .. totalFrames .. " frames hooked via SetScript(OnEvent)|r")
        end
        DEFAULT_CHAT_FRAME:AddMessage("[WT hooktest] Hook call count: " .. tostring(WT_hookCallCount))
        if WT_hookCallCount == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF8800[WT hooktest] Count=0: hook installed but no events fired yet (or all events filtered)|r")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[WT hooktest] Hook is firing correctly|r")
        end

    elseif cmd == "show" or cmd == "config" or cmd == "options" then
        WoWTranslate_ShowConfig()

    elseif cmd == "hide" then
        WoWTranslate_HideConfig()

    else
        DEFAULT_CHAT_FRAME:AddMessage("[WoWTranslate] Commands:")
        DEFAULT_CHAT_FRAME:AddMessage("  /wt show - Open configuration panel")
        DEFAULT_CHAT_FRAME:AddMessage("  /wt hide - Close configuration panel")
        DEFAULT_CHAT_FRAME:AddMessage("  /wt on|off - Enable/disable incoming translation")
        DEFAULT_CHAT_FRAME:AddMessage("  /wt status - Show status")
        DEFAULT_CHAT_FRAME:AddMessage("  /wt reset - Recover if translations stop after alt-tab")
        DEFAULT_CHAT_FRAME:AddMessage("  /wt clearcache - Clear cache")
        DEFAULT_CHAT_FRAME:AddMessage("  /wt debug - Toggle debug mode")
        DEFAULT_CHAT_FRAME:AddMessage("  -- Outgoing --")
        DEFAULT_CHAT_FRAME:AddMessage("  /wt outgoing - toggle outgoing translation (on/off to set explicitly)")
        DEFAULT_CHAT_FRAME:AddMessage("  /wt outchannel [type] - Show/toggle channel settings")
        DEFAULT_CHAT_FRAME:AddMessage("  /wt prefix <text> - Set message prefix")
    end
end


-- ============================================================================
-- ADDON INITIALIZATION
-- ============================================================================

function WT_InitializeSettings()
    if not WoWTranslateDB then WoWTranslateDB = {} end
    if not WoWTranslateDebugLog then WoWTranslateDebugLog = {} end
    if type(WoWTranslateCache) ~= "table" then WoWTranslateCache = {} end

    for key, value in pairs(WT_defaults) do
        if WoWTranslateDB[key] == nil then
            WoWTranslateDB[key] = value
        end
    end

    -- Migration: fix old short prefix to new full prefix
    if WoWTranslateDB.outgoingPrefix == "[Translated]" then
        WoWTranslateDB.outgoingPrefix = "[Translated by WoWTranslate]"
    end

    -- Migration: add BATTLEGROUND/CHANNEL/HARDCORE to existing outgoingChannels
    if WoWTranslateDB.outgoingChannels then
        if WoWTranslateDB.outgoingChannels.BATTLEGROUND == nil then
            WoWTranslateDB.outgoingChannels.BATTLEGROUND = true
        end
        if WoWTranslateDB.outgoingChannels.CHANNEL == nil then
            WoWTranslateDB.outgoingChannels.CHANNEL = true
        end
        if WoWTranslateDB.outgoingChannels.HARDCORE == nil then
            WoWTranslateDB.outgoingChannels.HARDCORE = false
        end
        if WoWTranslateDB.outgoingChannels.ENGLISH == nil then
            WoWTranslateDB.outgoingChannels.ENGLISH = false
        end
    end

    -- Migration: create incomingChannels if it doesn't exist
    if not WoWTranslateDB.incomingChannels then
        WoWTranslateDB.incomingChannels = {}
        for k, v in pairs(WT_defaults.incomingChannels) do
            WoWTranslateDB.incomingChannels[k] = v
        end
    end
    if WoWTranslateDB.incomingChannels.HARDCORE == nil then
        WoWTranslateDB.incomingChannels.HARDCORE = false
    end
    if WoWTranslateDB.incomingChannels.ENGLISH == nil then
        WoWTranslateDB.incomingChannels.ENGLISH = false
    end

    if WoWTranslateDB.translationColorFollow == nil then
        WoWTranslateDB.translationColorFollow = false
    end

    WT_DEBUG_MODE = WoWTranslateDB.debugMode or false

    -- Migrate: remove old apiKey and incomingFromLang fields
    WoWTranslateDB.apiKey = nil
    WoWTranslateDB.incomingFromLang = nil

    -- Migrate: add enabledSourceLangs if missing
    if WoWTranslateDB.enabledSourceLangs == nil then
        WoWTranslateDB.enabledSourceLangs = { zh=true, ja=true, ko=true, ru=true }
    end
    if WoWTranslateDB.enabledSourceLangs.en == nil then
        WoWTranslateDB.enabledSourceLangs.en = false
    end

    -- Migration: new name/guild translation settings (v1.3+)
    if WoWTranslateDB.translatePlayerNames == nil then
        WoWTranslateDB.translatePlayerNames = false
    end
    if WoWTranslateDB.translateGuildNames == nil then
        WoWTranslateDB.translateGuildNames = false
    end
    if WoWTranslateDB.translateNameplates == nil then
        WoWTranslateDB.translateNameplates = false
    end
    if WoWTranslateDB.translateGroupFinder == nil then
        WoWTranslateDB.translateGroupFinder = false
    end
    if WoWTranslateDB.outgoingButtonPos == nil then
        WoWTranslateDB.outgoingButtonPos = { x = 100, y = 100 }
    end
    if WoWTranslateDB.showOutgoingButton == nil then
        WoWTranslateDB.showOutgoingButton = true
    end
end

function WT_OnAddonLoaded()
    if WT_addonLoaded then return end
    WT_addonLoaded = true

    WT_InitializeSettings()

    if WoWTranslate_MinimapButton_Init then
        pcall(WoWTranslate_MinimapButton_Init)
    end

    WT_HookTooltips()
    WT_CreateOutgoingButton()

    local dllOk = WoWTranslate_API.CheckDLL()

    local glossaryCount = WoWTranslate_GetGlossaryCount()
    local cacheCount = WoWTranslate_CacheStats().entries
    local dllStatus = dllOk and "|cFF00FF00DLL OK|r" or "|cFFFFFF00DLL not loaded|r"

    DEFAULT_CHAT_FRAME:AddMessage("|cFF00CCFFWoWTranslate|r v1.5 - " .. dllStatus .. " | /wt show")
end


-- ============================================================================
-- EVENT FRAME
-- ============================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_FLAGS_CHANGED")
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")

eventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "WoWTranslate" then
        WT_OnAddonLoaded()
    elseif event == "PLAYER_LOGIN" then
        WT_OnPlayerLogin()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Re-check DLL after any loading screen (zone in, /reload, etc.)
        if not WoWTranslate_API.IsAvailable() then
            WoWTranslate_API.CheckDLL()
        end
    elseif event == "PLAYER_FLAGS_CHANGED" and arg1 == "player" then
        if UnitIsAFK then
            WT_playerIsAFK = (UnitIsAFK("player") == 1) or (UnitIsAFK("player") == true)
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        if arg1 and string.find(arg1, "You are now AFK") then
            WT_playerIsAFK = true
        elseif arg1 and string.find(arg1, "You are no longer AFK") then
            WT_playerIsAFK = false
        end
    end
end)

local cleanupFrame = CreateFrame("Frame")
local cleanupElapsed = 0
cleanupFrame:SetScript("OnUpdate", function()
    cleanupElapsed = cleanupElapsed + arg1
    if cleanupElapsed >= 5 then
        cleanupElapsed = 0
        WT_CleanupPendingMessages()
        WT_CleanupOutgoingQueue()
    end
end)

-- Watchdog: WoW 1.12 replaces SetScript("OnEvent") handlers on chat frames when
-- certain events fire (channel join, zone change, UPDATE_CHAT_WINDOWS, etc.).
-- Re-install our wrappers every 60s so hooks stay active after such events.
-- pcall prevents a WT_HookChatFrames error from silently killing this OnUpdate.
local hookWatchdogElapsed = 0
local hookWatchdogFrame = CreateFrame("Frame")
hookWatchdogFrame:SetScript("OnUpdate", function()
    hookWatchdogElapsed = hookWatchdogElapsed + arg1
    if hookWatchdogElapsed >= 60 then
        hookWatchdogElapsed = 0
        pcall(WT_HookChatFrames, true)
    end
end)

