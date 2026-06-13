-- WoWTranslate_Hooks.lua

-- ============================================================================
-- CHAT FRAME HOOKING
-- ============================================================================


-- Maps event to ChatTypeInfo key so we can read the native channel color.
-- CHAT_MSG_CHANNEL requires special handling (channel slot number determines the key).
local EVENT_TO_CHATTYPE = {
    CHAT_MSG_SAY                 = "SAY",
    CHAT_MSG_YELL                = "YELL",
    CHAT_MSG_WHISPER             = "WHISPER",
    CHAT_MSG_WHISPER_INFORM      = "WHISPER",
    CHAT_MSG_PARTY               = "PARTY",
    CHAT_MSG_GUILD               = "GUILD",
    CHAT_MSG_OFFICER             = "OFFICER",
    CHAT_MSG_RAID                = "RAID",
    CHAT_MSG_RAID_LEADER         = "RAID",
    CHAT_MSG_RAID_WARNING        = "RAID",
    CHAT_MSG_BATTLEGROUND        = "BATTLEGROUND",
    CHAT_MSG_BATTLEGROUND_LEADER = "BATTLEGROUND",
    CHAT_MSG_HARDCORE            = "HARDCORE",
}

-- Returns a 6-char uppercase hex string from ChatTypeInfo, or nil if not found.
function WT_GetChatTypeColorHex(event, channelStr)
    local chatType = EVENT_TO_CHATTYPE[event]
    if not chatType and event == "CHAT_MSG_CHANNEL" then
        local _, _, cap = string.find(channelStr or "", "^(%d+)%.")
        local num = cap and tonumber(cap)
        chatType = num and ("CHANNEL" .. num) or "CHANNEL"
    end
    if chatType and ChatTypeInfo and ChatTypeInfo[chatType] then
        local info = ChatTypeInfo[chatType]
        local r = info.r or 1
        local g = info.g or 1
        local b = info.b or 1
        return string.format("%02X%02X%02X",
            math.floor(r * 255 + 0.5),
            math.floor(g * 255 + 0.5),
            math.floor(b * 255 + 0.5))
    end
    return nil
end

-- Per-event display tags for the [WT-X] prefix shown with each translation.
-- CHAT_MSG_CHANNEL is handled dynamically from arg4 (channel name string).
local EVENT_CHANNEL_TAGS = {
    CHAT_MSG_SAY                  = "WT-Say",
    CHAT_MSG_YELL                 = "WT-Yell",
    CHAT_MSG_WHISPER              = "WT-Whisper",
    CHAT_MSG_WHISPER_INFORM       = "WT-Whisper",
    CHAT_MSG_PARTY                = "WT-Party",
    CHAT_MSG_GUILD                = "WT-Guild",
    CHAT_MSG_OFFICER              = "WT-Officer",
    CHAT_MSG_RAID                 = "WT-Raid",
    CHAT_MSG_RAID_LEADER          = "WT-Raid",
    CHAT_MSG_RAID_WARNING         = "WT-Raid",
    CHAT_MSG_BATTLEGROUND         = "WT-BG",
    CHAT_MSG_BATTLEGROUND_LEADER  = "WT-BG",
    CHAT_MSG_HARDCORE             = "WT-Hardcore",
}

-- Returns the [WT-X] tag string for a given event.
-- For CHAT_MSG_CHANNEL, channelStr is arg4 (e.g. "2. Trade" or "World").
function WT_GetChannelTag(event, channelStr)
    local tag = EVENT_CHANNEL_TAGS[event]
    if tag then return tag end
    if event == "CHAT_MSG_CHANNEL" then
        if channelStr and channelStr ~= "" then
            -- Strip leading "N. " number prefix that WoW prepends to channel names
            local name = string.gsub(channelStr, "^%d+%.%s*", "")
            if name and name ~= "" then return "WT-" .. name end
        end
        return "WT-Channel"
    end
    return "WT"
end


-- ============================================================================
-- GROUP FINDER (LFT) TRANSLATION
-- ============================================================================

-- Translates the title and description of each visible LFT group entry.
-- Hooks LFT_UpdateGroupsList (post-render); requires LFT addon to be loaded.
-- Gated on WoWTranslateDB.translateGroupFinder.

local lftHooked = false

-- After async translation resolves, find the entry frame still displaying
-- the same group and update the text widget.
function WT_LFT_ApplyTranslation(entryId, isTitle, translated)
    for i = 1, 8 do
        local btn = _G["LFTFrameGroupEntry"..i]
        if btn and btn:IsShown() and btn.data and btn.data.id == entryId then
            local suffix = isTitle and "Text" or "SubText"
            local widget = _G["LFTFrameGroupEntry"..i..suffix]
            if widget then widget:SetText(translated) end
        end
    end
end

function WT_LFT_TranslateField(entryId, rawText, isTitle)
    if not rawText or rawText == "" then return end
    local detectedLang = WT_DetectSourceLanguage(rawText)
    if not detectedLang then return end

    -- Cache hit: instant, no API call needed
    local cached, found = WoWTranslate_CacheGet(rawText)
    if found then
        WT_LFT_ApplyTranslation(entryId, isTitle, cached)
        return
    end

    -- Exact glossary hit: full-text WoW slang match
    if WoWTranslate_CheckGlossaryExact then
        local glossaryResult = WoWTranslate_CheckGlossaryExact(rawText)
        if glossaryResult then
            WoWTranslate_CacheSave(rawText, glossaryResult)
            WT_LFT_ApplyTranslation(entryId, isTitle, glossaryResult)
            return
        end
    end

    -- Partial glossary preprocessing then API translation
    local textToTranslate = rawText
    if WoWTranslate_CheckGlossaryPartial then
        local partial = WoWTranslate_CheckGlossaryPartial(rawText)
        if partial then textToTranslate = partial end
    end

    if not WoWTranslate_API or not WoWTranslate_API.IsAvailable() then return end
    WoWTranslate_API.Translate(textToTranslate, function(translation, err)
        if translation and translation ~= "" then
            WoWTranslate_CacheSave(rawText, translation)
            WT_LFT_ApplyTranslation(entryId, isTitle, translation)
        end
    end, detectedLang)
