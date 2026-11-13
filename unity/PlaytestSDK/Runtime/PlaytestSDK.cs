// Playtest SDK for Unity (Android). Records gameplay events and in-game issue reports and sends them
// to the Playtest Tracker backend. Design rules:
//   * Every network call is asynchronous (UnityWebRequest in a coroutine): the main thread never blocks.
//   * Nothing here throws into game code. Failures are swallowed and logged at Debug.Log level only.
//   * Events and reports are queued on disk when the network is down (bounded) and retried later.
//   * Every session, event and report carries a client-generated id, so a retry never creates duplicates.
//   * The ingest key can only SEND data. It cannot read anything. Never put admin or service keys in a game.
//
// NOT COMPILED OR RUN: this file was written without a Unity Editor available. See unity/README.md.
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Text;
using UnityEngine;
using UnityEngine.Networking;

namespace Playtest
{
    public static class PlaytestSDK
    {
        // ---------------------------------------------------------------- public API

        /// <summary>Call once at startup. url = https://xxxx.supabase.co, anonKey = publishable key, ingestKey = project ingest key.</summary>
        public static bool Initialize(string url, string anonKey, string ingestKey, string buildVersion, string testerId = null)
        {
            try
            {
                if (string.IsNullOrEmpty(url) || string.IsNullOrEmpty(anonKey) || string.IsNullOrEmpty(ingestKey) || string.IsNullOrEmpty(buildVersion))
                {
                    Log("Initialize failed: url, anonKey, ingestKey and buildVersion are all required.");
                    return false;
                }
                _url = url.TrimEnd('/');
                _anon = anonKey;
                _ingest = ingestKey;
                _build = buildVersion;
                _tester = string.IsNullOrEmpty(testerId) ? LoadOrCreateTesterId() : testerId;
                _runner = PlaytestRunner.Create();
                LoadQueue();
                Initialized = true;
                _runner.StartCoroutine(FlushLoop());
                return true;
            }
            catch (Exception e)
            {
                Log("Initialize error: " + e.Message);
                return false;
            }
        }

        public static bool Initialized { get; private set; }

        /// <summary>Pseudonymous id for this install. Not a name or an email.</summary>
        public static string TesterId { get { return _tester; } }

        public static void StartSession()
        {
            if (!Initialized) return;
            _sessionId = Guid.NewGuid().ToString("N");
            _eventSeq = 0;
            _recent.Clear();
            TrackEvent("session_started");
        }

        public static void TrackEvent(string name, Dictionary<string, object> props = null)
        {
            try
            {
                if (!Initialized || string.IsNullOrEmpty(name)) return;
                if (string.IsNullOrEmpty(_sessionId)) StartSession();
                var e = new QueuedEvent
                {
                    Session = _sessionId,
                    Eid = _sessionId + "-" + (++_eventSeq),
                    Name = name,
                    PropsJson = Json.Object(props),
                    At = DateTime.UtcNow.ToString("o"),
                };
                _queue.Add(e);
                while (_queue.Count > MaxQueuedEvents) _queue.RemoveAt(0);
                _recent.Add(e);
                while (_recent.Count > 20) _recent.RemoveAt(0);
                SaveQueue();
            }
            catch (Exception ex) { Log("TrackEvent error: " + ex.Message); }
        }

        /// <summary>Sends an issue report with the last events of this session. Never blocks the game.</summary>
        public static void SubmitReport(string description, string category = "Other", string severity = "Medium", Action<bool> done = null)
        {
            try
            {
                if (!Initialized || string.IsNullOrEmpty(description)) { if (done != null) done(false); return; }
                if (string.IsNullOrEmpty(_sessionId)) StartSession();
                TrackEvent("issue_reported", new Dictionary<string, object> { { "category", category } });
                var r = new QueuedReport
                {
                    Session = _sessionId,
                    ReportId = Guid.NewGuid().ToString("N"),
                    Description = description.Length > 2000 ? description.Substring(0, 2000) : description,
                    Category = category,
                    Severity = severity,
                    Recent = new List<QueuedEvent>(_recent),
                };
                _reports.Add(r);
                while (_reports.Count > MaxQueuedReports) _reports.RemoveAt(0);
                SaveQueue();
                _runner.StartCoroutine(SendReport(r, done));
            }
            catch (Exception ex) { Log("SubmitReport error: " + ex.Message); if (done != null) done(false); }
        }

        public static void EndSession()
        {
            if (!Initialized || string.IsNullOrEmpty(_sessionId)) return;
            TrackEvent("session_ended", new Dictionary<string, object> { { "duration_sec", (int)(Time.realtimeSinceStartup - _startedAt) } });
            _sessionId = null;
            _runner.StartCoroutine(FlushOnce());
        }

        // ---------------------------------------------------------------- internals

