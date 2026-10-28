> Deutsche Version: [README.de.md](README.de.md)

This folder contains PowerShell utilities for reducing video and high-resolution JPEG photo sizes while preserving
dates, removing matching Live Photo videos, and restoring media dates from filenames or metadata. Use Windows
PowerShell 5.1 or PowerShell 7 from a regular user session.

## Quick start

1. Install FFmpeg with the `libx265` and MJPEG encoders plus ExifTool; make the executables available in `PATH`.
2. Preview Live Photo videos identified by a same-name JPG in the same folder:

   ```powershell
   .\Remove-LivePhotos.ps1 -InputPath 'C:\Media' -WhatIf
   ```

3. After reviewing the candidates, remove matching MOV videos without confirmation by default:

   ```powershell
   .\Remove-LivePhotos.ps1 -InputPath 'C:\Media'
   ```
   Add `-Confirm` to request a prompt before each deletion.

4. Preview video and JPEG files in a folder:

   ```powershell
   .\Optimize-MediaSize.ps1 -InputPath 'C:\Media' -WhatIf
   ```

5. Optimize the folder, keeping each original as an `_orig` backup with its original extension:

   ```powershell
   .\Optimize-MediaSize.ps1 -InputPath 'C:\Media'
   ```

6. Preview removal of backups whose processed media file exists:

   ```powershell
   .\Remove-MediaBackups.ps1 -InputPath 'C:\Media' -WhatIf
   ```

7. After checking the list, remove eligible backups without confirmation by default:

   ```powershell
   .\Remove-MediaBackups.ps1 -InputPath 'C:\Media'
   ```
   Add `-Confirm` to request a prompt before each deletion.

8. Preview restoring dates and renaming supported media files:

   ```powershell
   .\Restore-MediaDate.ps1 -InputPath 'C:\Media' -WhatIf
   ```

9. Restore dates and rename files after reviewing the preview:

   ```powershell
   .\Restore-MediaDate.ps1 -InputPath 'C:\Media'
   ```

PowerShell execution policy may require a policy-approved way to run local scripts. Do not weaken system policy globally
just to run these tools.

## Dependency setup

`Optimize-MediaSize.ps1` requires:

- FFmpeg with the `libx265` and MJPEG encoders.
- FFprobe, included with FFmpeg, to identify video codecs and read JPEG dimensions.
- ExifTool, used to copy metadata and verify file-level EXIF/XMP and container capture dates.

If Chocolatey is installed, both can be installed with:

```powershell
choco install ffmpeg exiftool -y
```

FFmpeg must include `libx265` and MJPEG. Both programs must be discoverable in `PATH`. The script only checks for them;
it does not install software or require administrator rights. Missing tools are
reported individually with Chocolatey commands or a download link.

## Scripts and switches

### `Optimize-MediaSize.ps1`

Encodes eligible `.mov` and `.mp4` files as 720p H.265/HEVC MP4 using the `libx265` encoder, a 1.9 Mb/s average video
bitrate, the `medium` preset, and 96 kb/s audio. Landscape video is limited to 1280x720; portrait video is limited to
720x1280. This targets approximately 90 MB for a six-minute video, though actual size varies with duration and content.
H.264 sources at or below 1.9 Mb/s and HEVC, AV1, and VP9 sources are skipped. H.264 with unknown bitrate is skipped
conservatively, and a matching `_orig` backup prevents repeated lossy encoding. Other codecs are re-encoded.

JPEG photos over 6 MB are resized according to their source file size and pixel dimensions, then re-encoded with
FFmpeg's high-quality MJPEG setting. The estimated output pixel count is the source pixel count multiplied by
`5 MB / source size`; width and height are scaled by the square root of that ratio. Actual output size varies with
image detail and compression, so 5 MB is an estimate, not a hard limit. Photos at or below 6 MB are skipped and omitted
from the end-of-run success, skipped, and failure counts and lists. Folder searches are recursive, and a result is
accepted only when smaller than its source.

