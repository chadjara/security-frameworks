# Editorial guide: plain-language requirement content

Each requirement can carry an editorial overlay, written for this app, with four fields. The overlay
is shown before NIST's own text, which stays available under "NIST text" in the app.

| Field | Purpose | Shape |
|---|---|---|
| `question` | Asks what the organization does today, in plain language. | One sentence ending in `?`, about 12–30 words. |
| `whyItMatters` | The concrete risk or benefit. | 1–3 sentences. |
| `doneLooksLike` | Observable evidence that the requirement is met. | 1–3 sentences. |
| `nextSteps` | What to do when the answer is not "Implemented". | 2–4 short imperative steps. |
| `reviewed` | `false` until a qualified reviewer approves the entry. | Boolean. |

## Audience

Write for a capable small-business owner with no security background, without talking down to a
practitioner. Lead with plain language. Briefly explain a technical term the first time it appears
(for example "multi-factor authentication (a second check beyond a password)").

## Accuracy rules

- **Stay inside the requirement.** Paraphrase what NIST's statement, discussion, implementation
  examples, and assessment objectives already say. Do not add obligations that are not there, and do
  not drop essential parts of a multi-part requirement. A question may focus on the core of the
  requirement; `doneLooksLike` should cover all of its parts.
- **Organization-defined parameters.** When a requirement has parameters (time periods, frequencies,
  roles), say that the organization decides the value, for example "at a frequency you define". Do
  not invent specific values. A value may be offered only as an illustration, clearly labeled as one.
- **SP 800-53 enhancements.** Write about what the enhancement adds to its base control. Do not
  restate the whole base control.
- **No third-party standards or products.** Do not mention ISO, CIS, PCI, COBIT, vendors, or product
  names. Generic technology categories ("a password manager", "endpoint protection") are fine.
- **No compliance claims.** Never say that doing something makes an organization "compliant" or
  "certified".

## Voice

- Calm, precise, and specific. Use second person ("your organization", "you").
- US English, sentence case, and the Oxford comma.
- No emoji, no exclamation marks, and no marketing language ("supercharge", "seamless",
  "effortless", "game-changer", "world-class", "cutting-edge").
- Avoid "simply", "just", and "easy": security work is rarely any of these.
- No double spaces and no trailing whitespace. `convert.py` lints for these rules automatically.

## Example (SP 800-171 03.01.01, Account Management)

```json
"03.01.01": {
  "question": "Does your organization control who gets an account on systems that handle CUI, review those accounts, and disable them when they are no longer needed?",
  "whyItMatters": "Unused, shared, or forgotten accounts are a common way in for attackers. Managing accounts deliberately limits access to CUI to the people who need it.",
  "doneLooksLike": "You have defined which account types are allowed, approve each account against a valid need, record each account's users, roles, and privileges, monitor account use, and disable accounts that expire, sit inactive for the period you define, or belong to people who have left or changed roles. Account managers are notified within the time periods you set.",
  "nextSteps": [
    "List every account on systems that store or process CUI, including service and shared accounts.",
    "Define the account types you allow and the approval needed for each.",
    "Set the inactivity period after which accounts are disabled, and the notification times when people leave or change roles.",
    "Disable or remove accounts that have no current owner or need."
  ],
  "reviewed": false
}
```

## Files

Overlays live in `data/editorial/<framework-id>.json` (summary and notices) and
`data/editorial/<framework-id>/*.json` (batches of requirement entries, `{"requirements": {...}}`).
`python3 tools/oscal_convert/editorial_worklist.py <framework-id> …` prints NIST's text for the
requirements in a batch. Run `python3 tools/oscal_convert/convert.py` to lint and merge.
