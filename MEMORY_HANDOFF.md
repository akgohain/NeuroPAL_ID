# NeuroPAL_ID memory handoff: CZI/MAT image load

> Historical investigation: the snippets below describe an earlier implementation.
> The current performance changes, measured results, and remaining limits are in
> [PERFORMANCE.md](PERFORMANCE.md). Main loading no longer builds the eager
> z-score shown below, and main rendering retains two RGB planes.

## Context

User observed MATLAB/App memory reaching roughly 9 GB while loading:

- `/Users/adamg/neuroPAL/6_mYAa.czi`
- Converted companion: `/Users/adamg/neuroPAL/6_mYAa.mat`

Treat `/Users/adamg/neuroPAL/6_mYAa.czi` as the canonical representative NeuroPAL image-volume test case for this integration/debugging work unless a narrower fixture is specified.

This appears to be primarily predictable full-volume duplication and `double` promotion, not necessarily a classic memory leak.

## Observed file sizes and payload

- CZI file: `14M`
- Converted MAT file: `103M` compressed on disk
- MAT `data` payload:

```text
data: uint16, shape (7, 25, 751, 1597), about 400 MiB uncompressed
```

Even though the original CZI is small on disk, the uncompressed in-memory volume is substantial.

## Main code paths

- CZI import: `+DataHandling/imreadCZI.m`
- NeuroPAL conversion/load: `+DataHandling/NeuroPALImage.m`
- Main open routine: `+Program/+Routines/open.m`
- Display composition: `+Program/+Helpers/compose_display_volume.m`
- Display finalization: `+Program/+Helpers/finalize_display_volume.m`
- ID render: `+Program/+Routines/+ID/render.m`
- Z-score preprocessing: `+Methods/Preprocess.m`

## Major memory multipliers

### 1. Raw image retained

Location: `+Program/+Routines/open.m`

```matlab
app.image_data = data;
```

For this file, this is about 400 MiB as `uint16`.

### 2. Full-volume z-scored duplicate retained on open

Location: `+Program/+Routines/open.m`

```matlab
app.image_data_zscored = Methods.Preprocess.zscore_frame(app.image_data);
```

Location: `+Methods/Preprocess.m`

```matlab
zvideo = zeros(size(video));
for ch = 1: size(video,4)
    data = double(video(:,:,:,ch,:));
    zvideo(:,:,:,ch,:) = (data-nanmean(data(:)))/nanstd(data(:));
end
```

Since `zeros(size(video))` defaults to `double`, the z-scored copy is roughly 1.56 GiB persistent for this file, plus per-channel temporary doubles.

### 3. Display rendering promotes the whole volume to double

Location: `+Program/+Helpers/compose_display_volume.m`

```matlab
display_volume = double(Program.Helpers.to_user_uint8(raw_volume));
```

This creates another full-volume `double` copy, roughly 1.56 GiB for this file.

### 4. RGB render copy

Location: `+Program/+Helpers/compose_display_volume.m`

```matlab
render_volume = display_volume(:, :, :, color_indices);
```

This creates a 3-channel full-volume render as `double`, roughly 686 MiB for this file.

### 5. Final display normalization creates more large temporaries

Location: `+Program/+Helpers/finalize_display_volume.m`

```matlab
render_volume = double(render_volume) / volume_max;
```

This can allocate another large temporary before returning a display-scaled result.

### 6. Full rendered RGB view is retained

Location: `+Program/+Routines/+ID/render.m`

```matlab
package = Program.Helpers.get_display_volume(app, 'main', app.image_data);
app.image_view = package.display_volume;
```

The app retains the rendered volume even though the UI mainly displays a max projection and the current z-slice.

### 7. CZI conversion-time spike

Location: `+DataHandling/imreadCZI.m`

```matlab
data = bfopen(filename);
```

`bfopen` loads all CZI planes and metadata.

Location: `+DataHandling/imreadCZI.m`

```matlab
image.data = uint16(nan([image.pixels; numChannels]'));
```

This first creates a full-size `double` NaN array and then casts to `uint16`. It should be replaced with a direct `uint16` zero allocation.

Location: `+DataHandling/NeuroPALImage.m`

```matlab
[image_data, ~] = DataHandling.imreadCZI(czi_file);
data = image_data.data;
data = permute(data, data_order);
save(np_file, 'version', 'data', 'info', 'prefs', 'worm', '-v7.3');
```

Conversion retains `image_data`, copies/permutes `data`, saves, then the open path loads the MAT again. This can spike memory during conversion.

## Prioritized action items

## Progress on 2026-06-12

