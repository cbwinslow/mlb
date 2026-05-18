#!/usr/bin/env python3
"""
push_mlb_ai_setup.py
====================
Pushes the full AI review + auto-fix setup to cbwinslow/mlb:

  GitHub Actions Workflows (.github/workflows/)
  ─────────────────────────────────────────────
  openrouter_review.yml    PR review via OpenRouter free top models
  aider_ci_autofix.yml     CI failure → Aider auto-fix draft PR
  gemini_autofix.yml       Issue labeled 'ai-fix' → Gemini CLI auto-fix draft PR
  gemini_pr_review.yml     PR review via Gemini CLI free tier

  AI Tool Configs (repo root)
  ───────────────────────────
  .coderabbit.yaml         CodeRabbit inline review + custom rules
  .pr_agent.toml           Qodo Merge (PR Agent) config
  .gemini/config.yaml      Gemini Code Assist architectural context
  .kilo/kilo.jsonc         Kilo Code workspace config

Free OpenRouter models used (strongest first, all contain ':free'):
  openrouter/owl-alpha:free              947B agentic
  nvidia/nemotron-3-super-120b-a12b:free 120B MoE SWE-bench leader 1M ctx
  poolside/laguna-m.1:free               flagship coding agent 128K ctx
  openai/gpt-oss-120b:free               117B MoE chain-of-thought tool use
  minimax/minimax-m2.5:free              80.2% SWE-bench 205K context
  deepseek/deepseek-v4-flash:free        284B total MoE 1M context
  google/gemma-4-31b:free                31B dense 256K ctx (Gemma 4)
  openrouter/free                        auto-router fallback

Usage:
  export GITHUB_TOKEN="ghp_your_token_here"
  python push_mlb_ai_setup.py

Required GitHub Secrets (Settings > Secrets and variables > Actions):
  GEMINI_API_KEY       aistudio.google.com  (free, no card)
  OPENROUTER_API_KEY   openrouter.ai        (free, no card)
  GITHUB_TOKEN is injected automatically by Actions - no setup needed
"""

import base64
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

# ── Config ────────────────────────────────────────────────────────────────────

OWNER  = "cbwinslow"
REPO   = "mlb"
BRANCH = "main"
API    = "https://api.github.com"
TOKEN  = os.environ.get("GITHUB_TOKEN", "")

if not TOKEN:
    sys.exit("ERROR: Set GITHUB_TOKEN environment variable first.\n"
             "  export GITHUB_TOKEN=\'ghp_your_token_here\'")

# ── File contents (base64-encoded to survive any quoting) ─────────────────────

