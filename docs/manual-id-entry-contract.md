# Manual neuron identity entry design contract

**Status:** Implementation contract 1.0. **Date:** 2026-10-15.

See [implementation and validation scope](manual-id-implementation.md) for the delivered behavior and platform coverage.

The ID entry control is the boundary between a researcher's observation and the application's anatomical annotation. It must let the researcher record exactly what they know, preserve what remains unresolved, and revise an assignment without losing evidence. Its resting appearance remains one compact ID field and its assignment action.

This contract specifies required behavior. MUST denotes a correctness requirement; SHOULD denotes a preferred default with a documented reason required for exceptions. Pixel dimensions and wording are defaults that may evolve without changing the identity, confirmation, and persistence rules. Platform validation coverage is recorded separately.

## C01 Identity and ownership

Every editable target MUST have a stable source identifier and a stable logical neuron identifier. Neither the detection array index, display row, filename, nor a temporary graphics handle is an anatomical identity.

An observation identifies where a logical neuron was measured, including its frame and geometry revision. A track's 1,800 observations share one logical neuron owner. Reordering a list cannot change annotation ownership. Replacing detections creates new owners unless an explicit correspondence operation transfers existing owners.

Identity occupancy is scoped to a specimen. Independent specimens may both contain AVAL. Multiple acquisitions share a specimen and neuron owners only after explicit specimen association and correspondence. When specimen identity is unavailable, use a persistent isolated acquisition scope and show that limitation in metadata; do not infer a shared animal from filenames or image similarity.

## C02 Identity vocabulary

The engine MUST distinguish these namespaces even when their displayed text is identical.

| Record | Meaning | Example |
| --- | --- | --- |
| Canonical individual | One member of a versioned identity catalog | AVAL |
| Catalog group | An explicitly curated set of members, optionally hierarchical | AVA with AVAL and AVAR |
| Model class | One output of a particular model bundle and vocabulary version | The GAT bundle's AVA output |
| Identity hypothesis | The explicit possible individual members for one observed neuron | AVAL or AVAR, member unresolved |
| Human annotation | A reviewed assertion or hypothesis, with certainty and provenance | Confident AVA membership, unresolved side |
| Model evidence | An immutable inference result and its scores | GAT class score and ranked alternatives |

Catalog groups, model classes, and NeuroPAL color groups MUST NOT be equated by their spelling. Model-to-catalog mappings MUST be explicit and versioned with the model bundle.

Catalog records SHOULD provide canonical name, explicit aliases, applicable sexes, group membership, anatomical descriptors, ordinal/subtype when applicable, and region/stage metadata. An inapplicable catalog attribute is distinct from unknown specimen orientation.

No general suffix stripping, regular expression, coordinate ordering, or existing historical helper is authoritative for membership or laterality. The existing male class data and helpers require validation before they can supply this catalog.

## C03 Anatomical resolution

L/R/D/V MUST describe the animal's anatomy. Image coordinates, screen direction, display flips, alphabetical order, and another neuron's existing assignment MUST NOT silently establish anatomical identity.

| Query | Required members or interpretation |
| --- | --- |
| AVA | AVAL and AVAR |
| IL1 | IL1DL, IL1DR, IL1L, IL1R, IL1VL, IL1VR |
| RME | RMED, RMEL, RMER, RMEV |
| SAB | SABD, SABVL, SABVR; no fabricated fourth member |
| ADL | ADLL and ADLR; preserve the class name's final L |
| OLL | OLLL and OLLR |
| AS | AS1 through AS11 as distinct individuals, in natural numeric order |
| AQR, AVL, PQR, PVR, RIR | Exact individual names, without invented counterparts |
| Male R1 | R1AL, R1AR, R1BL, R1BR |

Display transformations MUST change presentation only. A command that changes anatomical identities, including a bilateral swap or a specimen-wide L/R correction, MUST be separately named, preview its affected associations, and use the annotation transaction and Undo rules below.

An optional future anatomical inference method must supply its own validated mapping, orientation provenance, and uncertainty. Its output enters the editor as a proposal, never as a consequence of opening or sorting suggestions.

