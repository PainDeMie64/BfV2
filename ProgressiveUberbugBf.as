namespace ProgressiveUberbugBf
{
    const string TARGET_ID = "progressive_uberbug";
    const string VAR_TIME_FROM = "progressive_uberbug_bf_time_from";
    const string VAR_TIME_TO = "progressive_uberbug_bf_time_to";
    const string VAR_MIN_GAIN = "progressive_uberbug_min_score_gain";

    class ScoreSnapshot
    {
        float score = 0.0f;
        float inward = 0.0f;
        float tangent = 0.0f;
        float exponent = 0.0f;
        float correction = 0.0f;
        float contact = 0.0f;
        float correctionMagnitude = 0.0f;
        float forceToDvEstimate = 0.0f;
        float centralForceMax = 0.0f;
        int raceMs = -1;
        int rawRaceMs = -1;
        int raceOffsetMs = 2600;
        int offsetValid = 0;
        bool hasSample = false;
        string reason = "No sample";
        string stage = "";
    }

    int timeFrom = 0;
    int timeTo = 0;
    float minScoreGain = 0.02f;
    float minScoreGainPercent = 2.0f;
    ScoreSnapshot baselineBest;
    ScoreSnapshot globalBest;
    ScoreSnapshot candidateBest;
    uint lastSearchIteration = 4294967295;
    bool baselineSummaryPrinted = false;
    bool bridgeStopPrinted = false;
    string lastPrintedStatus = "";
    float lastPrintedNearMissScore = -1.0f;

    void Main()
    {
        RegisterVariable(VAR_TIME_FROM, 0);
        RegisterVariable(VAR_TIME_TO, 0);
        RegisterVariable(VAR_MIN_GAIN, 2.0);
        auto eval = RegisterBruteforceEval(TARGET_ID, "Progressive uberbug", OnEvaluate, RenderSettings);
        @eval.onSimBegin = @OnSimulationBegin;
    }

    void OnSimulationBegin(SimulationManager @simManager)
    {
        RefreshSettings();
        PhysicsBridge::BeginRun("run", timeFrom, timeTo, simManager.RaceTime);
        ResetScores();
    }

    void RenderSettings()
    {
        UI::PushStyleColor(UI::Col::Text, vec4(1, 0, 0, 1));
        UI::TextWrapped("THIS TARGET REQUIRES THE TMPHYSICSBRIDGE MOD AND IS INCOMPATIBLE WITH KIMMOD.");
        UI::PopStyleColor();
        UI::Dummy(vec2(0, 8));
        UI::Text("Time frame");
        UI::InputTimeVar("From", VAR_TIME_FROM);
        UI::InputTimeVar("To", VAR_TIME_TO);
        UI::Dummy(vec2(0, 8));
        UI::SliderFloatVar("Minimum score gain", VAR_MIN_GAIN, 0.0f, 100.0f, "%.1f%%");
        toolTip(420, {"Required percentage-point increase over the current best uberbug likeliness.",
            "Example: current best 64.0%, gain 2.0%, accepts at 66.0% or higher."});
    }

    BFEvaluationResponse@ OnEvaluate(SimulationManager @simManager, const BFEvaluationInfo &in info)
    {
        RefreshSettings();

        auto resp = BFEvaluationResponse();
        resp.Decision = BFEvaluationDecision::DoNothing;

        int raceTime = simManager.RaceTime;
        bool inWindow = raceTime >= timeFrom && raceTime <= timeTo;
        bool pastWindow = raceTime > timeTo;
        bool conditionsMet = GlobalConditionsMet(simManager);
        PhysicsBridge::PollFast();
        if (!PhysicsBridge::IsReady())
            return StopMissingBridge();

        if (info.Phase == BFPhase::Initial)
        {
            if (inWindow)
            {
                ScoreSnapshot score = ScoreAtRaceTime(raceTime);
                if (conditionsMet && IsBetterScore(score, baselineBest))
                {
                    baselineBest = score;
                    globalBest = score;
                }
            }
            else if (pastWindow && !baselineSummaryPrinted)
            {
                ScoreSnapshot finalScore = ScoreAtRaceTime(timeTo);
                if (conditionsMet && IsBetterScore(finalScore, baselineBest))
                {
                    baselineBest = finalScore;
                    globalBest = finalScore;
                }
                baselineSummaryPrinted = true;
                if (baselineBest.hasSample)
                    PrintRuntime("Base run: " + FormatLikeliness(baselineBest));
                else
                    PrintRuntimeOnce("Base run: no bridge sample");
            }
            return resp;
        }

        if (info.Phase == BFPhase::Search)
        {
            if (info.Rewinded || info.Iterations != lastSearchIteration)
            {
                PhysicsBridge::BeginRun("search", timeFrom, timeTo, raceTime);
                candidateBest = ScoreSnapshot();
                lastSearchIteration = info.Iterations;
            }

            if (inWindow)
            {
                ScoreSnapshot score = ScoreAtRaceTime(raceTime);
                if (conditionsMet && IsBetterScore(score, candidateBest))
                {
                    candidateBest = score;
                }

                if (conditionsMet && candidateBest.score >= globalBest.score + minScoreGain)
                {
                    globalBest = candidateBest;
                    resp.Decision = BFEvaluationDecision::Accept;
                    resp.ResultFileStartContent = FormatAccepted(candidateBest);
                    PrintRuntime(FormatAccepted(candidateBest));
                    return resp;
                }
            }
            else if (pastWindow)
            {
                ScoreSnapshot finalScore = ScoreAtRaceTime(timeTo);
                if (conditionsMet && IsBetterScore(finalScore, candidateBest))
                {
                    candidateBest = finalScore;
                }
                if (conditionsMet && candidateBest.score >= globalBest.score + minScoreGain)
                {
                    globalBest = candidateBest;
                    resp.Decision = BFEvaluationDecision::Accept;
                    resp.ResultFileStartContent = FormatAccepted(candidateBest);
                    PrintRuntime(FormatAccepted(candidateBest));
                    return resp;
                }
                resp.Decision = BFEvaluationDecision::Reject;
                if (candidateBest.hasSample &&
                    candidateBest.score > globalBest.score &&
                    candidateBest.score > lastPrintedNearMissScore + 0.01f)
                {
                    lastPrintedNearMissScore = candidateBest.score;
                    PrintRuntime("Near miss: " + FormatLikeliness(candidateBest));
                }
            }
        }

        return resp;
    }

    void RefreshSettings()
    {
        timeFrom = int(GetVariableDouble(VAR_TIME_FROM));
        timeTo = int(GetVariableDouble(VAR_TIME_TO));
        if (timeTo < timeFrom)
            timeTo = timeFrom;
        minScoreGainPercent = Clamp(float(GetVariableDouble(VAR_MIN_GAIN)), 0.0f, 100.0f);
        minScoreGain = minScoreGainPercent / 100.0f;
    }

    void ResetScores()
    {
        baselineBest = ScoreSnapshot();
        globalBest = ScoreSnapshot();
        candidateBest = ScoreSnapshot();
        lastSearchIteration = 4294967295;
        baselineSummaryPrinted = false;
        bridgeStopPrinted = false;
        lastPrintedStatus = "";
        lastPrintedNearMissScore = -1.0f;
        PrintRuntime("Started. Window " + Time::Format(timeFrom) + " to " + Time::Format(timeTo) +
            ", minimum score gain " + Text::FormatFloat(minScoreGainPercent, "", 0, 1) + "%.");
    }

    BFEvaluationResponse@ StopMissingBridge()
    {
        auto resp = BFEvaluationResponse();
        resp.Decision = BFEvaluationDecision::Stop;
        resp.ResultFileStartContent = "# Progressive uberbug stopped: TMPhysicsBridge mod is not connected.";
        if (!bridgeStopPrinted)
        {
            bridgeStopPrinted = true;
            PrintRuntime("Stopped: TMPhysicsBridge mod is not connected. This target is incompatible with KimMod.");
        }
        return resp;
    }

    ScoreSnapshot ScoreAtRaceTime(int raceTime)
    {
        PhysicsBridge::BridgeSample@ sample = null;
        if (!PhysicsBridge::FindSampleExactOrNear(raceTime, sample, 20))
        {
            ScoreSnapshot missing;
            missing.reason = "No fresh bridge sample";
            missing.raceMs = raceTime;
            return missing;
        }
        ScoreSnapshot score = ScoreSample(sample);
        return score;
    }

    ScoreSnapshot ScoreSample(PhysicsBridge::BridgeSample@ sample)
    {
        ScoreSnapshot outScore;
        outScore.hasSample = true;
        outScore.raceMs = sample.raceMs;
        outScore.rawRaceMs = sample.rawRaceMs;
        outScore.raceOffsetMs = sample.raceOffsetMs;
        outScore.offsetValid = sample.offsetValid;
        outScore.stage = sample.stage;
        outScore.correctionMagnitude = sample.burnoutCorrectionMagnitude;
        outScore.forceToDvEstimate = sample.forceToDvEstimate;
        outScore.centralForceMax = sample.centralForceMax;

        if (sample.scoreProduct > 0.0f)
        {
            outScore.contact = sample.scoreContact;
            outScore.inward = sample.scoreInward;
            outScore.tangent = sample.scoreTangent;
            outScore.exponent = sample.scoreExponent;
            outScore.correction = sample.scoreCorrection;
            outScore.score = float(Math::Pow(sample.scoreProduct, 0.2f));
            outScore.reason = "Ready";
            return outScore;
        }

        if (sample.burnoutValid == 0)
        {
            outScore.reason = "Burnout math not valid";
            return outScore;
        }
        if (sample.wheelContacts <= 0)
        {
            outScore.reason = "No wheel contact";
            return outScore;
        }
        if (sample.bodyContacts != 0)
        {
            outScore.reason = "Body contact present";
            return outScore;
        }
        if (sample.lateralSlowdown != 0)
        {
            outScore.reason = "Lateral slowdown contact present";
            return outScore;
        }

        outScore.contact = 1.0f;
        outScore.inward = Clamp01((-sample.burnoutRadialSpeed - 5.0f) / 25.0f);
        outScore.tangent = Clamp01((Math::Abs(sample.burnoutTangentSpeed) - 20.0f) / 60.0f);
        outScore.exponent = Clamp01((sample.burnoutExponent - 1.0f) / 5.0f);
        outScore.correction = Clamp01((Log10Approx(MaxFloat(1.0f, sample.burnoutCorrectionMagnitude)) - 3.0f) / 2.0f);

        float product = outScore.contact * outScore.inward * outScore.tangent * outScore.exponent * outScore.correction;
        outScore.score = product <= 0.0f ? 0.0f : float(Math::Pow(product, 0.2f));
        outScore.reason = outScore.score > 0.0f ? "Ready" : "One score component is zero";
        return outScore;
    }

    bool IsBetterScore(const ScoreSnapshot &in candidate, const ScoreSnapshot &in current)
    {
        if (!candidate.hasSample)
            return false;
        if (!current.hasSample)
            return true;
        if (candidate.score > current.score + 0.005f)
            return true;
        if (Math::Abs(candidate.score - current.score) > 0.005f)
            return false;
        if (candidate.correctionMagnitude > current.correctionMagnitude)
            return true;
        if (candidate.correctionMagnitude < current.correctionMagnitude)
            return false;
        if (candidate.forceToDvEstimate > current.forceToDvEstimate)
            return true;
        if (candidate.forceToDvEstimate < current.forceToDvEstimate)
            return false;
        return candidate.centralForceMax > current.centralForceMax;
    }

    float Clamp01(float v)
    {
        return Clamp(v, 0.0f, 1.0f);
    }

    float Clamp(float v, float lo, float hi)
    {
        if (v < lo) return lo;
        if (v > hi) return hi;
        return v;
    }

    float MaxFloat(float a, float b)
    {
        return a > b ? a : b;
    }

    float Log10Approx(float value)
    {
        if (value <= 0.0f)
            return 0.0f;

        float scaled = value;
        float exponent = 0.0f;
        while (scaled >= 10.0f)
        {
            scaled /= 10.0f;
            exponent += 1.0f;
        }
        while (scaled < 1.0f)
        {
            scaled *= 10.0f;
            exponent -= 1.0f;
        }

        float y = (scaled - 1.0f) / (scaled + 1.0f);
        float y2 = y * y;
        float term = y;
        float ln = 0.0f;
        for (int denom = 1; denom <= 31; denom += 2)
        {
            ln += term / float(denom);
            term *= y2;
        }
        ln *= 2.0f;
        return exponent + ln / 2.302585093f;
    }

    string FormatScore(const ScoreSnapshot &in score)
    {
        if (!score.hasSample)
            return "none";
        return Text::FormatFloat(score.score, "", 0, 3) +
            " at " + Text::FormatInt(score.raceMs) + " ms" +
            " raw " + Text::FormatInt(score.rawRaceMs) + " ms" +
            " offset " + Text::FormatInt(score.raceOffsetMs) +
            (score.offsetValid != 0 ? "" : " fallback") +
            " (" + score.reason + ", stage " + score.stage +
            ", inward " + Text::FormatFloat(score.inward, "", 0, 3) +
            ", tangent " + Text::FormatFloat(score.tangent, "", 0, 3) +
            ", exponent " + Text::FormatFloat(score.exponent, "", 0, 3) +
            ", correction " + Text::FormatFloat(score.correction, "", 0, 3) +
            ", correction mag " + Text::FormatFloat(score.correctionMagnitude, "", 0, 3) +
            ", force dv est " + Text::FormatFloat(score.forceToDvEstimate, "", 0, 3) +
            ", central force " + Text::FormatFloat(score.centralForceMax, "", 0, 3) + ")";
    }

    string FormatLikeliness(const ScoreSnapshot &in score)
    {
        return Text::FormatFloat(score.score * 100.0f, "", 0, 1) +
            "% uberbug likeliness at " + Text::FormatInt(score.raceMs) + " ms";
    }

    string FormatAccepted(const ScoreSnapshot &in score)
    {
        return "Improvement: " + FormatLikeliness(score);
    }

    void PrintRuntime(const string &in message)
    {
        print(message);
    }

    void PrintRuntimeOnce(const string &in message)
    {
        if (message == lastPrintedStatus)
            return;
        lastPrintedStatus = message;
        PrintRuntime(message);
    }

}
