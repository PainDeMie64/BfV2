namespace InputModification
{
    int cachedStartIndex = -1;
    int cachedMinTime = -1;
    int g_earliestMutationTime = 2147483647;
    int ClampSteer(int value)
    {
        if (value < -65536)
            return -65536;
        if (value > 65536)
            return 65536;
        return value;
    }
    int ClampSteerToRange(int value, int minSteer, int maxSteer)
    {
        value = ClampSteer(value);
        if (value < minSteer)
            return minSteer;
        if (value > maxSteer)
            return maxSteer;
        return value;
    }
    int GetPreviousTickSteer(TM::InputEventBuffer @buffer, int selectedIndex, int finalAbsTime)
    {
        if (buffer is null)
            return 0;
        int previousTickAbsTime = finalAbsTime - 10;
        int previousSteer = 0;
        int previousSteerTime = -1;
        for (uint i = 0; i < buffer.Length; i++)
        {
            if (int(i) == selectedIndex)
                continue;
            auto evt = buffer[i];
            if (evt.Value.EventIndex != buffer.EventIndices.SteerId)
                continue;
            int evtTime = int(evt.Time);
            if (evtTime > previousTickAbsTime)
                continue;
            if (evtTime >= previousSteerTime)
            {
                previousSteer = int(evt.Value.Analog);
                previousSteerTime = evtTime;
            }
        }
        return previousSteer;
    }
    void ApplyRelativeSteerDeltaFrom(TM::InputEventBuffer @buffer, int selectedIndex, int fromAbsTime, int delta)
    {
        if (buffer is null || delta == 0)
            return;
        for (uint i = 0; i < buffer.Length; i++)
        {
            if (int(i) == selectedIndex)
                continue;
            auto evt = buffer[i];
            if (evt.Value.EventIndex != buffer.EventIndices.SteerId)
                continue;
            if (int(evt.Time) < fromAbsTime)
                continue;
            evt.Value.Analog = ClampSteer(int(evt.Value.Analog) + delta);
            buffer[i] = evt;
        }
    }
    void ApplyRelativeSteerDeltaFromRange(TM::InputEventBuffer @buffer, int fromAbsTime, int delta, int minSteer, int maxSteer)
    {
        if (buffer is null)
            return;
        for (uint i = 0; i < buffer.Length; i++)
        {
            auto evt = buffer[i];
            if (evt.Value.EventIndex != buffer.EventIndices.SteerId)
                continue;
            if (int(evt.Time) < fromAbsTime)
                continue;
            evt.Value.Analog = ClampSteerToRange(int(evt.Value.Analog) + delta, minSteer, maxSteer);
            buffer[i] = evt;
        }
    }
    void SortBufferManual(TM::InputEventBuffer @buffer, int startIndex = -1)
    {
        if (buffer is null || buffer.Length < 2)
            return;
        uint startCopy = 0;
        if (startIndex != -1)
        {
            startCopy = startIndex + 1;
        }
        if (startCopy >= buffer.Length)
            return;
        array<TM::InputEvent> events;
        for (uint i = startCopy; i < buffer.Length; i++)
        {
            events.Add(buffer[i]);
        }
        for (uint i = 1; i < events.Length; i++)
        {
            TM::InputEvent key = events[i];
            int j = i - 1;
            while (j >= 0 && events[j].Time > key.Time)
            {
                events[j + 1] = events[j];
                j--;
            }
            events[j + 1] = key;
        }
        for (uint i = 0; i < events.Length; i++)
        {
            buffer[startCopy + i] = events[i];
        }
    }
    void ReplaceBufferEvents(TM::InputEventBuffer @buffer, array<TM::InputEvent> &in events)
    {
        if (buffer is null)
            return;
        const uint bufferLen = buffer.Length;
        const uint eventsLen = events.Length;
        if (bufferLen > eventsLen)
        {
            uint i;
            for (i = 0; i < eventsLen; i++)
            {
                buffer[i] = events[i];
            }
            buffer.RemoveAt(i, bufferLen - eventsLen);
        }
        else
        {
            uint i;
            for (i = 0; i < bufferLen; i++)
            {
                buffer[i] = events[i];
            }
            while (i < eventsLen)
            {
                buffer.Add(events[i++]);
            }
        }
    }
    void NormalizeDuplicateInputs(TM::InputEventBuffer @buffer)
    {
        if (buffer is null || buffer.Length < 2)
            return;
        array<TM::InputEvent> events;
        for (uint i = 0; i < buffer.Length; i++)
        {
            auto evt = buffer[i];
            bool foundDuplicate = false;
            int j = int(events.Length) - 1;
            while (j >= 0)
            {
                if (events[j].Time != evt.Time)
                    break;
                if (events[j].Value.EventIndex == evt.Value.EventIndex)
                {
                    events[j] = evt;
                    foundDuplicate = true;
                    break;
                }
                j--;
            }
            if (!foundDuplicate)
            {
                events.Add(evt);
            }
        }
        if (events.Length != buffer.Length)
        {
            ReplaceBufferEvents(buffer, events);
            cachedStartIndex = -1;
        }
    }
    int FindTrackedEventIndex(array<int> &in eventIndices, int eventIndex)
    {
        for (uint i = 0; i < eventIndices.Length; i++)
        {
            if (eventIndices[i] == eventIndex)
                return int(i);
        }
        return -1;
    }
    void NormalizeRedundantStateChanges(TM::InputEventBuffer @buffer)
    {
        if (buffer is null || buffer.Length < 2)
            return;
        array<TM::InputEvent> events;
        array<int> eventIndices;
        array<int> lastValues;
        auto indices = buffer.EventIndices;
        eventIndices.Add(int(indices.SteerId));
        lastValues.Add(0);
        eventIndices.Add(int(indices.AccelerateId));
        lastValues.Add(0);
        eventIndices.Add(int(indices.BrakeId));
        lastValues.Add(0);
        for (uint i = 0; i < buffer.Length; i++)
        {
            auto evt = buffer[i];
            int eventIndex = int(evt.Value.EventIndex);
            int value = int(evt.Value.Analog);
            int trackedIndex = FindTrackedEventIndex(eventIndices, eventIndex);
            if (trackedIndex == -1)
            {
                eventIndices.Add(eventIndex);
                lastValues.Add(value);
                events.Add(evt);
                continue;
            }
            if (lastValues[trackedIndex] == value)
                continue;
            lastValues[trackedIndex] = value;
            events.Add(evt);
        }
        if (events.Length != buffer.Length)
        {
            ReplaceBufferEvents(buffer, events);
            cachedStartIndex = -1;
        }
    }
    void SortAndNormalizeBuffer(TM::InputEventBuffer @buffer, int startIndex = -1)
    {
        SortBufferManual(buffer, startIndex);
        NormalizeDuplicateInputs(buffer);
        NormalizeRedundantStateChanges(buffer);
    }
    bool MutateInputs(TM::InputEventBuffer @buffer, int inputCount, int minTime, int maxTime, int maxSteerDiff, int maxTimeDiff, bool fillInputs)
    {
        if (buffer is null)
            return false;
        if (maxTime <= 0)
            return false;
        if (minTime != cachedMinTime)
        {
            cachedMinTime = minTime;
            cachedStartIndex = -1;
        }
        if (fillInputs)
        {
            uint lenBefore = buffer.Length;
            FillInputs(buffer, maxTime, cachedStartIndex);
            if (buffer.Length != lenBefore)
                cachedStartIndex = -1;
        }
        array<int> indices;
        uint start = 0;
        if (cachedStartIndex != -1 && cachedStartIndex < int(buffer.Length))
        {
            start = cachedStartIndex;
        }
        for (uint i = start; i < buffer.Length; i++)
        {
            auto evt = buffer[i];
            if (int(evt.Time) - 100010 < minTime)
            {
                cachedStartIndex = i;
                continue;
            }
            if (int(evt.Time) - 100010 > maxTime)
                break;
            indices.Add(i);
        }
        if (indices.Length == 0)
        {
            print("No inputs found in the specified time frame to modify.", Severity::Warning);
            return false;
        }
        if (inputCount < 1)
            return false;
        int actualInputCount = Math::Rand(1, inputCount);
        if (actualInputCount > int(indices.Length))
            actualInputCount = int(indices.Length);
        for (int i = 0; i < actualInputCount; i++)
        {
            int timeOffset = Math::Rand(-maxTimeDiff / 10, maxTimeDiff / 10) * 10;
            int steerOffset = Math::Rand(-maxSteerDiff, maxSteerDiff);
            uint selectedIdx = uint(Math::Rand(0, int(indices.Length) - 1));
            int inputIdx = indices[selectedIdx];
            indices.RemoveAt(selectedIdx);
            auto evt = buffer[inputIdx];
            evt.Time += timeOffset;
            if (evt.Time < 100010)
            {
                evt.Time = 100010;
            }
            if (int(evt.Time) - 100010 < minTime)
            {
                evt.Time = 100010 + minTime;
            }
            if (int(evt.Time) - 100010 > maxTime)
            {
                evt.Time = 100010 + maxTime;
            }
            if (evt.Value.EventIndex == buffer.EventIndices.SteerId)
            {
                evt.Value.Analog = evt.Value.Analog + steerOffset;
                if (evt.Value.Analog < -65536)
                {
                    evt.Value.Analog = -65536;
                }
                if (evt.Value.Analog > 65536)
                {
                    evt.Value.Analog = 65536;
                }
            }
            int origRaceTime = int(buffer[inputIdx].Time) - 100010;
            int newRaceTime = int(evt.Time) - 100010;
            g_earliestMutationTime = Math::Min(g_earliestMutationTime, Math::Min(origRaceTime, newRaceTime));
            buffer[inputIdx] = evt;
        }
        SortAndNormalizeBuffer(buffer, cachedStartIndex);
        return actualInputCount > 0;
    }
    bool MutateRelativeInputs(TM::InputEventBuffer @buffer, int inputCount, int minTime, int maxTime, int maxSteerDiff, int maxTimeDiff, bool fillInputs)
    {
        if (buffer is null)
            return false;
        if (maxTime <= 0)
            return false;
        if (minTime != cachedMinTime)
        {
            cachedMinTime = minTime;
            cachedStartIndex = -1;
        }
        if (fillInputs)
        {
            uint lenBefore = buffer.Length;
            FillInputs(buffer, maxTime, cachedStartIndex);
            if (buffer.Length != lenBefore)
                cachedStartIndex = -1;
        }
        array<int> indices;
        uint start = 0;
        if (cachedStartIndex != -1 && cachedStartIndex < int(buffer.Length))
        {
            start = cachedStartIndex;
        }
        for (uint i = start; i < buffer.Length; i++)
        {
            auto evt = buffer[i];
            if (int(evt.Time) - 100010 < minTime)
            {
                cachedStartIndex = i;
                continue;
            }
            if (int(evt.Time) - 100010 > maxTime)
                break;
            indices.Add(i);
        }
        if (indices.Length == 0)
        {
            print("No inputs found in the specified time frame to modify.", Severity::Warning);
            return false;
        }
        if (inputCount < 1)
            return false;
        int actualInputCount = Math::Rand(1, inputCount);
        if (actualInputCount > int(indices.Length))
            actualInputCount = int(indices.Length);
        for (int i = 0; i < actualInputCount; i++)
        {
            int timeOffset = Math::Rand(-maxTimeDiff / 10, maxTimeDiff / 10) * 10;
            int steerOffset = Math::Rand(-maxSteerDiff, maxSteerDiff);
            uint selectedIdx = uint(Math::Rand(0, int(indices.Length) - 1));
            int inputIdx = indices[selectedIdx];
            indices.RemoveAt(selectedIdx);
            auto evt = buffer[inputIdx];
            int origRaceTime = int(evt.Time) - 100010;
            evt.Time += timeOffset;
            if (evt.Time < 100010)
            {
                evt.Time = 100010;
            }
            if (int(evt.Time) - 100010 < minTime)
            {
                evt.Time = 100010 + minTime;
            }
            if (int(evt.Time) - 100010 > maxTime)
            {
                evt.Time = 100010 + maxTime;
            }
            int newRaceTime = int(evt.Time) - 100010;
            if (evt.Value.EventIndex == buffer.EventIndices.SteerId)
            {
                int oldSteer = int(buffer[inputIdx].Value.Analog);
                int newSteer = ClampSteer(oldSteer + steerOffset);
                int appliedDelta = newSteer - oldSteer;
                evt.Value.Analog = newSteer;
                buffer[inputIdx] = evt;
                ApplyRelativeSteerDeltaFrom(buffer, inputIdx, int(evt.Time), appliedDelta);
            }
            else
            {
                buffer[inputIdx] = evt;
            }
            g_earliestMutationTime = Math::Min(g_earliestMutationTime, Math::Min(origRaceTime, newRaceTime));
        }
        SortAndNormalizeBuffer(buffer, cachedStartIndex);
        return actualInputCount > 0;
    }
    bool MutateInputsRange(TM::InputEventBuffer @buffer, int minInputCount, int maxInputCount, int minTime, int maxTime, int minSteer, int maxSteer, int maxTimeDiff, bool fillInputs)
    { 
        if (buffer is null)
            return false;
        if (maxTime <= 0)
            return false;
        if (minTime != cachedMinTime)
        {
            cachedMinTime = minTime;
            cachedStartIndex = -1;
        }
        if (fillInputs)
        {
            uint lenBefore = buffer.Length;
            FillInputs(buffer, maxTime, cachedStartIndex);
            if (buffer.Length != lenBefore)
                cachedStartIndex = -1;
        }
        if (minInputCount > maxInputCount)
        {
            int tmp = minInputCount;
            minInputCount = maxInputCount;
            maxInputCount = tmp;
        }
        if (minInputCount < 1) minInputCount = 1;
        if (maxInputCount < 1) maxInputCount = 1;
        if (maxInputCount < minInputCount) maxInputCount = minInputCount;
        array<int> indices;
        uint start = 0;
        if (cachedStartIndex != -1 && cachedStartIndex < int(buffer.Length))
        {
            start = cachedStartIndex;
        }
        for (uint i = start; i < buffer.Length; i++)
        {
            auto evt = buffer[i];
            if (int(evt.Time) - 100010 < minTime)
            {
                cachedStartIndex = i;
                continue;
            }
            if (int(evt.Time) - 100010 > maxTime)
                break;
            indices.Add(i);
        }
        if (indices.Length == 0)
        {
            print("No inputs found in the specified time frame to modify.", Severity::Warning);
            return false;
        }
        int actualInputCount = Math::Rand(minInputCount, maxInputCount);
        if (actualInputCount > int(indices.Length))
            actualInputCount = int(indices.Length);
        if (maxTimeDiff < 0)
            maxTimeDiff = -maxTimeDiff;
        if (minSteer > maxSteer)
        {
            int tmp = minSteer;
            minSteer = maxSteer;
            maxSteer = tmp;
        }
        for (int i = 0; i < actualInputCount; i++)
        {
            int timeOffset = Math::Rand(-maxTimeDiff / 10, maxTimeDiff / 10) * 10;
            int newSteerValue = Math::Rand(minSteer, maxSteer);
            uint selectedIdx = uint(Math::Rand(0, int(indices.Length) - 1));
            int inputIdx = indices[selectedIdx];
            indices.RemoveAt(selectedIdx);
            auto evt = buffer[inputIdx];
            evt.Time += timeOffset;
            if (evt.Time < 100010)
            {
                evt.Time = 100010;
            }
            if (int(evt.Time) - 100010 < minTime)
            {
                evt.Time = 100010 + minTime;
            }
            if (int(evt.Time) - 100010 > maxTime)
            {
                evt.Time = 100010 + maxTime;
            }
            if (evt.Value.EventIndex == buffer.EventIndices.SteerId)
            {
                evt.Value.Analog = newSteerValue;
                if (evt.Value.Analog < -65536)
                {
                    evt.Value.Analog = -65536;
                }
                if (evt.Value.Analog > 65536)
                {
                    evt.Value.Analog = 65536;
                }
            }
            int origRaceTime = int(buffer[inputIdx].Time) - 100010;
            int newRaceTime = int(evt.Time) - 100010;
            g_earliestMutationTime = Math::Min(g_earliestMutationTime, Math::Min(origRaceTime, newRaceTime));
            buffer[inputIdx] = evt;
        }
        SortAndNormalizeBuffer(buffer, cachedStartIndex);
        return actualInputCount > 0;
    }
    bool MutateRelativeInputsRange(TM::InputEventBuffer @buffer, int minInputCount, int maxInputCount, int minTime, int maxTime, int minSteer, int maxSteer, int maxTimeDiff, bool fillInputs)
    {
        if (buffer is null)
            return false;
        if (maxTime <= 0)
            return false;
        if (minTime != cachedMinTime)
        {
            cachedMinTime = minTime;
            cachedStartIndex = -1;
        }
        if (fillInputs)
        {
            uint lenBefore = buffer.Length;
            FillInputs(buffer, maxTime, cachedStartIndex);
            if (buffer.Length != lenBefore)
                cachedStartIndex = -1;
        }
        if (minInputCount > maxInputCount)
        {
            int tmp = minInputCount;
            minInputCount = maxInputCount;
            maxInputCount = tmp;
        }
        if (minInputCount < 1) minInputCount = 1;
        if (maxInputCount < 1) maxInputCount = 1;
        if (maxInputCount < minInputCount) maxInputCount = minInputCount;
        if (maxTimeDiff < 0)
            maxTimeDiff = -maxTimeDiff;
        if (minSteer > maxSteer)
        {
            int tmp = minSteer;
            minSteer = maxSteer;
            maxSteer = tmp;
        }
        minSteer = ClampSteer(minSteer);
        maxSteer = ClampSteer(maxSteer);

        array<int> indices;
        uint start = 0;
        if (cachedStartIndex != -1 && cachedStartIndex < int(buffer.Length))
        {
            start = cachedStartIndex;
        }
        for (uint i = start; i < buffer.Length; i++)
        {
            auto evt = buffer[i];
            if (int(evt.Time) - 100010 < minTime)
            {
                cachedStartIndex = i;
                continue;
            }
            if (int(evt.Time) - 100010 > maxTime)
                break;
            indices.Add(i);
        }
        if (indices.Length == 0)
        {
            print("No inputs found in the specified time frame to modify.", Severity::Warning);
            return false;
        }
        int actualInputCount = Math::Rand(minInputCount, maxInputCount);
        if (actualInputCount > int(indices.Length))
            actualInputCount = int(indices.Length);
        for (int i = 0; i < actualInputCount; i++)
        {
            int timeOffset = Math::Rand(-maxTimeDiff / 10, maxTimeDiff / 10) * 10;
            int pickedAbsoluteSteer = Math::Rand(minSteer, maxSteer);
            uint selectedIdx = uint(Math::Rand(0, int(indices.Length) - 1));
            int inputIdx = indices[selectedIdx];
            indices.RemoveAt(selectedIdx);
            auto evt = buffer[inputIdx];
            int origRaceTime = int(evt.Time) - 100010;
            evt.Time += timeOffset;
            if (evt.Time < 100010)
            {
                evt.Time = 100010;
            }
            if (int(evt.Time) - 100010 < minTime)
            {
                evt.Time = 100010 + minTime;
            }
            if (int(evt.Time) - 100010 > maxTime)
            {
                evt.Time = 100010 + maxTime;
            }
            int newRaceTime = int(evt.Time) - 100010;
            if (evt.Value.EventIndex == buffer.EventIndices.SteerId)
            {
                int previousTickSteer = GetPreviousTickSteer(buffer, inputIdx, int(evt.Time));
                int appliedDelta = pickedAbsoluteSteer - previousTickSteer;
                buffer[inputIdx] = evt;
                ApplyRelativeSteerDeltaFromRange(buffer, int(evt.Time), appliedDelta, minSteer, maxSteer);
            }
            else
            {
                buffer[inputIdx] = evt;
            }
            g_earliestMutationTime = Math::Min(g_earliestMutationTime, Math::Min(origRaceTime, newRaceTime));
        }
        SortAndNormalizeBuffer(buffer, cachedStartIndex);
        return actualInputCount > 0;
    }
    void FillInputs(TM::InputEventBuffer @buffer, int maxTime, int minIndex)
    {
        if (buffer is null)
            return;
        if (maxTime <= 0)
            return;
        const int OFFSET = 100010;
        int absMaxTime = OFFSET + maxTime;
        auto indices = buffer.EventIndices;
        array<TM::InputEvent> steer;
        int startIndex = 0;
        int prevSteerState = 0;
        int prevSteerTime = -1;
        bool hasPrevSteer = true;
        if (minIndex > 0 && minIndex < int(buffer.Length))
        {
            startIndex = minIndex;
            for (int i = minIndex - 1; i >= 0; i--)
            {
                if (buffer[i].Value.EventIndex == indices.SteerId)
                {
                    prevSteerState = int(buffer[i].Value.Analog);
                    prevSteerTime = int(buffer[i].Time);
                    break;
                }
            }
        }
        for (uint i = startIndex; i < buffer.Length; i++)
        {
            auto evt = buffer[i];
            if (int(evt.Time) > absMaxTime)
                break;
            if (evt.Value.EventIndex == indices.SteerId)
            {
                steer.Add(evt);
            }
        }
        uint k = 0;
        const uint steerLen = steer.Length;
        int loopStartTime = 0;
        if (startIndex > 0 && startIndex < int(buffer.Length))
        {
            loopStartTime = int(buffer[startIndex].Time) - OFFSET;
            loopStartTime = (loopStartTime / 10) * 10;
            if (loopStartTime < 0)
                loopStartTime = 0;
        }
        for (int t = loopStartTime; t <= maxTime; t += 10)
        {
            int absT = t + OFFSET;
            bool hadSteerAtT = false;
            while (k < steerLen && int(steer[k].Time) <= absT)
            {
                if (int(steer[k].Time) == absT)
                {
                    hadSteerAtT = true;
                }
                prevSteerState = int(steer[k].Value.Analog);
                prevSteerTime = int(steer[k].Time);
                hasPrevSteer = true;
                k++;
            }
            if (!hadSteerAtT && hasPrevSteer && absT > prevSteerTime)
            {
                buffer.Add(t, InputType::Steer, prevSteerState);
            }
        }
    }
    bool MutateInputsByType(TM::InputEventBuffer @buffer, int eventTypeId, int inputCount, int minTime, int maxTime, int maxSteerDiff, int maxTimeDiff, bool fillInputs, bool isBinaryInput)
    {
        if (buffer is null)
            return false;
        if (maxTime <= 0)
            return false;
        if (minTime != cachedMinTime)
        {
            cachedMinTime = minTime;
            cachedStartIndex = -1;
        }
        if (fillInputs && eventTypeId == int(buffer.EventIndices.SteerId))
        {
            uint lenBefore = buffer.Length;
            FillInputs(buffer, maxTime, cachedStartIndex);
            if (buffer.Length != lenBefore)
                cachedStartIndex = -1;
        }
        array<int> indices;
        uint start = 0;
        if (cachedStartIndex != -1 && cachedStartIndex < int(buffer.Length))
        {
            start = cachedStartIndex;
        }
        for (uint i = start; i < buffer.Length; i++)
        {
            auto evt = buffer[i];
            if (int(evt.Time) - 100010 < minTime)
            {
                if (cachedStartIndex < int(i))
                    cachedStartIndex = int(i);
                continue;
            }
            if (int(evt.Time) - 100010 > maxTime)
                break;
            if (int(evt.Value.EventIndex) == eventTypeId)
            {
                indices.Add(i);
            }
        }
        if (indices.Length == 0)
            return false;
        if (inputCount < 1)
            return false;
        int actualInputCount = Math::Rand(1, inputCount);
        if (actualInputCount > int(indices.Length))
            actualInputCount = int(indices.Length);
        for (int i = 0; i < actualInputCount; i++)
        {
            int timeOffset = Math::Rand(-maxTimeDiff / 10, maxTimeDiff / 10) * 10;
            uint selectedIdx = uint(Math::Rand(0, int(indices.Length) - 1));
            int inputIdx = indices[selectedIdx];
            indices.RemoveAt(selectedIdx);
            auto evt = buffer[inputIdx];
            evt.Time += timeOffset;
            if (evt.Time < 100010)
            {
                evt.Time = 100010;
            }
            if (int(evt.Time) - 100010 < minTime)
            {
                evt.Time = 100010 + minTime;
            }
            if (int(evt.Time) - 100010 > maxTime)
            {
                evt.Time = 100010 + maxTime;
            }
            if (isBinaryInput)
            {
                evt.Value.Analog = (evt.Value.Analog == 0) ? 1 : 0;
            }
            else
            {
                int steerOffset = Math::Rand(-maxSteerDiff, maxSteerDiff);
                evt.Value.Analog = evt.Value.Analog + steerOffset;
                if (evt.Value.Analog < -65536)
                {
                    evt.Value.Analog = -65536;
                }
                if (evt.Value.Analog > 65536)
                {
                    evt.Value.Analog = 65536;
                }
            }
            int origRaceTime = int(buffer[inputIdx].Time) - 100010;
            int newRaceTime = int(evt.Time) - 100010;
            g_earliestMutationTime = Math::Min(g_earliestMutationTime, Math::Min(origRaceTime, newRaceTime));
            buffer[inputIdx] = evt;
        }
        SortAndNormalizeBuffer(buffer, cachedStartIndex);
        return actualInputCount > 0;
    }
    bool MutateInputsRangeByType(TM::InputEventBuffer @buffer, int eventTypeId, int minInputCount, int maxInputCount, int minTime, int maxTime, int minSteer, int maxSteer, int minTimeDiff, int maxTimeDiff, bool fillInputs, bool isBinaryInput)
    {
        if (buffer is null)
            return false;
        if (maxTime <= 0)
            return false;
        if (minTime != cachedMinTime)
        {
            cachedMinTime = minTime;
            cachedStartIndex = -1;
        }
        if (fillInputs && eventTypeId == int(buffer.EventIndices.SteerId))
        {
            uint lenBefore = buffer.Length;
            FillInputs(buffer, maxTime, cachedStartIndex);
            if (buffer.Length != lenBefore)
                cachedStartIndex = -1;
        }
        if (minInputCount > maxInputCount)
        {
            int tmp = minInputCount;
            minInputCount = maxInputCount;
            maxInputCount = tmp;
        }
        if (minInputCount < 1) minInputCount = 1;
        if (maxInputCount < 1) maxInputCount = 1;
        if (maxInputCount < minInputCount) maxInputCount = minInputCount;
        array<int> indices;
        uint start = 0;
        if (cachedStartIndex != -1 && cachedStartIndex < int(buffer.Length))
        {
            start = cachedStartIndex;
        }
        for (uint i = start; i < buffer.Length; i++)
        {
            auto evt = buffer[i];
            if (int(evt.Time) - 100010 < minTime)
            {
                if (cachedStartIndex < int(i))
                    cachedStartIndex = int(i);
                continue;
            }
            if (int(evt.Time) - 100010 > maxTime)
                break;
            if (int(evt.Value.EventIndex) == eventTypeId)
            {
                indices.Add(i);
            }
        }
        if (indices.Length == 0)
            return false;
        int actualInputCount = Math::Rand(minInputCount, maxInputCount);
        if (actualInputCount > int(indices.Length))
            actualInputCount = int(indices.Length);
        if (minTimeDiff > maxTimeDiff)
        {
            int tmp = minTimeDiff;
            minTimeDiff = maxTimeDiff;
            maxTimeDiff = tmp;
        }
        if (minSteer > maxSteer)
        {
            int tmp = minSteer;
            minSteer = maxSteer;
            maxSteer = tmp;
        }
        for (int i = 0; i < actualInputCount; i++)
        {
            int timeOffset = Math::Rand(minTimeDiff / 10, maxTimeDiff / 10) * 10;
            uint selectedIdx = uint(Math::Rand(0, int(indices.Length) - 1));
            int inputIdx = indices[selectedIdx];
            indices.RemoveAt(selectedIdx);
            auto evt = buffer[inputIdx];
            evt.Time += timeOffset;
            if (evt.Time < 100010)
            {
                evt.Time = 100010;
            }
            if (int(evt.Time) - 100010 < minTime)
            {
                evt.Time = 100010 + minTime;
            }
            if (int(evt.Time) - 100010 > maxTime)
            {
                evt.Time = 100010 + maxTime;
            }
            if (isBinaryInput)
            {
                evt.Value.Analog = (evt.Value.Analog == 0) ? 1 : 0;
            }
            else
            {
                evt.Value.Analog = Math::Rand(minSteer, maxSteer);
                if (evt.Value.Analog < -65536)
                {
                    evt.Value.Analog = -65536;
                }
                if (evt.Value.Analog > 65536)
                {
                    evt.Value.Analog = 65536;
                }
            }
            int origRaceTime = int(buffer[inputIdx].Time) - 100010;
            int newRaceTime = int(evt.Time) - 100010;
            g_earliestMutationTime = Math::Min(g_earliestMutationTime, Math::Min(origRaceTime, newRaceTime));
            buffer[inputIdx] = evt;
        }
        SortAndNormalizeBuffer(buffer, cachedStartIndex);
        return actualInputCount > 0;
    }
    int ClampTimeToRange(int time, int minTime, int maxTime)
    {
        if (minTime > maxTime)
        {
            int tmp = minTime;
            minTime = maxTime;
            maxTime = tmp;
        }
        if (time < minTime) time = minTime;
        if (time > maxTime) time = maxTime;
        return (time / 10) * 10;
    }
    int RandomTimeInRange(int minTime, int maxTime)
    {
        if (minTime > maxTime)
        {
            int tmp = minTime;
            minTime = maxTime;
            maxTime = tmp;
        }
        minTime = (minTime / 10) * 10;
        maxTime = (maxTime / 10) * 10;
        if (maxTime < minTime)
            maxTime = minTime;
        return Math::Rand(minTime / 10, maxTime / 10) * 10;
    }
    int StateAtTime(array<TM::InputEvent> &in events, int eventTypeId, int raceTime, int defaultState)
    {
        int absTime = 100010 + raceTime;
        int state = defaultState;
        int bestTime = -1;
        for (uint i = 0; i < events.Length; i++)
        {
            auto evt = events[i];
            if (int(evt.Value.EventIndex) != eventTypeId)
                continue;
            int evtTime = int(evt.Time);
            if (evtTime <= absTime && evtTime >= bestTime)
            {
                state = int(evt.Value.Analog);
                bestTime = evtTime;
            }
        }
        return state;
    }
    void SnapshotEvents(TM::InputEventBuffer @buffer, array<TM::InputEvent> &out events)
    {
        events.Resize(0);
        if (buffer is null)
            return;
        for (uint i = 0; i < buffer.Length; i++)
            events.Add(buffer[i]);
    }
    bool RemoveEventsInRaceRange(TM::InputEventBuffer @buffer, int eventTypeId, int minTime, int maxTime)
    {
        if (buffer is null)
            return false;
        if (minTime > maxTime)
        {
            int tmp = minTime;
            minTime = maxTime;
            maxTime = tmp;
        }
        bool removed = false;
        for (int i = int(buffer.Length) - 1; i >= 0; i--)
        {
            auto evt = buffer[uint(i)];
            int raceTime = int(evt.Time) - 100010;
            if (int(evt.Value.EventIndex) == eventTypeId && raceTime >= minTime && raceTime <= maxTime)
            {
                g_earliestMutationTime = Math::Min(g_earliestMutationTime, raceTime);
                buffer.RemoveAt(uint(i));
                removed = true;
            }
        }
        if (removed)
            cachedStartIndex = -1;
        return removed;
    }
    bool InsertHeldInput(TM::InputEventBuffer @buffer, array<TM::InputEvent> &in baseEvents, InputType inputType, int eventTypeId, int minTime, int maxTime, int startTime, int value, int maxHeldTime, int defaultState)
    {
        if (buffer is null)
            return false;
        startTime = ClampTimeToRange(startTime, minTime, maxTime);
        int heldTime = 0;
        if (maxHeldTime > 0)
            heldTime = Math::Rand(0, maxHeldTime / 10) * 10;
        int endTime = ClampTimeToRange(startTime + heldTime, startTime, maxTime);
        RemoveEventsInRaceRange(buffer, eventTypeId, startTime, endTime);
        buffer.Add(startTime, inputType, value);
        if (heldTime > 0 && endTime > startTime)
        {
            int restoreState = StateAtTime(baseEvents, eventTypeId, endTime, defaultState);
            buffer.Add(endTime, inputType, restoreState);
        }
        g_earliestMutationTime = Math::Min(g_earliestMutationTime, startTime);
        cachedStartIndex = -1;
        return true;
    }
    bool InsertInputs(TM::InputEventBuffer @buffer, int minTime, int maxTime, const string &in steerMode, int steerMin, int steerMax, int steerAddDiff, int steerMaxCount, int steerMaxHeldTime, int accelMaxCount, int accelMaxHeldTime, int brakeMaxCount, int brakeMaxHeldTime)
    {
        if (buffer is null || maxTime < minTime)
            return false;
        auto indices = buffer.EventIndices;
        array<TM::InputEvent> baseEvents;
        SnapshotEvents(buffer, baseEvents);
        bool mutated = false;
        if (steerMaxCount > 0)
        {
            int count = Math::Rand(0, steerMaxCount);
            if (steerMin > steerMax)
            {
                int tmp = steerMin;
                steerMin = steerMax;
                steerMax = tmp;
            }
            steerMin = ClampSteer(steerMin);
            steerMax = ClampSteer(steerMax);
            for (int i = 0; i < count; i++)
            {
                int t = RandomTimeInRange(minTime, maxTime);
                int value = 0;
                if (steerMode == "add")
                    value = ClampSteer(StateAtTime(baseEvents, int(indices.SteerId), t, 0) + steerAddDiff);
                else
                    value = Math::Rand(steerMin, steerMax);
                mutated = InsertHeldInput(buffer, baseEvents, InputType::Steer, int(indices.SteerId), minTime, maxTime, t, value, steerMaxHeldTime, 0) || mutated;
            }
        }
        if (accelMaxCount > 0)
        {
            int count = Math::Rand(0, accelMaxCount);
            for (int i = 0; i < count; i++)
            {
                int t = RandomTimeInRange(minTime, maxTime);
                int value = StateAtTime(baseEvents, int(indices.AccelerateId), t, 0) == 0 ? 1 : 0;
                mutated = InsertHeldInput(buffer, baseEvents, InputType::Up, int(indices.AccelerateId), minTime, maxTime, t, value, accelMaxHeldTime, 0) || mutated;
            }
        }
        if (brakeMaxCount > 0)
        {
            int count = Math::Rand(0, brakeMaxCount);
            for (int i = 0; i < count; i++)
            {
                int t = RandomTimeInRange(minTime, maxTime);
                int value = StateAtTime(baseEvents, int(indices.BrakeId), t, 0) == 0 ? 1 : 0;
                mutated = InsertHeldInput(buffer, baseEvents, InputType::Down, int(indices.BrakeId), minTime, maxTime, t, value, brakeMaxHeldTime, 0) || mutated;
            }
        }
        if (mutated)
            SortAndNormalizeBuffer(buffer);
        return mutated;
    }
    bool DeleteInputsByType(TM::InputEventBuffer @buffer, int eventTypeId, int maxCount, int minTime, int maxTime)
    {
        if (buffer is null || maxCount <= 0 || maxTime < minTime)
            return false;
        int count = Math::Rand(0, maxCount);
        bool mutated = false;
        for (int n = 0; n < count; n++)
        {
            array<uint> candidates;
            for (uint i = 0; i < buffer.Length; i++)
            {
                auto evt = buffer[i];
                int raceTime = int(evt.Time) - 100010;
                if (int(evt.Value.EventIndex) == eventTypeId && raceTime >= minTime && raceTime <= maxTime)
                    candidates.Add(i);
            }
            if (candidates.Length == 0)
                break;
            uint chosen = candidates[uint(Math::Rand(0, int(candidates.Length) - 1))];
            int raceTime = int(buffer[chosen].Time) - 100010;
            g_earliestMutationTime = Math::Min(g_earliestMutationTime, raceTime);
            buffer.RemoveAt(chosen);
            mutated = true;
        }
        if (mutated)
        {
            cachedStartIndex = -1;
            SortAndNormalizeBuffer(buffer);
        }
        return mutated;
    }
}