## C04 Annotation state

The following states MUST remain distinguishable in memory, the saved ID file, counts, work queues, and structured exports.

| State | Stored meaning | Occupies an individual identity |
| --- | --- | --- |
| Unassigned | No anatomical assertion | No |
| Individual hypothesis | One candidate individual, not confidently confirmed | No |
| Confirmed individual | One reviewed, confidently asserted individual | Yes |
| Unresolved membership | Two or more explicit candidate individuals; membership may itself be tentative or confident | No |
| Artifact or non-neuronal classification | An explicit classification rather than a neuronal identity | No |
| Legacy issue | A preserved imported value requiring interpretation | No new binding until resolved |

"Definitely AVA, side unknown" and "possibly AVAL" MUST be different records. Neither becomes an arbitrary confirmed side. Human certainty MUST NOT be encoded as a model probability.

The minimal annotation record contains schema version, record/revision IDs, owner scope and logical neuron ID, catalog version, kind, explicit candidate individual IDs, optional catalog group reference, certainty, review state, annotation attributes, context exceptions, provenance, and referenced model evidence. Resolution follows the candidate set and kind; redundant fields must agree on validation.

Certainty defaults are `confident`, `tentative`, or `unspecified`; they are researcher statements, not calibrated numeric probabilities. `reviewed` means the researcher committed the record, not that an individual member has been resolved. AWC ON/OFF, emphasis, and notes are separate attributes. Newly recorded author/time metadata must be accurate; unavailable legacy authorship or time remains unknown.

A confirmed binding requires an individual assertion, exactly one valid canonical member, confident human certainty, a reviewed state, and no unresolved validation issue. Review state is `unreviewed`, `reviewed`, `legacy-reviewed`, or `needs-review`. `legacy-reviewed` preserves a demonstrable prior human review from a recognized source format; it qualifies for a confirmed binding without claiming a new review or inventing the original reviewer/time. A model confidence of 1 alone never establishes human review. Tentative or unspecified certainty remains an individual hypothesis. A singleton candidate set, including one narrowed by search or context, never promotes itself into a confirmed assertion.

Only confirmed individual bindings enforce one owner per canonical individual within an occupancy scope. Tentative hypotheses may overlap and MUST be shown as tentative elsewhere. Confirming an individual flags competing hypotheses for review; it does not erase them. Unresolved sets never reserve all their members or automatically infer missing counterparts.

## C05 Draft ownership and lifecycle

Search text, an accepted draft, the saved annotation, and model prefill MUST be separate states.

A draft is bound to its source, stable owner, annotation revision, geometry revision, catalog/context revision, and a draft generation token. Every suggestion response and assignment action carries that context. A late event MUST NOT apply to a new neuron just because it reuses an old numeric row.

Typing, highlighting, choosing a suggestion, changing Z, blurring the field, switching tabs, and navigating among neurons MUST NOT save or advance. In-session drafts are retained per owner and restored on return. Merely showing a model prefill does not mark work dirty; researcher edits or explicit suggestion choices do.

Source close/reset/replacement includes unsent drafts in the existing unsaved-work decision: return to editing or explicitly discard drafts. Drafts MUST NOT be promoted into annotations by closing or saving another component. Optional crash recovery must label recovered drafts separately from committed annotations.

Deleting/replacing an owner invalidates its draft target and pending events. If a researcher draft exists, the destructive action must allow return/discard or retain a recoverable orphan draft with its original owner context; it cannot silently discard the text or attach it to a replacement owner. Geometry or context changes require revalidation and preserve the text with an actionable explanation. Unrelated edits should not erase drafts or invalidate the entire editor.

## C06 Compact field and suggestion popup

The resting row remains **ID**, the entry field, and its assignment action, alongside the existing app actions. Rename Auto Name to **Prefill prediction** in this design. Do not add a permanent L/R toggle, second identity dropdown, new sidebar, or extra toolbar row.

