// Temporary, loopback-only DNS-to-DoH bridge for DiscordOnly.
// The HTTP server certificate is ALWAYS validated. No plain DNS upstream.
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

namespace DiscordOnlyDns {
    public static class Proxy {
        private static readonly string[] Domains = {
            "discord.com", "discord.gg", "discordapp.com", "discordapp.net",
            "discord.media", "discordcdn.com", "discordstatus.com"
        };
        private static readonly string[] DohEndpoints = {
            "https://1.1.1.1/dns-query", "https://1.0.0.1/dns-query"
        };
        private static readonly object SendGate = new object();
        private static readonly object LogGate = new object();
        private static UdpClient listener;
        private static string logFile;
        private static int inFlight;

        public static void Run(string readyFile, string diagnosticsFile) {
            logFile = diagnosticsFile;
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
            ServicePointManager.Expect100Continue = false;
            ServicePointManager.DefaultConnectionLimit = 16;
            listener = new UdpClient(new IPEndPoint(IPAddress.Loopback, 53));
            // Ready only after the socket is successfully bound. If port 53 is in use, fail closed.
            File.WriteAllText(readyFile, "ready");
            WriteLog("Listening on 127.0.0.1:53 (Discord-only; encrypted DNS upstream)");
            while (true) {
                IPEndPoint remote = new IPEndPoint(IPAddress.Loopback, 0);
                byte[] packet = listener.Receive(ref remote);
                if (Interlocked.Increment(ref inFlight) > 24) {
                    Interlocked.Decrement(ref inFlight);
                    // Return a DNS response instead of silently dropping queries
                    // when the bounded DoH worker pool is saturated.
                    int questionEnd;
                    if (QueryDomain(packet, out questionEnd) != null) {
                        byte[] busy = Failure(packet, questionEnd, 2); // SERVFAIL
                        if (busy != null) {
                            lock (SendGate) { listener.Send(busy, busy.Length, remote); }
                        }
                    }
                    continue;
                }
                IPEndPoint replyTo = remote;
                ThreadPool.QueueUserWorkItem(delegate(object state) {
                    try { Reply(packet, replyTo); }
                    catch (Exception ex) { WriteLog("Request error: " + ex.Message); }
                    finally { Interlocked.Decrement(ref inFlight); }
                });
            }
        }
        private static void Reply(byte[] packet, IPEndPoint remote) {
            int questionEnd;
            string name = QueryDomain(packet, out questionEnd);
            if (name == null) return;
            byte[] response;
            if (!Allowed(name)) {
                response = Failure(packet, questionEnd, 5); // REFUSED: never a general DNS proxy
            } else {
                response = Forward(packet);
                if (response == null) response = Failure(packet, questionEnd, 2); // SERVFAIL
            }
            if (response == null || response.Length > 65507) return;
            lock (SendGate) { listener.Send(response, response.Length, remote); }
        }
        private static string QueryDomain(byte[] packet, out int questionEnd) {
            questionEnd = 0;
            if (packet == null || packet.Length < 17 || packet.Length > 4096 ||
                (packet[2] & 0x80) != 0 || packet[4] != 0 || packet[5] != 1) return null;
            int pos = 12;
            var labels = new System.Collections.Generic.List<string>();
            while (pos < packet.Length) {
                int len = packet[pos++];
                if (len == 0) break;
                // Compression pointers are not expected in client queries; reject malformed DNS.
                if (len > 63 || pos + len > packet.Length) return null;
                for (int j = 0; j < len; j++) {
                    byte b = packet[pos + j];
                    if (!((b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') ||
                          (b >= '0' && b <= '9') || b == '-' || b == '_')) return null;
                }
                labels.Add(Encoding.ASCII.GetString(packet, pos, len));
                pos += len;
                if (pos > 254) return null;
            }
            if (labels.Count == 0 || pos + 4 > packet.Length || packet[pos - 1] != 0) return null;
            questionEnd = pos + 4;
            return string.Join(".", labels.ToArray()).ToLowerInvariant();
        }
        private static bool Allowed(string domain) {
            foreach (string suffix in Domains)
                if (domain == suffix || domain.EndsWith("." + suffix, StringComparison.Ordinal)) return true;
            return false;
        }
        private static byte[] Forward(byte[] dnsQuery) {
            foreach (string endpoint in DohEndpoints) {
                try {
                    HttpWebRequest request = (HttpWebRequest)WebRequest.Create(endpoint);
                    request.Method = "POST";
                    request.ContentType = "application/dns-message";
                    request.Accept = "application/dns-message";
                    request.ContentLength = dnsQuery.Length;
                    request.Timeout = 2700;
                    request.ReadWriteTimeout = 2700;
                    request.Proxy = null;
                    request.KeepAlive = true;
                    using (Stream body = request.GetRequestStream()) body.Write(dnsQuery, 0, dnsQuery.Length);
                    using (HttpWebResponse response = (HttpWebResponse)request.GetResponse()) {
                        if (response.StatusCode != HttpStatusCode.OK) continue;
                        using (Stream stream = response.GetResponseStream())
                        using (MemoryStream buffer = new MemoryStream()) {
                            stream.CopyTo(buffer);
                            byte[] result = buffer.ToArray();
                            if (result.Length < 12) continue;
                            // Restore transaction ID so the Windows DNS client can match replies.
                            result[0] = dnsQuery[0]; result[1] = dnsQuery[1];
                            return result;
                        }
                    }
                } catch (Exception ex) { WriteLog("DoH " + endpoint + ": " + ex.Message); }
            }
            return null;
        }
        private static byte[] Failure(byte[] q, int questionEnd, int rcode) {
            if (questionEnd < 17 || questionEnd > q.Length) return null;
            byte[] reply = new byte[questionEnd];
            Array.Copy(q, reply, questionEnd);
            reply[2] = (byte)(0x80 | (q[2] & 1));
            reply[3] = (byte)(0x80 | rcode);
            for (int i=6;i<=11;i++) reply[i] = 0;
            return reply;
        }
        private static void WriteLog(string message) {
            try { lock (LogGate) File.AppendAllText(logFile,
                "[" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "] " + message + Environment.NewLine); }
            catch { }
        }
    }
}
