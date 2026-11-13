// Tiny Unity test game ("Gem Hunt") that exercises every part of the Playtest SDK.
// It needs NO scene setup: the [RuntimeInitializeOnLoadMethod] below adds the game to any scene.
// Fill in the four constants, build for Android, install, play.
//
// NOT COMPILED OR RUN: written without a Unity Editor available. See unity/README.md.
using System.Collections.Generic;
using Playtest;
using UnityEngine;

public class GemHunt : MonoBehaviour
{
    // ---- configuration (the ingest key is shown in the dashboard: Game > Dashboard > SDK setup) ----
    const string SupabaseUrl = "https://YOUR-PROJECT.supabase.co";
    const string AnonKey = "YOUR-PUBLISHABLE-ANON-KEY";   // the public key; never a service-role key
    const string IngestKey = "YOUR-INGEST-KEY";
    const string BuildVersion = "0.1.0";

    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    static void Boot() { new GameObject("GemHunt").AddComponent<GemHunt>(); }

    enum Page { Menu, Play, Report }
    Page _screen = Page.Menu;
    int _level = 1, _gems, _target = 5;
    float _timeLeft;
    Rect _gem;
    string _text = "", _status = "";
    int _category, _severity = 1;
    static readonly string[] Categories = { "Gameplay", "Controls", "Visual", "Other" };
    static readonly string[] Severities = { "Low", "Medium", "High", "Critical" };

    void Start()
    {
        PlaytestSDK.Initialize(SupabaseUrl, AnonKey, IngestKey, BuildVersion);   // never throws; the game works if this fails
    }

    void NewLevel()
    {
        _gems = 0;
        _target = 4 + _level;
        _timeLeft = 20f;
        MoveGem();
        PlaytestSDK.TrackEvent("level_started", new Dictionary<string, object> { { "level", _level } });
    }

    void MoveGem()
    {
        _gem = new Rect(Random.Range(40, Screen_W() - 140), Random.Range(160, Screen_H() - 140), 100, 100);
    }

    static float Screen_W() { return UnityEngine.Screen.width; }
    static float Screen_H() { return UnityEngine.Screen.height; }

    void Update()
    {
        if (_screen != Page.Play) return;
        _timeLeft -= Time.deltaTime;
        if (_timeLeft <= 0f)
        {
            PlaytestSDK.TrackEvent("level_failed", new Dictionary<string, object> { { "level", _level }, { "gems", _gems } });
            _status = "Out of time";
            _screen = Page.Menu;
        }
    }

    void OnGUI()
    {
        GUI.skin.label.fontSize = GUI.skin.button.fontSize = GUI.skin.textField.fontSize = Mathf.RoundToInt(UnityEngine.Screen.height / 40f);
        float w = Screen_W(), h = Screen_H(), pad = h / 40f;
        switch (_screen)
        {
            case Page.Menu:
                GUI.Label(new Rect(pad, pad, w - 2 * pad, h / 10f), "Gem Hunt   (build " + BuildVersion + ")");
                if (_status != "") GUI.Label(new Rect(pad, h / 8f, w - 2 * pad, h / 12f), _status);
                if (GUI.Button(new Rect(pad, h / 4f, w - 2 * pad, h / 8f), "Play"))
                {
                    PlaytestSDK.StartSession();
                    PlaytestSDK.TrackEvent("game_started");
                    _level = 1; _status = ""; NewLevel(); _screen = Page.Play;
                }
                if (GUI.Button(new Rect(pad, h / 2.4f, w - 2 * pad, h / 8f), "Report a problem")) _screen = Page.Report;
                break;

            case Page.Play:
                GUI.Label(new Rect(pad, pad, w - 2 * pad, h / 12f), "Level " + _level + "   Gems " + _gems + "/" + _target + "   Time " + Mathf.CeilToInt(_timeLeft));
                if (GUI.Button(_gem, "GEM"))
                {
                    _gems++;
                    PlaytestSDK.TrackEvent("gem_collected", new Dictionary<string, object> { { "level", _level }, { "gems", _gems } });
                    if (_gems >= _target)
                    {
                        PlaytestSDK.TrackEvent("level_completed", new Dictionary<string, object> { { "level", _level } });
                        _level++; NewLevel();
                    }
                    else MoveGem();
                }
                if (GUI.Button(new Rect(w - h / 6f - pad, pad, h / 6f, h / 14f), "Quit"))
                {
                    PlaytestSDK.TrackEvent("game_quit", new Dictionary<string, object> { { "level", _level } });
                    PlaytestSDK.EndSession();
                    _screen = Page.Menu;
                }
                if (GUI.Button(new Rect(pad, h - h / 10f - pad, w / 2f, h / 10f), "Report a problem")) _screen = Page.Report;
                break;

            case Page.Report:
                GUI.Label(new Rect(pad, pad, w - 2 * pad, h / 12f), "Report a problem");
                GUI.Label(new Rect(pad, h / 10f, w - 2 * pad, h / 6f), "Do not include personal details. Your report and recent gameplay events are sent to the game's developer to help fix the problem.");
                _text = GUI.TextArea(new Rect(pad, h / 4f, w - 2 * pad, h / 5f), _text, 500);
                _category = GUI.SelectionGrid(new Rect(pad, h / 2f - h / 20f, w - 2 * pad, h / 12f), _category, Categories, 4);
                _severity = GUI.SelectionGrid(new Rect(pad, h / 2f + h / 20f, w - 2 * pad, h / 12f), _severity, Severities, 4);
                GUI.Label(new Rect(pad, h * 0.68f, w - 2 * pad, h / 14f), _status);
                if (GUI.Button(new Rect(pad, h * 0.75f, w / 2f - pad, h / 10f), "Send"))
                {
                    _status = "Sending...";
                    PlaytestSDK.SubmitReport(_text, Categories[_category], Severities[_severity], ok =>
                    {
                        _status = ok ? "Report sent. Thank you!" : "No connection: saved and will be sent later.";
                        if (ok) _text = "";
                    });
                }
                if (GUI.Button(new Rect(w / 2f + pad, h * 0.75f, w / 2f - 2 * pad, h / 10f), "Back")) { _screen = Page.Menu; }
                break;
        }
    }
}