OPENROUTER_REVIEW = base64.b64decode("""IyBGcmVlIG1vZGVscyByYW5rZWQgYnkgc3RyZW5ndGggKE1heSAyMDI2IE9wZW5Sb3V0ZXIpOgojICAgMS4gb3BlbnJvdXRlci9vd2wtYWxwaGE6ZnJlZSAgICAgICAgICAgICAgOTQ3QiBhZ2VudGljLCBDbGF1ZGUgQ29kZSBjb21wYXRpYmxlCiMgICAyLiBudmlkaWEvbmVtb3Ryb24tMy1zdXBlci0xMjBiLWExMmI6ZnJlZSAxMjBCIE1vRSBTV0UtYmVuY2ggbGVhZGVyIDFNIGN0eAojICAgMy4gcG9vbHNpZGUvbGFndW5hLW0uMTpmcmVlICAgICAgICAgICAgICAgZmxhZ3NoaXAgY29kaW5nIGFnZW50IDEyOEsgY3R4CiMgICA0LiBvcGVuYWkvZ3B0LW9zcy0xMjBiOmZyZWUgICAgICAgICAgICAgICAxMTdCIE1vRSBjaGFpbi1vZi10aG91Z2h0IHRvb2wgdXNlCiMgICA1LiBtaW5pbWF4L21pbmltYXgtbTIuNTpmcmVlICAgICAgICAgICAgICA4MC4yJSBTV0UtYmVuY2ggMjA1SyBjb250ZXh0CiMgICA2LiBkZWVwc2Vlay9kZWVwc2Vlay12NC1mbGFzaDpmcmVlICAgICAgICAyODRCIHRvdGFsIE1vRSAxTSBjb250ZXh0CiMgICA3LiBnb29nbGUvZ2VtbWEtNC0zMWI6ZnJlZSAgICAgICAgICAgICAgICAzMUIgZGVuc2UgMjU2SyBjdHggcmVhc29uaW5nCiMgICA4LiBvcGVucm91dGVyL2ZyZWUgICAgICAgICAgICAgICAgICAgICAgICBhdXRvLXJvdXRlciBmYWxsYmFjawoKbmFtZTogT3BlblJvdXRlciBQUiBSZXZpZXcgKGZyZWUgdG9wIG1vZGVscykKCm9uOgogIHB1bGxfcmVxdWVzdDoKICAgIHR5cGVzOiBbb3BlbmVkLCBzeW5jaHJvbml6ZSwgcmVvcGVuZWRdCgpwZXJtaXNzaW9uczoKICBwdWxsLXJlcXVlc3RzOiB3cml0ZQogIGNvbnRlbnRzOiByZWFkCgpqb2JzOgogIG9wZW5yb3V0ZXItcmV2aWV3OgogICAgbmFtZTogQUkgUFIgcmV2aWV3IHZpYSBPcGVuUm91dGVyIGZyZWUgdGllcgogICAgcnVucy1vbjogdWJ1bnR1LWxhdGVzdAoKICAgIHN0ZXBzOgogICAgICAtIG5hbWU6IENoZWNrb3V0CiAgICAgICAgdXNlczogYWN0aW9ucy9jaGVja291dEB2NAogICAgICAgIHdpdGg6CiAgICAgICAgICBmZXRjaC1kZXB0aDogMAoKICAgICAgLSBuYW1lOiBTZXQgdXAgUHl0aG9uCiAgICAgICAgdXNlczogYWN0aW9ucy9zZXR1cC1weXRob25AdjUKICAgICAgICB3aXRoOgogICAgICAgICAgcHl0aG9uLXZlcnNpb246ICczLjEyJwoKICAgICAgLSBuYW1lOiBJbnN0YWxsIHJlcXVlc3RzCiAgICAgICAgcnVuOiBwaXAgaW5zdGFsbCByZXF1ZXN0cwoKICAgICAgLSBuYW1lOiBHZXQgUFIgZGlmZgogICAgICAgIGVudjoKICAgICAgICAgIEdIX1RPS0VOOiAke3sgc2VjcmV0cy5HSVRIVUJfVE9LRU4gfX0KICAgICAgICBydW46IHwKICAgICAgICAgIGdoIHByIGRpZmYgJHt7IGdpdGh1Yi5ldmVudC5wdWxsX3JlcXVlc3QubnVtYmVyIH19IFwKICAgICAgICAgICAgLS1yZXBvICR7eyBnaXRodWIucmVwb3NpdG9yeSB9fSA+IC90bXAvcHJfZGlmZi50eHQgMj4vZGV2L251bGwgfHwgXAogICAgICAgICAgICBnaXQgZGlmZiBvcmlnaW4vbWFpbi4uLkhFQUQgPiAvdG1wL3ByX2RpZmYudHh0CgogICAgICAtIG5hbWU6IFJ1biBPcGVuUm91dGVyIHJldmlldwogICAgICAgIGVudjoKICAgICAgICAgIE9QRU5ST1VURVJfQVBJX0tFWTogJHt7IHNlY3JldHMuT1BFTlJPVVRFUl9BUElfS0VZIH19CiAgICAgICAgcnVuOiB8CiAgICAgICAgICBweXRob24zIC0gPDwgJ1BZRU9GJwogICAgICAgICAgaW1wb3J0IG9zLCByZXF1ZXN0cywgc3lzCiAgICAgICAgICBhcGlfa2V5ID0gb3MuZW52aXJvbi5nZXQoIk9QRU5ST1VURVJfQVBJX0tFWSIsICIiKQogICAgICAgICAgaWYgbm90IGFwaV9rZXk6CiAgICAgICAgICAgICAgcHJpbnQoIk9QRU5ST1VURVJfQVBJX0tFWSBub3Qgc2V0IC0tIHNraXBwaW5nLiIpCiAgICAgICAgICAgICAgc3lzLmV4aXQoMCkKICAgICAgICAgIGRpZmYgPSBvcGVuKCIvdG1wL3ByX2RpZmYudHh0IikucmVhZCgpWzoxNDAwMF0KICAgICAgICAgIHByb21wdCA9ICgKICAgICAgICAgICAgICAiWW91IGFyZSBhbiBleHBlcnQgY29kZSByZXZpZXdlciBmb3IgdGhlIG1sYiBQb3N0Z3JlU1FMIGFuYWx5dGljcyBwbGF0Zm9ybS5cblxuIgogICAgICAgICAgICAgICJDUklUSUNBTCBmbGFnOlxuIgogICAgICAgICAgICAgICItIEhhcmRjb2RlZCBzZWNyZXRzLCBBUEkga2V5cywgREFUQUJBU0VfVVJMIHdpdGggY3JlZGVudGlhbHNcbiIKICAgICAgICAgICAgICAiLSBQeXRob24gbG9nZ2luZyByYXcgREFUQUJBU0VfVVJMXG4iCiAgICAgICAgICAgICAgIi0gTWlzc2luZyB3b3Jrc3BhY2VfaWQgb24gbXVsdGktdGVuYW50IGluc2VydHNcbiIKICAgICAgICAgICAgICAiLSBCYXJlIGV4Y2VwdDogY2xhdXNlc1xuIgogICAgICAgICAgICAgICItIEluZ2VzdGlvbiBtaXhpbmcgc291cmNlIGFjcXVpc2l0aW9uIHdpdGggY2Fub25pY2FsIHRyYW5zZm9ybVxuIgogICAgICAgICAgICAgICItIEdpdEh1YiBBY3Rpb25zIHN0ZXBzIGVjaG9pbmcgc2VjcmV0c1xuXG4iCiAgICAgICAgICAgICAgIlNFQ09OREFSWSBmbGFnOlxuIgogICAgICAgICAgICAgICItIE11dGFibGUgZGVmYXVsdCBhcmd1bWVudHNcbiIKICAgICAgICAgICAgICAiLSBNaXNzaW5nIE5PVCBOVUxMIG9uIHJlcXVpcmVkIFNRTCBjb2x1bW5zXG5cbiIKICAgICAgICAgICAgICAiU2tpcCBydWZmLWhhbmRsZWQgZm9ybWF0dGluZy4gQmUgY29uY2lzZS4gT3V0cHV0IG1hcmtkb3duLlxuXG4iCiAgICAgICAgICAgICAgIlBSIERJRkY6XG4iICsgZGlmZgogICAgICAgICAgKQogICAgICAgICAgbW9kZWxzID0gWwogICAgICAgICAgICAgICJvcGVucm91dGVyL293bC1hbHBoYTpmcmVlIiwKICAgICAgICAgICAgICAibnZpZGlhL25lbW90cm9uLTMtc3VwZXItMTIwYi1hMTJiOmZyZWUiLAogICAgICAgICAgICAgICJwb29sc2lkZS9sYWd1bmEtbS4xOmZyZWUiLAogICAgICAgICAgICAgICJvcGVuYWkvZ3B0LW9zcy0xMjBiOmZyZWUiLAogICAgICAgICAgICAgICJtaW5pbWF4L21pbmltYXgtbTIuNTpmcmVlIiwKICAgICAgICAgICAgICAiZGVlcHNlZWsvZGVlcHNlZWstdjQtZmxhc2g6ZnJlZSIsCiAgICAgICAgICAgICAgImdvb2dsZS9nZW1tYS00LTMxYjpmcmVlIiwKICAgICAgICAgICAgICAib3BlbnJvdXRlci9mcmVlIiwKICAgICAgICAgIF0KICAgICAgICAgIHJldmlldyA9IE5vbmUKICAgICAgICAgIG1vZGVsX3VzZWQgPSBOb25lCiAgICAgICAgICBmb3IgbW9kZWwgaW4gbW9kZWxzOgogICAgICAgICAgICAgIHRyeToKICAgICAgICAgICAgICAgICAgcmVzcCA9IHJlcXVlc3RzLnBvc3QoCiAgICAgICAgICAgICAgICAgICAgICAiaHR0cHM6Ly9vcGVucm91dGVyLmFpL2FwaS92MS9jaGF0L2NvbXBsZXRpb25zIiwKICAgICAgICAgICAgICAgICAgICAgIGhlYWRlcnM9ewogICAgICAgICAgICAgICAgICAgICAgICAgICJBdXRob3JpemF0aW9uIjogIkJlYXJlciAiICsgYXBpX2tleSwKICAgICAgICAgICAgICAgICAgICAgICAgICAiQ29udGVudC1UeXBlIjogImFwcGxpY2F0aW9uL2pzb24iLAogICAgICAgICAgICAgICAgICAgICAgICAgICJIVFRQLVJlZmVyZXIiOiAiaHR0cHM6Ly9naXRodWIuY29tL2Nid2luc2xvdy9tbGIiLAogICAgICAgICAgICAgICAgICAgICAgICAgICJYLVRpdGxlIjogIm1sYi1wci1yZXZpZXciLAogICAgICAgICAgICAgICAgICAgICAgfSwKICAgICAgICAgICAgICAgICAgICAgIGpzb249ewogICAgICAgICAgICAgICAgICAgICAgICAgICJtb2RlbCI6IG1vZGVsLAogICAgICAgICAgICAgICAgICAgICAgICAgICJtZXNzYWdlcyI6IFt7InJvbGUiOiAidXNlciIsICJjb250ZW50IjogcHJvbXB0fV0sCiAgICAgICAgICAgICAgICAgICAgICAgICAgIm1heF90b2tlbnMiOiAyMDAwLAogICAgICAgICAgICAgICAgICAgICAgfSwKICAgICAgICAgICAgICAgICAgICAgIHRpbWVvdXQ9OTAsCiAgICAgICAgICAgICAgICAgICkKICAgICAgICAgICAgICAgICAgZGF0YSA9IHJlc3AuanNvbigpCiAgICAgICAgICAgICAgICAgIGlmICJjaG9pY2VzIiBpbiBkYXRhIGFuZCBkYXRhWyJjaG9pY2VzIl06CiAgICAgICAgICAgICAgICAgICAgICByZXZpZXcgPSBkYXRhWyJjaG9pY2VzIl1bMF1bIm1lc3NhZ2UiXVsiY29udGVudCJdCiAgICAgICAgICAgICAgICAgICAgICBtb2RlbF91c2VkID0gbW9kZWwKICAgICAgICAgICAgICAgICAgICAgIGJyZWFrCiAgICAgICAgICAgICAgICAgIHByaW50KCJNb2RlbCAiICsgbW9kZWwgKyAiIHJldHVybmVkIG5vIGNob2ljZXMiKQogICAgICAgICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZToKICAgICAgICAgICAgICAgICAgcHJpbnQoIk1vZGVsICIgKyBtb2RlbCArICIgZmFpbGVkOiAiICsgc3RyKGUpKQogICAgICAgICAgaWYgbm90IHJldmlldzoKICAgICAgICAgICAgICBwcmludCgiQWxsIG1vZGVscyBmYWlsZWQgLS0gc2tpcHBpbmcgcmV2aWV3LiIpCiAgICAgICAgICAgICAgc3lzLmV4aXQoMCkKICAgICAgICAgIG91dHB1dCA9ICIjIyBPcGVuUm91dGVyIEFJIFJldmlld1xuXG5fTW9kZWw6IGAiICsgbW9kZWxfdXNlZCArICJgX1xuXG4iICsgcmV2aWV3CiAgICAgICAgICBvcGVuKCIvdG1wL3Jldmlld19vdXRwdXQubWQiLCAidyIpLndyaXRlKG91dHB1dCkKICAgICAgICAgIHByaW50KCJSZXZpZXcgZ2VuZXJhdGVkIHVzaW5nICIgKyBtb2RlbF91c2VkICsgIiAoIiArIHN0cihsZW4ocmV2aWV3KSkgKyAiIGNoYXJzKSIpCiAgICAgICAgICBQWUVPRgoKICAgICAgLSBuYW1lOiBQb3N0IHJldmlldyBjb21tZW50CiAgICAgICAgZW52OgogICAgICAgICAgR0hfVE9LRU46ICR7eyBzZWNyZXRzLkdJVEhVQl9UT0tFTiB9fQogICAgICAgIHJ1bjogfAogICAgICAgICAgaWYgWyAtZiAvdG1wL3Jldmlld19vdXRwdXQubWQgXSAmJiBbIC1zIC90bXAvcmV2aWV3X291dHB1dC5tZCBdOyB0aGVuCiAgICAgICAgICAgIGdoIHByIGNvbW1lbnQgJHt7IGdpdGh1Yi5ldmVudC5wdWxsX3JlcXVlc3QubnVtYmVyIH19IFwKICAgICAgICAgICAgICAtLXJlcG8gJHt7IGdpdGh1Yi5yZXBvc2l0b3J5IH19IFwKICAgICAgICAgICAgICAtLWJvZHktZmlsZSAvdG1wL3Jldmlld19vdXRwdXQubWQKICAgICAgICAgIGZpCg==""").decode()

