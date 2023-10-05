bool permissionsOkay = false;
uint startTime = uint(-1);

void Main() {
    trace('ghost picker checking permissions');
    CheckRequiredPermissions();
    trace('checked permissions');
    startnew(MapCoro);
    startnew(ClearTaskCoro);
    startnew(SetupIntercepts);
    startnew(InitGP);
    trace('started coros');
    startTime = Time::Now;

}

void InitGP() {
    trace('registering callback');
    MLHook::RegisterPlaygroundMLExecutionPointCallback(ML_PG_Callback);
    trace('checking spec');
    if (IsSpectatingGhost()) {
        trace('is spectating ghost! getting current values');
        // get current spec'd ghost id and update values
        SetCurrentGhostValues();
        trace("starting watch loop on init because we're spectating a ghost");
        startnew(CoroutineFunc(g_SaveGhostTab.WatchGhostsToLoopThem));
    }
    trace('init done');
}

void Unload() {
    trace('unloading ghost picker #1 paused');
    // if (scrubberPaused) GhostClipsMgr::UnpauseClipPlayers(GhostClipsMgr::Get(GetApp()), 0., 60.0);
    scrubberMgr.SetPlayback(true);
    trace('unloading ghost picker #2 mlhook');
    MLHook::UnregisterMLHooksAndRemoveInjectedML();
    trace('unloading ghost picker #3 done');
}
void OnDestroyed() { Unload(); }
void OnDisabled() { Unload(); }

// check for permissions and
void CheckRequiredPermissions() {
    permissionsOkay = Permissions::ViewRecords() && Permissions::PlayRecords();
    if (!permissionsOkay) {
        NotifyWarning("Your edition of the game does not support playing against record ghosts.\n\nThis plugin won't work, sorry :(.");
        while(true) { sleep(10000); } // do nothing forever
    }
}

string s_currMap = "";

void MapCoro() {
    while(true) {
        sleep(273); // no need to check that frequently. 273 seems primeish
        if (s_currMap != CurrentMap) {
            s_currMap = CurrentMap;
            ResetToggleCache();
            OnMapChange();
        }
    }
}

void OnMapChange() {
    for (uint i = 0; i < tabs.Length; i++) {
        tabs[i].OnMapChange();
    }
}

dictionary toggleCache;
void ResetToggleCache() {
    toggleCache.DeleteAll();
    records = Json::Value();
    lastRecordPid = "";
}

int g_numGhosts = 20;
int g_ghostRankOffset = 0;

// returns e.g., "the top X ghosts" or "ghosts ranked 5 to 56";
const string GenGhostRankString() {
    if (g_ghostRankOffset == 0)
        return "the top " + g_numGhosts + " ghosts";
    int startRank = g_ghostRankOffset + 1;
    if (g_numGhosts == 1) {
        return "the ghost ranked " + startRank;
    }
    int endRank = startRank + g_numGhosts - 1;
    return "ghosts ranked " + startRank + " to " + endRank;
}


uint lastRefresh = 0;
const uint disableTime = 3000;
void Render() {
    if (!permissionsOkay) return;
    if (!S_ShowWindow) return;
    if (IsSpectatingGhost()) {
        DrawScrubber();
    }
    return;
}

void RenderMenu() {
    if (!permissionsOkay) return;
    if (UI::MenuItem("\\$888" + Icons::HandPointerO + "\\$z Ghost Picker", "", S_ShowWindow)) {
        S_ShowWindow = !S_ShowWindow;
    }
}

CTrackMania@ get_app() {
    return cast<CTrackMania>(GetApp());
}

CGameManiaAppPlayground@ get_cmap() {
    return app.Network.ClientManiaAppPlayground;
}

string get_CurrentMap() {
    auto map = GetApp().RootMap;
    if (map is null) return "";
    return map.MapInfo.MapUid;
}

string lastRecordPid;
int lastOffset = -1;
Json::Value records = Json::Value(); // null

array<string> UpdateMapRecords() {
    if (!permissionsOkay) return array<string>();
    if (records.GetType() != Json::Type::Array || int(records.Length) < g_numGhosts || lastOffset != g_ghostRankOffset) {
        lastOffset = g_ghostRankOffset;
        Json::Value mapRecords = Live::GetMapRecords("Personal_Best", CurrentMap, true, g_numGhosts, g_ghostRankOffset);
        // trace(Json::Write(records));
        auto tops = mapRecords['tops'];
        if (tops.GetType() != Json::Type::Array) {
            warn('api did not return an array for records; instead got: ' + Json::Write(mapRecords));
            NotifyWarning("API did not return map records.");
            return array<string>();
        }
        records = tops[0]['top'];
    }
    array<string> pids = {};
    if (records.GetType() == Json::Type::Array) {
        for (uint i = 0; i < records.Length; i++) {
            auto item = records[i];
            pids.InsertLast(item['accountId']);
        }
    }
    lastRecordPid = pids[pids.Length - 1];
    return pids;
}