One popup anchors beneath the input and overlays the viewer. Proposed defaults: at least 320 logical pixels wide when space permits, at most eight visible approximately 28-pixel rows with scrolling, constrained to the app window. Use grayscale surfaces, a thin border, and restrained hover/selection states. These dimensions can change after native review.

Individual rows show the canonical name with a concise anatomical description and occupancy status when relevant. Catalog group headings reveal actual members in curated order, keeping bilateral counterparts adjacent where appropriate. Groups with asymmetric or numbered membership retain their actual structure.

For example, typing IL1 exposes its six members with dorsal left, dorsal right, left, right, ventral left, and ventral right descriptors. No first member becomes active merely because it sorts first.

Group headings navigate; they do not assign. An explicit **Keep AVA unresolved** action may stage the complete AVA member set. Assign then records that unresolved assertion. A filtered search result is not automatically a candidate set: a partial query cannot silently redefine what "AVA unresolved" means. Arbitrary subset editing can be added later through an explicit structured action.

The unresolved action preserves valid parsed modifiers: plain AVA stages confident AVA membership with unresolved individual, AVA? stages tentative membership, and AVA?! also carries emphasis. Neither confidence nor emphasis resolves a member. The popup must identify the complete staged member set before assignment.

Saved, edited draft, unresolved membership, and validation conflict MUST be distinguishable through concise text or symbols with accessible descriptions, not color alone. Put details in the popup or a compact field badge rather than a permanent explanatory paragraph. Decorative labels MUST remain separate from canonical stored values.

During a pending assignment, the affected action shows **Saving…** and prevents duplicate submission. This is local to that transaction; unrelated neuron inspection, tabs, and background jobs remain usable. Failure restores the actionable draft with a concise error. Success must not overwrite text the researcher edited after the captured draft.

## C07 Search and context

Search is local, case-insensitive, and deterministic. Rank exact canonical individuals first, then explicit aliases and exact catalog groups, canonical prefixes, and substring/anatomical descriptor matches. Use curated group order and natural numeric order within equivalent ranks. Search MUST NOT fuzzy-correct a name into a committed identity.

All applicable individuals remain discoverable independently of model coverage, body region, current prediction ranks, or occupancy. Already assigned choices remain visible with their status. A model class score appears at its model/group level with its source, never duplicated across members as side-specific confidence or divided into fabricated individual probabilities.

Known sex selects the applicable catalog by default. An **All atlas names** action can reveal other entries with applicability labels; assigning a conflicting entry requires an explicit context exception and reason. It does not change specimen sex. Unknown sex uses the catalog union with applicability metadata rather than silently assuming XX. Changing sex preserves existing annotations and marks conflicts for review.

Region, crop, age, and stage influence ranking or contextual warnings where supported by curated metadata. They do not silently hide otherwise valid identities. A confident anatomical assignment outside the current model's vocabulary remains valid manual work.

Prefill prediction never overrides a saved annotation, retained researcher draft, or explicit member/group choice. An exact individual prediction can supply a visibly provisional draft. A model-class prediction may supply a candidate search context only through its validated, versioned model-to-catalog mapping; it must not select a catalog group by matching displayed text. An unmapped model class remains inspectable evidence and cannot stage an anatomical assertion. Toggling prefill never commits, clears, or replaces researcher work. Suggestions remain available when prefill is off.

## C08 Keyboard and mouse behavior

All assignment gestures invoke the same command with one captured draft and target. There is no hidden save on whitespace or focus loss. The text-editing rules below apply while the input or its popup has focus. A focused explicit Assign/Update ID button retains normal Enter/Space activation: activating that command is deliberate confirmation.