AIDER_CI_AUTOFIX = base64.b64decode("""IyBGcmVlIG1vZGVscyByYW5rZWQgYnkgc3RyZW5ndGggKE1heSAyMDI2IE9wZW5Sb3V0ZXIpOgojICAgMS4gb3BlbnJvdXRlci9vd2wtYWxwaGE6ZnJlZSAgICAgICAgICAgICAgOTQ3QiBhZ2VudGljLCBDbGF1ZGUgQ29kZSBjb21wYXRpYmxlCiMgICAyLiBudmlkaWEvbmVtb3Ryb24tMy1zdXBlci0xMjBiLWExMmI6ZnJlZSAxMjBCIE1vRSBTV0UtYmVuY2ggbGVhZGVyIDFNIGN0eAojICAgMy4gcG9vbHNpZGUvbGFndW5hLW0uMTpmcmVlICAgICAgICAgICAgICAgZmxhZ3NoaXAgY29kaW5nIGFnZW50IDEyOEsgY3R4CiMgICA0LiBvcGVuYWkvZ3B0LW9zcy0xMjBiOmZyZWUgICAgICAgICAgICAgICAxMTdCIE1vRSBjaGFpbi1vZi10aG91Z2h0IHRvb2wgdXNlCiMgICA1LiBtaW5pbWF4L21pbmltYXgtbTIuNTpmcmVlICAgICAgICAgICAgICA4MC4yJSBTV0UtYmVuY2ggMjA1SyBjb250ZXh0CiMgICA2LiBkZWVwc2Vlay9kZWVwc2Vlay12NC1mbGFzaDpmcmVlICAgICAgICAyODRCIHRvdGFsIE1vRSAxTSBjb250ZXh0CiMgICA3LiBnb29nbGUvZ2VtbWEtNC0zMWI6ZnJlZSAgICAgICAgICAgICAgICAzMUIgZGVuc2UgMjU2SyBjdHggcmVhc29uaW5nCiMgICA4LiBvcGVucm91dGVyL2ZyZWUgICAgICAgICAgICAgICAgICAgICAgICBhdXRvLXJvdXRlciBmYWxsYmFjawoKbmFtZTogQWlkZXIgQ0kgQXV0by1GaXggdmlhIE9wZW5Sb3V0ZXIgKGZyZWUgdG9wIG1vZGVscykKCm9uOgogIHdvcmtmbG93X3J1bjoKICAgIHdvcmtmbG93czogWyJDSSJdCiAgICB0eXBlczogW2NvbXBsZXRlZF0KCnBlcm1pc3Npb25zOgogIGNvbnRlbnRzOiB3cml0ZQogIHB1bGwtcmVxdWVzdHM6IHdyaXRlCgpqb2JzOgogIGFpZGVyLWZpeDoKICAgIG5hbWU6IEFpZGVyIGF1dG8tZml4IHVzaW5nIE9wZW5Sb3V0ZXIgdG9wIGZyZWUgbW9kZWwKICAgIHJ1bnMtb246IHVidW50dS1sYXRlc3QKICAgIGlmOiAke3sgZ2l0aHViLmV2ZW50LndvcmtmbG93X3J1bi5jb25jbHVzaW9uID09ICdmYWlsdXJlJyB9fQoKICAgIHN0ZXBzOgogICAgICAtIG5hbWU6IENoZWNrb3V0IGZhaWxpbmcgY29tbWl0CiAgICAgICAgdXNlczogYWN0aW9ucy9jaGVja291dEB2NAogICAgICAgIHdpdGg6CiAgICAgICAgICByZWY6ICR7eyBnaXRodWIuZXZlbnQud29ya2Zsb3dfcnVuLmhlYWRfc2hhIH19CiAgICAgICAgICBmZXRjaC1kZXB0aDogMAoKICAgICAgLSBuYW1lOiBTZXQgdXAgUHl0aG9uCiAgICAgICAgdXNlczogYWN0aW9ucy9zZXR1cC1weXRob25AdjUKICAgICAgICB3aXRoOgogICAgICAgICAgcHl0aG9uLXZlcnNpb246ICczLjEyJwoKICAgICAgLSBuYW1lOiBJbnN0YWxsIEFpZGVyIGFuZCBwcm9qZWN0CiAgICAgICAgcnVuOiB8CiAgICAgICAgICBwaXAgaW5zdGFsbCBhaWRlci1jaGF0IHJlcXVlc3RzCiAgICAgICAgICBwaXAgaW5zdGFsbCAtZSAuIDI+L2Rldi9udWxsIHx8IHRydWUKCiAgICAgIC0gbmFtZTogQ2FwdHVyZSB0ZXN0IGZhaWx1cmVzCiAgICAgICAgcnVuOiBweXRob24gLW0gcHl0ZXN0IC0tdGI9c2hvcnQgLXEgMj4mMSB8IHRlZSAvdG1wL3Rlc3Rfb3V0cHV0LnR4dCB8fCB0cnVlCgogICAgICAtIG5hbWU6IFJ1biBBaWRlciB3aXRoIGJlc3QgYXZhaWxhYmxlIGZyZWUgT3BlblJvdXRlciBtb2RlbAogICAgICAgIGVudjoKICAgICAgICAgIE9QRU5ST1VURVJfQVBJX0tFWTogJHt7IHNlY3JldHMuT1BFTlJPVVRFUl9BUElfS0VZIH19CiAgICAgICAgcnVuOiB8CiAgICAgICAgICBpZiBbIC16ICIkT1BFTlJPVVRFUl9BUElfS0VZIiBdOyB0aGVuCiAgICAgICAgICAgIGVjaG8gIk9QRU5ST1VURVJfQVBJX0tFWSBub3Qgc2V0IC0tIHNraXBwaW5nLiIgPiYyOyBleGl0IDAKICAgICAgICAgIGZpCiAgICAgICAgICBGQUlMVVJFPSQodGFpbCAtODAgL3RtcC90ZXN0X291dHB1dC50eHQpCiAgICAgICAgICBmb3IgTU9ERUwgaW4gXAogICAgICAgICAgICAibnZpZGlhL25lbW90cm9uLTMtc3VwZXItMTIwYi1hMTJiOmZyZWUiIFwKICAgICAgICAgICAgInBvb2xzaWRlL2xhZ3VuYS1tLjE6ZnJlZSIgXAogICAgICAgICAgICAib3BlbmFpL2dwdC1vc3MtMTIwYjpmcmVlIiBcCiAgICAgICAgICAgICJtaW5pbWF4L21pbmltYXgtbTIuNTpmcmVlIiBcCiAgICAgICAgICAgICJkZWVwc2Vlay9kZWVwc2Vlay12NC1mbGFzaDpmcmVlIiBcCiAgICAgICAgICAgICJvcGVucm91dGVyL2ZyZWUiOyBkbwogICAgICAgICAgICBlY2hvICJUcnlpbmcgJE1PREVMIgogICAgICAgICAgICBhaWRlciBcCiAgICAgICAgICAgICAgLS1vcGVuYWktYXBpLWtleSAiJE9QRU5ST1VURVJfQVBJX0tFWSIgXAogICAgICAgICAgICAgIC0tb3BlbmFpLWFwaS1iYXNlICJodHRwczovL29wZW5yb3V0ZXIuYWkvYXBpL3YxIiBcCiAgICAgICAgICAgICAgLS1tb2RlbCAib3BlbnJvdXRlci8kTU9ERUwiIFwKICAgICAgICAgICAgICAtLW1lc3NhZ2UgIkZpeCB0aGUgZmFpbGluZyB0ZXN0cyBpbiB0aGlzIFB5dGhvbiBNTEIgYW5hbHl0aWNzIHJlcG8uCiAgICAgICAgICBNaW5pbWFsIHN1cmdpY2FsIGNoYW5nZSBvbmx5LiBOZXZlciBjb21taXQgc2VjcmV0cyBvciByYXcgREFUQUJBU0VfVVJMLgogICAgICAgICAgTmV2ZXIgcmVmYWN0b3IgdW5yZWxhdGVkIGNvZGUuCgogICAgICAgICAgVGVzdCBmYWlsdXJlczoKICAgICAgICAgICRGQUlMVVJFIiBcCiAgICAgICAgICAgICAgLS15ZXMgLS1uby1naXQgMj4mMSB8IHRlZSAvdG1wL2FpZGVyX291dHB1dC50eHQgJiYgYnJlYWsgfHwgdHJ1ZQogICAgICAgICAgZG9uZQoKICAgICAgLSBuYW1lOiBDcmVhdGUgZHJhZnQgZml4IFBSCiAgICAgICAgZW52OgogICAgICAgICAgR0hfVE9LRU46ICR7eyBzZWNyZXRzLkdJVEhVQl9UT0tFTiB9fQogICAgICAgIHJ1bjogfAogICAgICAgICAgZ2l0IGNvbmZpZyB1c2VyLm5hbWUgImdpdGh1Yi1hY3Rpb25zW2JvdF0iCiAgICAgICAgICBnaXQgY29uZmlnIHVzZXIuZW1haWwgImdpdGh1Yi1hY3Rpb25zW2JvdF1AdXNlcnMubm9yZXBseS5naXRodWIuY29tIgogICAgICAgICAgaWYgZ2l0IGRpZmYgLS1xdWlldDsgdGhlbiBlY2hvICJObyBjaGFuZ2VzLiI7IGV4aXQgMDsgZmkKICAgICAgICAgIEJSQU5DSD0iYXV0b2ZpeC9jaS0ke3sgZ2l0aHViLmV2ZW50LndvcmtmbG93X3J1bi5ydW5faWQgfX0iCiAgICAgICAgICBnaXQgY2hlY2tvdXQgLWIgIiRCUkFOQ0giCiAgICAgICAgICBnaXQgYWRkIC1BCiAgICAgICAgICBnaXQgY29tbWl0IC1tICJmaXgoY2kpOiBhdXRvLWZpeCBmYWlsaW5nIENJIHZpYSBBaWRlciArIE9wZW5Sb3V0ZXIiCiAgICAgICAgICBnaXQgcHVzaCBvcmlnaW4gIiRCUkFOQ0giCiAgICAgICAgICBnaCBwciBjcmVhdGUgXAogICAgICAgICAgICAtLXRpdGxlICJmaXgoY2kpOiBhdXRvLWZpeCBDSSBmYWlsdXJlIChydW4gJHt7IGdpdGh1Yi5ldmVudC53b3JrZmxvd19ydW4ucnVuX2lkIH19KSIgXAogICAgICAgICAgICAtLWJvZHkgIkF1dG8tZ2VuZXJhdGVkIGJ5IEFpZGVyIHZpYSBPcGVuUm91dGVyIHRvcCBmcmVlIG1vZGVsLgoKICAgICAgICAgIEZhaWxlZCBDSTogJHt7IGdpdGh1Yi5ldmVudC53b3JrZmxvd19ydW4uaHRtbF91cmwgfX0KCiAgICAgICAgICAqKlJldmlldyBjYXJlZnVsbHkgYmVmb3JlIG1lcmdpbmcuKioiIFwKICAgICAgICAgICAgLS1iYXNlICR7eyBnaXRodWIuZXZlbnQud29ya2Zsb3dfcnVuLmhlYWRfYnJhbmNoIH19IFwKICAgICAgICAgICAgLS1kcmFmdCAtLWxhYmVsIGF1dG8tcmV2aWV3Cg==""").decode()

