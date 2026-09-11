#!/usr/bin/env python3
"""Install an app manifest beside a verified fold-00 handoff (no training)."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

YOLO_HASHES = {
    'infer_volume_slices_yolo.py': 'a0b89925fdfaa37f5828167af4cc5df74c0905eefbb897d18a4fde37eb26cc88',
    'mip_centroids_iou_color_fuse.py': 'f6601b3ac7ff296f658e82268b1ffcc23fcecfb53fee956af0dd71d3420289cc',
    'mip_centroids_from_predictions_summary.py': '362eec88b43b67d4018d6df8b7a1ffb0508c606ac9a7efb6b5911ffd64259226',
}

def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(8*1024*1024), b''): h.update(block)
    return h.hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    parser.add_argument('--yolo-source', type=Path, action='append', default=[])
    parser.add_argument('--python', type=Path, required=True)
    args = parser.parse_args()
    if not args.python.is_file(): raise FileNotFoundError(args.python)
    root = args.bundle.resolve()
    expected = json.loads((root/'manifest.json').read_text())
    if expected['source_commit'] != '2276e61dedf9671740c1a36fab7d6d976b86de37' or expected['fold'] != 0:
        raise ValueError('This installer supports the pinned fold-00 integration fixture only')
    for line in (root/'SHA256SUMS').read_text().splitlines():
        checksum, name = line.split(None, 1)
        path = (root/name).resolve()
        if not path.is_relative_to(root) or digest(path) != checksum:
            raise ValueError(f'Invalid bundle artifact: {name}')
    target = root/'app_support/yolo_inf2'
    target.mkdir(parents=True, exist_ok=True)
    for name, checksum in YOLO_HASHES.items():
        candidates = [target/name, *[folder/name for folder in args.yolo_source]]
        match = next((p for p in candidates if p.is_file() and digest(p) == checksum), None)
        if match is None: raise FileNotFoundError(f'Supply the hash-matched YOLO source {name} via --yolo-source')
        if match.resolve() != (target/name).resolve(): shutil.copy2(match, target/name)
    (root/'app_support/SHA256SUMS').write_text(''.join(f'{v}  yolo_inf2/{k}\n' for k,v in YOLO_HASHES.items()))
    roles = {**expected['models'], 'source': 'source/GAT-NeuroPAL', 'yolo_source':'app_support/yolo_inf2',
             'checksums':'SHA256SUMS', 'router_policy':'provenance/router.json', 'features':'configuration/ordered_features.json'}
    manifest = dict(schema_version=1, method_id='detection_moe', display_name='Nonlinear MoE (fold 00, experimental)',
                    source_revision=expected['source_commit'],
                    configuration={'python_executable':str(args.python.absolute()),'device':'cpu','dataset_id':'unknown'},
                    artifacts=[dict(role=k,path=v,required=True) for k,v in roles.items()])
    (root/'method_bundle.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(f'Installed {root}/method_bundle.json')

if __name__ == '__main__': main()
