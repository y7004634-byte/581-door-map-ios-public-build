import json,os,subprocess,sys
from pathlib import Path
repo=Path(__file__).resolve().parents[1]
roots={'accepted':repo.parent/'native-restoration-reference/fitlock6/public','native':repo/'DoorMap581/Behavior'}
if '--native-only' in sys.argv:roots={'native':roots['native']}
results=[]
for target,root in roots.items():
    for test in sorted((repo/'scripts/reference-tests').glob('*.mjs')):
        env=dict(os.environ,DOOR_TEST_ROOT=str(root.resolve()).replace('\\','/'))
        done=subprocess.run(['node',str(test)],env=env,cwd=repo,capture_output=True,text=True,encoding='utf-8')
        results.append({'target':target,'test':test.name,'exit':done.returncode,'output':done.stdout,'error':done.stderr})
        print(target,test.name,'PASS' if done.returncode==0 else 'FAIL')
        if done.returncode:print(done.stderr)
native_only='--native-only' in sys.argv
name='NATIVE_REGRESSION_RESULTS.json' if native_only else 'REFERENCE_REGRESSION_RESULTS.json'
outdir=(repo/'cloud-build'/'native-port') if native_only else (repo/'docs')
outdir.mkdir(parents=True,exist_ok=True)
(outdir/name).write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
sys.exit(0 if all(r['exit']==0 for r in results) else 1)