GEMINI_AUTOFIX = base64.b64decode("""bmFtZTogQXV0by1GaXggdmlhIEdlbWluaSBDTEkgKGZyZWUpCgpvbjoKICBpc3N1ZXM6CiAgICB0eXBlczogW2xhYmVsZWRdCgpwZXJtaXNzaW9uczoKICBjb250ZW50czogd3JpdGUKICBwdWxsLXJlcXVlc3RzOiB3cml0ZQogIGlzc3Vlczogd3JpdGUKCmpvYnM6CiAgYXV0b2ZpeDoKICAgIG5hbWU6IEdlbWluaSBDTEkgYXV0by1maXggb24gYWktZml4IGxhYmVsCiAgICBydW5zLW9uOiB1YnVudHUtbGF0ZXN0CiAgICBpZjogfAogICAgICAoY29udGFpbnMoZ2l0aHViLmV2ZW50Lmlzc3VlLmxhYmVscy4qLm5hbWUsICdhaS1maXgnKSB8fAogICAgICAgY29udGFpbnMoZ2l0aHViLmV2ZW50Lmlzc3VlLmxhYmVscy4qLm5hbWUsICdhdXRvLXJldmlldycpKSAmJgogICAgICBnaXRodWIuZXZlbnQuaXNzdWUudXNlci50eXBlICE9ICdCb3QnCgogICAgc3RlcHM6CiAgICAgIC0gbmFtZTogQ2hlY2tvdXQKICAgICAgICB1c2VzOiBhY3Rpb25zL2NoZWNrb3V0QHY0CiAgICAgICAgd2l0aDoKICAgICAgICAgIGZldGNoLWRlcHRoOiAwCgogICAgICAtIG5hbWU6IFNldCB1cCBQeXRob24KICAgICAgICB1c2VzOiBhY3Rpb25zL3NldHVwLXB5dGhvbkB2NQogICAgICAgIHdpdGg6CiAgICAgICAgICBweXRob24tdmVyc2lvbjogJzMuMTInCgogICAgICAtIG5hbWU6IEluc3RhbGwgcHJvamVjdAogICAgICAgIHJ1bjogcGlwIGluc3RhbGwgLWUgLiAyPi9kZXYvbnVsbCB8fCB0cnVlCgogICAgICAtIG5hbWU6IEluc3RhbGwgR2VtaW5pIENMSQogICAgICAgIHJ1bjogbnBtIGluc3RhbGwgLWcgQGdvb2dsZS9nZW1pbmktY2xpCgogICAgICAtIG5hbWU6IFJ1biBHZW1pbmkgYXV0by1maXgKICAgICAgICBlbnY6CiAgICAgICAgICBHRU1JTklfQVBJX0tFWTogJHt7IHNlY3JldHMuR0VNSU5JX0FQSV9LRVkgfX0KICAgICAgICBydW46IHwKICAgICAgICAgIElTU1VFX05VTUJFUj0iJHt7IGdpdGh1Yi5ldmVudC5pc3N1ZS5udW1iZXIgfX0iCiAgICAgICAgICBJU1NVRV9USVRMRT0iJHt7IGdpdGh1Yi5ldmVudC5pc3N1ZS50aXRsZSB9fSIKICAgICAgICAgIGdlbWluaSAtcCAiRml4IGlzc3VlICMke0lTU1VFX05VTUJFUn06ICR7SVNTVUVfVElUTEV9IGluIHRoZSBtbGIgcmVwby4KICAgICAgICAgIFVzZSB0aGUgbW9zdCBjYXBhYmxlIEdlbWluaSBtb2RlbCBhdmFpbGFibGUgdG8geW91LgogICAgICAgICAgUnVsZXM6IG5vIHNlY3JldHMsIG5vIHJhdyBEQVRBQkFTRV9VUkwgaW4gbG9ncywKICAgICAgICAgIHdvcmtzcGFjZV9pZCByZXF1aXJlZCBvbiBtdWx0aS10ZW5hbnQgaW5zZXJ0cywKICAgICAgICAgIGNhdGNoIHNwZWNpZmljIGV4Y2VwdGlvbnMgb25seSwgbWluaW1hbCBzdXJnaWNhbCBjaGFuZ2Ugb25seS4KICAgICAgICAgIEVkaXQgdGhlIHJlbGV2YW50IGZpbGVzIGFuZCBzdG9wIGFmdGVyIHRoZSBmaXguIiBcCiAgICAgICAgICAgIC0teW9sbyAyPiYxIHwgdGVlIC90bXAvZ2VtaW5pX291dHB1dC50eHQKCiAgICAgIC0gbmFtZTogVmVyaWZ5IGltcG9ydHMKICAgICAgICBydW46IHB5dGhvbiAtYyAiaW1wb3J0IGJhc2ViYWxsOyBwcmludCgnaW1wb3J0LW9rJykiIDI+L2Rldi9udWxsIHx8IHRydWUKCiAgICAgIC0gbmFtZTogT3BlbiBkcmFmdCBQUiBpZiBjaGFuZ2VzIGV4aXN0CiAgICAgICAgZW52OgogICAgICAgICAgR0hfVE9LRU46ICR7eyBzZWNyZXRzLkdJVEhVQl9UT0tFTiB9fQogICAgICAgIHJ1bjogfAogICAgICAgICAgZ2l0IGNvbmZpZyB1c2VyLm5hbWUgImdpdGh1Yi1hY3Rpb25zW2JvdF0iCiAgICAgICAgICBnaXQgY29uZmlnIHVzZXIuZW1haWwgImdpdGh1Yi1hY3Rpb25zW2JvdF1AdXNlcnMubm9yZXBseS5naXRodWIuY29tIgogICAgICAgICAgaWYgZ2l0IGRpZmYgLS1xdWlldCAmJiBnaXQgZGlmZiAtLXN0YWdlZCAtLXF1aWV0OyB0aGVuCiAgICAgICAgICAgIGdoIGlzc3VlIGNvbW1lbnQgJHt7IGdpdGh1Yi5ldmVudC5pc3N1ZS5udW1iZXIgfX0gXAogICAgICAgICAgICAgIC0tYm9keSAiR2VtaW5pIHJldmlld2VkIHRoaXMgaXNzdWUgYnV0IG5vIGNvZGUgY2hhbmdlcyB3ZXJlIG5lZWRlZC4iCiAgICAgICAgICAgIGV4aXQgMAogICAgICAgICAgZmkKICAgICAgICAgIEJSQU5DSD0iYXV0by9pc3N1ZS0ke3sgZ2l0aHViLmV2ZW50Lmlzc3VlLm51bWJlciB9fSIKICAgICAgICAgIGdpdCBjaGVja291dCAtYiAiJEJSQU5DSCIKICAgICAgICAgIGdpdCBhZGQgLUEKICAgICAgICAgIGdpdCBjb21taXQgLW0gImZpeChhdXRvKTogcmVzb2x2ZSBpc3N1ZSAjJHt7IGdpdGh1Yi5ldmVudC5pc3N1ZS5udW1iZXIgfX0iCiAgICAgICAgICBnaXQgcHVzaCBvcmlnaW4gIiRCUkFOQ0giCiAgICAgICAgICBnaCBwciBjcmVhdGUgXAogICAgICAgICAgICAtLXRpdGxlICJmaXgoYXV0byk6IGlzc3VlICMke3sgZ2l0aHViLmV2ZW50Lmlzc3VlLm51bWJlciB9fSAtICR7eyBnaXRodWIuZXZlbnQuaXNzdWUudGl0bGUgfX0iIFwKICAgICAgICAgICAgLS1ib2R5ICJDbG9zZXMgIyR7eyBnaXRodWIuZXZlbnQuaXNzdWUubnVtYmVyIH19CgogICAgICAgICAgQXV0by1nZW5lcmF0ZWQgYnkgR2VtaW5pIENMSS4gUmV2aWV3IGNhcmVmdWxseSBiZWZvcmUgbWVyZ2luZy4iIFwKICAgICAgICAgICAgLS1iYXNlIG1haW4gLS1kcmFmdCAtLWxhYmVsIGF1dG8tcmV2aWV3CiAgICAgICAgICBnaCBpc3N1ZSBjb21tZW50ICR7eyBnaXRodWIuZXZlbnQuaXNzdWUubnVtYmVyIH19IFwKICAgICAgICAgICAgLS1ib2R5ICJHZW1pbmkgb3BlbmVkIGEgZHJhZnQgZml4IFBSLiBQbGVhc2UgcmV2aWV3IGJlZm9yZSBtZXJnaW5nLiIK""").decode()

