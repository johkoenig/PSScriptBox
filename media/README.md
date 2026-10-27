> Deutsche Version: [README.de.md](README.de.md)

This folder contains PowerShell utilities for reducing video file sizes while preserving dates. Use Windows PowerShell
5.1 or PowerShell 7 from a regular user session.

## Quick start

1. Install FFmpeg with the `libx265` encoder and ExifTool; make both executables available in `PATH`.
2. Preview MOV and MP4 files in a folder:

   ```powershell
   .\Optimize-MediaSize.ps1 -InputPath 'C:\Videos' -WhatIf
   ```

3. Optimize the folder, keeping each original as an `_orig` backup with its original extension:

   ```powershell
   .\Optimize-MediaSize.ps1 -InputPath 'C:\Videos'
   ```

PowerShell execution policy may require a policy-approved way to run local scripts. Do not weaken system policy globally
just to run these tools.

## Dependency setup

`Optimize-MediaSize.ps1` requires:

- FFmpeg with the `libx265` encoder.
- FFprobe, included with FFmpeg, to identify each video's codec.
- ExifTool, used to copy metadata and verify file-level EXIF/XMP and container capture dates.

If Chocolatey is installed, both can be installed with:

```powershell
choco install ffmpeg exiftool -y
```

FFmpeg must include `libx265`. Both programs must be discoverable in `PATH`. The script only checks for them; it does
not install software or require administrator rights.

## Scripts and switches

### `Optimize-MediaSize.ps1`

Encodes eligible `.mov` and `.mp4` files as 720p H.265/HEVC MP4 using the `libx265` encoder, a 1.9 Mb/s average video
bitrate, the `medium` preset, and 96 kb/s audio. Landscape video is limited to 1280x720; portrait video is limited to
720x1280. This targets approximately 90 MB for a six-minute video, though actual size varies with duration and content.
H.264 sources at or below 1.9 Mb/s and HEVC, AV1, and VP9 sources are skipped. H.264 with unknown bitrate is skipped
conservatively, and a matching `_orig` backup prevents repeated lossy encoding. Other codecs are re-encoded.
Folders are searched recursively, and a result is accepted only when smaller than the source.

| Parameter / switch  | Description                                                                                     |
|---------------------|-------------------------------------------------------------------------------------------------|
| `-InputPath <path>` | MOV or MP4 file or folder to process. If omitted, prompts for a path.                           |
| `-ReplaceOriginal`  | Replaces the source after successful encoding and date verification, without an `_orig` backup. |
| `-WhatIf`           | Probes codecs and previews planned file changes without encoding or modifying files.            |
| `-Confirm`          | Prompts before processing each eligible video.                                                  |
| `-EnglishOutput`    | Forces English console output regardless of Windows UI language.                                |

Examples:

```powershell
.\Optimize-MediaSize.ps1
.\Optimize-MediaSize.ps1 -InputPath 'C:\Videos' -WhatIf
.\Optimize-MediaSize.ps1 -InputPath 'C:\Videos\clip.mp4'
.\Optimize-MediaSize.ps1 -InputPath 'C:\Videos' -ReplaceOriginal -Confirm
```

By default, the original is moved to `<Name>_orig.mov` or `<Name>_orig.mp4` only after a smaller, date-verified MP4 is
ready. An existing output or backup is never overwritten; that file is reported as an issue. When optimizing an MP4, the
output occupies the source path only after the source has been moved to its backup.

## Shared PowerShell parameters

The script supports common parameters including `-Verbose`, `-Debug`, `-ErrorAction`, `-WarningAction`, `-WhatIf`, and
`-Confirm`. `-WhatIf` and `-Confirm` are provided through `SupportsShouldProcess`.

## Safety and behavior

- FFmpeg maps global and stream metadata and chapters. ExifTool copies supported metadata from the source and the script
  compares file-level EXIF/XMP and container capture dates before accepting the result. Per-track creation and
  modification timestamps are excluded because output streams may differ. If relevant date metadata cannot be copied
  or differs, the source is left in place.
- The source's creation, last-write, and last-access file timestamps are restored on the MP4. ExifTool's supported
  file-level EXIF/XMP and container capture dates are copied and checked. Windows does not permit the script to set
  NTFS change time, so that low-level file-system timestamp cannot be preserved.
- The original is not replaced unless the MP4 is smaller. Existing outputs and backups are preserved, not overwritten.
- A high-bitrate H.264 file with an existing matching `_orig` backup is skipped to avoid another lossy encode on
  subsequent runs.
- Average-bitrate H.265 encoding is lossy and cannot guarantee that no visible quality change occurs. The bitrate
  targets a size range, not a fixed output size.
- Temporary MP4 files are created beside their source with a `.mp4.part` suffix and removed after processing.
- `-ReplaceOriginal` replaces the source only after the output is present, smaller, and its dates are verified. Back up
  important files before using this option.
- The script does not delete matching Live Photo videos or process formats other than `.mov` and `.mp4`.
- Do not use this tool on files that must remain byte-identical.
- The project is licensed under the [MIT License](../LICENSE.md).
- Contribution guidance is in [CONTRIBUTING.md](../CONTRIBUTING.md).
