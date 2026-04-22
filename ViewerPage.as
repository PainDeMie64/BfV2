string ViewerBridgeScript()
{
    string s = "";
    s += "<script>(function(){";
    s += "var runsByUid={};";
    s += "var readyPosted=false;";
    s += "var pendingMessages=[];";
    s += "function getApi(){return window.TMRenderer||window;}";
    s += "function hasApi(){var a=getApi();return !!(a&&a.addRaceStateTrack);}";
    s += "function postReady(){try{window.parent.postMessage({type:'tmviewer-ready'},'*');}catch(e){}}";
    s += "function toUid(v){var s=(v===null||v===undefined)?'':String(v);return s.length?s:'';}";
    s += "function toStates(payload){";
    s += "var src=Array.isArray(payload.samples)?payload.samples:[];";
    s += "var states=[];";
    s += "for(var i=0;i<src.length;i++){";
    s += "var smp=src[i]||{};var p=smp.position||{};var v=smp.velocity||{};var r=smp.rotation||{};var av=smp.angularVelocity||{};";
    s += "states.push({";
    s += "position:[Number(p.x)||0,Number(p.y)||0,Number(p.z)||0],";
    s += "velocity:[Number(v.x)||0,Number(v.y)||0,Number(v.z)||0],";
    s += "rotation:{x:Number(r.x)||0,y:Number(r.y)||0,z:Number(r.z)||0,w:(Number(r.w)||1)},";
    s += "angularVelocity:[Number(av.x)||0,Number(av.y)||0,Number(av.z)||0]";
    s += "});}";
    s += "return states;";
    s += "}";
    s += "function removeUidRun(uid){";
    s += "uid=toUid(uid);if(!uid)return true;";
    s += "if(!hasApi())return false;";
    s += "var api=getApi();";
    s += "var trackId=runsByUid[uid];";
    s += "if(!trackId)return true;";
    s += "try{";
    s += "if(api.removeRaceStateTrack){api.removeRaceStateTrack(trackId);}else if(api.setStateTrackVisible){api.setStateTrackVisible(trackId,false);}";
    s += "}catch(e){}";
    s += "delete runsByUid[uid];";
    s += "return true;";
    s += "}";
    s += "function upsertUidRun(payload){";
    s += "payload=payload||{};";
    s += "if(!hasApi())return false;";
    s += "var uid=toUid(payload.instanceUid);";
    s += "if(!uid)return true;";
    s += "var api=getApi();";
    s += "var prevId=runsByUid[uid]||null;";
    s += "var wasEnabled=false;var wasFollow=false;";
    s += "try{";
    s += "if(prevId&&api.isStateTrackVisible)wasEnabled=!!api.isStateTrackVisible(prevId);";
    s += "if(prevId&&api.getCameraFollowTrack)wasFollow=(api.getCameraFollowTrack()===prevId);";
    s += "}catch(e){}";
    s += "var states=toStates(payload);";
    s += "if(states.length===0){removeUidRun(uid);return true;}";
    s += "var period=Math.max(1,Number(payload.samplePeriodMs)||10);";
    s += "var label=(payload.label&&String(payload.label).length)?String(payload.label):('Initial '+uid);";
    s += "var newId=api.addRaceStateTrack(label,period,states);";
    s += "runsByUid[uid]=newId;";
    s += "if(wasEnabled&&api.setStateTrackVisible)api.setStateTrackVisible(newId,true);";
    s += "if(wasFollow&&api.setCameraFollowTrack)api.setCameraFollowTrack(newId);";
    s += "if(prevId&&prevId!==newId){try{if(api.removeRaceStateTrack)api.removeRaceStateTrack(prevId);else if(api.setStateTrackVisible)api.setStateTrackVisible(prevId,false);}catch(e){}}";
    s += "return true;";
    s += "}";
    s += "function applyMessage(msg){";
    s += "if(!msg||typeof msg!=='object')return true;";
    s += "if(msg.type==='tmviewer-upsert-instance-run')return upsertUidRun(msg.payload||{});";
    s += "if(msg.type==='tmviewer-remove-instance-run')return removeUidRun(msg.instanceUid);";
    s += "if(msg.type==='tmviewer-replace-initial-run'){";
    s += "var p=msg.payload||{};";
    s += "if(!p.instanceUid)p.instanceUid='legacy';";
    s += "if(!p.label)p.label='Initial phase';";
    s += "return upsertUidRun(p);";
    s += "}";
    s += "return true;";
    s += "}";
    s += "function flushReady(){";
    s += "if(!readyPosted&&hasApi()){readyPosted=true;postReady();}";
    s += "if(!hasApi())return;";
    s += "if(pendingMessages.length){";
    s += "var list=pendingMessages.slice();pendingMessages=[];";
    s += "for(var i=0;i<list.length;i++){if(!applyMessage(list[i]))pendingMessages.push(list[i]);}";
    s += "}";
    s += "}";
    s += "window.addEventListener('message',function(ev){";
    s += "var msg=ev&&ev.data?ev.data:null;";
    s += "if(!msg)return;";
    s += "if(!applyMessage(msg))pendingMessages.push(msg);";
    s += "});";
    s += "if(document.readyState==='complete'||document.readyState==='interactive')setTimeout(flushReady,0);";
    s += "else document.addEventListener('DOMContentLoaded',flushReady);";
    s += "var readyInt=setInterval(function(){flushReady();if(readyPosted)clearInterval(readyInt);},100);";
    s += "})();</script>";
    return s;
}

string HandleViewerSingle(const string &in body)
{
    string html = GetEmbeddedViewerSingleHtml();
    if (html.Length == 0)
    {
        return "<!DOCTYPE html><html><body style='font-family:sans-serif;background:#0d1117;color:#c9d1d9'>"
            + "<h2>Viewer HTML not embedded</h2>"
            + "<p>Run <code>scripts/generate_viewer_single_embed.mjs</code> in <code>BfV2Dashboard</code>.</p>"
            + "</body></html>";
    }

    string bridge = ViewerBridgeScript();
    int bodyEnd = html.FindLast("</body>");
    if (bodyEnd >= 0)
    {
        return html.Substr(0, bodyEnd) + bridge + html.Substr(bodyEnd);
    }
    return html + bridge;
}
