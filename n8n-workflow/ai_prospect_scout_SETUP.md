# AI Prospect Scout v1 — n8n

Importa `ai_prospect_scout_n8n.json` in n8n.

## Foglio Google
Tab: `Prospects`

Prima riga:
name | company | role | linkedin_notes | website | status | score | reason | pain | opening | dm | error | processed_at

## Configurazione
1. Nei nodi `Read Prospects`, `Mark PROCESSING`, `Update Prospect`:
   - sostituisci `YOUR_GOOGLE_SHEET_ID`
   - seleziona la credenziale Google Sheets.
2. Esponi nel container/VPS n8n:
   - APIFY_TOKEN
   - OPENAI_API_KEY
3. Riavvia n8n se hai aggiunto variabili d'ambiente.
4. Inserisci una riga con `status=NEW`.
5. Avvia `Manual Test`.
6. Quando il test è OK, attiva il workflow.

Il workflow prende massimo 5 prospect per esecuzione, usa Apify Website Content Crawler su massimo 5 pagine/prospect, usa OpenAI Structured Outputs e aggiorna il foglio a READY o ERROR.
