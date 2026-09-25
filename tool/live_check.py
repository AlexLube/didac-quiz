"""Prueba rápida contra el servidor real (se ejecuta en CI con los secretos).

Entra como invitado, consulta el reto de hoy, pide la primera pregunta (sin
responderla), mira el ranking y borra el usuario de prueba.
"""
import json
import os
import sys

import requests

U = os.environ.get("SUPABASE_URL", "").rstrip("/")
K = os.environ.get("SUPABASE_ANON_KEY", "")
if not U or not K:
    print("Sin secretos de Supabase: se omite la prueba real.")
    sys.exit(0)

r = requests.post(f"{U}/auth/v1/signup", headers={"apikey": K, "Content-Type": "application/json"},
                  json={}, timeout=30)
print("alta de invitado:", r.status_code)
r.raise_for_status()
H = {"apikey": K, "Authorization": f"Bearer {r.json()['access_token']}", "Content-Type": "application/json"}


def rpc(fn, **params):
    resp = requests.post(f"{U}/rest/v1/rpc/{fn}", headers=H, json=params, timeout=30)
    if resp.status_code >= 300:
        print(f"{fn}: ERROR {resp.status_code} {resp.text[:300]}")
        sys.exit(1)
    return resp.json() if resp.text else None


ok = True
try:
    t = rpc("get_today")
    print("reto de hoy:", json.dumps({k: t.get(k) for k in ("date", "available", "status", "jokers_left")}))
    ok &= bool(t.get("available"))
    q = rpc("next_question")["question"]
    print(f"pregunta 1 [{q['format']}, dificultad {q['difficulty']}]: {q['prompt']['es']}")
    print("  opciones:", [o["es"] for o in q["options"]])
    print("  ¿la respuesta viaja a la app?:", "answer" in q)
    ok &= "answer" not in q
    lb = rpc("get_leaderboard", p_scope="world", p_period="day")
    print("ranking mundial de hoy, jugadores:", lb["total_players"])
    cities = rpc("search_cities", p_country="ES", p_query="valen")
    print("búsqueda de ciudades:", [c["name"] for c in cities[:3]])
    ok &= len(cities) > 0
finally:
    rpc("delete_my_account")
    print("usuario de prueba borrado")
print("RESULTADO:", "OK" if ok else "FALLO")
sys.exit(0 if ok else 1)
