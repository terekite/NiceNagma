#!/usr/bin/env python3
"""Detect on-screen sam (beat 1) times from the cycle-wheel sweep hand.

The wheel is driven by the app's audio clock; the sweep hand points to the
current matra and crosses the top (12 o'clock) exactly at sam. This tracks the
hand's angle per frame (isolating the thin hand line in an annulus) and reports
the times it crosses the top — the ground-truth sam grid used to phase-lock the
dubbed soundtrack in scripts/build_track.py. Run it on the CFR working video
(demo/build/phone.mp4), not the raw VFR capture, so timestamps are exact.

Usage: detect_sam.py demo/build/phone.mp4
Geometry constants (CX,CY,R) are for the 1206x2622 iPhone 17 Pro simulator capture.
"""
import subprocess, sys, numpy as np
VID=sys.argv[1]
CX,CY,R=600.0,895.0,500.0
FPS=30.0
R_IN,R_OUT=0.34*R,0.68*R
W,H=1206,2622
buf=np.frombuffer(subprocess.run(["ffmpeg","-v","error","-i",VID,"-vf",f"fps={FPS},format=gray","-f","rawvideo","-"],capture_output=True).stdout,dtype=np.uint8)
nfr=buf.size//(W*H); buf=buf[:nfr*W*H].reshape(nfr,H,W)
ys,xs=np.mgrid[0:H,0:W]; dx=xs-CX; dy=ys-CY; rr=np.sqrt(dx*dx+dy*dy)
m=(rr>=R_IN)&(rr<=R_OUT); idx=np.where(m); ang=np.arctan2(dy[idx],dx[idx])
# also a wheel-activity gauge: mean brightness of the disc (dialogs drop a scrim → darker)
disc=(rr<=R_OUT); didx=np.where(disc)
angles=np.full(nfr,np.nan); darkcnt=np.zeros(nfr); scrim=np.zeros(nfr)
for i in range(nfr):
    g=buf[i][idx].astype(np.float32)
    scrim[i]=buf[i][didx].mean()
    dark=g<160; darkcnt[i]=dark.sum()
    if dark.sum()<15: continue
    w=(160.0-g); w[~dark]=0
    angles[i]=np.arctan2(np.sum(w*np.sin(ang)),np.sum(w*np.cos(ang)))
t=np.arange(nfr)/FPS
# unwrap continuous angle where valid; detect crossings of -90deg (up) in sweep dir
up=-np.pi/2
sams=[]
for i in range(1,nfr):
    a0,a1=angles[i-1],angles[i]
    if np.isnan(a0) or np.isnan(a1): continue
    if scrim[i]<205: continue  # skip dialog scrim frames (wheel dimmed)
    # signed distance to up
    d0=np.arctan2(np.sin(a0-up),np.cos(a0-up))
    d1=np.arctan2(np.sin(a1-up),np.cos(a1-up))
    # sweep is clockwise (angle increasing). sam when d crosses 0 upward-ish
    if d0<0 and d1>=0 and abs(d1-d0)<1.0:
        # linear interp crossing time
        frac=-d0/(d1-d0) if (d1-d0)!=0 else 0
        sams.append(t[i-1]+frac/FPS)
# merge within 0.6s
merged=[]
for s in sams:
    if not merged or s-merged[-1]>0.6: merged.append(s)
print("nfr",nfr,"dur",round(t[-1],2))
print("SAMS:",[round(s,2) for s in merged])
# intervals
iv=np.diff(merged)
print("INTERVALS:",[round(x,2) for x in iv])
# scrim dips (dialogs) 
lowscrim=[round(t[i],1) for i in range(nfr) if scrim[i]<200]
def runs(xs):
    out=[]; 
    for x in xs:
        if out and x-out[-1][1]<=0.4: out[-1][1]=x
        else: out.append([x,x])
    return [(a,b) for a,b in out if b-a>0.3]
print("DIALOG/DIM WINDOWS:",runs(lowscrim))
