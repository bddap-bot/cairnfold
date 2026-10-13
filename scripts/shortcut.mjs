// Adds or corrects the "Cairnfold" Steam library VR shortcut to run INSTALL_DIR/play.sh, through the headset's
// Steam client (its CEF debugger on 127.0.0.1:8080, which developer mode serves) tunnelled over ssh:
// shortcut.mjs INSTALL_DIR [SSH_OPTION...] SSH_HOST
import { spawn } from 'node:child_process';
import net from 'node:net';

const [dir, ...ssh] = process.argv.slice(2);
const port = await new Promise(resolve => {
  const s = net.createServer().listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => resolve(p)); });
});
const cdp = `http://127.0.0.1:${port}`;
const tunnel = spawn('ssh', [...ssh.slice(0, -1), '-N', '-o', 'ExitOnForwardFailure=yes', '-L', `${port}:127.0.0.1:8080`, ssh.at(-1)], { stdio: 'ignore' });
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

const steamEval = async expression => {
  let targets;
  for (let i = 0; ; i++) {
    try { targets = await (await fetch(`${cdp}/json/list`, { signal: AbortSignal.timeout(5000) })).json(); break; } catch (e) {
      if (i === 50 || tunnel.exitCode !== null || tunnel.signalCode !== null) throw new Error(`the headset's Steam CEF debugger is unreachable: ${e.message}`);
      await delay(200);
    }
  }
  const path = targets.find(t => t?.title === 'SharedJSContext')?.webSocketDebuggerUrl?.replace(/^ws:\/\/[^/]+/, '');
  if (!path) throw new Error('the headset\'s Steam has no SharedJSContext');
  const ws = new WebSocket(`ws://127.0.0.1:${port}${path}`);
  return await new Promise((resolve, reject) => {
    setTimeout(() => reject(new Error('CEF evaluation timed out')), 30000).unref();
    ws.onerror = () => reject(new Error('CEF websocket failed'));
    ws.onopen = () => ws.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: { expression, returnByValue: true, awaitPromise: true } }));
    ws.onclose = () => reject(new Error('CEF websocket closed'));
    ws.onmessage = m => {
      const { id, result } = JSON.parse(m.data);
      if (id !== 1) return;
      ws.close();
      if (result?.exceptionDetails) reject(new Error(result.exceptionDetails.exception?.description ?? result.exceptionDetails.text));
      else resolve(result?.result?.value);
    };
  });
};

const want = { exe: JSON.stringify(`${dir}/play.sh`), startDir: dir };
try {
  const got = await steamEval(`(async () => {
    const want = ${JSON.stringify(want)};
    const details = appid => new Promise(resolve => {
      // The callback can fire synchronously, before the registration is returned.
      let r, got;
      r = SteamClient.Apps.RegisterForAppDetails(appid, d => { got = d; r?.unregister?.(); resolve(d); });
      if (got) r?.unregister?.();
    });
    let appid = appStore.allApps.find(a => a.app_type === 1073741824 && a.display_name === 'Cairnfold')?.appid;
    if (appid === undefined) {
      appid = await SteamClient.Apps.AddShortcut('Cairnfold', want.exe, '', want.startDir);
      // AddShortcut names the tile after the executable.
      SteamClient.Apps.SetShortcutName(appid, 'Cairnfold');
    }
    SteamClient.Apps.SetShortcutExe(appid, want.exe);
    SteamClient.Apps.SetShortcutStartDir(appid, want.startDir);
    SteamClient.Apps.SetShortcutLaunchOptions(appid, '');
    SteamClient.Apps.SetShortcutIsVR(appid, true);
    for (let i = 0; ; i++) {
      const d = await details(appid);
      const ok = d.strShortcutExe === want.exe && d.strShortcutStartDir === want.startDir && !d.strShortcutLaunchOptions && d.bShortcutIsVR;
      if (ok || i === 20) return { appid, ok, exe: d.strShortcutExe, startDir: d.strShortcutStartDir, launchOptions: d.strShortcutLaunchOptions, vr: d.bShortcutIsVR };
      await new Promise(r => setTimeout(r, 250));
    }
  })()`);
  console.log(JSON.stringify(got));
  if (!got?.ok) {
    console.error('the shortcut did not take');
    process.exitCode = 1;
  }
} finally {
  tunnel.kill();
}