        const int MaxQueuedEvents = 500, MaxQueuedReports = 20, BatchSize = 100;
        static string _url, _anon, _ingest, _build, _tester, _sessionId;
        static int _eventSeq;
        static float _startedAt;
        static PlaytestRunner _runner;
        static readonly List<QueuedEvent> _queue = new List<QueuedEvent>();
        static readonly List<QueuedEvent> _recent = new List<QueuedEvent>();
        static readonly List<QueuedReport> _reports = new List<QueuedReport>();
        static bool _flushing;

        class QueuedEvent { public string Session, Eid, Name, PropsJson, At; }
        class QueuedReport { public string Session, ReportId, Description, Category, Severity; public List<QueuedEvent> Recent; }

        static void Log(string m) { Debug.Log("[Playtest] " + m); }

        static string LoadOrCreateTesterId()
        {
            const string key = "playtest_tester_id";
            var id = PlayerPrefs.GetString(key, "");
            if (string.IsNullOrEmpty(id))
            {
                id = "tester-" + Guid.NewGuid().ToString("N").Substring(0, 6);
                PlayerPrefs.SetString(key, id);
                PlayerPrefs.Save();
            }
            return id;
        }

        static string Device { get { return SystemInfo.deviceModel; } }
        static string AndroidVersion { get { return SystemInfo.operatingSystem; } }

        // Calls the sdk_ingest function with the public key only. Reports success through the callback.
        static IEnumerator Post(string json, Action<bool> done)
        {
            bool ok = false;
            UnityWebRequest req = null;
            try
            {
                req = new UnityWebRequest(_url + "/rest/v1/rpc/sdk_ingest", "POST");
                req.uploadHandler = new UploadHandlerRaw(Encoding.UTF8.GetBytes(json));
                req.downloadHandler = new DownloadHandlerBuffer();
                req.SetRequestHeader("Content-Type", "application/json");
                req.SetRequestHeader("apikey", _anon);
                req.SetRequestHeader("Authorization", "Bearer " + _anon);
                req.timeout = 15;
            }
            catch (Exception e) { Log("request setup failed: " + e.Message); }
            if (req != null)
            {
                yield return req.SendWebRequest();            // asynchronous: the game keeps running
                ok = req.result == UnityWebRequest.Result.Success;
                if (!ok) Log("send failed (" + req.responseCode + "), will retry");
                req.Dispose();
            }
            if (done != null) done(ok);
        }

        static string BuildPayload(string sessionId, List<QueuedEvent> events, QueuedReport report)
        {
            var sb = new StringBuilder("{");
            sb.Append("\"p_ingest_key\":").Append(Json.Str(_ingest));
            sb.Append(",\"p_build\":").Append(Json.Str(_build));
            sb.Append(",\"p_tester\":").Append(Json.Str(_tester));
            sb.Append(",\"p_client_session_id\":").Append(Json.Str(sessionId));
            sb.Append(",\"p_device_model\":").Append(Json.Str(Device));
            sb.Append(",\"p_android_version\":").Append(Json.Str(AndroidVersion));
            sb.Append(",\"p_events\":[");
            for (int i = 0; i < events.Count; i++)
            {
                if (i > 0) sb.Append(',');
                var e = events[i];
                sb.Append("{\"name\":").Append(Json.Str(e.Name)).Append(",\"props\":").Append(e.PropsJson)
                  .Append(",\"at\":").Append(Json.Str(e.At)).Append(",\"eid\":").Append(Json.Str(e.Eid)).Append('}');
            }
            sb.Append(']');
            if (report != null)
            {
                sb.Append(",\"p_description\":").Append(Json.Str(report.Description));
                sb.Append(",\"p_category\":").Append(Json.Str(report.Category));
                sb.Append(",\"p_severity\":").Append(Json.Str(report.Severity));
                sb.Append(",\"p_client_report_id\":").Append(Json.Str(report.ReportId));
            }
            return sb.Append('}').ToString();
        }

        static IEnumerator SendReport(QueuedReport r, Action<bool> done)
        {
            bool ok = false;
            yield return Post(BuildPayload(r.Session, r.Recent, r), s => ok = s);
            if (ok) { _reports.Remove(r); SaveQueue(); }
            if (done != null) done(ok);
        }

        static IEnumerator FlushOnce()
        {
            if (_flushing || _queue.Count == 0) yield break;
            _flushing = true;
            while (_queue.Count > 0)
            {
                string session = _queue[0].Session;
                var batch = new List<QueuedEvent>();
                foreach (var e in _queue) { if (e.Session == session && batch.Count < BatchSize) batch.Add(e); }
                bool ok = false;
                yield return Post(BuildPayload(session, batch, null), s => ok = s);
                if (!ok) break;                                  // keep the queue, try again later
                foreach (var e in batch) _queue.Remove(e);
                SaveQueue();
            }
            _flushing = false;
        }

