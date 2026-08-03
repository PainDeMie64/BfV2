namespace ScriptingReference
{
    string playgroundCompiledSource = "";
    string playgroundResult = "Waiting for run step.";
    string playgroundCompileStatus = "";
    bool playgroundCompiled = false;
    bool playgroundIsCondition = false;
    int playgroundLastRaceTime = -1;
    Scripting::ConditionCallback @playgroundCondition = null;
    Scripting::FloatGetter @playgroundValue = null;

    void ResetPlaygroundProgram()
    {
        playgroundCompiled = false;
        playgroundIsCondition = false;
        playgroundCompiledSource = "";
        playgroundResult = "Waiting for script.";
        playgroundCompileStatus = "";
        @playgroundCondition = null;
        @playgroundValue = null;
    }

    bool HasComparisonOperator(const string &in line)
    {
        return Scripting::FindTopLevel(line, ">=") != -1
            || Scripting::FindTopLevel(line, "<=") != -1
            || Scripting::FindTopLevel(line, ">") != -1
            || Scripting::FindTopLevel(line, "<") != -1
            || Scripting::FindTopLevel(line, "=") != -1;
    }

    int CountPlayableLines(const array<string> &in lines)
    {
        int count = 0;
        for (uint i = 0; i < lines.Length; i++)
        {
            if (Scripting::CleanSource(lines[i]) != "")
                count++;
        }
        return count;
    }

    void CompilePlaygroundIfNeeded()
    {
        string source = Replace(GetVariableString("bf_scripting_playground_script"), ":", "\n");
        if (source == playgroundCompiledSource)
            return;

        ResetPlaygroundProgram();
        playgroundCompiledSource = source;
        array<string> lines = source.Split("\n");
        int playableLines = CountPlayableLines(lines);
        if (playableLines == 0)
        {
            playgroundCompileStatus = "Enter a script to evaluate.";
            return;
        }

        bool shouldCompileAsCondition = playableLines > 1;
        string expressionLine = "";
        if (playableLines == 1)
        {
            for (uint i = 0; i < lines.Length; i++)
            {
                string cleaned = Scripting::CleanSource(lines[i]);
                if (cleaned != "")
                {
                    expressionLine = cleaned;
                    shouldCompileAsCondition = HasComparisonOperator(cleaned);
                    break;
                }
            }
        }

        if (shouldCompileAsCondition)
        {
            Scripting::ConditionCallback @condition = Scripting::CompileMulti(lines);
            if (condition is null)
            {
                playgroundCompileStatus = "Compile error.";
                playgroundResult = "No result.";
                return;
            }
            @playgroundCondition = @condition;
            playgroundIsCondition = true;
            playgroundCompiled = true;
            playgroundCompileStatus = "Compiled as condition.";
            playgroundResult = "Waiting for run step.";
            return;
        }

        Scripting::FloatGetter @value = Scripting::ParseExpression(expressionLine);
        if (value is null)
        {
            playgroundCompileStatus = "Compile error.";
            playgroundResult = "No result.";
            return;
        }
        @playgroundValue = @value;
        playgroundIsCondition = false;
        playgroundCompiled = true;
        playgroundCompileStatus = "Compiled as expression.";
        playgroundResult = "Waiting for run step.";
    }

    void OnRunStep(SimulationManager @simManager)
    {
        if (simManager is null)
            return;
        CompilePlaygroundIfNeeded();
        if (!playgroundCompiled)
            return;
        if (playgroundLastRaceTime == simManager.RaceTime)
            return;
        playgroundLastRaceTime = simManager.RaceTime;
        if (playgroundIsCondition)
        {
            if (playgroundCondition is null)
                return;
            bool result = playgroundCondition(simManager);
            playgroundResult = result ? "true" : "false";
        }
        else
        {
            if (playgroundValue is null)
                return;
            float result = playgroundValue(simManager);
            playgroundResult = Text::FormatFloat(result, "", 0, 6);
        }
    }

    void RenderPlayground()
    {
        SectionHeader("Playground");
        string lines = Replace(GetVariableString("bf_scripting_playground_script"), ":", "\n");
        int currentHeight = int(GetVariableDouble("bf_scripting_playground_script_height"));
        if (currentHeight < 40)
            currentHeight = 40;
        if (UI::InputTextMultiline("##bf_scripting_playground_script", lines, vec2(0, currentHeight)))
        {
            SetVariable("bf_scripting_playground_script", Replace(lines, "\n", ":"));
            CompilePlaygroundIfNeeded();
        }
        if (UI::Button("^##scripting_playground_up"))
        {
            if (currentHeight > 40)
                SetVariable("bf_scripting_playground_script_height", currentHeight - 17);
        }
        UI::SameLine();
        if (UI::Button("v##scripting_playground_down"))
            SetVariable("bf_scripting_playground_script_height", currentHeight + 17);
        UI::SameLine();
        UI::TextDimmed(playgroundCompileStatus);
        UI::Dummy(vec2(0, 2));
        UI::Text("Result:");
        UI::SameLine();
        UI::PushStyleColor(UI::Col::Text, playgroundCompiled ? vec4(0.6, 1.0, 0.6, 1.0) : vec4(1.0, 0.45, 0.35, 1.0));
        UI::Text(playgroundResult);
        UI::PopStyleColor();
        UI::Dummy(vec2(0, 6));
    }

    void SectionHeader(const string &in title)
    {
        UI::Dummy(vec2(0, 6));
        UI::PushStyleColor(UI::Col::Text, vec4(1.0, 0.85, 0.3, 1.0));
        UI::Text(title);
        UI::PopStyleColor();
        UI::Separator();
        UI::Dummy(vec2(0, 2));
    }
    void SubHeader(const string &in title)
    {
        UI::Dummy(vec2(0, 3));
        UI::PushStyleColor(UI::Col::Text, vec4(0.5, 0.85, 1.0, 1.0));
        UI::Text(title);
        UI::PopStyleColor();
        UI::Dummy(vec2(0, 1));
    }
    uint copyId = 0;
    void Code(const string &in code)
    {
        UI::PushStyleColor(UI::Col::Text, vec4(0.6, 1.0, 0.6, 1.0));
        UI::Text("  " + code);
        UI::PopStyleColor();
        UI::SameLine();
        if (UI::Button("Copy##c" + copyId++))
            IO::SetClipboard(code);
    }
    void CodeNoCopy(const string &in code)
    {
        UI::PushStyleColor(UI::Col::Text, vec4(0.6, 1.0, 0.6, 1.0));
        UI::Text("  " + code);
        UI::PopStyleColor();
    }
    void CodeBlock(const string &in line1, const string &in line2)
    {
        UI::PushStyleColor(UI::Col::Text, vec4(0.6, 1.0, 0.6, 1.0));
        UI::Text("  " + line1);
        UI::Text("  " + line2);
        UI::PopStyleColor();
        UI::SameLine();
        if (UI::Button("Copy##c" + copyId++))
            IO::SetClipboard(line1 + "\n" + line2);
    }
    void CodeBlock3(const string &in l1, const string &in l2, const string &in l3)
    {
        UI::PushStyleColor(UI::Col::Text, vec4(0.6, 1.0, 0.6, 1.0));
        UI::Text("  " + l1);
        UI::Text("  " + l2);
        UI::Text("  " + l3);
        UI::PopStyleColor();
        UI::SameLine();
        if (UI::Button("Copy##c" + copyId++))
            IO::SetClipboard(l1 + "\n" + l2 + "\n" + l3);
    }
    void Desc(const string &in text)
    {
        UI::TextDimmed("    " + text);
    }
    void VarRow(const string &in name, const string &in desc)
    {
        UI::TableNextRow();
        UI::TableSetColumnIndex(0);
        UI::PushStyleColor(UI::Col::Text, vec4(0.6, 1.0, 0.6, 1.0));
        UI::Text(name);
        UI::PopStyleColor();
        UI::SameLine();
        string copyName = name;
        int slashPos = copyName.FindFirst(" /");
        if (slashPos != -1)
            copyName = copyName.Substr(0, slashPos);
        while (copyName.Length > 0 && copyName[copyName.Length - 1] == 32)
            copyName = copyName.Substr(0, copyName.Length - 1);
        if (UI::Button("Copy##v" + copyId++))
            IO::SetClipboard(copyName);
        UI::TableSetColumnIndex(1);
        UI::TextDimmed(desc);
    }
    void SurfaceRow(const string &in id, const string &in name, const string &in id2, const string &in name2)
    {
        UI::TableNextRow();
        UI::TableSetColumnIndex(0);
        UI::Text(id);
        UI::TableSetColumnIndex(1);
        UI::TextDimmed(name);
        UI::TableSetColumnIndex(2);
        UI::Text(id2);
        UI::TableSetColumnIndex(3);
        UI::TextDimmed(name2);
    }
    void Render()
    {
        copyId = 0;
        CompilePlaygroundIfNeeded();
        RenderPlayground();
        UI::PushStyleColor(UI::Col::Text, vec4(1, 1, 1, 0.95));
        UI::TextWrapped("This page documents the scripting language used in Condition Scripts, Restart Condition Scripts, and Custom Target Scripts. All three share the same expression language.");
        UI::PopStyleColor();
        UI::Dummy(vec2(0, 4));
        if (UI::CollapsingHeader("Condition Script"))
        {
            UI::Dummy(vec2(0, 2));
            UI::TextWrapped("Used in the Conditions and Restart Condition fields. Each line is a boolean comparison. All lines must be true (AND logic).");
            SubHeader("Format");
            CodeNoCopy("EXPRESSION  OPERATOR  EXPRESSION");
            UI::Dummy(vec2(0, 2));
            UI::TextDimmed("  Operators:  >  <  >=  <=  =");
            SubHeader("Examples");
            Code("kmh(car.speed) > 500");
            Desc("Speed must exceed 500 km/h");
            UI::Dummy(vec2(0, 1));
            Code("car.z < 10.5");
            Desc("Z position must be below 10.5");
            UI::Dummy(vec2(0, 1));
            CodeBlock("deg(car.pitch) > 80", "car.wheels.frontleft.groundcontact = 1");
            Desc("Nose up and front-left wheel touching ground");
            UI::Dummy(vec2(0, 1));
            Code("distance(car.pos, (105.5, 20.0, 300.0)) < 5.0");
            Desc("Car within 5m of a fixed point");
            UI::Dummy(vec2(0, 1));
            Code("distance(car.pos, variable(bf_target_point)) < 3.0");
            Desc("Car within 3m of the single point BF target");
            UI::Dummy(vec2(0, 1));
            Code("car.wheels.frontleft.surface = 2");
            Desc("Front-left wheel is on Grass (ID 2)");
            UI::Dummy(vec2(0, 1));
            Code("time_since(last_improvement.time) > 60");
            Desc("Restart if no improvement for 60 seconds");
            UI::Dummy(vec2(0, 1));
            Code("time_since(last_restart.time) > 60*5");
            Desc("Restart every 5 minutes");
            UI::Dummy(vec2(0, 4));
        }
        if (UI::CollapsingHeader("Custom Target Script"))
        {
            UI::Dummy(vec2(0, 2));
            UI::TextWrapped("Used in the Custom Target bruteforce evaluation. Each line defines an optimization objective instead of a boolean condition.");
            SubHeader("Directives");
            if (UI::BeginTable("##directives_table", 2))
            {
                UI::TableSetupColumn("Directive");
                UI::TableSetupColumn("Meaning");
                VarRow("min EXPR", "Minimize the expression (lower is better)");
                VarRow("max EXPR", "Maximize the expression (higher is better)");
                VarRow("target VALUE EXPR", "Get expression as close to VALUE as possible");
                UI::EndTable();
            }
            UI::Dummy(vec2(0, 2));
            UI::TextDimmed("  Lines starting with # are comments. Blank lines are ignored.");
            SubHeader("Multi-Objective (Pareto)");
            UI::TextWrapped("  When multiple directives are used, a run is accepted only if it improves at least one objective without worsening any other.");
            SubHeader("Examples");
            Code("max car.speed");
            Desc("Maximize raw speed");
            UI::Dummy(vec2(0, 1));
            Code("target 500 car.x");
            Desc("Get car.x as close to 500 as possible");
            UI::Dummy(vec2(0, 1));
            Code("min distance(car.pos, (105.5, 20.0, 300.0))");
            Desc("Minimize distance to a point");
            UI::Dummy(vec2(0, 1));
            CodeBlock("max kmh(car.speed)", "target 200 car.x");
            Desc("Maximize speed while keeping car.x near 200");
            UI::Dummy(vec2(0, 1));
            CodeBlock("# Optimize for altitude", "max car.y");
            Desc("Comments are allowed with #");
            UI::Dummy(vec2(0, 4));
        }
        if (UI::CollapsingHeader("Variables Reference"))
        {
            UI::Dummy(vec2(0, 2));
            SubHeader("Position");
            if (UI::BeginTable("##vars_pos", 2))
            {
                UI::TableSetupColumn("Variable");
                UI::TableSetupColumn("Description");
                VarRow("car.x  /  car.position.x", "X position");
                VarRow("car.y  /  car.position.y", "Y position (height)");
                VarRow("car.z  /  car.position.z", "Z position");
                VarRow("car.prev.x  /  car.prev.position.x", "Previous tick X position");
                VarRow("car.prev.y  /  car.prev.position.y", "Previous tick Y position");
                VarRow("car.prev.z  /  car.prev.position.z", "Previous tick Z position");
                UI::EndTable();
            }
            SubHeader("Velocity");
            if (UI::BeginTable("##vars_vel", 2))
            {
                UI::TableSetupColumn("Variable");
                UI::TableSetupColumn("Description");
                VarRow("car.vel.x  /  car.velocity.x", "X velocity, world (m/s)");
                VarRow("car.vel.y  /  car.velocity.y", "Y velocity, world (m/s)");
                VarRow("car.vel.z  /  car.velocity.z", "Z velocity, world (m/s)");
                VarRow("car.vel.pitch  /  car.velocity.pitch", "Angular velocity pitch (rad/s)");
                VarRow("car.vel.yaw  /  car.velocity.yaw", "Angular velocity yaw (rad/s)");
                VarRow("car.vel.roll  /  car.velocity.roll", "Angular velocity roll (rad/s)");
                VarRow("car.speed", "Total speed (m/s)");
                VarRow("car.localvel.x  /  car.localvelocity.x", "X velocity, car-relative (m/s)");
                VarRow("car.localvel.y  /  car.localvelocity.y", "Y velocity, car-relative (m/s)");
                VarRow("car.localvel.z  /  car.localvelocity.z", "Z velocity, car-relative (m/s)");
                VarRow("car.localspeed", "Total local speed (m/s)");
                VarRow("car.prev.vel.x  /  car.prev.velocity.x", "Previous tick X velocity, world (m/s)");
                VarRow("car.prev.vel.y  /  car.prev.velocity.y", "Previous tick Y velocity, world (m/s)");
                VarRow("car.prev.vel.z  /  car.prev.velocity.z", "Previous tick Z velocity, world (m/s)");
                VarRow("car.prev.vel.pitch  /  car.prev.velocity.pitch", "Previous tick angular velocity pitch (rad/s)");
                VarRow("car.prev.vel.yaw  /  car.prev.velocity.yaw", "Previous tick angular velocity yaw (rad/s)");
                VarRow("car.prev.vel.roll  /  car.prev.velocity.roll", "Previous tick angular velocity roll (rad/s)");
                VarRow("car.prev.speed", "Previous tick total speed (m/s)");
                VarRow("car.prev.localvel.x  /  car.prev.localvelocity.x", "Previous tick X velocity, car-relative (m/s)");
                VarRow("car.prev.localvel.y  /  car.prev.localvelocity.y", "Previous tick Y velocity, car-relative (m/s)");
                VarRow("car.prev.localvel.z  /  car.prev.localvelocity.z", "Previous tick Z velocity, car-relative (m/s)");
                VarRow("car.prev.localspeed", "Previous tick total local speed (m/s)");
                UI::EndTable();
            }
            SubHeader("Rotation");
            if (UI::BeginTable("##vars_rot", 2))
            {
                UI::TableSetupColumn("Variable");
                UI::TableSetupColumn("Description");
                VarRow("car.yaw  /  car.rotation.yaw", "Yaw angle (radians)");
                VarRow("car.pitch  /  car.rotation.pitch", "Pitch angle (radians)");
                VarRow("car.roll  /  car.rotation.roll", "Roll angle (radians)");
                VarRow("car.prev.yaw  /  car.prev.rotation.yaw", "Previous tick yaw angle (radians)");
                VarRow("car.prev.pitch  /  car.prev.rotation.pitch", "Previous tick pitch angle (radians)");
                VarRow("car.prev.roll  /  car.prev.rotation.roll", "Previous tick roll angle (radians)");
                UI::EndTable();
            }
            SubHeader("Vehicle State");
            if (UI::BeginTable("##vars_state", 2))
            {
                UI::TableSetupColumn("Variable");
                UI::TableSetupColumn("Description");
                VarRow("car.freewheel", "1 if freewheeling, 0 otherwise");
                VarRow("car.lateralcontact", "1 if lateral contact, 0 otherwise");
                VarRow("car.sliding  /  car.is_sliding  /  car.is", "1 if sliding, 0 otherwise");
                VarRow("car.gear", "Current gear (-1 = reverse)");
                VarRow("car.rpm", "Actual engine RPM");
                VarRow("car.turning_rate  /  car.tr", "Turning rate");
                VarRow("car.turbo_type  /  car.tt", "0 none, 1 normal, 2 roulette");
                VarRow("car.turbo_boost_factor  /  car.tbf", "Turbo boost factor");
                UI::EndTable();
            }
            SubHeader("Wheels - Ground Contact");
            if (UI::BeginTable("##vars_gc", 2))
            {
                UI::TableSetupColumn("Variable");
                UI::TableSetupColumn("Value");
                VarRow("car.wheels.frontleft.groundcontact", "0 or 1");
                VarRow("car.wheels.frontright.groundcontact", "0 or 1");
                VarRow("car.wheels.backleft.groundcontact", "0 or 1");
                VarRow("car.wheels.backright.groundcontact", "0 or 1");
                UI::EndTable();
            }
            SubHeader("Wheels - Sliding");
            if (UI::BeginTable("##vars_wheel_sliding", 2))
            {
                UI::TableSetupColumn("Variable");
                UI::TableSetupColumn("Value");
                VarRow("car.wheels.frontleft.is_sliding  /  .is", "0 or 1");
                VarRow("car.wheels.frontright.is_sliding  /  .is", "0 or 1");
                VarRow("car.wheels.backleft.is_sliding  /  .is", "0 or 1");
                VarRow("car.wheels.backright.is_sliding  /  .is", "0 or 1");
                UI::EndTable();
            }
            SubHeader("Wheels - Surface Material");
            if (UI::BeginTable("##vars_surf", 2))
            {
                UI::TableSetupColumn("Variable");
                UI::TableSetupColumn("Value");
                VarRow("car.wheels.frontleft.surface", "Material ID (see table)");
                VarRow("car.wheels.frontright.surface", "Material ID (see table)");
                VarRow("car.wheels.backleft.surface", "Material ID (see table)");
                VarRow("car.wheels.backright.surface", "Material ID (see table)");
                UI::EndTable();
            }
            SubHeader("Vectors (for distance() function)");
            if (UI::BeginTable("##vars_vec", 2))
            {
                UI::TableSetupColumn("Variable");
                UI::TableSetupColumn("Description");
                VarRow("car.pos  /  car.position", "Position as vec3");
                VarRow("car.vel  /  car.velocity", "Velocity as vec3 (world)");
                VarRow("car.localvel  /  car.localvelocity", "Velocity as vec3 (car-relative)");
                VarRow("car.prev.pos  /  car.prev.position", "Previous tick position as vec3");
                VarRow("car.prev.vel  /  car.prev.velocity", "Previous tick velocity as vec3 (world)");
                VarRow("car.prev.localvel  /  car.prev.localvelocity", "Previous tick velocity as vec3 (car-relative)");
                VarRow("(x, y, z)", "Constant vec3 literal");
                UI::EndTable();
            }
            SubHeader("Bruteforce State");
            if (UI::BeginTable("##vars_bf", 2))
            {
                UI::TableSetupColumn("Variable");
                UI::TableSetupColumn("Description");
                VarRow("iterations", "Current iteration count");
                VarRow("last_improvement.time", "Timestamp of last improvement (s)");
                VarRow("last_restart.time", "Timestamp of last restart (s)");
                UI::EndTable();
            }
            UI::Dummy(vec2(0, 4));
        }
        if (UI::CollapsingHeader("Functions Reference"))
        {
            UI::Dummy(vec2(0, 2));
            if (UI::BeginTable("##funcs_table", 2))
            {
                UI::TableSetupColumn("Function");
                UI::TableSetupColumn("Description");
                VarRow("kmh(value)", "Converts m/s to km/h (x 3.6)");
                VarRow("deg(value)", "Converts radians to degrees");
                VarRow("distance(vec1, vec2)", "Euclidean distance between two vec3s");
                VarRow("time_since(timestamp)", "Seconds elapsed since timestamp");
                VarRow("variable(name) / var(name)", "Read a TMInterface variable as float or vec3");
                UI::EndTable();
            }
            SubHeader("Operators");
            UI::TextDimmed("  Arithmetic:   +   -   *   /");
            UI::TextDimmed("  Comparison:   >   <   >=   <=   =");
            UI::TextDimmed("  Grouping:     ( ... )");
            UI::Dummy(vec2(0, 4));
        }
        if (UI::CollapsingHeader("Surface Material IDs"))
        {
            UI::Dummy(vec2(0, 2));
            UI::TextDimmed("  Use with car.wheels.*.surface variables in conditions.");
            UI::Dummy(vec2(0, 2));
            if (UI::BeginTable("##surface_ids", 4))
            {
                UI::TableSetupColumn("ID");
                UI::TableSetupColumn("Surface");
                UI::TableSetupColumn("ID");
                UI::TableSetupColumn("Surface");
                UI::TableHeadersRow();
                SurfaceRow("0", "Concrete", "15", "Rubber");
                SurfaceRow("1", "Pavement", "16", "SlidingRubber");
                SurfaceRow("2", "Grass", "17", "Test");
                SurfaceRow("3", "Ice", "18", "Rock");
                SurfaceRow("4", "Metal", "19", "Water");
                SurfaceRow("5", "Sand", "20", "Wood");
                SurfaceRow("6", "Dirt", "21", "Danger");
                SurfaceRow("7", "DirtRoad", "22", "Asphalt");
                SurfaceRow("8", "Plastic", "23", "WetDirtRoad");
                SurfaceRow("9", "Green", "24", "WetAsphalt");
                SurfaceRow("10", "Snow", "25", "WetPavement");
                SurfaceRow("11", "MetalTrans", "26", "WetGrass");
                SurfaceRow("12", "GrassGreen", "27", "Snow2");
                SurfaceRow("13", "GrassBrown", "28", "TurboRoulette");
                SurfaceRow("14", "NotCollidable", "29", "FreeWheeling");
                UI::EndTable();
            }
            UI::Dummy(vec2(0, 4));
        }
    }
}