| Gesture | Required result |
| --- | --- |
| Type or paste | Edit/search only; preserve raw draft until resolved |
| Space or trailing whitespace in the input | Ordinary text; never save or advance |
| Alt+Down in the input with popup closed | Open suggestions with no active row; retain text focus |
| Down in the input with popup closed | Open suggestions with no active row; a subsequent Down begins deliberate navigation |
| Up/Down with popup open | Navigate suggestions without selecting a side for commitment |
| Left/Right/Home/End in the input | Move the text caret; never navigate the image |
| Enter on an active individual row | Accept that individual into the draft and close the popup; do not save |
| Enter on an active group | Reveal its members; do not choose the first member |
| Enter with no active suggestion | Resolve/validate the draft locally; do not save |
| Ctrl+Enter | Invoke the explicit assignment command once for a valid captured draft |
| Cmd+Enter on macOS | Alias for the same explicit assignment command |
| Tab or Shift+Tab from the input | Close popup, retain draft, move focus; do not choose or save |
| Ctrl+Down with popup open | Focus the popup actions; Tab traverses All atlas names, Clear ID, and Undo |
| Enter/Space on a focused popup action | Activate that explicitly focused action using its confirmation rules |
| Escape with popup open | Close popup and retain draft |
| Escape with popup closed | Discard this owner's unsent draft; restore saved annotation, or blank if none |
| Click an individual row | Accept a draft only |
| Click outside | Close popup and retain draft |
| Double-click a suggestion | Same selection outcome as one click; no extra assignment gesture |
| Click another neuron | Retain old owner's draft and load the new owner's state |
| Click Assign | Validate and commit the captured draft exactly once |
| Enter/Space on the focused assignment button | Activate that explicit command once, with the same validation as a click |

No implicit active first row is allowed on a family query. Opening suggestions, scrolling them, or changing their ordering cannot change the committed annotation. The modified assignment shortcut may commit valid exact individual text or an explicitly staged unresolved set, whether the popup is open or closed. A merely highlighted but unaccepted row is never substituted for the text/draft. An unstaged ambiguous family, stale draft generation, or active conflict modal blocks the shortcut with specific guidance; it cannot commit an arbitrary first suggestion. Applicable shortcuts cannot activate controls behind a modal.

The assignment button reads the visible editor's current draft directly. It MUST NOT depend on a blur callback reaching a hidden field before the button event. Repeated/double-clicked assignment gestures share an operation token and cannot assign the next neuron accidentally.

## C09 Validation and annotation attributes

Normalization may trim surrounding whitespace, canonicalize name case, and apply explicit catalog aliases. It MUST NOT truncate malformed names, strip meaningful terminal letters, or automatically collapse numbered IDs. AS01 maps to AS1 only when the catalog/model mapping explicitly defines that alias.

Retain legacy shorthand as a strict parser into structured attributes:

| Shorthand | Intended draft |
| --- | --- |
| AVAL | Confident individual assertion |
| AVAL? | Tentative individual hypothesis |
| AVAL! | Individual assertion with emphasis; no extra permissions |
| AVAL?! | Tentative individual with emphasis |
| AWCL-ON or AWCR-OFF | Individual plus applicable functional-state attribute |

The accepted suffix order is canonical token, optional ON/OFF, optional `?`, optional `!`. Duplicate, unknown, reversed, or inapplicable suffixes produce actionable validation feedback and preserve the draft. AWCL-GARBAGE MUST be rejected, not truncated to AWCL. A standalone `?` is not an identity. Group queries with modifiers remain unresolved until an explicit group/member action stages their meaning.

AWC ON/OFF is independent of laterality and applicable only where the catalog permits it. Replacing an AWC identity with a different identity must explicitly resolve an incompatible retained state. Emphasis changes presentation/metadata; it MUST NOT bypass sex checks, uniqueness, or solver policy.

Incomplete family, unknown name, wrong context, missing target, read-only source, occupied identity, and stale draft are distinct conditions with specific feedback. Ordinary incomplete typing needs no modal error. Missing model weights MUST NOT prevent manual lookup, annotation, save, or Undo.

## C10 Assignment commands and conflicts

The visible action may read **Assign** for a new record and **Update ID** for a changed existing record. Both use one annotation service. An unchanged resulting annotation state is an idempotent no-op: no new revision, model change, or advancement. Compare kind, members, certainty, review state, attributes, exceptions, and applicable policy, not merely the displayed text; explicitly reviewing a previously unreviewed hypothesis is a real change.