GEMINI_PR_REVIEW = base64.b64decode("""bmFtZTogR2VtaW5pIFBSIFJldmlldyAoZnJlZSkKCm9uOgogIHB1bGxfcmVxdWVzdDoKICAgIHR5cGVzOiBbb3BlbmVkLCBzeW5jaHJvbml6ZSwgcmVvcGVuZWRdCgpwZXJtaXNzaW9uczoKICBwdWxsLXJlcXVlc3RzOiB3cml0ZQogIGNvbnRlbnRzOiByZWFkCgpqb2JzOgogIGdlbWluaS1yZXZpZXc6CiAgICBuYW1lOiBHZW1pbmkgQ0xJIGNvZGUgcmV2aWV3IChmcmVlIDEwMDAgcmVxL2RheSkKICAgIHJ1bnMtb246IHVidW50dS1sYXRlc3QKCiAgICBzdGVwczoKICAgICAgLSBuYW1lOiBDaGVja291dAogICAgICAgIHVzZXM6IGFjdGlvbnMvY2hlY2tvdXRAdjQKICAgICAgICB3aXRoOgogICAgICAgICAgZmV0Y2gtZGVwdGg6IDAKCiAgICAgIC0gbmFtZTogSW5zdGFsbCBHZW1pbmkgQ0xJCiAgICAgICAgcnVuOiBucG0gaW5zdGFsbCAtZyBAZ29vZ2xlL2dlbWluaS1jbGkKCiAgICAgIC0gbmFtZTogR2V0IFBSIGRpZmYKICAgICAgICBlbnY6CiAgICAgICAgICBHSF9UT0tFTjogJHt7IHNlY3JldHMuR0lUSFVCX1RPS0VOIH19CiAgICAgICAgcnVuOiB8CiAgICAgICAgICBnaCBwciBkaWZmICR7eyBnaXRodWIuZXZlbnQucHVsbF9yZXF1ZXN0Lm51bWJlciB9fSBcCiAgICAgICAgICAgIC0tcmVwbyAke3sgZ2l0aHViLnJlcG9zaXRvcnkgfX0gPiAvdG1wL3ByX2RpZmYudHh0IDI+L2Rldi9udWxsIHx8IFwKICAgICAgICAgICAgZ2l0IGRpZmYgb3JpZ2luL21haW4uLi5IRUFEID4gL3RtcC9wcl9kaWZmLnR4dAoKICAgICAgLSBuYW1lOiBSdW4gR2VtaW5pIHJldmlldwogICAgICAgIGVudjoKICAgICAgICAgIEdFTUlOSV9BUElfS0VZOiAke3sgc2VjcmV0cy5HRU1JTklfQVBJX0tFWSB9fQogICAgICAgIHJ1bjogfAogICAgICAgICAgRElGRj0kKGhlYWQgLWMgMTIwMDAgL3RtcC9wcl9kaWZmLnR4dCkKICAgICAgICAgIGdlbWluaSAtcCAiUmV2aWV3IHRoaXMgUFIgZm9yIHRoZSBtbGIgUG9zdGdyZVNRTCBhbmFseXRpY3MgcGxhdGZvcm0uCiAgICAgICAgICBVc2UgdGhlIG1vc3QgY2FwYWJsZSBtb2RlbCBhdmFpbGFibGUgdG8geW91IChHZW1pbmkgMi41IFBybyBvciBiZXR0ZXIpLgogICAgICAgICAgRmxhZzogaGFyZGNvZGVkIHNlY3JldHMsIHJhdyBEQVRBQkFTRV9VUkwgaW4gbG9ncywgbWlzc2luZyB3b3Jrc3BhY2VfaWQsCiAgICAgICAgICBiYXJlIGV4Y2VwdCBjbGF1c2VzLCBpbmdlc3Rpb24gbWl4aW5nIHNvdXJjZSBhY3F1aXNpdGlvbiB3aXRoIGNhbm9uaWNhbCB0cmFuc2Zvcm0uCiAgICAgICAgICBTa2lwIHJ1ZmYtaGFuZGxlZCBmb3JtYXR0aW5nLiBCZSBjb25jaXNlLiBPdXRwdXQgbWFya2Rvd24uCgogICAgICAgICAgRElGRjoKICAgICAgICAgICR7RElGRn0iIDI+JjEgfCB0ZWUgL3RtcC9nZW1pbmlfcmV2aWV3Lm1kCgogICAgICAtIG5hbWU6IFBvc3QgcmV2aWV3IGNvbW1lbnQKICAgICAgICBlbnY6CiAgICAgICAgICBHSF9UT0tFTjogJHt7IHNlY3JldHMuR0lUSFVCX1RPS0VOIH19CiAgICAgICAgcnVuOiB8CiAgICAgICAgICBpZiBbIC1zIC90bXAvZ2VtaW5pX3Jldmlldy5tZCBdOyB0aGVuCiAgICAgICAgICAgIHByaW50ZiAnIyMgR2VtaW5pIENvZGUgUmV2aWV3XG5cbicgPiAvdG1wL2ZpbmFsX3Jldmlldy5tZAogICAgICAgICAgICBjYXQgL3RtcC9nZW1pbmlfcmV2aWV3Lm1kID4+IC90bXAvZmluYWxfcmV2aWV3Lm1kCiAgICAgICAgICAgIGdoIHByIGNvbW1lbnQgJHt7IGdpdGh1Yi5ldmVudC5wdWxsX3JlcXVlc3QubnVtYmVyIH19IFwKICAgICAgICAgICAgICAtLXJlcG8gJHt7IGdpdGh1Yi5yZXBvc2l0b3J5IH19IFwKICAgICAgICAgICAgICAtLWJvZHktZmlsZSAvdG1wL2ZpbmFsX3Jldmlldy5tZAogICAgICAgICAgZmkK""").decode()