| Parameter / switch  | Description                                                                                         |
|---------------------|-----------------------------------------------------------------------------------------------------|
| `-InputPath <path>` | MOV, MP4, JPG, or JPEG file or folder to process. If omitted, prompts for a path.                   |
| `-ReplaceOriginal`  | Replaces the source after successful optimization and date verification, without an `_orig` backup. |
| `-WhatIf`           | Probes codecs and previews planned file changes without encoding or modifying files.                |
| `-Confirm`          | Prompts before processing each eligible video or photo.                                             |
| `-EnglishOutput`    | Forces English console output regardless of Windows UI language.                                    |

Examples:

```powershell
.\Optimize-MediaSize.ps1
.\Optimize-MediaSize.ps1 -InputPath 'C:\Videos' -WhatIf
.\Optimize-MediaSize.ps1 -InputPath 'C:\Videos\clip.mp4'
.\Optimize-MediaSize.ps1 -InputPath 'C:\Photos\large-camera-photo.jpg'
.\Optimize-MediaSize.ps1 -InputPath 'C:\Videos' -ReplaceOriginal -Confirm
```

By default, the original is moved to `<Name>_orig` with its original extension only after a smaller, date-verified
result is ready. An existing backup is never overwritten; that file is reported as an issue.

### `Remove-MediaBackups.ps1`

Recursively finds `_orig` backups for MOV, MP4, JPG, and JPEG files. A backup is eligible only when its processed
counterpart exists in the same folder. A MOV backup such as `clip_orig.mov` is paired with the optimized `clip.mp4`;
other supported backups are paired with the same extension. The script previews with `-WhatIf` and deletes eligible
backups without confirmation by default. Use `-Confirm` to opt in to per-file prompts.

| Parameter / switch  | Description                                                                      |
|---------------------|----------------------------------------------------------------------------------|
| `-InputPath <path>` | Folder to search recursively. If omitted, prompts for a folder.                  |
| `-WhatIf`           | Lists eligible backups without deleting files.                                   |
| `-Confirm`          | Prompts before deleting each eligible backup. No prompt is requested by default. |
| `-EnglishOutput`    | Forces English console output regardless of Windows UI language.                 |

Examples:

```powershell
.\Remove-MediaBackups.ps1
.\Remove-MediaBackups.ps1 -InputPath 'C:\Media' -WhatIf
.\Remove-MediaBackups.ps1 -InputPath 'C:\Media'
```

### `Remove-LivePhotos.ps1`

Recursively finds `.mov` videos with a same-name `.jpg` still image in the same folder, then deletes the video and
keeps the image. This follows the legacy Live Photo matching pattern; `.jpeg` files do not count as a match. The
script deletes matching videos without confirmation by default; use `-Confirm` to opt in to per-file prompts or
`-WhatIf` for preview.

| Parameter / switch  | Description                                                      |
|---------------------|------------------------------------------------------------------|
| `-InputPath <path>` | Folder to search recursively. If omitted, prompts for a folder.  |
| `-WhatIf`           | Lists matching videos without deleting them.                     |
| `-Confirm`          | Prompts before deleting each matching video.                     |
| `-EnglishOutput`    | Forces English console output regardless of Windows UI language. |

Examples:

```powershell
.\Remove-LivePhotos.ps1
.\Remove-LivePhotos.ps1 -InputPath 'C:\Photos' -WhatIf
.\Remove-LivePhotos.ps1 -InputPath 'C:\Photos'
```

### `Restore-MediaDate.ps1`

Recursively processes `.jpg`, `.jpeg`, `.png`, `.mp4`, `.mov`, `.avi`, `.mkv`, `.gif`, `.heic`, `.webp`, `.3gp`, and
`.m4v` files. It chooses the date in this order: a leading `YY-MM-DD HH-mm-ss` filename timestamp, EXIF
`DateTimeOriginal`, general `CreateDate`, then `ModifyDate`. A malformed date-shaped filename is reported instead of
falling back to metadata. Files are renamed to `YY-MM-DD HH-mm-ss XXXX.ext`, where `XXXX` is a random four-character
uppercase alphanumeric code. Files whose names already match this full pattern keep their current name while their
dates are restored. Existing names are not overwritten; another code is generated on collision.