| Command | Required meaning |
| --- | --- |
| Assign | Record the explicitly staged individual, hypothesis, group membership, or classification |
| Replace | Withdraw the current owner's prior claim and record the replacement |
| Move | Transfer an occupied confirmed identity after showing both resulting owners and any displaced target claim |
| Swap | Exchange two confirmed individual identities in one transaction |
| Clear ID | Withdraw the anatomical claim while retaining the neuron, track, geometry, original predictions, and history |
| Cancel | Preserve saved state, selection, and draft |

Choosing an occupied identity MUST NOT silently delete its old owner. A conflict prompt previews both resulting associations and offers only valid explicit actions, with Cancel as the safe default. For an AVAL/AVAR correction, Move and Swap are different choices.

For X holding A and Y holding B, moving B to X withdraws Y's B binding and X's prior A binding, leaving X bound to B and Y unassigned. Swapping instead results in X bound to B and Y bound to A. Each confirmed result requires explicit confirmation of both resulting mappings; accepting an uncertain alternative stages hypotheses rather than falsely claiming a confirmed Move/Swap. Withdrawn records remain in history. A claim already tentative or unresolved is not eligible for a confirmed-identity Swap without separate resolution.

Tentative claims do not block another confirmed binding, but confirmation marks competing hypotheses as conflicts requiring review. Same-owner repeated observations are not duplicate bindings. Emphasis, artifacts, and non-neuronal roles do not create exceptions to confirmed neuronal occupancy.

Notes and evidence stay attached to their source observation/record. Move/Swap must not blindly transport certainty, phenotype observations, or anatomical evidence with a name. The resulting associations get their own reviewed provenance and attribute validation.

Clearing an empty field alone never deletes an annotation. Explicit Clear ID, or Assign on an intentionally emptied saved annotation, requires the same deletion confirmation. Cancel retains the selected neuron and edit context. Assign on an empty unassigned target is disabled; skipping is a separate navigation action.

After a successful changed commit, the existing nearest/uncertainty next-neuron policy may advance to another unreviewed owner only if the researcher is still on the captured target and has not created a newer draft. Otherwise publish the saved result to its owner without stealing selection or replacing the newer draft. It MUST NOT treat "all reviewed" as "all individual identities resolved." Tentative and unresolved records remain available in resolution queues. Failure, cancellation, no-op, or draft acceptance never advances.

## C11 Model evidence and solver constraints

Human assignment MUST NOT overwrite original deterministic/model class outputs, probability vectors, model scores, or their vocabulary. Human certainty and model evidence have distinct sources and meanings.

The default assignment transaction writes human annotation only. It does not implicitly invoke CRF, GAT, or another model. Optional live recomputation must be an explicit setting/action, execute outside the save transaction, identify its backend, and publish a new inference result.

Constraint use is a separate explicit policy, off by default for new or migrated annotations until selected for a run. Only confident, reviewed assertions of a supported type are eligible for hard constraints; tentative individual or group hypotheses are never hard pins. A confidently reviewed unresolved set may constrain a model only if that backend supports its exact set constraint. Unsupported constraints stop dispatch until the researcher changes backend/policy or explicitly acknowledges proceeding without those constraints. They must not be silently omitted or converted to the first individual.

Every recomputation records the input source/geometry, exact constraint snapshot, model bundle/vocabulary, and inference ID. Model results may change suggestions, but never replace newer human annotations. The original evidence remains inspectable after Clear, Replace, Undo, or rerunning a model.

## C12 Persistence and Undo

The existing `_ID.mat` is the proposed authoritative save artifact for the first implementation. Extend it with a versioned annotation store, stable owner mapping, inference evidence or verifiable references, and an annotation event journal. Keep a clearly defined legacy neuron projection alongside them. Loaders MUST prefer the validated versioned store and surface disagreements rather than silently choosing one representation. Evidence references are content-addressed and integrity-checked; a machine-local absolute pathname alone is not a portable evidence reference. Missing evidence is reported as unavailable without fabricating scores or blocking preservation of valid manual work.

One annotation command follows this transaction boundary:

