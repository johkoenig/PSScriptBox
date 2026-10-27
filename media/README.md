> Deutsche Version: [README.de.md](README.de.md)

This folder contains PowerShell utilities for reducing video and high-resolution JPEG photo sizes while preserving
dates. Use Windows PowerShell 5.1 or PowerShell 7 from a regular user session.

## Quick start

1. Install FFmpeg with the `libx265` and MJPEG encoders plus ExifTool; make the executables available in `PATH`.
2. Preview video and JPEG files in a folder:

   ```powershell
   .\Optimize-MediaSize.ps1 -InputPath 'C:\Media' -WhatIf
   ```

3. Optimize the folder, keeping each original as an `_orig` backup with its original extension:

   ```powershell
   .\Optimize-MediaSize.ps1 -InputPath 'C:\Media'
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
it does not install software or require administrator rights.

## Scripts and switches

### `Optimize-MediaSize.ps1`

Encodes eligible `.mov` and `.mp4` files as 720p H.265/HEVC MP4 using the `libx265` encoder, a 1.9 Mb/s average video
bitrate, the `medium` preset, and 96 kb/s audio. Landscape video is limited to 1280x720; portrait video is limited to
720x1280. This targets approximately 90 MB for a six-minute video, though actual size varies with duration and content.
H.264 sources at or below 1.9 Mb/s and HEVC, AV1, and VP9 sources are skipped. H.264 with unknown bitrate is skipped
conservatively, and a matching `_orig` backup prevents repeated lossy encoding. Other codecs are re-encoded.

JPEG photos over 6 MB are resized according to their source file size and pixel dimensions, then re-encoded with
FFmpeg's high-quality MJPEG setting. The estimated output pixel count is the source pixel count multiplied by
`5.5 MB / source size`; width and height are scaled by the square root of that ratio. Actual output size varies with
image detail and compression, so 5.5 MB is an estimate, not a hard limit. Photos at or below 6 MB are skipped. Folder
searches are recursive, and a result is accepted only when smaller than its source.

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

## Shared PowerShell parameters

The script supports common parameters including `-Verbose`, `-Debug`, `-ErrorAction`, `-WarningAction`, `-WhatIf`, and
`-Confirm`. `-WhatIf` and `-Confirm` are provided through `SupportsShouldProcess`.

## Safety and behavior

- FFmpeg maps video metadata and chapters; ExifTool copies supported metadata. File-level EXIF/XMP and container
  capture dates are checked before accepting an output. Per-track creation and modification timestamps are excluded
  because video stream layouts may differ. The Samsung maker-note `TimeStamp` and non-capture EXIF `IFD0:ModifyDate`
  are also excluded; standard EXIF capture dates remain checked. A mismatch in relevant dates leaves the source in
  place.
- The source's creation, last-write, and last-access file timestamps are restored on the optimized file. ExifTool copies
  and verifies embedded dates. Windows does not permit the script to set NTFS change time, so that low-level file-system
  timestamp cannot be preserved.
- JPEG photos at or below 6 MB are skipped. Larger photos are proportionally downscaled toward an estimated 5.5 MB
  output and encoded at high quality (FFmpeg MJPEG quality-scale value 2). Resizing is lossy; actual output size varies
  with image detail and the estimate is not a guaranteed limit.
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
- The script does not delete matching Live Photo videos or process formats other than `.mov`, `.mp4`, `.jpg`, and
  `.jpeg`.
- Do not use this tool on files that must remain byte-identical.
- The project is licensed under the [MIT License](../LICENSE.md).
- Contribution guidance is in [CONTRIBUTING.md](../CONTRIBUTING.md).