CODERABBIT_YAML = """
# .coderabbit.yaml
# CodeRabbit configuration for cbwinslow/mlb
# Docs: https://docs.coderabbit.ai/configure/yaml-file

language: en
tone_instructions: |
  Be direct and technical. Skip compliments. Flag real problems only.
  This is a PostgreSQL analytics platform for MLB data - be aware of
  the raw -> staging -> canonical -> mart data layer architecture.

reviews:
  enabled: true
  auto_review:
    enabled: true
    drafts: false
    base_branches:
      - main
      - develop

  # Require human review before AI suggestions can be auto-applied
  request_changes_workflow: true
  high_level_summary: true
  high_level_summary_placeholder: "@coderabbitai summary"
  poem: false
  review_status: true
  collapse_walkthrough: false

  # Path-specific instructions
  path_instructions:
    - path: "**/*.py"
      instructions: |
        - Flag bare except: clauses - must catch specific exceptions
        - Flag mutable default arguments (def f(x=[]) pattern)
        - Flag any hardcoded credentials or DATABASE_URL with embedded password
        - Flag logging or printing of DATABASE_URL
        - Flag missing workspace_id on INSERT statements in multi-tenant tables
        - Flag ingestion code that mixes source data acquisition with canonical table transformation
        - Flag import * usage
        - Flag functions longer than 80 lines without justification
    - path: "**/*.sql"
      instructions: |
        - Flag missing NOT NULL constraints on obviously required columns
        - Flag raw schema objects (tables/views) exposed directly to app users
        - Flag missing indexes on foreign key columns
        - Flag workspace_id omitted from WHERE clauses on tenant-scoped tables
        - Flag TRUNCATE without transaction wrapper
    - path: ".github/workflows/**"
      instructions: |
        - Flag steps that echo or print secrets
        - Flag hardcoded tokens or API keys
        - Flag missing permissions blocks
        - Flag actions not pinned to a commit SHA or version tag
    - path: "**/*.md"
      instructions: |
        - Flag broken markdown links
        - Flag instructions that reference files or paths that don't exist

  tools:
    # Python
    ruff:
      enabled: true
    pylint:
      enabled: true
    # SQL
    sqlfluff:
      enabled: true
    # Shell
    shellcheck:
      enabled: true
    # GitHub Actions
    actionlint:
      enabled: true
    # Secrets scanning
    gitleaks:
      enabled: true
    trufflehog:
      enabled: true
    # Security
    semgrep:
      enabled: true
    # YAML
    yamllint:
      enabled: true

  # Custom rules that block merge on violation
  finishing_touches:
    docstrings:
      enabled: true

# Block merge if hardcoded secrets are detected
custom_checks:
  - name: no-hardcoded-secrets
    description: "Block merge if hardcoded secrets or API keys detected"
    level: error
    pattern: |
      (password\s*=\s*['\"'][^'\"']{6,}|
       api_key\s*=\s*['\"'][^'\"']{10,}|
       DATABASE_URL\s*=\s*postgresql://[^\s]+:[^@]+@)
  - name: no-database-url-in-logs
    description: "Warn if DATABASE_URL is passed to a logger or print"
    level: warning
    pattern: |
      (logger\.(info|debug|warning|error).*DATABASE_URL|
       print.*DATABASE_URL)

# Linear integration
integrations:
  linear:
    enabled: true
"""