end

function WT_LFT_ScanVisibleEntries()
    if not WoWTranslateDB or not WoWTranslateDB.translateGroupFinder then return end
    if not WoWTranslateDB.enabled then return end
    for i = 1, 8 do
        local btn = _G["LFTFrameGroupEntry"..i]
        if btn and btn:IsShown() and btn.data then
            local entry = btn.data
            WT_LFT_TranslateField(entry.id, entry.title, true)
            WT_LFT_TranslateField(entry.id, entry.description, false)
        end
    end
end

function WT_HookLFT()
    if lftHooked then return end
    if not LFT_UpdateGroupsList then return end
    local originalUpdate = LFT_UpdateGroupsList
    LFT_UpdateGroupsList = function()
        originalUpdate()
        WT_LFT_ScanVisibleEntries()
    end
    lftHooked = true
end


-- ============================================================================
function WT_HookGameTooltip()
    if not GameTooltip then return end
    if GameTooltip.WoWTranslateOrigSetUnit then
        GameTooltip.SetUnit = GameTooltip.WoWTranslateOrigSetUnit
    end
    if GameTooltip.WoWTranslateOrigSetHyperlink then
        GameTooltip.SetHyperlink = GameTooltip.WoWTranslateOrigSetHyperlink
    end
    if not GameTooltip.WoWTranslateOrigSetUnit then
        GameTooltip.WoWTranslateOrigSetUnit = GameTooltip.SetUnit
    end
    if GameTooltip.SetHyperlink and not GameTooltip.WoWTranslateOrigSetHyperlink then
        GameTooltip.WoWTranslateOrigSetHyperlink = GameTooltip.SetHyperlink
    end
    GameTooltip.WoWTranslateTooltipHooked = true
    local origSetUnit = GameTooltip.WoWTranslateOrigSetUnit
    function GameTooltip:SetUnit(unit)
        WT_ClearTooltipNameHeader(GameTooltip)
        GameTooltip.wtUnit = unit
        GameTooltip.wtPlayerName = nil
        GameTooltip.wtNameResolvePending = nil
        if unit and UnitExists(unit) and UnitIsPlayer(unit) then
            GameTooltip.wtPlayerName = UnitName(unit)
        end
        if origSetUnit then return origSetUnit(self, unit) end
    end
    if GameTooltip.WoWTranslateOrigSetHyperlink then
        local origSetHyperlink = GameTooltip.WoWTranslateOrigSetHyperlink
        function GameTooltip:SetHyperlink(link)
            WT_ClearTooltipNameHeader(GameTooltip)
            GameTooltip.wtUnit = nil
            GameTooltip.wtPlayerName = WT_ParsePlayerHyperlink(link)
            GameTooltip.wtNameResolvePending = nil
            if origSetHyperlink then return origSetHyperlink(self, link) end
        end
    end
    if not wtTooltipFrame then wtTooltipFrame = getglobal("WoWTranslateTooltipFrame") end
    if not wtTooltipFrame then
        wtTooltipFrame = CreateFrame("Frame", "WoWTranslateTooltipFrame", GameTooltip)
        local function DeferUpdateGameTooltip()
            if not WT_TooltipIsShown(GameTooltip) then return end
            if GameTooltip.wtAddedNameLine or GameTooltip.wtNameResolvePending then return end
            WT_UpdateTooltipPlayerNames(GameTooltip)
        end
        local function ArmTooltipDefer()
            wtTooltipFrame.elapsed = 0
            wtTooltipFrame:SetScript("OnUpdate", function()
                if not WT_TooltipIsShown(GameTooltip) then
                    wtTooltipFrame.elapsed = 0
                    wtTooltipFrame:SetScript("OnUpdate", nil)
                    return
                end
                if GameTooltip.wtAddedNameLine or GameTooltip.wtNameResolvePending then
                    wtTooltipFrame:SetScript("OnUpdate", nil)
                    return
                end
                wtTooltipFrame.elapsed = wtTooltipFrame.elapsed + arg1
                if wtTooltipFrame.elapsed < 0.4 then return end
                wtTooltipFrame:SetScript("OnUpdate", nil)
                DeferUpdateGameTooltip()
            end)
        end
        wtTooltipFrame:SetScript("OnShow", function() ArmTooltipDefer() end)
        if not GameTooltip.WoWTranslateOrigOnHide then
            GameTooltip.WoWTranslateOrigOnHide = GameTooltip:GetScript("OnHide")
        end
        local origOnHide = GameTooltip.WoWTranslateOrigOnHide
        GameTooltip:SetScript("OnHide", function()
            WT_ClearTooltipNameHeader(GameTooltip)
            GameTooltip.wtUnit = nil
            GameTooltip.wtPlayerName = nil
            GameTooltip.wtNameResolvePending = nil
            if origOnHide then origOnHide() end
        end)
    end
end