The script compares filesystem creation and last-write times and the legacy date tags before writing. Only values that
differ from the selected date are changed; unchanged values are left untouched. It does not change last-access time.
Because Windows does not permit the script to set NTFS change time, that low-level timestamp cannot be preserved.
Files without a valid date are reported as failures; processing continues for other files.

| Parameter / switch  | Description                                                      |
|---------------------|------------------------------------------------------------------|
| `-InputPath <path>` | Folder to search recursively. If omitted, prompts for a folder.  |
| `-WhatIf`           | Shows date sources and proposed names without changing files.    |
| `-Confirm`          | Prompts before renaming and changing each file's dates.          |
| `-EnglishOutput`    | Forces English console output regardless of Windows UI language. |

Examples:

```powershell
.\Restore-MediaDate.ps1
.\Restore-MediaDate.ps1 -InputPath 'C:\Media' -WhatIf
.\Restore-MediaDate.ps1 -InputPath 'C:\Media' -Confirm
```

ExifTool must be available in `PATH`. This script changes filenames and embedded dates; test with `-WhatIf` first and
keep a backup of important files.

## Shared PowerShell parameters

All scripts support common parameters including `-Verbose`, `-Debug`, `-ErrorAction`, and `-WarningAction`.
`-WhatIf` and `-Confirm` are available on scripts that change files.

## Safety and behavior

- FFmpeg maps video metadata and chapters; ExifTool copies supported metadata. File-level EXIF/XMP and container
  capture dates are checked before accepting an output. Per-track creation and modification timestamps are excluded
  because video stream layouts may differ. The Samsung maker-note `TimeStamp` and non-capture EXIF `IFD0:ModifyDate`
  are also excluded; standard EXIF capture dates remain checked. A mismatch in relevant dates leaves the source in
  place.
- The source's creation, last-write, and last-access file timestamps are restored on the optimized file. ExifTool copies
  and verifies embedded dates. Windows does not permit the script to set NTFS change time, so that low-level file-system
  timestamp cannot be preserved.
- JPEG photos at or below 6 MB are skipped and omitted from the end-of-run summary. Larger photos are proportionally
  downscaled toward an estimated 5 MB output and encoded at high quality (FFmpeg MJPEG quality-scale value 2).
  Resizing is lossy; actual output size varies with image detail and the estimate is not a guaranteed limit.
- JPEG EXIF orientation is preserved without rotating the source pixels. The optimized JPEG retains its original
  `.jpg` or `.jpeg` extension.
- An original is not replaced unless its optimized result is smaller. Existing backups are preserved, not overwritten.
- A high-bitrate H.264 file with an existing matching `_orig` backup is skipped to avoid another lossy encode on
  subsequent runs.
- Video and JPEG re-encoding are lossy and cannot guarantee that no visible quality change occurs. Video bitrate and
  JPEG quality target a size range, not a fixed output size.
- Temporary video and photo files are created beside their source with `.mp4.part` or `.jpg.part` suffixes and removed
  after processing.
- `-ReplaceOriginal` replaces the source only after the output is present, smaller, and its dates are verified. Back up
  important files before using this option.
- `Optimize-MediaSize.ps1` does not delete matching Live Photo videos or process formats other than `.mov`, `.mp4`,
  `.jpg`, and `.jpeg`. Use `Remove-LivePhotos.ps1` for the separate same-name MOV/JPG cleanup.
- `Remove-MediaBackups.ps1` deletes only `_orig` backups with an existing processed counterpart in the same folder.
  MOV backups are matched to MP4 outputs. Use `-WhatIf` to review candidates before deletion.
- `Remove-LivePhotos.ps1` deletes only MOV files that have a same-name JPG in the same folder. It keeps the JPG and
  does not treat `.jpeg` as a match. Review candidates with `-WhatIf` before deletion.
- `Restore-MediaDate.ps1` uses filename date, EXIF `DateTimeOriginal`, `CreateDate`, and then `ModifyDate`; it renames
  every valid supported file and updates filesystem and embedded dates. Its random four-character suffix uses uppercase
  letters and digits. Windows does not permit the script to set NTFS change time.
- Do not use this tool on files that must remain byte-identical.
- The project is licensed under the [MIT License](../LICENSE.md).
- Contribution guidance is in [CONTRIBUTING.md](../CONTRIBUTING.md).
