namespace PhysicsBridge
{
    const uint16 PORT_FIRST = 39870;
    const uint16 PORT_LAST = 39879;
    const uint MAX_BUFFER_SIZE = 65536;
    const uint MAX_LINE_SIZE = 2048;
    const uint MAX_SAMPLES = 4096;

    class BridgeSample
    {
        bool valid = false;
        uint seq = 0;
        uint run = 0;
        int raceMs = -1;
        int rawRaceMs = -1;
        int raceOffsetMs = 2600;
        int offsetValid = 0;
        int tickMs = -1;
        string stage = "";
        string hookStatus = "";
        uint dropped = 0;
        float scoreProduct = 0.0f;
        float scoreInward = 0.0f;
        float scoreTangent = 0.0f;
        float scoreExponent = 0.0f;
        float scoreCorrection = 0.0f;
        float scoreContact = 0.0f;
        float speed = 0.0f;
        float deltaSpeed = 0.0f;
        int wheelContacts = 0;
        int bodyContacts = 0;
        int lateralSlowdown = 0;
        int replacementCount = 0;
        vec3 contactNormalAvg = vec3();
        vec3 contactPointLast = vec3();
        vec3 replacementTotal = vec3();
        float replacementMax = 0.0f;
        vec3 impulseTotal = vec3();
        float centralForceMax = 0.0f;
        float forceToDvEstimate = 0.0f;
        int model6State = 0;
        int burnoutValid = 0;
        vec3 burnoutCenter = vec3();
        vec3 burnoutNormal = vec3();
        float burnoutRadius = 0.0f;
        float burnoutTargetRadius = 0.0f;
        float burnoutBaseRadius = 0.0f;
        float burnoutRadialSpeed = 0.0f;
        float burnoutTangentSpeed = 0.0f;
        float burnoutTangentialTerm = 0.0f;
        float burnoutExponent = 0.0f;
        float burnoutCorrectionMagnitude = 0.0f;
        int burnoutFlags = 0;
    }

    Net::Socket@ listenSock = null;
    Net::Socket@ clientSock = null;
    uint16 listenPort = 0;
    string buffer = "";
    bool connected = false;
    uint parseErrors = 0;
    uint latestSeq = 0;
    uint activeRun = 0;
    uint runCounter = 0;
    int latestRaceMs = -1;
    int latestRawRaceMs = -1;
    int latestRaceOffsetMs = 2600;
    int offsetValid = 0;
    string hookStatus = "";
    string hookSeen = "";
    uint dropped = 0;
    uint eventSeq = 0;
    uint eventsSeen = 0;
    uint validEvents = 0;
    uint invalidEvents = 0;
    uint samplesSent = 0;
    uint commandsSeen = 0;
    uint sampleCount = 0;
    uint64 lastReadTime = 0;
    string lastError = "Not started";
    string pendingControlLine = "";
    BridgeSample@ latestBestSample = null;
    array<BridgeSample@> sampleSlots;

    void Start()
    {
        if (sampleSlots.Length != MAX_SAMPLES)
            sampleSlots.Resize(MAX_SAMPLES);
        if (@listenSock !is null)
            return;

        @clientSock = null;
        buffer = "";
        connected = false;
        listenPort = 0;
        lastReadTime = 0;
        lastError = "No free bridge port";

        for (uint16 p = PORT_FIRST; p <= PORT_LAST; p++)
        {
            Net::Socket@ sock = Net::Socket();
            if (sock.Listen("127.0.0.1", p))
            {
                @listenSock = sock;
                listenPort = p;
                lastError = "";
                return;
            }
        }
    }

    void Stop()
    {
        @clientSock = null;
        @listenSock = null;
        buffer = "";
        connected = false;
        listenPort = 0;
        lastError = "Stopped";
    }

    void ClearSamples()
    {
        if (sampleSlots.Length != MAX_SAMPLES)
            sampleSlots.Resize(MAX_SAMPLES);
        for (uint i = 0; i < sampleSlots.Length; i++)
            @sampleSlots[i] = null;
        sampleCount = 0;
        latestRaceMs = -1;
        latestRawRaceMs = -1;
        @latestBestSample = null;
    }

