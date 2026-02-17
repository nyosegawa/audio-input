#!/bin/bash
set -euo pipefail

# Integration test for AudioInput transcription services
# Tests API connectivity and transcription accuracy

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$PROJECT_DIR/.env"

echo "=== AudioInput Integration Test ==="
echo ""

# Generate test audio with Japanese speech
echo "[1/4] Generating test audio..."
say -v "Kyoko" "こんにちは、今日はいい天気ですね。音声入力のテストをしています。" -o /tmp/ai_test.aiff 2>/dev/null
ffmpeg -y -i /tmp/ai_test.aiff -ar 16000 -ac 1 -sample_fmt s16 /tmp/ai_test.wav 2>/dev/null
EXPECTED="こんにちは、今日はいい天気ですね。音声入力のテストをしています。"
echo "  Expected: $EXPECTED"
echo ""

# Test OpenAI gpt-4o-mini-transcribe
echo "[2/4] Testing OpenAI gpt-4o-mini-transcribe..."
OPENAI_START=$(date +%s%N)
OPENAI_RESULT=$(curl -s https://api.openai.com/v1/audio/transcriptions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -F file="@/tmp/ai_test.wav" \
  -F model="gpt-4o-mini-transcribe" \
  -F language="ja" \
  -F response_format="json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('text','ERROR'))")
OPENAI_END=$(date +%s%N)
OPENAI_MS=$(( (OPENAI_END - OPENAI_START) / 1000000 ))
echo "  Result:  $OPENAI_RESULT"
echo "  Latency: ${OPENAI_MS}ms"
if [ "$OPENAI_RESULT" = "$EXPECTED" ]; then
  echo "  Status:  PASS (exact match)"
elif echo "$OPENAI_RESULT" | grep -q "テスト"; then
  echo "  Status:  PASS (partial match)"
else
  echo "  Status:  FAIL"
fi
echo ""

# Test Gemini
echo "[3/4] Testing Gemini 2.5 Flash..."
AUDIO_BASE64=$(base64 < /tmp/ai_test.wav)
GEMINI_START=$(date +%s%N)
GEMINI_RESULT=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"contents\": [{
      \"parts\": [
        {\"text\": \"Transcribe this audio in Japanese. Return ONLY the transcribed text, nothing else.\"},
        {\"inline_data\": {\"mime_type\": \"audio/wav\", \"data\": \"$AUDIO_BASE64\"}}
      ]
    }],
    \"generationConfig\": {\"temperature\": 0}
  }" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['candidates'][0]['content']['parts'][0]['text'].strip())")
GEMINI_END=$(date +%s%N)
GEMINI_MS=$(( (GEMINI_END - GEMINI_START) / 1000000 ))
echo "  Result:  $GEMINI_RESULT"
echo "  Latency: ${GEMINI_MS}ms"
if echo "$GEMINI_RESULT" | grep -q "テスト"; then
  echo "  Status:  PASS"
else
  echo "  Status:  FAIL"
fi
echo ""

# Test text processing
echo "[4/4] Testing text processing (cleanup mode)..."
PROCESS_RESULT=$(curl -s https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [
      {"role": "system", "content": "以下の音声認識テキストを整形してください。フィラーワードを除去し、適切な句読点を追加してください。整形後のテキストのみを返してください。"},
      {"role": "user", "content": "えーと、今日はあのー、天気がいいですね。まあ、えーっと、散歩に行きたいなーと思ってます。"}
    ],
    "temperature": 0.3
  }' | python3 -c "import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'].strip())")
echo "  Input:   えーと、今日はあのー、天気がいいですね。まあ、えーっと、散歩に行きたいなーと思ってます。"
echo "  Output:  $PROCESS_RESULT"
echo ""

# Cleanup
rm -f /tmp/ai_test.aiff /tmp/ai_test.wav

echo "=== Integration Test Complete ==="