function WT_HookItemRefTooltip()
    if not ItemRefTooltip then return end
    if ItemRefTooltip.WoWTranslateOrigSetHyperlink then
        ItemRefTooltip.SetHyperlink = ItemRefTooltip.WoWTranslateOrigSetHyperlink
    end
    if ItemRefTooltip.SetHyperlink and not ItemRefTooltip.WoWTranslateOrigSetHyperlink then
        ItemRefTooltip.WoWTranslateOrigSetHyperlink = ItemRefTooltip.SetHyperlink
    end
    ItemRefTooltip.WoWTranslateTooltipHooked = true
    if ItemRefTooltip.WoWTranslateOrigSetHyperlink then
        local origSetHyperlink = ItemRefTooltip.WoWTranslateOrigSetHyperlink
        function ItemRefTooltip:SetHyperlink(link)
            WT_ClearTooltipNameHeader(ItemRefTooltip)
            ItemRefTooltip.wtUnit = nil
            ItemRefTooltip.wtPlayerName = WT_ParsePlayerHyperlink(link)
            ItemRefTooltip.wtNameResolvePending = nil
            if origSetHyperlink then return origSetHyperlink(self, link) end
        end
    end
    local refFrame = getglobal("WoWTranslateItemRefTooltipFrame")
    if not refFrame then
        refFrame = CreateFrame("Frame", "WoWTranslateItemRefTooltipFrame", ItemRefTooltip)
        refFrame:SetScript("OnShow", function()
            refFrame.elapsed = 0
            refFrame:SetScript("OnUpdate", function()
                if not WT_TooltipIsShown(ItemRefTooltip) then
                    refFrame:SetScript("OnUpdate", nil); return
                end
                if ItemRefTooltip.wtAddedNameLine or ItemRefTooltip.wtNameResolvePending then
                    refFrame:SetScript("OnUpdate", nil); return
                end
                refFrame.elapsed = refFrame.elapsed + arg1
                if refFrame.elapsed < 0.25 then return end
                refFrame:SetScript("OnUpdate", nil)
                WT_UpdateTooltipPlayerNames(ItemRefTooltip)
            end)
        end)
        if not ItemRefTooltip.WoWTranslateOrigOnHide then
            ItemRefTooltip.WoWTranslateOrigOnHide = ItemRefTooltip:GetScript("OnHide")
        end
        local refOrigOnHide = ItemRefTooltip.WoWTranslateOrigOnHide
        ItemRefTooltip:SetScript("OnHide", function()
            WT_ClearTooltipNameHeader(ItemRefTooltip)
            ItemRefTooltip.wtPlayerName = nil
            ItemRefTooltip.wtNameResolvePending = nil
            if refOrigOnHide then refOrigOnHide() end
        end)
    end
end

function WT_HookTooltips()
    WT_HookGameTooltip()
    WT_HookItemRefTooltip()
    WT_HookNameplates()
end


-- ============================================================================
-- OUTGOING TOGGLE BUTTON
-- ============================================================================

local outgoingButton = nil

function WT_UpdateOutgoingButton()
    if not outgoingButton then return end
    if WoWTranslateDB and WoWTranslateDB.outgoingEnabled then
        outgoingButton:SetText("|cFF00FF00OUT:ON|r")
    else
        outgoingButton:SetText("|cFFFF4444OUT:OFF|r")
    end
end

function WT_CreateOutgoingButton()
    if outgoingButton then return end
    local f = CreateFrame("Button", "WoWTranslateOutgoingButton", UIParent)
    outgoingButton = f
    f:SetWidth(48)
    f:SetHeight(15)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "",
        tile = true, tileSize = 8, edgeSize = 0,
        insets = { left=0, right=0, top=0, bottom=0 },
    })
    f:SetBackdropColor(0, 0, 0, 0.7)

    local pos = WoWTranslateDB and WoWTranslateDB.outgoingButtonPos or { x=100, y=100 }
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetAllPoints(f)
    f.label = label

    f:SetScript("OnMouseDown", function()
        -- Toggle on click release (OnMouseUp handles it); just visual feedback.
    end)
    f:SetScript("OnMouseUp", function()
        if arg1 == "LeftButton" then
            local nowEnabled = not (WoWTranslateDB and WoWTranslateDB.outgoingEnabled)
            WoWTranslate_SetOutgoingEnabled(nowEnabled)
        end
    end)
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local x = f:GetLeft()
        local y = f:GetBottom()
        if WoWTranslateDB then
            WoWTranslateDB.outgoingButtonPos = { x = x, y = y }
        end
    end)

    -- Expose SetText on the frame so WT_UpdateOutgoingButton works cleanly.
    function f:SetText(text) self.label:SetText(text) end

    if WoWTranslateDB and WoWTranslateDB.showOutgoingButton == false then
        f:Hide()
    else
        f:Show()
    end
    WT_UpdateOutgoingButton()
end

function WT_ApplyOutgoingButtonVisibility()
    if not outgoingButton then return end
    if WoWTranslateDB and WoWTranslateDB.showOutgoingButton == false then
        outgoingButton:Hide()
    else
        outgoingButton:Show()
    end
end

-- ============================================================================
function WT_SafeAddMessage(func, self, text, r, g, b, id, holdTime)
    if holdTime ~= nil then return func(self, text, r, g, b, id, holdTime)
    elseif id ~= nil then return func(self, text, r, g, b, id)
    elseif b ~= nil then return func(self, text, r, g, b)
    elseif g ~= nil then return func(self, text, r, g)
    elseif r ~= nil then return func(self, text, r)
    else return func(self, text)
    end
end

