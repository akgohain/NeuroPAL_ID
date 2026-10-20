# Manual ID editor implementation

The NeuroPAL ID toolbar keeps one ID field and one assignment button. Suggestions open below that field; model selection remains in the existing settings controls. The implementation follows [the manual ID entry contract](manual-id-entry-contract.md).

## Researcher workflow

1. Open an image and select a detected or manually added neuron.
2. Type an individual name or a family such as `IL1`. The applicable catalog is searchable even when models are unavailable. Unknown specimen sex searches the catalog union.
3. Choose an individual, or explicitly choose **Keep IL1 unresolved**. Choosing a suggestion stages a draft; it does not save.
4. Use **Assign** / **Update ID** to save. Tab moves from the input to that button without saving; press Enter or Space there to confirm. Enter in the input only accepts or validates the draft. Whitespace, blur, Z movement and tab changes never assign.
5. Use the popup or Neurons menu for Undo. Clear ID asks before withdrawing an annotation. A confirmed occupied identity offers an explicit Move or Swap with both resulting associations shown.
6. Save normally to the companion `_ID.mat`. Export neuron IDs defaults to a full structured MAT exchange. The legacy analysis CSV requires acknowledgement and has a full annotation MAT companion.

Drafts stay with stable neuron owners when selection changes. `?` marks a tentative claim; `!` marks emphasis. `AWCL-ON` / `AWCR-OFF` carry a separate functional attribute. A bare family is never resolved by choosing its first member. Prefill prediction only proposes exact individual names; it neither commits nor replaces a retained draft or saved annotation.

MATLAB R2024a can deliver pasted text only when the native field commits on Enter or focus loss. Suggestions then refresh from that final value. Standard Tab navigation finalizes the text before the researcher activates Assign. Modified Enter has no annotation or focus action; the app does not depend on its missing native key-release events. A pending focus intent can absorb final text for the same owner/context, while captured mouse and keyboard commands keep their original draft generations. Native button event duplicates reuse the same operation.

## Components and authority

- `Annotations.Catalog` reads the versioned explicit anatomy catalog. Catalog groups, anatomical individuals and model classes have separate lookup paths. The pinned GAT class map does not imply side-specific confidence.
- `ManualIDInput` provides the native field, anchored popup and compact actions. `ManualIDController` owns per-neuron drafts, focus, explicit staging and captured gesture tokens.
- `ManualIDService` validates source/owner/geometry/context, resolves conflicts, stages detached values and publishes the durable save before applying it to the live image.
- `Annotations.Store` contains structured human assertions, stable owners, model evidence and a saved event journal. A legacy neuron projection remains available for compatible consumers. Tentative or unresolved claims do not become confirmed occupancy or hard solver pins.
- `Annotations.Exchange` provides a validated, content-checked full MAT round trip. Legacy exports declare their omitted semantics.
- `Annotations.IDWriters` protects structured saves from older batch writers and coordinates processing image/ID publication. Unsupported legacy batch overwrites stop with an actionable error.

Manual edits preserve the model outputs. They do not launch a solver or rewrite model probabilities. CRF constraints are a separate opt-in policy; unsupported backend/policy combinations stop dispatch. Background results validate their captured geometry, owners and actual selected constraints before publication.

## Save and recovery behavior

The `_ID.mat` top-level annotation store is authoritative. Publication uses a same-directory staged MAT file, verified content, an OS writer lease, an expected content hash/generation, a last-good copy, and atomic replacement. Failures before replacement preserve the old save. A failure after replacement is treated as potentially committed: the service verifies the published store or makes editing read-only until recovery, retaining the draft.

Lineage detects an older/external writer erasing or contradicting structured state when recovery evidence exists. It cannot infer historical loss in a standalone legacy file. Recovery never chooses a backup by timestamp or associates owners by row number. Missing original model evidence is reported as unavailable or unverified; the app does not reconstruct invented probabilities.

**File → Review ID recovery…** previews explicit current, legacy or previous-save choices when they have preserved stable owner IDs. It retains unique byte-verified copies before reconciling. A damaged authoritative store opens as a read-only compatibility view, with every derived label marked for review. An interrupted image/ID processing pair remains blocked for annotation-only repair; both files must be reconciled together.

## Validation scope

The [October 19 validation record](feedback-validation-20261019.md) links the local test artifacts and separates native observations, callback tests and model-integration results. Automated coverage exercises catalog membership and modifiers, typed state migration, conflict and Undo transactions, evidence preservation, structured exchange, competing/stale writers, processing rollback, captured background contexts and the editor/service integration. Native computer use covers the researcher-facing selection, typing, staging, assignment, cancellation, Undo and export paths on Apple silicon macOS with MATLAB R2024a; programmatic reopen verifies durable annotation/evidence/history preservation. A native assignment also completed during an actual ZephIR run.

Windows, Linux and screen-reader behavior require separate platform validation. Search timing is measured for the warm local search/controller path, not as a guaranteed end-to-end display latency. Legacy snapshots are preserved, but their original scientific provenance cannot be established retroactively.
