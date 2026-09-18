# Agent Skills Workflow

This project uses the engineering skills installed under `.agents/skills/`.

## Skill Routing

- Start each task by considering `using-agent-skills`.
- New features: use `spec-driven-development`, then `planning-and-task-breakdown`.
- Implementation: use `incremental-implementation` and `test-driven-development`.
- Bugs and failures: use `debugging-and-error-recovery`; reproduce before fixing.
- API work: use `api-and-interface-design`.
- UI work: use `frontend-ui-engineering`.
- Security-sensitive work: use `security-and-hardening`.
- Performance work: use `performance-optimization`.
- Before merge: use `code-review-and-quality`.
- Before release: use `shipping-and-launch`.

## Engineering Standards

- Work in small, independently verifiable increments.
- Write a failing test before changing behavior.
- Run relevant tests, lint, type checks, and builds before completion.
- Never remove or weaken tests merely to make checks pass.
- Never commit secrets or expose them in logs.
- Validate untrusted input at system boundaries.
- Keep formatting-only changes separate from behavior changes.
- Ask before destructive operations, schema changes, or new production dependencies.

## Specialized Personas

Use the custom agents under `.github/agents/` for focused reviews:

- `code-reviewer`: correctness, readability, architecture, security, and performance.
- `test-engineer`: test strategy, coverage gaps, and reproduction tests.
- `security-auditor`: threat modeling and vulnerability review.
- `web-performance-auditor`: browser and Core Web Vitals performance review.

Personas do not invoke other personas. The user or primary agent coordinates multi-persona work.
