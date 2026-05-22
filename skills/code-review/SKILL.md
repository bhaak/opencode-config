---
name: code-review
description: conducts a code review
disable-model-invocation: true
---

Review the changes in the commits or files $ARGUMENTS.

Output the review as markdown.

Rules:
- Be concise.
- Look for correctness, performance, and security issues.
- Default to reviewing the last commit's diff using `git diff HEAD~1`.
- If asked to review a file (not a commit), review the full file content, not just recent commits.
- Every comment that can be assigned to a line MUST first output the relative path to the file and the linenumber in the format path:linenumber.
- Comments that cannot be assigned to a specific line goes into a general section at the end.
- Use Markdown inside body strings.
- Prepend comments with severity levels high 🛑, medium ⚠️, low  🟩.
- Summary: High-level overview

For each issue: What -> Where (file:line) -> Why -> How (code example)

Invocation: /code-review commit oder commits or file or files