-- force=true clears WoWTranslateHooked so all frames are re-hooked (used by /wt reset).
-- origScript is saved on the frame so re-hooking always wraps the real WoW handler,
-- never a previously-installed WoWTranslate wrapper (no double-wrapping).
function WT_HookChatFrames(force)
    if not WT_originalAddMessage and DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        WT_originalAddMessage = DEFAULT_CHAT_FRAME.AddMessage
    end

    for i = 1, NUM_CHAT_WINDOWS do
        local frameName = "ChatFrame" .. i
        local frame = getglobal(frameName)

        if frame then
            if force then frame.WoWTranslateHooked = false end

            if not frame.WoWTranslateHooked then
                -- On re-hook use the saved original so we never wrap our own wrapper
                local origScript = frame.WoWTranslate_OrigScript or frame:GetScript("OnEvent")
                if not origScript then
                    WT_DebugLog("No OnEvent script on", frameName)
                else
                    frame.WoWTranslate_OrigScript = origScript  -- persist for safe re-hook
                    frame.WoWTranslateHooked = true

                    frame:SetScript("OnEvent", function()
                        WT_hookCallCount = WT_hookCallCount + 1

                        -- Capture event globals before origScript may clobber them
                        local capturedEvent = event
                        local capturedArg1  = arg1
                        local capturedArg2  = arg2
                        local capturedArg4  = arg4  -- channel name string for CHAT_MSG_CHANNEL
                        local capturedThis  = this

                        -- Wrap in pcall: an unhandled Lua error in a SetScript handler
                        -- silently disables it in WoW 1.12. Capture the error for debug.
                        local _ok, _err = pcall(function()
                            -- Let WoW's own filter decide: if origScript didn't add a message
                            -- to this frame (filtered out), don't add a translation either.
							-- Primary: shadow AddMessage on the frame instance to detect the call
							-- directly — this works even when the ring-buffer is full (128 msgs),
							-- where GetNumMessages() alone cannot distinguish "shown" from "filtered".
							-- Fallback: if the shadow was never triggered (e.g. WoW build ignores
 							-- instance-table shadows for built-in methods), use GetNumMessages with
							-- the pre-fix < 128 heuristic so we degrade gracefully.
                            local msgsBefore = capturedThis:GetNumMessages()
                            local messageShownInFrame = false
                            local origFrameAddMsg = capturedThis.AddMessage
                            -- replaceMode: args from the intercepted AddMessage call; nil = not captured.
                            local pendingArgs = nil

                            capturedThis.AddMessage = function(f, a, b, c, d, e, g)
                                messageShownInFrame = true
                                capturedThis.AddMessage = origFrameAddMsg
                                if WoWTranslateDB and WoWTranslateDB.replaceMode then
                                    -- Suppress the original; hold args so we can show the original
                                    -- on early-exit paths or show the translation on success.
                                    pendingArgs = {f=f, a=a, b=b, c=c, d=d, e=e, g=g}
                                else
                                    WT_SafeAddMessage(origFrameAddMsg, f, a, b, c, d, e, g)
                                end
                            end

                            -- Shows the original message if it was suppressed and translation
                            -- was not produced (early exit, DLL error, etc.).
                            local function FlushOriginal()
                                if pendingArgs then
                                    WT_SafeAddMessage(origFrameAddMsg, pendingArgs.f, pendingArgs.a, pendingArgs.b,
                                                    pendingArgs.c, pendingArgs.d, pendingArgs.e,
                                                    pendingArgs.g)
                                    pendingArgs = nil
                                end
                            end

                            local origOk, origErr = pcall(origScript)
							
                            -- Always restore; never leave our wrapper or a nil in place.
                            capturedThis.AddMessage = origFrameAddMsg

                            if not origOk then
                                WT_DebugLog("origScript error:", tostring(origErr))
                                FlushOriginal(); return
                            end

                            -- WIM: when WIM suppresses a whisper from chat frames, we post
                            -- the translation directly to the WIM window instead.
                            local wimWhisperUser = nil

                            if not messageShownInFrame then
                                -- WIM compatibility: WIM suppresses whispers from standard chat frames
                                -- (supressWisps=true is WIM's default). Detect this and route the
                                -- translation to the WIM window instead of a chat frame AddMessage.
                                if (capturedEvent == "CHAT_MSG_WHISPER" or capturedEvent == "CHAT_MSG_WHISPER_INFORM") and
                                   type(WIM_Data) == "table" and WIM_Data.enableWIM and
                                   WIM_Data.supressWisps ~= false and
                                   type(WIM_PostMessage) == "function" and
                                   capturedArg2 and capturedArg2 ~= "" then
                                    wimWhisperUser = capturedArg2
                                else
                                    -- Shadow either worked (message filtered) or wasn't triggered.
                                    -- Use GetNumMessages as fallback — ambiguous only at 128.
                                    local msgsAfter = capturedThis:GetNumMessages()
                                    if msgsAfter < msgsBefore
                                        or (msgsAfter == msgsBefore and msgsBefore < 128)then
                                        FlushOriginal(); return
                                    end
                                end
                            end

                            if not WoWTranslateDB or not WoWTranslateDB.enabled then FlushOriginal(); return end
                            if WoWTranslateDB.disableWhileAfk and WT_playerIsAFK then FlushOriginal(); return end

                            local channel  = WT_EVENT_TO_CHANNEL[capturedEvent]
                            local isSystem = WT_SYSTEM_EVENTS[capturedEvent]
                            if not channel and not isSystem then FlushOriginal(); return end
                            if isSystem and not WoWTranslateDB.translateSystemMessages then FlushOriginal(); return end

                            if channel then
                                local inChannels = WoWTranslateDB.incomingChannels
                                local effectiveChannel = channel
                                if channel == "CHANNEL" and capturedArg4 then
                                    local chanName = string.gsub(capturedArg4, "^%d+%.%s*", "")
                                    local lowerChan = string.lower(chanName)
                                    if string.find(lowerChan, "^english") then
                                        effectiveChannel = "ENGLISH"
                                    elseif lowerChan == "lft" or lowerChan == "vqueue" or string.find(lowerChan, "^pfquest") or lowerChan == "xtensionxtooltip2" then
                                        -- Ignore known addon sync channels
                                        FlushOriginal(); return
                                    end
                                end
                                if inChannels and not inChannels[effectiveChannel] then FlushOriginal(); return end
                            end

                            if not capturedArg1 or capturedArg1 == "" then FlushOriginal(); return end
                            if string.sub(capturedArg1, 1, 1) == "#" then FlushOriginal(); return end
                            -- Ignore addon communication protocols
                            if string.find(capturedArg1, "^Meeting:[CR]:") or 
                               string.find(capturedArg1, "^BGTBL,") or
                               string.find(capturedArg1, "^Atlas: Version:") or
                               string.find(capturedArg1, "^Bath:V:") or
                               string.find(capturedArg1, "%[Translated by chat translator addon%] Session:") or
                               string.find(capturedArg1, "^Session: V: ") then
                                FlushOriginal(); return
                            end
                            -- Strip any WoWTranslate prefix that another addon user prepended.
                            -- All prefix variants are [... WoWTranslate ...] — strip up to the
                            -- closing ] so the body is still translated normally.
                            do
                                local p = string.find(capturedArg1, "WoWTranslate", 1, true)
                                if p and p <= 50 then
                                    local closeBracket = string.find(capturedArg1, "]", p, true)
                                    if closeBracket then
                                        local stripped = string.gsub(string.sub(capturedArg1, closeBracket + 1), "^%s+", "")
                                        if stripped ~= "" then capturedArg1 = stripped end
                                    end
                                end
                            end

                            local detectedLang = WT_DetectSourceLanguage(capturedArg1)
                            WT_DebugLog("Event:", capturedEvent, "lang=", tostring(detectedLang), "msg=", string.sub(capturedArg1, 1, 30))
                            if not detectedLang then FlushOriginal(); return end
                            -- Skip no-op translations (e.g. zh→zh when Chinese player sets target=zh).
                            -- Without this, the ZH→EN glossary fires on Chinese text, inserts English,
                            -- and the result is shown in English or sent to the DLL as zh→zh garbage.
                            local incomingTargetLang = (WoWTranslateDB and WoWTranslateDB.incomingToLang) or "en"
                            if detectedLang == incomingTargetLang then FlushOriginal(); return end

                            -- Resolved name/guild; set by ResolveNamesAndPost before BuildWTMsg.
                            -- Default to rawName so WT_BuildSenderPrefix matches old behavior when
                            -- translatePlayerNames/translateGuildNames are both off.
                            local resolvedSenderName = capturedArg2
                            local resolvedGuildName  = nil

                            local channelTag   = WT_GetChannelTag(capturedEvent, capturedArg4)
                            local msgColor     = (WoWTranslateDB and WoWTranslateDB.translationColor) or ""
                            local chanColorHex = WT_GetChatTypeColorHex(capturedEvent, capturedArg4)
                            -- Channel name part of the tag (everything after "WT-"), or nil for bare "WT".
                            local chanNamePart = string.sub(channelTag, 1, 3) == "WT-" and string.sub(channelTag, 4) or nil

                            -- (wimWhisperUser declaration moved up)

                            local function BuildWTMsg(body)
                                -- Prefix: [WT- in cyan, channel name in the native channel color.
                                local prefix
                                if chanColorHex and chanNamePart then
                                    prefix = "|cFF00FFFF[WT-|r|cFF" .. chanColorHex .. chanNamePart .. "]|r"
                                else
                                    prefix = "|cFF00FFFF[" .. channelTag .. "]|r"
                                end
                                -- Body: use channel color when "follow" is on, else custom or default.
                                local bodyHex = msgColor
                                if WoWTranslateDB and WoWTranslateDB.translationColorFollow then
                                    bodyHex = chanColorHex or ""
                                end
                                local displayBody = bodyHex ~= "" and ("|cFF" .. bodyHex .. body .. "|r") or body
                                local sp = WT_BuildSenderPrefix(capturedArg2, resolvedSenderName, channel, resolvedGuildName)
                                return prefix .. " " .. sp .. displayBody
                            end

                            -- Resolves player display name (async when translatePlayerNames is on,
                            -- synchronous no-op when off), then calls postFn with the built WTMsg.
                            -- Guild translation is tooltip-only; chat lines never show guild.
                            local function ResolveNamesAndPost(body, postFn)
                                WT_ResolvePlayerDisplayName(capturedArg2, function(dName)
                                    resolvedSenderName = dName
                                    resolvedGuildName  = nil
                                    postFn(BuildWTMsg(body))
                                end)
                            end

                            local function PostWTMsg(wtMsg)
                                if wimWhisperUser and type(WIM_PostMessage) == "function" then
                                    WIM_PostMessage(wimWhisperUser, wtMsg, 3)
                                else
                                    capturedThis:AddMessage(wtMsg)
                                end
                            end

                            -- Split into text and hyperlink segments.
                            -- Chinese bytes in link display names (e.g. [剑]) are NOT
                            -- translatable plain text — WT_HasTranslatableContent checks only
                            -- text segments. Pure-link messages are skipped here, which
                            -- also prevents the raw | pipe codes from breaking DLL parsing.
                            local segments = WT_SplitIntoSegments(capturedArg1)
                            if not WT_HasTranslatableContent(segments) then FlushOriginal(); return end

                            -- Build text with hyperlinks as URL placeholders so the DLL
                            -- never sees WoW pipe-codes in the text it sends to Google.
                            local plainText = WT_BuildTranslatableText(segments)

                            -- Register this frame as a recipient for the translation of
                            -- this message.  WoW fires each chat frame's OnEvent in turn
                            -- for the same message, so capturedThis differs per iteration.
                            -- Dedup lets only the first frame reach the DLL; we collect all
                            -- frames here so the async callback posts to every relevant tab.
                            -- Only register when the AddMessage interception confirmed the
                            -- original message actually appeared in this frame.  Frames that
                            -- filtered the message (channel disabled, tab not showing it)
                            -- must not receive the translation either.
                            if not wimWhisperUser then
                                if not WT_frameTranslationTargets[capturedArg1] then
                                    WT_frameTranslationTargets[capturedArg1] = {}
                                end
                                WT_frameTranslationTargets[capturedArg1][capturedThis] = true
                            end

                            local cached, found = WoWTranslate_CacheGet(capturedArg1)
                            if found then
                                WT_DebugLog("Cache hit")
                                local reconstructed = WT_ReconstructMessage(segments, cached)
                                WT_frameTranslationTargets[capturedArg1] = nil
                                ResolveNamesAndPost(reconstructed, PostWTMsg)
                                return
                            end

                            local textToTranslate = plainText
                            if detectedLang == "en" then
                                -- English source: apply EN→ZH outgoing glossary
                                if WoWTranslate_CheckOutGlossaryExact then
                                    local r = WoWTranslate_CheckOutGlossaryExact(plainText)
                                    if r then
                                        WT_DebugLog("Outgoing glossary exact (incoming EN):", r)
                                        WoWTranslate_CacheSave(capturedArg1, r)
                                        WT_frameTranslationTargets[capturedArg1] = nil
                                        ResolveNamesAndPost(WT_ReconstructMessage(segments, r), PostWTMsg)
                                        return
                                    end
                                end
                                if WoWTranslate_CheckOutGlossaryPartial then
                                    local r = WoWTranslate_CheckOutGlossaryPartial(plainText)
                                    if r then
                                        WT_DebugLog("Outgoing glossary partial (incoming EN):", r)
                                        textToTranslate = r
                                    end
                                end
                            else
                                -- Preprocess: currency (XG = gold, XY = silver), 88 = bye, 110 = patrol
                                plainText = WT_PreprocessIncoming(plainText)
                                textToTranslate = plainText
                                -- CJK/Russian source: apply ZH→EN incoming glossary
                                local glossaryResult = WoWTranslate_CheckGlossaryExact(plainText)
                                if glossaryResult then
                                    WT_DebugLog("Glossary exact:", glossaryResult)
                                    WoWTranslate_CacheSave(capturedArg1, glossaryResult)
                                    WT_frameTranslationTargets[capturedArg1] = nil
                                    ResolveNamesAndPost(WT_ReconstructMessage(segments, glossaryResult), PostWTMsg)
                                    return
                                end
                                local partialResult = WoWTranslate_CheckGlossaryPartial(plainText)
                                if partialResult then
                                    if not WT_DetectSourceLanguage(partialResult) then
                                        WT_DebugLog("Glossary full partial:", partialResult)
                                        WoWTranslate_CacheSave(capturedArg1, partialResult)
                                        WT_frameTranslationTargets[capturedArg1] = nil
                                        ResolveNamesAndPost(WT_ReconstructMessage(segments, partialResult), PostWTMsg)
                                        return
                                    end
                                    textToTranslate = partialResult
                                    WT_DebugLog("Glossary pre-processed, sending to API")
                                end
                            end

                            if not WoWTranslate_API or not WoWTranslate_API.IsAvailable() then
                                if not WT_dllWarnShown then
                                    WT_dllWarnShown = true
                                    capturedThis:AddMessage("|cFFFFFF00[WoWTranslate] DLL not connected - run /wt status|r")
                                end
                                FlushOriginal(); return
                            end

                            -- replaceMode: capture original args before the API call, but only
                            -- register the 30s safety-net entry for frames whose callback will
                            -- actually fire. WoW fires every chat frame's OnEvent for the same
                            -- message; the API deduplicates (returns false for frames 2-N).
                            -- Those frames get the translation via WT_frameTranslationTargets.
                            -- Storing a safety-net entry for deduplicated frames causes the
                            -- original to reappear 30s later even when translation succeeded.
                            local replacePendingKey = nil
                            local replacePendingData = nil
                            if pendingArgs then
                                replacePendingData = {
                                    WT_originalAddMessage = origFrameAddMsg,
                                    frame              = pendingArgs.f,
                                    originalText       = pendingArgs.a,
                                    r = pendingArgs.b, g = pendingArgs.c, b = pendingArgs.d,
                                    id = pendingArgs.e, holdTime = pendingArgs.g,
                                }
                                pendingArgs = nil
                            end

                            -- Safe UTF-8 Truncation to avoid DLL buffer overflow (approx ~20-25 Chinese characters max).
                            -- 75 bytes URL-encoded is safe for a 256-byte DLL limit.
                            local function SafeUTF8Truncate(str, maxBytes)
                                if string.len(str) <= maxBytes then return str end
                                local bytePos = maxBytes
                                while bytePos > 0 and string.byte(str, bytePos) >= 128 and string.byte(str, bytePos) <= 191 do
                                    bytePos = bytePos - 1
                                end
                                return string.sub(str, 1, bytePos - 1)
                            end
                            textToTranslate = SafeUTF8Truncate(textToTranslate, 75)

                            local apiQueued = WoWTranslate_API.Translate(textToTranslate, function(translation, err)
                                if translation and translation ~= "" then
                                    WT_DebugLog("Translation:", string.sub(translation, 1, 50))
                                    WT_translationErrWarnShown = false
                                    WoWTranslate_CacheSave(capturedArg1, translation)
                                    local reconstructed = WT_ReconstructMessage(segments, translation)
                                    -- replaceMode: original was suppressed; clear safety net entry.
                                    if replacePendingKey then
                                        WT_pendingMessages[replacePendingKey] = nil
                                    end
                                    -- Post to every frame that displayed the original message.
                                    -- Capture targets before async name resolution so the table
                                    -- is not modified by concurrent messages.
                                    local targets = WT_frameTranslationTargets[capturedArg1]
                                    WT_frameTranslationTargets[capturedArg1] = nil
                                    ResolveNamesAndPost(reconstructed, function(wtMsg)
                                        if wimWhisperUser and type(WIM_PostMessage) == "function" then
                                            WIM_PostMessage(wimWhisperUser, wtMsg, 3)
                                        elseif targets then
                                            for targetFrame in pairs(targets) do
                                                targetFrame:AddMessage(wtMsg)
                                            end
                                        else
                                            DEFAULT_CHAT_FRAME:AddMessage(wtMsg)
                                        end
                                    end)
                                else
                                    WT_DebugLog("Translation error:", tostring(err))
                                    WT_frameTranslationTargets[capturedArg1] = nil
                                    -- replaceMode: translation failed — show original immediately.
                                    if replacePendingKey then
                                        local rp = WT_pendingMessages[replacePendingKey]
                                        if rp then
                                            WT_pendingMessages[replacePendingKey] = nil
                                            WT_SafeAddMessage(rp.WT_originalAddMessage, rp.frame, rp.originalText,
                                                rp.r, rp.g, rp.b, rp.id, rp.holdTime)
                                        end
                                    end
                                    if not WT_translationErrWarnShown then
                                        WT_translationErrWarnShown = true
                                        capturedThis:AddMessage("|cFFFFFF00[WoWTranslate] Translation failing (" .. tostring(err) .. ") - try /wt reset|r")
                                    end
                                end
                            end, detectedLang)
                            -- Only store the safety-net entry when this frame's callback will
                            -- fire (apiQueued=true). Deduplicated frames (false) will receive
                            -- the translation via WT_frameTranslationTargets when the first frame's
                            -- callback fires, so their suppressed original can be discarded.
                            if apiQueued and replacePendingData then
                                replacePendingKey = "r|" .. tostring(capturedThis) .. "|" .. capturedArg1
                                replacePendingData.timestamp = GetTime()
                                WT_pendingMessages[replacePendingKey] = replacePendingData
                            end
                        end)  -- end pcall
                        if not _ok then WT_DebugLog("OnEvent hook error:", tostring(_err)) end
                    end)

                    WT_DebugLog("Hooked", frameName, "via SetScript")
                end
            end

        end
    end
end

function WT_CleanupPendingMessages()
    local now = GetTime()
    for msgId, pending in pairs(WT_pendingMessages) do
        if now - pending.timestamp > 30 then
            WT_DebugLog("Message timed out:", msgId)
            WT_SafeAddMessage(pending.WT_originalAddMessage, pending.frame, pending.originalText, pending.r, pending.g, pending.b, pending.id, pending.holdTime)
            WT_pendingMessages[msgId] = nil
        end
    end
end


-- ============================================================================
-- OUTGOING TRANSLATION (English -> Chinese)
-- ============================================================================


function WT_SafeSendChatMessage(msg, chatType, language, channel)
    if channel ~= nil then
        return WT_originalSendChatMessage(msg, chatType, language, channel)
    elseif language ~= nil then
        return WT_originalSendChatMessage(msg, chatType, language)
    elseif chatType ~= nil then
        return WT_originalSendChatMessage(msg, chatType)
    else
        return WT_originalSendChatMessage(msg)
    end
end

-- Clean up queued outgoing messages after timeout
function WT_CleanupOutgoingQueue()
    local now = GetTime()
    for queueId, item in pairs(WT_outgoingQueue) do
        if now - item.timestamp > 30 then
            WT_DebugLog("Outgoing message timed out:", queueId)
            if WT_originalAddMessage then
                WT_SafeAddMessage(WT_originalAddMessage, DEFAULT_CHAT_FRAME, "|cFFFF0000[WoWTranslate] Translation timed out, sending original|r")
            end
            WT_SafeSendChatMessage(item.originalMsg, item.chatType, item.language, item.channel)
            WT_outgoingQueue[queueId] = nil
        end
    end
end

-- Hooked SendChatMessage for outgoing translation
function WT_HookedSendChatMessage(msg, chatType, language, channel)
    -- Handle nil chatType (WoW 1.12 compatibility)
    if not chatType then
        WT_DebugLog("chatType is nil, sending original")
        return WT_SafeSendChatMessage(msg, chatType, language, channel)
    end

    -- Skip if outgoing disabled
    if not WoWTranslateDB or not WoWTranslateDB.outgoingEnabled then
        return WT_SafeSendChatMessage(msg, chatType, language, channel)
    end

    -- Skip translation while AFK
    if WoWTranslateDB.disableWhileAfk and WT_playerIsAFK then
        return WT_SafeSendChatMessage(msg, chatType, language, channel)
    end

    -- Skip if channel not enabled
    if not WoWTranslateDB.outgoingChannels then
        WT_DebugLog("Channel not enabled for outgoing:", chatType)
        return WT_SafeSendChatMessage(msg, chatType, language, channel)
    end
    local effectiveOutChannel = chatType
    if chatType == "CHANNEL" and channel then
        -- GetChannelName(number) does not reliably return the name in WoW 1.12;
        -- iterate GetChannelList() instead (returns id, name, id, name, ...).
        local list = {GetChannelList()}
        for i = 1, table.getn(list), 2 do
            if list[i] == channel then
                if string.find(string.lower(list[i+1] or ""), "^english") then
                    effectiveOutChannel = "ENGLISH"
                end
                break
            end
        end
    end
    if not WoWTranslateDB.outgoingChannels[effectiveOutChannel] then
        WT_DebugLog("Channel not enabled for outgoing:", effectiveOutChannel)
        return WT_SafeSendChatMessage(msg, chatType, language, channel)
    end

    -- Skip empty messages
    if not msg or msg == "" then
        return WT_SafeSendChatMessage(msg, chatType, language, channel)
    end

    -- Skip macro directives (#showtooltip, #show, etc.)
    if string.sub(msg, 1, 1) == "#" then
        return WT_SafeSendChatMessage(msg, chatType, language, channel)
    end

    -- Skip dot-commands sent by addons (e.g. .server info from PizzaWorldBuffs)
    if string.sub(msg, 1, 1) == "." then
        return WT_SafeSendChatMessage(msg, chatType, language, channel)
    end

    -- Skip addon inter-communication messages (PizzaWorldBuffs, Atlas-CFM, etc.)
    -- These follow the format: ADDONNAME:VERSION:DATA
    if string.find(msg, "^[A-Za-z][A-Za-z0-9_]*:%d+:") then
        return WT_SafeSendChatMessage(msg, chatType, language, channel)
    end

    -- Skip if already contains target language (don't double-translate)
    if WT_ContainsOutgoingTargetLanguage(msg) then
        WT_DebugLog("Message already contains target language, skipping outgoing translation")
        return WT_SafeSendChatMessage(msg, chatType, language, channel)
    end

    -- Skip if DLL not available
    if not WoWTranslate_API or not WoWTranslate_API.IsAvailable() then
        WT_DebugLog("DLL not available for outgoing translation")
        return WT_SafeSendChatMessage(msg, chatType, language, channel)
    end

    -- Split message into segments (text and hyperlinks) to preserve links
    local segments = WT_SplitIntoSegments(msg)
    WT_DebugLog("Outgoing segments:", table.getn(segments))

    -- Build text to translate (hyperlinks replaced with URL placeholders)
    local textToTranslate = WT_BuildTranslatableText(segments)
    WT_DebugLog("Outgoing to translate:", textToTranslate)

    -- Apply the glossary that matches the outgoing source language direction.
    local outFromLang = WoWTranslateDB.outgoingFromLang or "en"
    if outFromLang == "en" then
        -- Convert EN currency notation to CN before glossary/API (Xg→XG, Xs→XY)
        textToTranslate = WT_PreprocessOutgoing(textToTranslate)
        -- EN→ZH: apply EN→ZH outgoing glossary
        if WoWTranslate_CheckOutGlossaryExact then
            local glossaryResult = WoWTranslate_CheckOutGlossaryExact(textToTranslate)
            if not glossaryResult and WoWTranslate_CheckOutGlossaryPartial then
                glossaryResult = WoWTranslate_CheckOutGlossaryPartial(textToTranslate)
            end
            if glossaryResult then
                WT_DebugLog("Outgoing glossary (EN→ZH) applied:", glossaryResult)
                textToTranslate = glossaryResult
            end
        end
    else
        -- ZH→EN (or other non-English source): apply ZH→EN incoming glossary
        if WoWTranslate_CheckGlossaryExact then
            local glossaryResult = WoWTranslate_CheckGlossaryExact(textToTranslate)
            if not glossaryResult and WoWTranslate_CheckGlossaryPartial then
                glossaryResult = WoWTranslate_CheckGlossaryPartial(textToTranslate)
            end
            if glossaryResult then
                WT_DebugLog("Outgoing glossary (ZH→EN) applied:", glossaryResult)
                textToTranslate = glossaryResult
            end
        end
    end

    -- Queue for translation
    WT_outgoingCounter = WT_outgoingCounter + 1
    local queueId = tostring(WT_outgoingCounter)

    WT_outgoingQueue[queueId] = {
        originalMsg = msg,
        segments = segments,  -- Store segments for reconstruction
        chatType = chatType,
        language = language,
        channel = channel,
        timestamp = GetTime()
    }

    -- Show local feedback
    if WT_originalAddMessage then
        WT_SafeAddMessage(WT_originalAddMessage, DEFAULT_CHAT_FRAME, "|cFFFFFF00[WoWTranslate] Translating...|r")
    end

    WT_DebugLog("Outgoing queued:", queueId, msg)

    -- Request translation (send only the text portions, not hyperlinks)
    WoWTranslate_API.TranslateOutgoing(textToTranslate, function(translation, err)
        local queued = WT_outgoingQueue[queueId]
        if not queued then
            WT_DebugLog("Outgoing callback but queue item gone:", queueId)
            return
        end
        WT_outgoingQueue[queueId] = nil

        if translation then
            WT_DebugLog("Outgoing translation received:", translation)

            -- Reconstruct message with original hyperlinks
            local reconstructed = WT_ReconstructMessage(queued.segments, translation)
            WT_DebugLog("Outgoing reconstructed:", reconstructed)

            -- Build message, optionally prepending the prefix
            local finalMsg
            if WoWTranslateDB.outgoingPrefixEnabled then
                local userPrefix = WoWTranslateDB.outgoingPrefix or WT_DEFAULT_PREFIX
                local prefix
                if userPrefix == WT_DEFAULT_PREFIX then
                    local targetLang = WoWTranslateDB.outgoingToLang or "zh"
                    prefix = WT_TRANSLATED_PREFIXES[targetLang] or userPrefix
                else
                    prefix = userPrefix
                end
                finalMsg = prefix .. " " .. reconstructed
            else
                finalMsg = reconstructed
            end

            -- Truncate if over 255 bytes (WoW chat limit)
            if string.len(finalMsg) > 255 then
                finalMsg = string.sub(finalMsg, 1, 252) .. "..."
            end

            WT_SafeSendChatMessage(finalMsg, queued.chatType, queued.language, queued.channel)

            if WT_originalAddMessage then
                WT_SafeAddMessage(WT_originalAddMessage, DEFAULT_CHAT_FRAME, "|cFF00FF00[WoWTranslate] Sent:|r " .. finalMsg)
            end
        else
            -- Translation failed - send original
            WT_DebugLog("Outgoing translation failed:", err)
            if WT_originalAddMessage then
                WT_SafeAddMessage(WT_originalAddMessage, DEFAULT_CHAT_FRAME, "|cFFFF0000[WoWTranslate] Translation failed, sending original|r")
            end
            WT_SafeSendChatMessage(queued.originalMsg, queued.chatType, queued.language, queued.channel)
        end
    end)
end

-- Track if hook is installed (for diagnostics)
local outgoingHookInstalled = false

-- Install the outgoing message hook
function WT_InstallOutgoingHook()
    if SendChatMessage ~= WT_HookedSendChatMessage then
        WT_DebugLog("Installing outgoing SendChatMessage hook")
        SendChatMessage = WT_HookedSendChatMessage
        outgoingHookInstalled = true
    end
end

-- Remove the outgoing message hook
function WT_RemoveOutgoingHook()
    if SendChatMessage == WT_HookedSendChatMessage then
        WT_DebugLog("Removing outgoing SendChatMessage hook")
        SendChatMessage = WT_originalSendChatMessage
        outgoingHookInstalled = false
    end
end

-- Check if hook is active (for diagnostics)
function WT_IsOutgoingHookActive()
    return outgoingHookInstalled and SendChatMessage == WT_HookedSendChatMessage
end

