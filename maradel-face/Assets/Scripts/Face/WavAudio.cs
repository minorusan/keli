using System;
using UnityEngine;

namespace Maradel.Face
{
    /// <summary>
    /// Minimal RIFF/WAVE → AudioClip decoder. Used so we can download WAV bytes with a plain
    /// HttpClient (bypassing Unity's insecure-HTTP policy) and still build a playable AudioClip.
    /// Supports PCM 8/16/24/32-bit and IEEE float32, mono or multi-channel.
    /// </summary>
    public static class WavAudio
    {
        public static bool TryDecode(byte[] bytes, string name, out AudioClip clip, out string error)
        {
            clip = null;
            error = null;
            try
            {
                if (bytes == null || bytes.Length < 44) { error = "too short / null"; return false; }
                if (bytes[0] != 'R' || bytes[1] != 'I' || bytes[2] != 'F' || bytes[3] != 'F') { error = "no RIFF header"; return false; }
                if (bytes[8] != 'W' || bytes[9] != 'A' || bytes[10] != 'V' || bytes[11] != 'E') { error = "no WAVE tag"; return false; }

                int audioFormat = 0, channels = 0, sampleRate = 0, bits = 0;
                int dataStart = -1, dataSize = 0;

                int i = 12;
                while (i + 8 <= bytes.Length)
                {
                    string id = new string(new[] { (char)bytes[i], (char)bytes[i + 1], (char)bytes[i + 2], (char)bytes[i + 3] });
                    int size = BitConverter.ToInt32(bytes, i + 4);
                    int body = i + 8;

                    if (id == "fmt ")
                    {
                        audioFormat = BitConverter.ToInt16(bytes, body);
                        channels = BitConverter.ToInt16(bytes, body + 2);
                        sampleRate = BitConverter.ToInt32(bytes, body + 4);
                        bits = BitConverter.ToInt16(bytes, body + 14);
                    }
                    else if (id == "data")
                    {
                        dataStart = body;
                        dataSize = Mathf.Min(size, bytes.Length - body);
                        break; // data is what we need; stop
                    }

                    i = body + size + (size & 1); // chunks are word-aligned
                }

                if (dataStart < 0 || channels <= 0 || sampleRate <= 0)
                { error = $"bad header (ch={channels} hz={sampleRate} bits={bits} fmt={audioFormat} data@{dataStart})"; return false; }

                float[] samples = ConvertToFloat(bytes, dataStart, dataSize, bits, audioFormat, out error);
                if (samples == null) return false;

                int frames = samples.Length / channels;
                clip = AudioClip.Create(name, frames, channels, sampleRate, false);
                clip.SetData(samples, 0);
                return true;
            }
            catch (Exception e)
            {
                error = e.Message;
                return false;
            }
        }

        static float[] ConvertToFloat(byte[] b, int start, int size, int bits, int fmt, out string error)
        {
            error = null;
            switch (bits)
            {
                case 16:
                {
                    int n = size / 2;
                    var s = new float[n];
                    for (int k = 0; k < n; k++) s[k] = BitConverter.ToInt16(b, start + k * 2) / 32768f;
                    return s;
                }
                case 32 when fmt == 3: // IEEE float
                {
                    int n = size / 4;
                    var s = new float[n];
                    for (int k = 0; k < n; k++) s[k] = BitConverter.ToSingle(b, start + k * 4);
                    return s;
                }
                case 32: // 32-bit PCM int
                {
                    int n = size / 4;
                    var s = new float[n];
                    for (int k = 0; k < n; k++) s[k] = BitConverter.ToInt32(b, start + k * 4) / 2147483648f;
                    return s;
                }
                case 24:
                {
                    int n = size / 3;
                    var s = new float[n];
                    for (int k = 0; k < n; k++)
                    {
                        int o = start + k * 3;
                        int v = (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16));
                        if ((v & 0x800000) != 0) v |= unchecked((int)0xFF000000); // sign-extend
                        s[k] = v / 8388608f;
                    }
                    return s;
                }
                case 8:
                {
                    var s = new float[size];
                    for (int k = 0; k < size; k++) s[k] = (b[start + k] - 128) / 128f; // 8-bit is unsigned
                    return s;
                }
                default:
                    error = $"unsupported bit depth {bits} (fmt {fmt})";
                    return null;
            }
        }
    }
}
