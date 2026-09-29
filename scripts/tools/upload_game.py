import os
PS4_IP = os.environ.get('PS4_IP', '192.168.1.100')  # your console
# Resumable upload of the extracted Skate 3 disc (+ TU3 xexp) to the console: /data/skate3/game
import ftplib, os, sys, time
SRC = os.environ.get('SKATE3_GAME_DIR', r'..\..\..\skate3recomp\game')
DST = '/data/skate3/game'
log = open('upload_game.log', 'a', buffering=1)
def connect():
    f = ftplib.FTP(); f.connect(PS4_IP, 2121, timeout=60); f.login(); return f
f = connect()
def mkd(p):
    try: f.mkd(p)
    except ftplib.error_perm: pass
files = []
for root, dirs, names in os.walk(SRC):
    rel = os.path.relpath(root, SRC).replace(os.sep, '/')
    for n in names:
        files.append((os.path.join(root, n), (DST + '/' + ('' if rel == '.' else rel + '/') + n)))
total = sum(os.path.getsize(p) for p, _ in files); done = 0; t0 = time.time()
mkd('/data/skate3'); mkd(DST)
made = set()
for local, remote in files:
    d = remote.rsplit('/', 1)[0]
    parts = d.split('/')
    for i in range(3, len(parts) + 1):
        sub = '/'.join(parts[:i])
        if sub not in made: mkd(sub); made.add(sub)
    size = os.path.getsize(local)
    try: have = f.size(remote)
    except Exception: have = -1
    if have == size:
        done += size; continue
    for attempt in range(3):
        try:
            with open(local, 'rb') as fh: f.storbinary('STOR ' + remote, fh, blocksize=1 << 20)
            break
        except Exception as e:
            log.write(f'retry {remote}: {e}\n'); time.sleep(3); f = connect()
    done += size
    el = time.time() - t0
    log.write(f'{done/2**30:.2f}/{total/2**30:.2f} GB  {done/max(el,1)/2**20:.1f} MB/s  {remote}\n')
log.write('UPLOAD COMPLETE\n')