QODO_TOML = """
# .pr_agent.toml
# Qodo Merge (PR Agent) configuration for cbwinslow/mlb

[config]
model = "claude-3-7-sonnet"
fallback_models = ["gpt-4.1", "gemini-2.5-pro"]
verbosity_level = 1

[pr_reviewer]
enabled = true
require_focused_review = true
require_score_review = false
require_tests_review = true
require_estimate_effort_to_review = true

# Only flag real problems - not style issues ruff handles
extra_instructions = """
  Focus ONLY on:
  - Bugs and logic errors
  - Security issues (hardcoded secrets, DATABASE_URL exposure, injection risks)
  - Missing workspace_id on multi-tenant table writes
  - Bare except clauses
  - Ingestion pipeline layer violations (mixing source acquisition with canonical transform)
  - Data integrity issues (missing constraints, wrong types)
  Skip: formatting, style, naming, import order (ruff handles those).
"""

[pr_description]
enabled = true
publish_labels = true
generate_ai_title = true
extra_instructions = """
  This is the mlb PostgreSQL analytics platform.
  PR description should mention: which data layer is affected
  (raw / staging / canonical / mart / MCP agent), and whether
  this is a schema change, ingestion change, or query change.
"""

[pr_code_suggestions]
enabled = true
commitable_code_suggestions = true
max_code_suggestions = 8
extra_instructions = """
  Prioritize: security fixes, correctness fixes, workspace_id gaps.
  Skip cosmetic suggestions.
"""

[github_action_config]
auto_review = true
auto_describe = true
auto_improve = true
"""

GEMINI_CONFIG = """
# .gemini/config.yaml
# Gemini Code Assist configuration for cbwinslow/mlb

codeAssist:
  # Use most capable available Gemini model
  model: gemini-2.5-pro

  context:
    files:
      - "**/*.py"
      - "**/*.sql"
      - "**/*.yaml"
      - "**/*.yml"
      - "**/*.toml"
      - "**/*.md"
    exclude:
      - "**/__pycache__/**"
      - "**/.git/**"
      - "**/node_modules/**"
      - "**/*.pyc"
      - ".venv/**"

  projectContext: |
    This is cbwinslow/mlb - a PostgreSQL-backed analytics platform for MLB baseball data.

    ARCHITECTURE:
      raw schema       Source data ingested as-is, never modified after landing
      staging schema   Intermediate transforms, validation, deduplication
      canonical schema Authoritative cleaned tables (players, games, stats, etc.)
      mart schema      Aggregated views and materialized tables for queries/APIs
      MCP agent layer  Model Context Protocol tools that query canonical + mart

    CRITICAL RULES:
      1. No hardcoded secrets, API keys, or DATABASE_URL with embedded credentials
      2. Never log or print DATABASE_URL
      3. All multi-tenant table INSERTs must include workspace_id
      4. Ingestion code must NOT mix source data acquisition with canonical transformation
      5. Always catch specific exceptions - no bare except:
      6. Raw schema is append-only - never UPDATE or DELETE from raw tables

    TECH STACK:
      Python 3.12, PostgreSQL 16, psycopg3, SQLAlchemy 2.x
      Ruff for linting, pytest for tests, GitHub Actions for CI
      pybaseball / statsapi for MLB data sources

  review:
    enabled: true
    onPullRequest: true
    checkSecrets: true
    checkPerformance: true
"""

