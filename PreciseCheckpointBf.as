namespace PreciseCheckpointBf
{
    int targetCp;
    double bestTime = -1;
    int bestTimeMsImprecise = -1;
    bool conditionsMetBeforeCompute = false;
    bool set = false;
    void RenderEvalSettings()
    {
        targetCp = UI::InputIntVar("Target Checkpoint Index", "bf_target_cp");
    }
    BFEvaluationResponse @OnEvaluate(SimulationManager @simManager, const BFEvaluationInfo &in info)
    {
        int raceTime = simManager.RaceTime;
        auto resp = BFEvaluationResponse();
        resp.Decision = BFEvaluationDecision::DoNothing;
        bool hasCp = int(simManager.PlayerInfo.CurCheckpointCount) >= targetCp;
        if (info.Phase == BFPhase::Search && !PreciseFinish::IsEstimating && bestTimeMsImprecise != -1)
        {
            if (hasCp && raceTime < bestTimeMsImprecise)
            {
                if (GlobalConditionsMet(simManager))
                {
                    resp.Decision = BFEvaluationDecision::Accept;
                }
                else
                {
                    resp.Decision = BFEvaluationDecision::Reject;
                }
                PreciseFinish::Reset();
                return resp;
            }
            if (raceTime > bestTimeMsImprecise + 50)
            {
                resp.Decision = BFEvaluationDecision::Reject;
                PreciseFinish::Reset();
                return resp;
            }
        }
        double preciseTime;
        if (hasCp && !PreciseFinish::IsEstimating)
        {
            conditionsMetBeforeCompute = GlobalConditionsMet(simManager);
        }
        bool calculationDone = PreciseFinish::Compute(simManager, hasCp, preciseTime);
        if (!calculationDone)
        {
            return resp;
        }
        if (!conditionsMetBeforeCompute)
        {
            if (info.Phase == BFPhase::Initial)
            {
                print("Base run hit checkpoint but conditions not met. Search will require meeting these conditions.", Severity::Warning);
            }
            else
            {
                resp.Decision = BFEvaluationDecision::Reject;
                PreciseFinish::Reset();
                return resp;
            }
        }
        if (info.Phase == BFPhase::Initial && !set)
        {
            if (bestTime != -1 && preciseTime >= bestTime + 1e-7)
            {
                resp.Decision = BFEvaluationDecision::Reject;
                PreciseFinish::Reset();
                return resp;
            }
            if (bestTime != -1)
                print("Precise checkpoint time: " + Text::FormatFloat(preciseTime, "", 0, 9));
            else
                print("Base run checkpoint time: " + Text::FormatFloat(preciseTime, "", 0, 9));
            bestTime = preciseTime;
            bestTimeMsImprecise = PreciseFinish::StateBeforeHitTime;
            resp.Decision = BFEvaluationDecision::Accept;
            resp.ResultFileStartContent = "# Precise Checkpoint Time: " + Text::FormatFloat(bestTime, "", 0, 9) + " s";
            set = true;
        }
        else
        {
            double scaled = preciseTime * 10000.0;
            double frac = scaled - int64(scaled);
            if (frac < 0) frac = -frac;
            if (frac < 1e-5 || frac > (1.0 - 1e-5))
            {
                resp.Decision = BFEvaluationDecision::Reject;
                PreciseFinish::Reset();
                return resp;
            }
            if (preciseTime < bestTime)
            {
                bestTime = preciseTime;
                bestTimeMsImprecise = PreciseFinish::StateBeforeHitTime;
                resp.Decision = BFEvaluationDecision::Accept;
                resp.ResultFileStartContent = "# Precise Checkpoint Time: " + Text::FormatFloat(bestTime, "", 0, 9) + " s";
                set = false;
            }
            else
            {
                resp.Decision = BFEvaluationDecision::Reject;
            }
        }
        PreciseFinish::Reset();
        return resp;
    }
    void OnSimulationBegin(SimulationManager @simManager)
    {
        PreciseFinish::Reset();
        bestTime = -1;
        bestTimeMsImprecise = -1;
        targetCp = int(GetVariableDouble("bf_target_cp"));
        set = false;
    }
    void Main()
    {
        auto bfEval = RegisterBruteforceEval("precisecheckpoint", "Checkpoint", OnEvaluate, RenderEvalSettings);
        @bfEval.onSimBegin = @OnSimulationBegin;
    }
}