        static IEnumerator FlushLoop()
        {
            _startedAt = Time.realtimeSinceStartup;
            float wait = 5f;
            while (true)
            {
                yield return new WaitForSecondsRealtime(wait);
                int before = _queue.Count + _reports.Count;
                yield return FlushOnce();
                foreach (var r in _reports.ToArray()) yield return SendReport(r, null);
                int after = _queue.Count + _reports.Count;
                wait = after > 0 && after >= before ? Mathf.Min(wait * 2f, 120f) : 5f;   // back off while offline
            }
        }

        // ---------------------------------------------------------------- bounded offline queue on disk
        static string QueuePath { get { return Path.Combine(Application.persistentDataPath, "playtest_queue.txt"); } }

        static void SaveQueue()
        {
            try
            {
                var sb = new StringBuilder();
                foreach (var e in _queue) sb.Append("E\t").Append(e.Session).Append('\t').Append(e.Eid).Append('\t').Append(e.Name)
                    .Append('\t').Append(e.At).Append('\t').Append(Convert.ToBase64String(Encoding.UTF8.GetBytes(e.PropsJson))).Append('\n');
                foreach (var r in _reports) sb.Append("R\t").Append(r.Session).Append('\t').Append(r.ReportId).Append('\t')
                    .Append(Convert.ToBase64String(Encoding.UTF8.GetBytes(r.Description))).Append('\t').Append(r.Category).Append('\t').Append(r.Severity).Append('\n');
                File.WriteAllText(QueuePath, sb.ToString());
            }
            catch (Exception e) { Log("could not save queue: " + e.Message); }
        }

        static void LoadQueue()
        {
            try
            {
                if (!File.Exists(QueuePath)) return;
                foreach (var line in File.ReadAllLines(QueuePath))
                {
                    var p = line.Split('\t');
                    if (p[0] == "E" && p.Length == 6)
                        _queue.Add(new QueuedEvent { Session = p[1], Eid = p[2], Name = p[3], At = p[4], PropsJson = Encoding.UTF8.GetString(Convert.FromBase64String(p[5])) });
                    else if (p[0] == "R" && p.Length == 6)
                        _reports.Add(new QueuedReport { Session = p[1], ReportId = p[2], Description = Encoding.UTF8.GetString(Convert.FromBase64String(p[3])), Category = p[4], Severity = p[5], Recent = new List<QueuedEvent>() });
                }
            }
            catch (Exception e) { Log("could not load queue: " + e.Message); }
        }

        // ---------------------------------------------------------------- minimal JSON writer (no external packages)
        static class Json
        {
            public static string Str(string s)
            {
                if (s == null) return "null";
                var sb = new StringBuilder("\"");
                foreach (char c in s)
                {
                    switch (c)
                    {
                        case '"': sb.Append("\\\""); break;
                        case '\\': sb.Append("\\\\"); break;
                        case '\n': sb.Append("\\n"); break;
                        case '\r': sb.Append("\\r"); break;
                        case '\t': sb.Append("\\t"); break;
                        default:
                            if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("x4"));
                            else sb.Append(c);
                            break;
                    }
                }
                return sb.Append('"').ToString();
            }

            public static string Object(Dictionary<string, object> d)
            {
                if (d == null || d.Count == 0) return "{}";
                var sb = new StringBuilder("{");
                bool first = true;
                foreach (var kv in d)
                {
                    if (!first) sb.Append(',');
                    first = false;
                    sb.Append(Str(kv.Key)).Append(':');
                    object v = kv.Value;
                    if (v == null) sb.Append("null");
                    else if (v is bool) sb.Append((bool)v ? "true" : "false");
                    else if (v is int || v is long || v is short || v is byte) sb.Append(Convert.ToString(v, System.Globalization.CultureInfo.InvariantCulture));
                    else if (v is float || v is double) sb.Append(Convert.ToDouble(v).ToString("R", System.Globalization.CultureInfo.InvariantCulture));
                    else sb.Append(Str(v.ToString()));
                }
                return sb.Append('}').ToString();
            }
        }
    }

    /// <summary>Invisible object that owns the SDK's coroutines.</summary>
    public class PlaytestRunner : MonoBehaviour
    {
        public static PlaytestRunner Create()
        {
            var go = new GameObject("PlaytestSDK");
            DontDestroyOnLoad(go);
            go.hideFlags = HideFlags.HideInHierarchy;
            return go.AddComponent<PlaytestRunner>();
        }

        void OnApplicationPause(bool paused) { if (paused) PlaytestSDK.EndSession(); }
        void OnApplicationQuit() { PlaytestSDK.EndSession(); }
    }
}