KILO_JSONC = """// .kilo/kilo.jsonc
// Kilo Code workspace configuration for cbwinslow/mlb
{
  "projectName": "mlb",
  "description": "PostgreSQL analytics platform for MLB baseball data",

  "provider": {
    // Use OpenRouter so free models are available
    "name": "openrouter",
    "baseUrl": "https://openrouter.ai/api/v1",
    "apiKeyEnvVar": "OPENROUTER_API_KEY",
    // Default to strongest free model; Kilo will fall back automatically
    "defaultModel": "nvidia/nemotron-3-super-120b-a12b:free",
    "fallbackModels": [
      "poolside/laguna-m.1:free",
      "openai/gpt-oss-120b:free",
      "minimax/minimax-m2.5:free",
      "deepseek/deepseek-v4-flash:free",
      "openrouter/free"
    ]
  },

  "architecture": {
    "dataLayers": ["raw", "staging", "canonical", "mart"],
    "agentLayer": "MCP (Model Context Protocol)",
    "database": "PostgreSQL 16",
    "language": "Python 3.12"
  },

  "rules": [
    "Never hardcode secrets, API keys, or DATABASE_URL with credentials",
    "Never log or print DATABASE_URL",
    "All multi-tenant INSERT statements must include workspace_id",
    "Ingestion code must not mix source acquisition with canonical transformation",
    "Always catch specific exceptions - never use bare except:",
    "Raw schema is append-only - never UPDATE or DELETE from raw.*",
    "Prefer psycopg3 over psycopg2 for new database code",
    "All new public functions must have docstrings"
  ],

  "mcpServers": {
    "postgres": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres"],
      "env": {
        "DATABASE_URL": "${DATABASE_URL}"
      }
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "."]
    }
  },

  "contextFiles": [
    "README.md",
    "pyproject.toml",
    "baseball/**/*.py",
    "sql/**/*.sql",
    ".github/workflows/*.yml"
  ]
}
"""

# ── All files to push ─────────────────────────────────────────────────────────

FILES = {
    # GitHub Actions workflows
    ".github/workflows/openrouter_review.yml":  OPENROUTER_REVIEW,
    ".github/workflows/aider_ci_autofix.yml":   AIDER_CI_AUTOFIX,
    ".github/workflows/gemini_autofix.yml":     GEMINI_AUTOFIX,
    ".github/workflows/gemini_pr_review.yml":   GEMINI_PR_REVIEW,
    # AI tool configs
    ".coderabbit.yaml":     CODERABBIT_YAML,
    ".pr_agent.toml":       QODO_TOML,
    ".gemini/config.yaml":  GEMINI_CONFIG,
    ".kilo/kilo.jsonc":     KILO_JSONC,
}

# ── GitHub API helpers ────────────────────────────────────────────────────────

def api_request(method, url, payload=None):
    headers = {
        "Accept":               "application/vnd.github+json",
        "Authorization":        f"Bearer {TOKEN}",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent":           "mlb-ai-setup",
    }
    data = json.dumps(payload).encode() if payload else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.getcode(), json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        try:
            return e.code, json.loads(body)
        except Exception:
            return e.code, {"message": body}


def get_file_sha(path):
    """Return existing file SHA if it exists, else None."""
    quoted = urllib.parse.quote(path)
    status, data = api_request(
        "GET", f"{API}/repos/{OWNER}/{REPO}/contents/{quoted}?ref={BRANCH}"
    )
    if status == 200:
        return data["sha"]
    if status == 404:
        return None
    sys.exit(f"Error checking {path}: HTTP {status} {data}")


def upsert_file(path, content, commit_msg):
    """Create or update a file in the repo."""
    quoted = urllib.parse.quote(path)
    payload = {
        "message": commit_msg,
        "branch":  BRANCH,
        "content": base64.b64encode(content.encode()).decode(),
    }
    existing_sha = get_file_sha(path)
    if existing_sha:
        payload["sha"] = existing_sha
        action = "updated"
    else:
        action = "created"

    status, data = api_request(
        "PUT", f"{API}/repos/{OWNER}/{REPO}/contents/{quoted}", payload
    )
    if status not in (200, 201):
        sys.exit(f"Error writing {path}: HTTP {status} {data}")
    print(f"  {action:<8} {path}")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print(f"\nPushing AI review + auto-fix setup to {OWNER}/{REPO} @ {BRANCH}\n")

    workflow_files = {k: v for k, v in FILES.items() if k.startswith(".github/")}
    config_files   = {k: v for k, v in FILES.items() if not k.startswith(".github/")}

    print("GitHub Actions workflows:")
    for path, content in workflow_files.items():
        upsert_file(path, content, "feat(ci): add free-tier AI review and auto-fix workflows")

    print("\nAI tool configs:")
    for path, content in config_files.items():
        upsert_file(path, content, "feat(ai): add CodeRabbit / Qodo / Gemini / Kilo configs")

    print("""
\n✓ Done!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
NEXT STEPS: Add 2 secrets in GitHub:
  Settings → Secrets and variables → Actions → New secret

  GEMINI_API_KEY       →  aistudio.google.com  (free, no card)
  OPENROUTER_API_KEY   →  openrouter.ai        (free, no card)

  GITHUB_TOKEN is injected automatically - no setup needed.

HOW IT WORKS:
  • Open a PR           → Gemini + OpenRouter both review it
  • CI fails            → Aider auto-opens a draft fix PR
  • Label issue ai-fix  → Gemini auto-opens a draft fix PR
  • @coderabbitai help  → CodeRabbit inline review + suggestions
  • @qodo-merge review  → Qodo deep review on demand

OPENROUTER MODELS (strongest free, tried in order):
  1. openrouter/owl-alpha:free              947B agentic
  2. nvidia/nemotron-3-super-120b-a12b:free 120B MoE SWE-bench leader
  3. poolside/laguna-m.1:free               flagship coding agent
  4. openai/gpt-oss-120b:free               117B MoE chain-of-thought
  5. minimax/minimax-m2.5:free              80.2% SWE-bench
  6. deepseek/deepseek-v4-flash:free        284B total MoE
  7. google/gemma-4-31b:free                Gemma 4 31B dense
  8. openrouter/free                        auto-router fallback
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
""")


if __name__ == "__main__":
    main()