1. Capture visible draft, operation token, owner scope, and relevant revisions.
2. Parse and validate meaning, context, and ownership.
3. Resolve explicit conflicts; revalidate after any modal interaction.
4. Stage complete before/after values for every affected owner without mutating live handle objects.
5. Validate resulting occupancy and attributes.
6. Save all authoritative annotation state and its compatible projection to a temporary file in the destination directory; close and verify its schema, owner mapping, record consistency, and integrity.
7. Acquire the authoritative file's writer lease, compare its current generation/content hash with the captured expected save, and revalidate affected source/geometry/context and occupancy. Under that lease, preserve a verified last-known-good recovery copy and atomically replace the authoritative file using a supported same-filesystem strategy. Release the lease only after checking the published generation. Unsupported destinations fail or require a supported local destination; never fall back silently to an unsafe overwrite.
8. Publish committed state to the UI and, if appropriate, advance once.

Disk-full, permission, validation, verification, and replacement failures preserve the prior authoritative file, annotation state, selection, and draft. A successful durable save followed by a render failure reports **Saved; display could not refresh**, then rebuilds the view from committed state. Retrying an operation token cannot create a second edit.

All application paths writing this authoritative file must share the writer protocol, including geometry and session saves. Atomic replacement prevents torn writes; the lease and generation check prevent competing supported writers from losing updates. A stale write retains its draft and reconciles or retries against the newer save rather than overwriting it. Cloud/shared destinations without reliable coordination are not supported for concurrent writing. Older/external applications that ignore the protocol cannot be guaranteed safe concurrent writers; do not advertise that guarantee.

Source close/reset or deletion of an affected owner must wait for an in-flight transaction to finish, or cancel it before publication with a verified unchanged authoritative file. A late completion remains bound to its captured source and owner; it cannot publish into whichever source is currently visible. The UI must distinguish cancelling pending work from undoing an already durable commit.

The bounded last-known-good recovery copy and lineage metadata are recovery evidence, not a second annotation authority. Failure to preserve required recovery evidence aborts the transaction before replacement. Startup handles abandoned temporary files/leases and interrupted publication by verifying generations and file integrity; it must not break a live lease or choose a backup solely because its timestamp is newer.

Undo is a new saved inverse transaction. One Replace/Move/Swap is one Undo unit covering all affected owners. Undo checks current affected revisions and occupancy; if subsequent work conflicts, it explains the conflict instead of erasing a third owner's annotation. It restores annotation associations and applicable attributes without reverting unrelated coordinates, tracks, activity, or historical model evidence. History survives save/reload; a later session can recover or explicitly reverse supported recent events.

Undo records and commits MUST NOT copy the image volume or video stack. Annotation history stores small deltas and evidence references. Annotation edits do not invalidate activity extraction solely because a label changed.

## C13 Background work and downstream identity

Unrelated ZephIR/detection/inference jobs MUST NOT prevent manual ID work. Jobs read immutable snapshots and publish predictions or geometry proposals; they do not mutate human annotation records directly.

Applying results checks stable ownership and the relevant source/geometry/constraint revisions. Newer human annotations win over stale job output. A run based on older constraints is labeled accordingly. Concurrent geometry edits and source replacement require explicit conflict handling; unrelated annotation changes should not unnecessarily reject valid model evidence.

Names are attributes of stable logical neurons, not tracking row numbers. Importing NeuroPAL identities into another acquisition requires explicit correspondence. Later renaming must synchronize through that association or be reported as a separate copied annotation, never silently guessed from equal numeric IDs.

## C14 Migration and export

Migration preserves the original file and raw values, records its schema/migration version, and does not invent lost model scores, reviewer identity, side evidence, or timestamps.

Exact legacy individuals are imported with their recorded certainty only through a recognized producer/schema mapping. Explicit prior human review may be preserved as `legacy-reviewed`, with unknown author/time left unknown; numeric model confidence alone does not establish that review. An exact legacy group token may become unresolved membership only when its catalog-group meaning is unambiguous, or its source model/vocabulary and validated membership mapping are known. Same-spelling namespace collisions remain migration issues until explicitly resolved. Unknown names, malformed suffixes, incompatible sex, and conflicting duplicate bindings also become visible issues. Do not resolve them by choosing the first member or owner. Preserve legacy ARTIFACT/MUTATION/emphasis meaning as classification/metadata or an explicit legacy issue; do not use those strings as permissions to duplicate canonical identities.

