import os
PS4_IP = os.environ.get('PS4_IP', '192.168.1.100')  # your console
import ftplib, sys
tag = sys.argv[1]
for n in ('boot.txt', 'crash.txt', 'log.txt'):
    try:
        f = ftplib.FTP(); f.connect(PS4_IP, 2121, timeout=30); f.login()
        with open(tag + '_' + n, 'wb') as o: f.retrbinary('RETR /data/skate3/' + n, o.write)
        try: f.quit()
        except Exception: pass
    except Exception as e: print(n, 'missing:', e)