- Action 1 is implemented in the main open path, the alternate identification GUI open path, and processing materialization paths: `app.image_data_zscored` is left empty instead of eagerly storing a full z-scored volume.
- Action 2 is implemented in `+DataHandling/imreadCZI.m`: CZI import allocates the output volume directly as `uint16`.
- Action 3 is partially implemented in `+Program/+Helpers/compose_display_volume.m`: display composition now uses `single` for working render arrays instead of full-volume `double`.
- Action 4 is implemented for the main ID viewer: `+Program/+Helpers/render_main_display_view.m` streams z-slices to build only the max projection and current slice, and `app.image_view` now stores that lightweight main-view cache instead of a full RGB volume. Processing views still use the older full-volume package path.
- Action 5 is partially implemented in `+Program/+Helpers/finalize_display_volume.m`: final normalization uses `single` and accepts a precomputed volume maximum so streamed main-view rendering does not need a full RGB stack.
- Action 6 is partially implemented in `+DataHandling/NeuroPALImage.m`: CZI conversion clears `image_data.data` before permuting/saving the output `data`, reducing retention of the unpermuted source array during conversion.

Validation performed:

- `git diff --check` passes.
- `matlab` was not available on PATH in the Codex shell, so MATLAB/AppDesigner syntax/runtime validation still needs to be run in MATLAB.

### Action 1: stop eager z-scoring on open

Minimal change in `+Program/+Routines/open.m`:

```matlab
app.image_data_zscored = [];
```

Instead of:

```matlab
app.image_data_zscored = Methods.Preprocess.zscore_frame(app.image_data);
```

Compute z-scored data lazily only in paths that require it, such as neuron detection or color readout.

Expected impact: removes a persistent roughly 1.56 GiB `double` volume for this test file.

### Action 2: fix CZI allocation

Change in `+DataHandling/imreadCZI.m`:

```matlab
image.data = zeros([image.pixels; numChannels]', 'uint16');
```

Instead of:

```matlab
image.data = uint16(nan([image.pixels; numChannels]'));
```

Expected impact: avoids a full-size temporary `double` during CZI import.

### Action 3: avoid full-volume `double` display conversion

In `+Program/+Helpers/compose_display_volume.m`, avoid:

```matlab
display_volume = double(Program.Helpers.to_user_uint8(raw_volume));
```

Prefer keeping the base display volume as `uint8` or `single`, and cast only the specific channel/slice where adjustment requires it.

Expected impact: removes another roughly 1.56 GiB full-volume `double` allocation during render.

### Action 4: render slice and max projection instead of full RGB volume

Current render builds and stores a full RGB rendered volume in `app.image_view`, then uses it for:

- max projection
- current z-slice

Consider changing the render path to compute only:

- current z-slice RGB image
- max projection RGB image

Do not retain a full `Y x X x Z x 3` rendered RGB volume unless downstream code actually requires it.

Expected impact: reduces retained memory and redraw-time peak memory.

### Action 5: reduce `finalize_display_volume` temporaries

In `+Program/+Helpers/finalize_display_volume.m`, avoid full-volume `double` normalization where the result ultimately becomes `uint8`.

Possible strategies:

- Use `single` normalization.
- Normalize per-channel or per-slice.
- Keep uint8-aware arithmetic where possible.

### Action 6: clear conversion intermediates before reloading MAT

After CZI conversion in `+DataHandling/NeuroPALImage.m`, explicitly clear large variables before load continues where possible:

```matlab
clear image_data data
```

This is secondary to the render/z-score fixes but may reduce conversion-time spikes.

## Suggested instrumentation

Add temporary memory logging around these checkpoints:

- after `DataHandling.NeuroPALImage.open(filename)` returns
- after `app.image_data = data`
- before and after z-score creation
- before and after `Program.Routines.ID.render()`
- after `app.image_view = package.display_volume`

Useful checks:

```matlab
whos data
whos app.image_data app.image_data_zscored app.image_view
memory
```

`memory` availability depends on platform/MATLAB behavior; `whos` is reliable for MATLAB variables.

## Minimal first patch recommendation

Start with the two low-risk changes:

```matlab
% +Program/+Routines/open.m
app.image_data_zscored = [];
```

```matlab
% +DataHandling/imreadCZI.m
image.data = zeros([image.pixels; numChannels]', 'uint16');
```

These should reduce baseline and conversion-time memory without redesigning the display pipeline.

## Expected overall diagnosis

The 9 GB MATLAB process size is plausible from:

- 400 MiB raw `uint16` volume
- 1.56 GiB z-scored `double` copy
- 1.56 GiB display `double` copy
- 686 MiB RGB render `double` copy
- normalization temporaries
- per-channel temporaries
- MATLAB graphics/UI objects
- Bio-Formats/CZI conversion intermediates

The next big improvement after the minimal patch is to stop rendering/storing the whole image volume as `double` RGB when only the current slice and max projection are displayed.
