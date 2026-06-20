using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using UnityEngine;

namespace Maradel.Diagnostics
{
    /// <summary>
    /// File-based session logger. On launch it opens a NEW file per run under
    /// <c>persistentDataPath/Logs/session-&lt;timestamp&gt;.log</c> and mirrors EVERY Unity log message
    /// (Debug.Log/Warning/Error/Exception, from any thread) into it, flushing each line to disk so the
    /// log survives even if the app is killed. The overlay's "Dump" button uploads the current file to
    /// nukshare via the egregor-share API. Always on (verbose) — this is a diagnostic build.
    /// </summary>
    public static class SessionLog
    {
        static StreamWriter _writer;
        static readonly object _lock = new();

        public static string FilePath { get; private set; }
        public static bool Active => _writer != null;
        public static int Lines { get; private set; }

        // live tail for the on-screen log window (last N lines), newest last
        const int TailMax = 200;
        static readonly Queue<string> _tail = new();
        /// <summary>Snapshot of the most recent log lines (oldest→newest) for an on-screen log window.</summary>
        public static string[] Tail() { lock (_lock) { return _tail.ToArray(); } }

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        static void Init()
        {
            if (_writer != null) return;
            try
            {
                string dir = Path.Combine(Application.persistentDataPath, "Logs");
                Directory.CreateDirectory(dir);
                FilePath = Path.Combine(dir, $"session-{DateTime.Now:yyyyMMdd-HHmmss}.log");
                // FileShare.ReadWrite so the Dump button can read the file while we keep writing to it.
                var fs = new FileStream(FilePath, FileMode.Create, FileAccess.Write, FileShare.ReadWrite);
                _writer = new StreamWriter(fs, new UTF8Encoding(false)) { AutoFlush = true };

                Application.logMessageReceivedThreaded += OnLog;
                Application.quitting += Close;

                WriteRaw("INFO", $"=== SESSION START {DateTime.Now:O} ===");
                WriteRaw("INFO", $"app={Application.productName} v={Application.version} unity={Application.unityVersion}");
                WriteRaw("INFO", $"device={SystemInfo.deviceModel} os={SystemInfo.operatingSystem}");
                WriteRaw("INFO", $"persistentDataPath={Application.persistentDataPath}");
                WriteRaw("INFO", $"logfile={FilePath}");
            }
            catch (Exception e) { Debug.LogWarning($"[SessionLog] init failed: {e.Message}"); }
        }

        static void OnLog(string condition, string stackTrace, LogType type)
        {
            // include the stack for errors/exceptions/warnings — that's where lipsync faults will surface
            bool withStack = type == LogType.Error || type == LogType.Exception || type == LogType.Assert;
            WriteRaw(type.ToString().ToUpperInvariant(), condition, withStack ? stackTrace : null);
        }

        static void WriteRaw(string level, string msg, string stack = null)
        {
            var w = _writer;
            if (w == null) return;
            lock (_lock)
            {
                try
                {
                    w.Write(DateTime.Now.ToString("HH:mm:ss.fff"));
                    w.Write(" [");
                    w.Write(level);
                    w.Write("] ");
                    w.WriteLine(msg);
                    if (!string.IsNullOrEmpty(stack)) w.WriteLine(stack.TrimEnd());
                    Lines++;
                    _tail.Enqueue($"{level[0]} {msg}");          // compact line for the on-screen window
                    while (_tail.Count > TailMax) _tail.Dequeue();
                }
                catch { /* never let logging throw */ }
            }
        }

        /// <summary>Read the whole current log (tolerant of the writer still holding the file open).</summary>
        public static byte[] ReadAllBytes()
        {
            lock (_lock)
            {
                try
                {
                    if (string.IsNullOrEmpty(FilePath) || !File.Exists(FilePath)) return Array.Empty<byte>();
                    using var fs = new FileStream(FilePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                    using var ms = new MemoryStream();
                    fs.CopyTo(ms);
                    return ms.ToArray();
                }
                catch (Exception e) { Debug.LogWarning($"[SessionLog] read failed: {e.Message}"); return Array.Empty<byte>(); }
            }
        }

        public static string FileName => string.IsNullOrEmpty(FilePath) ? "(none)" : Path.GetFileName(FilePath);

        static void Close()
        {
            lock (_lock)
            {
                try { _writer?.Flush(); _writer?.Dispose(); } catch { }
                _writer = null;
            }
        }
    }
}
