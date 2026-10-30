using System.Globalization;
using System.IO;
using System.Text;
using UnityEditor;
using UnityEngine;

// Unity's own evaluation of curve-tangents.anim, as voice-vr's vr/golden/unity-curves.json: put both in an
// empty project's Assets (this under Assets/Editor) and run the editor with
// -batchmode -nographics -executeMethod Sample.Run, SAMPLE_OUT naming the output.
public static class Sample
{
    static string F(float v) => float.IsInfinity(v) ? "null" : v.ToString("R", CultureInfo.InvariantCulture);

    public static void Run()
    {
        AssetDatabase.ImportAsset("Assets/curve-tangents.anim", ImportAssetOptions.ForceUpdate);
        var clip = AssetDatabase.LoadAssetAtPath<AnimationClip>("Assets/curve-tangents.anim");
        var s = new StringBuilder("{");
        var first = true;
        foreach (var b in AnimationUtility.GetCurveBindings(clip))
        {
            var curve = AnimationUtility.GetEditorCurve(clip, b);
            s.Append(first ? "" : ",").Append("\n\"").Append(b.path).Append("\": {\"keys\": [");
            first = false;
            for (var i = 0; i < curve.keys.Length; i++)
            {
                var k = curve.keys[i];
                var w = (int)k.weightedMode;
                var weights = w == 0 ? "" : $", {F((w & 1) != 0 ? k.inWeight : 1f / 3f)}, {F((w & 2) != 0 ? k.outWeight : 1f / 3f)}";
                s.Append(i == 0 ? "" : ", ").Append($"[{F(k.time)}, {F(k.value)}, {F(k.inTangent)}, {F(k.outTangent)}{weights}]");
            }
            s.Append("], \"unity\": [");
            for (var i = 0; i < 20; i++)
            {
                var t = -0.05f + i * 1.4f / 19f;
                s.Append(i == 0 ? "" : ", ").Append($"[{F(t)}, {F(curve.Evaluate(t))}]");
            }
            s.Append("]}");
        }
        s.Append("\n}\n");
        File.WriteAllText(System.Environment.GetEnvironmentVariable("SAMPLE_OUT"), s.ToString());
        EditorApplication.Exit(0);
    }
}