The legacy individual annotation field contains an exact compatible confirmed individual/non-neuronal token or is empty. Tentative/unspecified hypotheses and unresolved sets MUST NOT populate a field that an older consumer interprets as a hard identity pin, even with a confidence of 0.5. Omit them with an explicit loss report/marker in that compatibility projection. Never serialize them as IL1, AVAL/R, UI descriptions, or the first candidate. The versioned store preserves their full meaning.

The full structured export includes owner/source/specimen IDs, record and catalog versions, assertion kind, candidate individuals/group, certainty, review state, ON/OFF and other attributes, context exceptions, provenance, inference references, and constraint policy. Full export/reimport must preserve those meanings and original model evidence. Package referenced evidence artifacts or guarantee their integrity-checked retrieval; an export with unavailable references must declare that limitation and cannot claim full evidence fidelity.

Older consumers that cannot represent ambiguity receive a declared compatibility projection with omitted fields reported. Round-trip preservation through an older app is not promised. Lossy export requires acknowledgement; it never invents a side. Where recovery/lineage evidence exists, report an older writer dropping or contradicting the versioned store and offer explicit reconciliation; do not silently restore the backup over subsequent legacy edits. A standalone legacy file without that evidence cannot reveal whether newer information was previously erased. Import it as legacy with unknown loss rather than claiming that loss was detected or that nothing was lost.

## C15 Accessibility and performance

Keyboard-only use must reach every identity and every assignment/conflict action. Focus remains understandable through popup navigation, errors, cancellation, and auto-advance. Screen-reader text identifies owner, draft/saved state, group versus individual, anatomical descriptor, and occupied status. Review must include actual supported MATLAB/platform combinations; native widget defaults are not proof of accessibility.

Opening suggestions and typing perform no model execution, volume traversal, full-image rendering, or disk access. Build/cache the small catalog/search index at source/catalog changes. A proposed interaction budget is at most 100 ms from keystroke to visible suggestions at the 95th percentile on the meeting Mac, measured over at least 100 scripted/native queries after first render, with the catalog version recorded. First-open and steady-state results are reported separately.

Popup geometry, scrolling, large text/DPI settings, and narrow windows must keep the field and assignment action usable. Resize/tab/source changes close or reposition the popup without changing annotations or silently discarding drafts. No performance workaround may weaken ownership, persistence, or confirmation semantics.

## C16 Acceptance criteria

Each test must check saved state and original model evidence where applicable, not only the displayed field. Native event-order tests supplement controller/schema tests.

