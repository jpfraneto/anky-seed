# Feature 02: Language Detection

## Problem
User writes in English but receives Spanish reflection starting with "hola, gracias por ser quien eres. mis pensamientos:" The LLM (Claude Sonnet 4.6 via OpenRouter) is supposed to autodetect language from the prompt instruction "Respond in the same language they wrote in" but fails.

## Root Cause
- `buildStorytellerPrompt()` (server.ts:2051) says "Respond in the same language they wrote in" (line 2067)
- No actual language detection happens before the LLM call
- The greeting template (line 2075-2076) says "natural equivalent... of: hey, thanks for being who you are. my thoughts:" which is ambiguous — Claude may interpret "natural equivalent" as "translate to my native language"
- Claude Sonnet 4.6 apparently defaults to Spanish for this prompt pattern

## Solution
Add explicit language detection before building the LLM prompt, then inject the detected language as a hard instruction.

### Implementation

#### Step 1: Language Detection Function (server.ts)

Add a `detectLanguage(text: string): string` function that returns an ISO language code. Use a simple heuristic approach that works without external dependencies:

```typescript
function detectLanguage(text: string): string {
  // Count language-specific character patterns
  const spanishIndicators = [
    /\b(que|el|la|los|las|de|en|con|por|para|un|una|es|son|me|te|se|lo|le|los|les|y|o|no|si|como|muy|mas|pero|todo|mas|esta|este|esos|esas|aquí|ahora|bien|todo|mismo|muy)\b/i,
    /[áéíóúñ¿¡]/,
  ];
  
  const englishIndicators = [
    /\b(the|and|for|are|but|not|you|all|can|her|was|one|our|out|day|get|has|him|his|how|man|new|now|old|see|two|way|who|boy|did|its|let|put|say|she|too|use|and|that|this|with|have|what|been|from|will|your|come|them|just|know|want|when|like|time|could|people|there|call|first|may|should|its|them|very|than|its|these|would|other|which|their|after|over|such|also|back|only|its|then|its|its|its)\b/i,
  ];
  
  // Count matches and return highest scoring language
  // Default to English if uncertain
}
```

#### Step 2: Inject Language Into Prompt (server.ts:2051)

In `buildStorytellerPrompt()`, detect language then add explicit instruction:

```typescript
export function buildStorytellerPrompt(writing: string): string {
  const detectedLang = detectLanguage(writing);
  const langName = LANG_NAMES[detectedLang] || "English";
  
  return [
    // ... existing preamble ...
    `LANGUAGE: The user wrote in ${langName} (${detectedLang}).`,
    `You MUST respond in ${langName}. Do not switch languages.`,
    `The greeting after the H1 must be in ${langName}.`,
    // ... rest of prompt ...
  ].join("\n");
}
```

#### Step 3: Fix Greeting Template (server.ts:2075-2076)

Current (ambiguous):
```
"After the H1, the first paragraph must begin with the natural equivalent, in the same language the user wrote in, of: hey, thanks for being who you are. my thoughts:"
```

New (explicit):
```
"After the H1, the first paragraph must begin with this exact greeting in ${langName}: 'hey, thanks for being who you are. my thoughts:'"
```

## Files to Modify
1. `backend/server.ts` — add `detectLanguage()` function, modify `buildStorytellerPrompt()`

## Testing
- Write in English, verify reflection is in English with English greeting
- Write in Spanish, verify reflection is in Spanish with Spanish greeting
- Write in mixed language, verify it picks the dominant language
