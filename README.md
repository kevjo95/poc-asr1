# poc-asr1

Proof of concept for ASR1 (webhook-ingestion scalability) of the group project for
**ARTI4207 Architecting for the Cloud** (MATI, Universidad de los Andes).

> **Academic use only.** This repository is a university coursework project. It uses
> synthetic data and generic names. It contains no employer or client data, schemas,
> credentials or infrastructure identifiers.

See [`PoC-ingesta-webhooks.md`](PoC-ingesta-webhooks.md) for the PoC definition
(hypothesis, scenarios, acceptance criteria).

## Guardrails

- A pre-commit hook (`.githooks/pre-commit`, enabled via `core.hooksPath`) blocks
  credential-like strings and ARNs. Enable it after cloning:
  `git config core.hooksPath .githooks`