void ToggleTopGhosts() {
    array<string> pids = UpdateMapRecords();
    Notify("Toggling " + pids.Length + " ghosts...");
    yield();
    for (uint i = 0; i < pids.Length; i++) {
        auto playerId = pids[i];
        ToggleGhost(playerId);
        yield();
    }
}

void _ShowTopGhosts(bool hideInstead = false) {
    array<string> pids = UpdateMapRecords();
    Notify((hideInstead ? "Hiding " : "Showing ") + pids.Length + " ghosts...");
    yield();
    for (uint i = 0; i < pids.Length; i++) {
        auto playerId = pids[i];
        bool enabled = false;
        toggleCache.Get(playerId, enabled);
        if (enabled == hideInstead) {
            ToggleGhost(playerId);
            yield();
        }
    }
}

void ShowTopGhosts() {
    _ShowTopGhosts(false);
}

void HideTopGhosts() {
    _ShowTopGhosts(true);
}

void HideAllGhosts() {
    auto pids = toggleCache.GetKeys();
    for (uint i = 0; i < pids.Length; i++) {
        auto pid = pids[i];
        if (bool(toggleCache[pid])) {
            ToggleGhost(pid);
            yield();
        }
    }
}

/**
TMGame_Record_SpectateGhost
TMGame_Record_ToggleGhost
TMGame_Record_TogglePB
 */
void ToggleGhost(const string &in playerId) {
    if (!permissionsOkay) return;
    // trace('toggled ghost for ' + playerId);
    MLHook::Queue_SH_SendCustomEvent("TMGame_Record_ToggleGhost", {playerId});
    bool enabled = false;
    toggleCache.Get(playerId, enabled);
    toggleCache[playerId] = !enabled;
}

void ToggleSpectator() {
    if (!permissionsOkay) return;
    auto pids = UpdateMapRecords();
    if (lastRecordPid == "" || int(pids.Length) < g_numGhosts) {
        NotifyWarning("\n>> Toggle ghosts first at least once. <<\n");
    } else {
        MLHook::Queue_SH_SendCustomEvent("TMGame_Record_SpectateGhost", {pids[g_numGhosts - 1]});
    }
}


/*
UI STUFF
*/

void Notify(const string &in msg) {
    UI::ShowNotification(Meta::ExecutingPlugin().Name, msg);
    trace("Notified: " + msg);
}

void NotifySuccess(const string &in msg) {
    UI::ShowNotification(Meta::ExecutingPlugin().Name, msg, vec4(.4, .7, .1, .3), 12000);
    trace("Notified: " + msg);
}

void NotifyError(const string &in msg) {
    warn(msg);
    UI::ShowNotification(Meta::ExecutingPlugin().Name + ": Error", msg, vec4(.9, .3, .1, .3), 12000);
}

void NotifyWarning(const string &in msg) {
    warn(msg);
    UI::ShowNotification(Meta::ExecutingPlugin().Name + ": Warning", msg, vec4(.7, .4, .1, .3), 12000);
}


bool IsSpectatingGhost() {
    auto ps = GetApp().PlaygroundScript;
    if (ps is null || ps.UIManager is null) return false;
    return ps.UIManager.UIAll.ForceSpectator;
}

void ExitSpectatingGhost() {
    auto ps = GetApp().PlaygroundScript;
    if (ps is null || ps.UIManager is null) return;
    MLHook::Queue_PG_SendCustomEvent("TMGame_Record_Spectate", {""});
}

void ExitSpectatingGhostAndCleanUp() {
    auto ps = cast<CSmArenaRulesMode>(GetApp().PlaygroundScript);
    auto cp = GetApp().CurrentPlayground;
    if (ps is null || ps.UIManager is null || cp is null) return;
    ps.Ghosts_SetStartTime(-1);
    ps.UIManager.UIAll.UISequence = CGamePlaygroundUIConfig::EUISequence::Playing;
    ps.RespawnPlayer(cast<CSmScriptPlayer>(cast<CSmPlayer>(cp.Players[0]).ScriptAPI));
    ps.UIManager.UIAll.ForceSpectator = false;
    ps.UIManager.UIAll.SpectatorForceCameraType = -1;
    ps.UIManager.UIAll.Spectator_SetForcedTarget_Clear();
    MLHook::Queue_PG_SendCustomEvent("TMGame_Record_Spectate", {""});
}

/** Called whenever a key is pressed on the keyboard. See the documentation for the [`VirtualKey` enum](https://openplanet.dev/docs/api/global/VirtualKey).
*/
UI::InputBlocking OnKeyPress(bool down, VirtualKey key) {
    if (down && key == VirtualKey::Escape && IsSpectatingGhost()) {
        ExitSpectatingGhost();
    }
    return UI::InputBlocking::DoNothing;
}