| Test | Required outcome |
| --- | --- |
| A01 AVA, IL1, RME, SAB, male R1 | Expose exactly the actual members; no automatic side/member |
| A02 AQR, AVL, ADL, OLL, SDQL/SDQR | Preserve exact catalog identity and valid membership without suffix guessing |
| A03 AS1 versus AS10 and AS01 | Distinct exact IDs, natural display order, aliases only if explicitly registered |
| A04 CANL with GAT selected or no weights | Remains available and manually savable, without claiming model support |
| A05 Class score for IL1 | Remains a class score; no invented member confidence |
| A06 Keep AVA, AVA?, or AVA?! unresolved then save/reload/export/reimport | Same complete member set, certainty, emphasis, and provenance; no occupied individual |
| A07 Two tentative IL1L claims then one confirmation | Preserve hypotheses, mark conflict, enforce one confirmed owner |
| A08 Two specimens and repeated frames of one track | Valid repeated names in different scopes and one owner across time |
| A09 Type, paste, highlight, select, Space, Tab, blur, Escape in input/popup | Draft behavior only; no save or advancement |
| A10 Type trailing space then click Assign | Exactly one captured-target commit; never a second assignment to the next neuron |
| A11 Enter and modified Enter paths with popup open/closed | Input Enter only accepts/validates; explicit shortcut commits valid text/staged sets once, never highlighted substitutes or stale drafts; focused Assign has native Enter/Space activation |
| A12 Double-click or delayed duplicate Assign | One operation token, one revision, one advancement |
| A13 Switch neuron/tab and return | Restore correct owner's draft; model prefill does not replace it |
| A14 Replace source, reorder/replace detections, or complete a stale popup event | No reassignment through reused numeric indices |
| A15 Change sex/region/catalog while editing | Preserve text/annotations, refresh context, require explicit conflict resolution |
| A16 Unknown sex or intentional context exception | No silent XX assumption or sex change; exception recorded |
| A17 Valid modifiers and malformed AWC/suffix strings | Structured attributes round-trip; invalid input changes no annotation |
| A18 Occupied ID and Cancel | Both owners, draft, focus, selection, and model evidence unchanged |
| A19 Move/Swap/Replace and Undo | One complete saved transaction and one valid inverse across all owners |
| A20 Clear and deletion Cancel | Preserve geometry/evidence; cancellation preserves editing context |
| A21 Disk-full/permission/verification/atomic replacement failures | Prior save and live annotation survive; draft remains available |
| A22 Rendering failure after durable commit | Accurate saved status, recovery from committed state, no duplicate edit |
| A23 Stale conflict modal or worker completion after manual edit | Revalidate affected context; preserve newer human work |
| A24 Tentative annotation and optional solver update | No automatic hard pin or fabricated 100 percent model evidence |
| A25 Full versus legacy export | Full fidelity where supported; declared loss where unsupported; no arbitrary individual |
| A26 Legacy duplicates/unknown tokens/overwritten scores | Visible issues and original raw values, no invented certainty/provenance |
| A27 Display flip or popup sort change | No anatomical annotation changes |
| A28 Auto Name renamed Prefill prediction | Checkbox only affects provisional prefills; autocomplete and saved annotations remain independent |
| A29 Native keyboard, narrow window, large UI scale, screen reader | Usable focus, labels, popup placement, and confirmation on supported platforms |
| A30 Search under background tracking | Meets measured interaction budget without expensive typing work or cross-source edit blocking |
| A31 Competing writers, interrupted save, stale generation, corrupt temporary file | No lost updates or partial publication; verify/retain prior save and drafts; safe recovery under the writer protocol |
| A32 Older writer drops versioned state; export moved to another machine | Detect regression only with lineage evidence, preserve later edits for reconciliation; report unavailable evidence honestly; no fabricated restoration |
| A33 Navigate or edit another draft during a slow save; close/reset its source | Save stays with captured owner, newer draft/selection survives, no surprise auto-advance; close/reset waits or safely cancels before publication |

## Delivery and review

Implement the contract in this dependency order: validated catalog/owner/schema; annotation commands and atomic persistence/Undo; draft/controller state and explicit confirmation; grouped suggestions and context handling; migration/export; native interaction and failure testing.

Do not expose unresolved annotation as a shipping UI feature until save/reload/export and consumers preserve its meaning or explicitly declare loss. Do not represent a partial implementation as full contract compliance.

The main product choices to review are the modified-Enter confirmation shortcut, explicit unresolved membership, confirmed-only occupancy, opt-in solver constraints, per-owner retained drafts, and persisted annotation history. The defaults above are concrete proposals, not claims that these departures from current behavior have been approved or implemented.

Current integration points are [ManualIDInput](../+Program/+GUI/ManualIDInput.m), [NeuronIDChooser](../+Program/+GUI/NeuronIDChooser.m), [GUIHandling](../+Program/GUIHandling.m), the SelectNeuron/SaveUserID/SaveIDToFile callbacks in visualize_light.mlapp, [Neuron](../+Neurons/Neuron.m), [AutoId](../+Methods/AutoId.m), [ImageAnalysis export](../+Output/ImageAnalysis.m), and [tracking neuron names](../+Tracking/NeuronNames.m). Current native checks and code audit artifacts are under `/Users/adamg/neuroPAL/artifacts/manual-id-ui-20261015`; they establish the starting behavior rather than compliance with this proposed contract.
