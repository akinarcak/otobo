# ASSIST-01 — Explainable agent assistance

Status: implemented in `CareOnCloudAssist` 0.1.1.

The first CareOnCloud Intelligence capability ranks completed requests inside the explicitly authorized tenant using catalog context and normalized query-term overlap. It returns a bounded set of request references, reusable completed-task notes, a confidence score and human-readable matching evidence.

No tenant content leaves CareOnCloud (`ExternalDataTransfer=0`), raw request answers are never returned, only `fulfilled` requests are candidates, every read requires `case.read`, and tenant intersection occurs before querying. Results are advisory and explicitly require agent review. This deterministic provider is the safe baseline for later pluggable local-model or approved-LLM providers.