    uint BeginRun(const string &in phase, int windowFrom, int windowTo, int simRaceMs)
    {
        Start();
        ClearSamples();
        runCounter++;
        if (runCounter == 0)
            runCounter++;
        activeRun = runCounter;

        pendingControlLine = "TPB1|kind=control|run=" + Text::FormatUInt(activeRun) +
            "|phase=" + phase +
            "|windowFrom=" + Text::FormatInt(windowFrom) +
            "|windowTo=" + Text::FormatInt(windowTo) +
            "|simRaceMs=" + Text::FormatInt(simRaceMs) + "\n";

        PollFast();
        SendPendingControl();
        PollFast();
        return activeRun;
    }

    void PollFast()
    {
        Poll();
    }

    uint PollForRace(int raceMs)
    {
        PollFast();
        return activeRun;
    }

    uint PollForRaceEx(int raceMs, bool wantSample)
    {
        PollFast();
        return activeRun;
    }

    void Poll()
    {
        if (@listenSock is null)
            Start();
        if (@listenSock is null)
            return;

        if (@clientSock is null)
        {
            Net::Socket@ newSock = listenSock.Accept(0);
            if (@newSock !is null)
            {
                @clientSock = newSock;
                buffer = "";
                connected = true;
                lastReadTime = Time::Now;
                lastError = "";
                SendPendingControl();
            }
            return;
        }

        uint avail = clientSock.Available;
        if (avail == 0)
        {
            if (lastReadTime != 0 && Time::Now - lastReadTime > 5000)
            {
                @clientSock = null;
                connected = false;
                buffer = "";
                lastError = "Bridge socket idle timeout";
            }
            return;
        }

        uint toRead = avail;
        if (buffer.Length + avail > MAX_BUFFER_SIZE)
            toRead = MAX_BUFFER_SIZE - buffer.Length;

        if (toRead > 0)
        {
            buffer += clientSock.ReadString(toRead);
            lastReadTime = Time::Now;
        }

        if (buffer.Length >= MAX_BUFFER_SIZE)
        {
            @clientSock = null;
            connected = false;
            buffer = "";
            lastError = "Bridge buffer overflow";
            return;
        }

        int newline = buffer.FindFirst("\n");
        while (newline >= 0)
        {
            string line = buffer.Substr(0, newline);
            if (line.Length > 0 && line.Substr(line.Length - 1, 1) == "\r")
                line = line.Substr(0, line.Length - 1);
            buffer = buffer.Substr(uint(newline + 1));
            if (line.Length <= MAX_LINE_SIZE)
                ParseLine(line);
            else
                parseErrors++;
            newline = buffer.FindFirst("\n");
        }
    }

    void SendPendingControl()
    {
        if (@clientSock is null || pendingControlLine == "")
            return;
        clientSock.Write(pendingControlLine);
    }

    string StatusText()
    {
        if (@listenSock is null)
            return "Physics bridge: debug only, ignore unless broken; " + lastError;
        string s = "Physics bridge: debug only, ignore unless broken; listening " + Text::FormatUInt(listenPort);
        s += connected ? ", connected" : ", disconnected";
        if (latestRaceMs >= 0)
            s += ", sample " + Text::FormatInt(latestRaceMs) + " ms";
        if (latestRawRaceMs >= 0)
            s += ", raw " + Text::FormatInt(latestRawRaceMs) + " ms";
        s += ", offset " + Text::FormatInt(latestRaceOffsetMs);
        if (offsetValid == 0)
            s += " fallback";
        s += ", cached " + Text::FormatUInt(sampleCount);
        if (hookStatus != "")
            s += ", hooks " + hookStatus;
        if (hookSeen != "")
            s += ", seen " + hookSeen;
        s += ", run " + Text::FormatUInt(activeRun) +
            ", events " + Text::FormatUInt(eventsSeen) +
            ", valid " + Text::FormatUInt(validEvents) +
            ", sent " + Text::FormatUInt(samplesSent) +
            ", commands " + Text::FormatUInt(commandsSeen);
        if (eventSeq > 0)
            s += ", eventSeq " + Text::FormatUInt(eventSeq);
        if (dropped > 0)
            s += ", dropped " + Text::FormatUInt(dropped);
        if (parseErrors > 0)
            s += ", parse errors " + Text::FormatUInt(parseErrors);
        if (lastError != "")
            s += ", " + lastError;
        return s;
    }

    bool FindSampleExactOrNear(int raceMs, BridgeSample@ &out sample, int maxAgeMs = 20)
    {
        @sample = null;
        if (FindSampleExact(raceMs, sample))
            return true;
        for (int d = 1; d <= maxAgeMs; d++)
        {
            BridgeSample@ a = null;
            BridgeSample@ b = null;
            bool haveA = FindSampleExact(raceMs - d, a);
            bool haveB = FindSampleExact(raceMs + d, b);
            if (haveA && (!haveB || a.seq >= b.seq))
            {
                @sample = a;
                return true;
            }
            if (haveB)
            {
                @sample = b;
                return true;
            }
        }
        if (latestBestSample !is null && latestBestSample.valid)
        {
            @sample = latestBestSample;
            return true;
        }
        return false;
    }

    bool FindSampleExact(int raceMs, BridgeSample@ &out sample)
    {
        @sample = null;
        if (raceMs < 0 || sampleSlots.Length != MAX_SAMPLES)
            return false;
        uint index = uint(raceMs) % MAX_SAMPLES;
        BridgeSample@ s = sampleSlots[index];
        if (s is null || !s.valid || s.raceMs != raceMs)
            return false;
        @sample = s;
        return true;
    }

    void ParseLine(const string &in rawLine)
    {
        if (rawLine.Length < 5 || rawLine.Substr(0, 5) != "TPB1|")
            return;

        array<string>@ parts = rawLine.Split("|");
        string kind = "";
        BridgeSample@ sample = BridgeSample();

        for (uint i = 1; i < parts.Length; i++)
        {
            int eq = parts[i].FindFirst("=");
            if (eq <= 0)
                continue;
            string key = parts[i].Substr(0, eq);
            string value = parts[i].Substr(uint(eq + 1));
            if (key == "kind") kind = value;
            else if (key == "seq") { sample.seq = uint(Text::ParseInt(value)); latestSeq = sample.seq; }
            else if (key == "run") sample.run = uint(Text::ParseInt(value));
            else if (key == "raceMs") sample.raceMs = int(Text::ParseInt(value));
            else if (key == "rawRaceMs") sample.rawRaceMs = int(Text::ParseInt(value));
            else if (key == "raceOffsetMs") sample.raceOffsetMs = int(Text::ParseInt(value));
            else if (key == "offsetValid") sample.offsetValid = int(Text::ParseInt(value));
            else if (key == "tickMs") sample.tickMs = int(Text::ParseInt(value));
            else if (key == "stage") sample.stage = value;
            else if (key == "scoreProduct") sample.scoreProduct = float(Text::ParseFloat(value));
            else if (key == "scoreInward") sample.scoreInward = float(Text::ParseFloat(value));
            else if (key == "scoreTangent") sample.scoreTangent = float(Text::ParseFloat(value));
            else if (key == "scoreExponent") sample.scoreExponent = float(Text::ParseFloat(value));
            else if (key == "scoreCorrection") sample.scoreCorrection = float(Text::ParseFloat(value));
            else if (key == "scoreContact") sample.scoreContact = float(Text::ParseFloat(value));
            else if (key == "hookStatus") { sample.hookStatus = value; hookStatus = value; }
            else if (key == "hookSeen") hookSeen = value;
            else if (key == "dropped") { sample.dropped = uint(Text::ParseInt(value)); dropped = sample.dropped; }
            else if (key == "eventSeq") eventSeq = uint(Text::ParseInt(value));
            else if (key == "events") eventsSeen = uint(Text::ParseInt(value));
            else if (key == "valid") validEvents = uint(Text::ParseInt(value));
            else if (key == "invalid") invalidEvents = uint(Text::ParseInt(value));
            else if (key == "samplesSent") samplesSent = uint(Text::ParseInt(value));
            else if (key == "commands") commandsSeen = uint(Text::ParseInt(value));
            else if (key == "speed") sample.speed = float(Text::ParseFloat(value));
            else if (key == "deltaSpeed") sample.deltaSpeed = float(Text::ParseFloat(value));
            else if (key == "wheelContacts") sample.wheelContacts = int(Text::ParseInt(value));
            else if (key == "bodyContacts") sample.bodyContacts = int(Text::ParseInt(value));
            else if (key == "lateralSlowdown") sample.lateralSlowdown = int(Text::ParseInt(value));
            else if (key == "replacementCount") sample.replacementCount = int(Text::ParseInt(value));
            else if (key == "contactNormalAvg") sample.contactNormalAvg = ParseVec3(value);
            else if (key == "contactPointLast") sample.contactPointLast = ParseVec3(value);
            else if (key == "replacementTotal") sample.replacementTotal = ParseVec3(value);
            else if (key == "replacementMax") sample.replacementMax = float(Text::ParseFloat(value));
            else if (key == "impulseTotal") sample.impulseTotal = ParseVec3(value);
            else if (key == "centralForceMax") sample.centralForceMax = float(Text::ParseFloat(value));
            else if (key == "forceToDvEstimate") sample.forceToDvEstimate = float(Text::ParseFloat(value));
            else if (key == "model6State") sample.model6State = int(Text::ParseInt(value));
            else if (key == "burnoutValid") sample.burnoutValid = int(Text::ParseInt(value));
            else if (key == "burnoutCenter") sample.burnoutCenter = ParseVec3(value);
            else if (key == "burnoutNormal") sample.burnoutNormal = ParseVec3(value);
            else if (key == "burnoutRadius") sample.burnoutRadius = float(Text::ParseFloat(value));
            else if (key == "burnoutTargetRadius") sample.burnoutTargetRadius = float(Text::ParseFloat(value));
            else if (key == "burnoutBaseRadius") sample.burnoutBaseRadius = float(Text::ParseFloat(value));
            else if (key == "burnoutRadialSpeed") sample.burnoutRadialSpeed = float(Text::ParseFloat(value));
            else if (key == "burnoutTangentSpeed") sample.burnoutTangentSpeed = float(Text::ParseFloat(value));
            else if (key == "burnoutTangentialTerm") sample.burnoutTangentialTerm = float(Text::ParseFloat(value));
            else if (key == "burnoutExponent") sample.burnoutExponent = float(Text::ParseFloat(value));
            else if (key == "burnoutCorrectionMagnitude") sample.burnoutCorrectionMagnitude = float(Text::ParseFloat(value));
            else if (key == "burnoutFlags") sample.burnoutFlags = int(Text::ParseInt(value));
        }

        if (kind == "hello" || kind == "status")
        {
            connected = true;
            lastError = "";
            if (sample.raceOffsetMs > 0)
                latestRaceOffsetMs = sample.raceOffsetMs;
            if (sample.offsetValid != 0)
                offsetValid = sample.offsetValid;
            return;
        }

        if (kind != "sample")
        {
            parseErrors++;
            return;
        }

        if (activeRun != 0 && sample.run != 0 && sample.run != activeRun)
            return;
        if (sample.raceMs < 0)
        {
            parseErrors++;
            return;
        }

        sample.valid = true;
        latestRaceMs = sample.raceMs;
        latestRawRaceMs = sample.rawRaceMs;
        latestRaceOffsetMs = sample.raceOffsetMs;
        offsetValid = sample.offsetValid;

        uint index = uint(sample.raceMs) % MAX_SAMPLES;
        if (sampleSlots[index] is null)
            sampleCount++;
        @sampleSlots[index] = sample;
        if (latestBestSample is null || sample.scoreProduct >= latestBestSample.scoreProduct)
            @latestBestSample = sample;
    }

    vec3 ParseVec3(const string &in value)
    {
        array<string>@ parts = value.Split(",");
        if (parts.Length < 3)
            return vec3();
        return vec3(
            float(Text::ParseFloat(parts[0])),
            float(Text::ParseFloat(parts[1])),
            float(Text::ParseFloat(parts[2])));
    }
}
